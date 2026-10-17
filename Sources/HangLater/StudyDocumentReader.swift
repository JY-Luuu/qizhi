import Foundation
import PDFKit
import HangLaterCore

enum StudyTextExtraction {
    static func plainHTML(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "nav", "header", "footer", "noscript", "svg"] {
            text = text.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)\\s*>", with: "\n", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?i)</?(?:p|div|article|section|h[1-6]|li|br|tr)\\b[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        let pattern = "&#(x[0-9a-fA-F]+|[0-9]+);"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: text), let numberRange = Range(match.range(at: 1), in: text) else { continue }
                let number = String(text[numberRange])
                let value = number.lowercased().hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
                if let value, let scalar = UnicodeScalar(value) { text.replaceSubrange(range, with: String(scalar)) }
            }
        }
        for (entity, replacement) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
    }

    static func passages(_ text: String, page: Int? = nil, offset: Int = 0) -> [EvidencePassage] {
        var parts = text.components(separatedBy: .newlines).map(ActionValidation.normalized).filter { $0.count >= 8 }
        if parts.isEmpty, !ActionValidation.normalized(text).isEmpty { parts = [ActionValidation.normalized(text)] }
        var passages: [EvidencePassage] = []
        for part in parts {
            var remaining = part[...]
            while !remaining.isEmpty {
                let chunk = String(remaining.prefix(1000))
                remaining = remaining.dropFirst(min(1000, remaining.count))
                passages.append(EvidencePassage(id: "p\(offset + passages.count + 1)", text: chunk, page: page))
                if passages.count >= 24 { return passages }
            }
        }
        return passages
    }

    static func document(source: StudySource, data: Data, isPDF: Bool, isHTML: Bool) throws -> StudyDocument {
        var evidence: [EvidencePassage] = [], truncated = false
        if isPDF {
            guard let pdf = PDFDocument(data: data), !pdf.isLocked else { throw ActionPlanError("PDF 无法读取或已加密。 / PDF unreadable or encrypted.") }
            let count = min(pdf.pageCount, 20)
            for index in 0..<count {
                if let text = pdf.page(at: index)?.string {
                    evidence += passages(text, page: index + 1, offset: evidence.count)
                    if evidence.count >= 24 { truncated = index + 1 < pdf.pageCount; break }
                }
            }
            truncated = truncated || pdf.pageCount > 20
        } else {
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw ActionPlanError("资料需要 UTF-8/UTF-16 文本或可提取文字的 PDF。 / Unsupported text encoding.")
            }
            let plain = isHTML ? plainHTML(String(text.prefix(1_000_000))) : text
            evidence = passages(String(plain.prefix(80_000)))
            truncated = plain.count > 80_000 || evidence.count >= 24
        }
        evidence = Array(evidence.prefix(24))
        var count = 0
        evidence = evidence.filter { part in
            count += part.text.count
            if count > 16_000 { truncated = true; return false }
            return true
        }
        guard evidence.contains(where: { $0.text.count >= 8 }) else {
            throw ActionPlanError("没有读到足够正文。扫描 PDF 需要先做 OCR，登录网页可将正文粘贴到备注。 / No readable text; OCR or pasted notes may be needed.")
        }
        return StudyDocument(source: source, passages: evidence, truncated: truncated)
    }
}

struct NativeStudyReader: StudyDocumentReading {
    func read(_ source: StudySource) async throws -> StudyDocument {
        try Task.checkCancellation()
        if let path = source.filePath {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            guard ["pdf", "txt", "md", "markdown", "html", "htm"].contains(ext) else {
                throw ActionPlanError("请选择 PDF、文本、Markdown 或网页资料。 / Unsupported document type.")
            }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 10 * 1024 * 1024 else { throw ActionPlanError("单份资料不能超过 10 MB。 / Source exceeds 10 MB.") }
            return try await Task.detached(priority: .utility) {
                try Task.checkCancellation()
                return try StudyTextExtraction.document(source: source, data: Data(contentsOf: url), isPDF: ext == "pdf", isHTML: ["html", "htm"].contains(ext))
            }.value
        }
        if let address = source.url, let url = TaskInput.webURL(address) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 35; configuration.timeoutIntervalForResource = 50
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: url)
            request.setValue("text/html, text/plain, application/pdf", forHTTPHeaderField: "Accept")
            let (data, response) = try await BoundedNetwork.load(request, session: session, limit: 10 * 1024 * 1024)
            guard (200...299).contains(response.statusCode) else {
                throw ActionPlanError("资料返回 HTTP \(response.statusCode)，可重试或将正文保存为文字资料。 / Source unavailable.")
            }
            let mime = response.mimeType ?? ""
            let pdf = mime == "application/pdf" || data.starts(with: Data("%PDF-".utf8))
            guard pdf || mime.hasPrefix("text/") || mime == "application/xhtml+xml" else {
                throw ActionPlanError("网页没有提供可读取的正文。 / Source is not readable text or PDF.")
            }
            return try await Task.detached(priority: .utility) {
                try StudyTextExtraction.document(source: source, data: data, isPDF: pdf, isHTML: mime.contains("html"))
            }.value
        }
        return try StudyTextExtraction.document(source: source, data: Data(source.note.utf8), isPDF: false, isHTML: false)
    }
}
