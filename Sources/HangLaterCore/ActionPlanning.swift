import Foundation
import CryptoKit

public struct StudySource: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: String?
    public var filePath: String?
    public var note: String
    public init(id: UUID = UUID(), title: String, url: String? = nil, filePath: String? = nil, note: String = "") {
        self.id = id; self.title = title; self.url = url; self.filePath = filePath; self.note = note
    }
}

public struct EvidencePassage: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var page: Int?
    public init(id: String, text: String, page: Int? = nil) {
        self.id = id; self.text = text; self.page = page
    }
    public var locator: String { page.map { "p. \($0) · \(id)" } ?? id }
}

public struct StudyDocument: Codable, Equatable, Sendable {
    public var source: StudySource
    public var passages: [EvidencePassage]
    public var fingerprint: String
    public var truncated: Bool
    public init(source: StudySource, passages: [EvidencePassage], truncated: Bool = false) {
        self.source = source; self.passages = passages; self.truncated = truncated
        self.fingerprint = SHA256.hash(data: Data(passages.map { $0.locator + ":" + $0.text }.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

public struct ActionCitation: Codable, Equatable, Sendable {
    public var sourceID: UUID
    public var passageID: String
    public var quote: String
    enum CodingKeys: String, CodingKey { case sourceID = "source_id", passageID = "passage_id", quote }
    public init(sourceID: UUID, passageID: String, quote: String) {
        self.sourceID = sourceID; self.passageID = passageID; self.quote = quote
    }
}

public struct ActionDraft: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var instruction: String
    public var outcome: String
    public var minutes: Int
    public var citations: [ActionCitation]
    enum CodingKeys: String, CodingKey { case id, title, instruction, outcome, minutes, citations }
    public init(id: UUID = UUID(), title: String, instruction: String, outcome: String, minutes: Int, citations: [ActionCitation]) {
        self.id = id; self.title = title; self.instruction = instruction; self.outcome = outcome
        self.minutes = minutes; self.citations = citations
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        instruction = try c.decode(String.self, forKey: .instruction)
        outcome = try c.decode(String.self, forKey: .outcome)
        minutes = try c.decode(Int.self, forKey: .minutes)
        citations = try c.decode([ActionCitation].self, forKey: .citations)
    }
}

public struct SavedCitation: Codable, Equatable, Identifiable, Sendable {
    public var id: String { source.id.uuidString + ":" + passage.id + ":" + quote }
    public var source: StudySource
    public var passage: EvidencePassage
    public var quote: String
    public var fingerprint: String
    public init(source: StudySource, passage: EvidencePassage, quote: String, fingerprint: String) {
        self.source = source; self.passage = passage; self.quote = quote; self.fingerprint = fingerprint
    }
}

public struct ActionTaskOrigin: Codable, Equatable, Sendable {
    public var runID: UUID
    public var cardID: UUID
    public var minutes: Int
    public var outcome: String
    public var citations: [SavedCitation]
    public var isDemo: Bool
}

public enum StudyStatus: String, Codable, Sendable {
    case running, review, failed, cancelled, interrupted, completed
}

public struct StudyEvent: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var kind: String
    public var detail: String
    public init(_ kind: String, _ detail: String) { self.kind = kind; self.detail = detail }
}

public struct StudyRun: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var goal: String
    public var budget: Int
    public var sources: [StudySource]
    public var documents: [StudyDocument]
    public var drafts: [ActionDraft]
    public var status: StudyStatus
    public var events: [StudyEvent]
    public var inputTokens: Int
    public var outputTokens: Int
    public var elapsedSeconds: Double
    public var isDemo: Bool
    public var failure: String?
    public init(goal: String, budget: Int, sources: [StudySource], isDemo: Bool = false) {
        id = UUID(); createdAt = Date(); updatedAt = createdAt
        self.goal = goal; self.budget = budget; self.sources = sources; self.isDemo = isDemo
        documents = []; drafts = []; events = []; status = .running
        inputTokens = 0; outputTokens = 0; elapsedSeconds = 0
    }
    public mutating func record(_ kind: String, _ detail: String) {
        updatedAt = Date(); events.append(StudyEvent(kind, detail))
        if events.count > 80 { events.removeFirst(events.count - 80) }
    }
}

public struct ActionPlanError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum ActionValidation {
    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    public static func validate(_ cards: [ActionDraft], documents: [StudyDocument], budget: Int,
                                requireAllSources: Bool = true) throws {
        guard (1...6).contains(cards.count), (5...120).contains(budget) else {
            throw ActionPlanError("需要 1–6 张行动卡，时间预算为 5–120 分钟。 / Invalid card count or budget.")
        }
        guard Set(cards.map(\.id)).count == cards.count else { throw ActionPlanError("行动卡 ID 重复。 / Duplicate card ID.") }
        var covered = Set<UUID>()
        for card in cards {
            guard !normalized(card.title).isEmpty, card.title.count <= 120,
                  !normalized(card.instruction).isEmpty, card.instruction.count <= 1800,
                  !normalized(card.outcome).isEmpty, card.outcome.count <= 600,
                  (1...120).contains(card.minutes), (1...4).contains(card.citations.count) else {
                throw ActionPlanError("行动卡缺少有效的标题、步骤、产出或引用。 / Incomplete action card.")
            }
            for citation in card.citations {
                guard let doc = documents.first(where: { $0.source.id == citation.sourceID }),
                      let passage = doc.passages.first(where: { $0.id == citation.passageID }),
                      normalized(citation.quote).count >= 8,
                      normalized(citation.quote).count <= 500,
                      normalized(passage.text).contains(normalized(citation.quote)) else {
                    throw ActionPlanError("引用未能匹配读取的原文，请重新生成。 / Citation does not match the source snapshot.")
                }
                covered.insert(citation.sourceID)
            }
        }
        guard cards.reduce(0, { $0 + $1.minutes }) <= budget else {
            throw ActionPlanError("行动卡总时长超过时间预算。 / The plan exceeds its time budget.")
        }
        if requireAllSources && covered != Set(documents.map { $0.source.id }) {
            throw ActionPlanError("计划没有使用每份选中的资料。 / Some selected sources were not used.")
        }
    }
}

/// One owner (the main-actor coordinator) writes this journal. API credentials
/// and raw provider responses are never included. In-flight jobs recover paused.
public final class StudyRunStore {
    public let file: URL
    public private(set) var runs: [StudyRun]
    public init(directory: URL) throws {
        let folder = directory.appendingPathComponent("ActionStudio", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        file = folder.appendingPathComponent("runs.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { runs = try JSONDecoder().decode([StudyRun].self, from: Data(contentsOf: file)) }
            catch { throw ActionPlanError("行动记录无法读取，原文件已保留。 / The run journal is unreadable; it was preserved.") }
        } else { runs = [] }
        for index in runs.indices where runs[index].status == .running {
            runs[index].status = .interrupted
            runs[index].record("interrupted", "上次执行被中断，可从资料快照继续。 / Interrupted; source checkpoints are available.")
        }
        if !runs.isEmpty { try save(runs) }
    }
    public func upsert(_ run: StudyRun) throws {
        var next = runs.filter { $0.id != run.id }
        next.insert(run, at: 0)
        try save(Array(next.prefix(10)))
    }
    private func save(_ next: [StudyRun]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        runs = next
    }
}

public enum StudySamples {
    public static let sources: [StudySource] = [
        StudySource(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, title: "工具设计 · 示例资料", note: "工具应有明确的输入和输出。把读取资料与写入任务分开，并在执行前检查参数，可以减少不可预期的操作。"),
        StudySource(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, title: "可靠执行 · 示例资料", note: "长任务需要保存进度。每次产生外部效果的操作都要有唯一标识；重试同一个操作时，应返回已有结果，避免重复创建任务。"),
        StudySource(id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!, title: "效果验证 · 示例资料", note: "评测应检查最终状态，而不只看回答是否流畅。为正常输入、缺失资料、错误引用和中断恢复分别定义验收条件。")
    ]
    public static var documents: [StudyDocument] {
        sources.map { StudyDocument(source: $0, passages: [EvidencePassage(id: "p1", text: $0.note)]) }
    }
    public static var drafts: [ActionDraft] {
        let titles = ["画出工具的输入与输出", "设计一次安全的失败重试", "写下三个可验证的验收条件"]
        let steps = ["阅读工具设计资料，列出 read_source 与保存任务分别需要哪些参数。", "画出一次中断与恢复的流程，给保存操作设计唯一标识。", "根据评测资料，分别为缺失资料、错误引用和重复保存写一个检查。"]
        let outcomes = ["一张包含两个工具及权限边界的草图", "一份能解释如何避免重复任务的流程笔记", "三个有明确预期结果的测试案例"]
        return sources.enumerated().map { i, source in
            ActionDraft(title: titles[i], instruction: steps[i], outcome: outcomes[i], minutes: 15,
                        citations: [ActionCitation(sourceID: source.id, passageID: "p1", quote: source.note)])
        }
    }
}
