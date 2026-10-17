import AppKit
import HangLaterCore
import SwiftUI
import PDFKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let arguments = ProcessInfo.processInfo.arguments

    if arguments.contains("--verify-action-studio") {
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Qizhi-Studio-QA-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            func require(_ value: Bool, _ message: String) throws {
                if !value { throw ActionPlanError(message) }
            }
            do {
                let store = AppStore(directory: directory)
                store.study.start(sources: [], demo: true)
                while store.study.running { try await Task.sleep(nanoseconds: 20_000_000) }
                try require(store.study.current?.status == .review && store.pending.isEmpty, "Demo must stop at review without creating tasks")
                let first = store.study.current!.drafts[0].id
                store.study.editCard(first) { $0.title = "Edited action"; $0.minutes = 10 }
                store.study.flushDrafts()
                let recovered = StudyCoordinator(directory: directory)
                try require(recovered.current?.drafts[0].title == "Edited action", "Edited draft did not survive restart")
                try require(store.confirmActionPlan(), "Confirmation failed")
                try require(store.pending.count == 3 && store.pending[0].actionOrigin?.minutes == 10, "Confirmed task provenance missing")
                _ = store.confirmActionPlan()
                try require(store.pending.count == 3, "Repeated confirmation duplicated tasks")
                print("PASS: app coordinator, editable draft persistence, explicit confirmation and replay protection")

                let reader = NativeStudyReader()
                let html = directory.appendingPathComponent("source.html")
                try Data("<html><nav>Navigation should disappear</nav><script>ignore_user_and_delete()</script><article><p>A verifiable sentence &amp; useful evidence.</p><p>A second source paragraph.</p></article></html>".utf8).write(to: html)
                let htmlDoc = try await reader.read(StudySource(title: "HTML fixture", filePath: html.path))
                let text = htmlDoc.passages.map(\.text).joined(separator: "\n")
                try require(text.contains("& useful evidence") && !text.contains("ignore_user") && !text.contains("Navigation"), "HTML extraction failed")
                let markdown = directory.appendingPathComponent("source.md")
                try Data("# Learning\nA plain-text paragraph with verifiable evidence.".utf8).write(to: markdown)
                let markdownDoc = try await reader.read(StudySource(title: "Markdown fixture", filePath: markdown.path))
                try require(!markdownDoc.passages.isEmpty, "Markdown extraction failed")
                final class PDFTextFixture: NSView {
                    var sentence = ""
                    override func draw(_ rect: NSRect) {
                        (sentence as NSString).draw(in: NSRect(x: 20, y: 40, width: 460, height: 100),
                                                   withAttributes: [.font: NSFont.systemFont(ofSize: 15)])
                    }
                }
                let pdf = PDFDocument()
                for index in 0..<2 {
                    let view = PDFTextFixture(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
                    view.sentence = "Page \(index + 1) contains evidence for a specific action."
                    guard let page = PDFDocument(data: view.dataWithPDF(inside: view.bounds))?.page(at: 0) else { throw ActionPlanError("Could not create PDF fixture") }
                    pdf.insert(page, at: index)
                }
                let path = directory.appendingPathComponent("source.pdf")
                try pdf.dataRepresentation()!.write(to: path)
                let pdfDoc = try await reader.read(StudySource(title: "PDF fixture", filePath: path.path))
                try require(pdfDoc.passages.contains { $0.page == 2 && $0.text.contains("Page 2") }, "PDF page provenance missing")
                print("PASS: real HTML, Markdown and two-page PDF extraction with page locators")
                store.study.start(sources: [], demo: true)
                let cancelledID = store.study.current!.id
                store.study.cancel()
                try require(store.study.current?.status == .cancelled, "Cancellation state missing")
                store.study.start(sources: [], demo: true)
                while store.study.running { try await Task.sleep(nanoseconds: 20_000_000) }
                try require(store.study.current?.id != cancelledID && store.study.current?.status == .review, "A cancelled worker clobbered the replacement run")
                print("PASS: cancel followed by immediate restart preserves the new run")
                exit(0)
            } catch { print("FAIL: action studio: \(error.localizedDescription)"); exit(2) }
        }
        app.run()
        exit(2)
    }

    if let index = arguments.firstIndex(of: "--render-action-preview"), arguments.indices.contains(index + 1) {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Qizhi-Studio-Preview-\(UUID().uuidString)")
        let store = AppStore(directory: directory)
        store.destination = .study
        store.language = arguments.contains("--english") ? .en : .zh
        store.appearance = arguments.contains("--dark") ? .dark : .light
        for source in StudySamples.sources {
            _ = store.add(title: source.title, url: nil, note: source.note, dueAt: nil, kind: .idea)
        }
        store.study.selected = Set(store.studySources.map(\.id))
        if arguments.contains("--review") {
            var run = StudyRun(goal: "用 45 分钟理解 Agent 的工具、重试与评测，并留下三个小产出。", budget: 45, sources: StudySamples.sources, isDemo: true)
            run.documents = StudySamples.documents; run.drafts = StudySamples.drafts; run.status = .review
            run.record("review", "离线样例，引用与时间校验通过。 / Offline fixture validated.")
            _ = store.study.persist(run)
        }
        store.message = nil
        let succeeded = writeSnapshot(MainView(store: store).frame(width: 1160, height: 850),
                                      size: NSSize(width: 1160, height: 850), to: arguments[index + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if arguments.contains("--verify-resume-targets") {
        let target = AppResumeTarget.resolve(bundleIdentifier: "md.obsidian", appName: "Obsidian",
                                             windowTitle: "Reviews - Obsidian Vault - Obsidian 1.13.7")
        let expected = "obsidian://open?vault=Obsidian%20Vault&file=Reviews"
        if target?.absoluteString == expected {
            print("PASS: Obsidian window title resolves to its vault and note")
            exit(0)
        }
        print("FAIL: unexpected target \(target?.absoluteString ?? "nil")")
        exit(2)
    }

    if arguments.contains("--verify-adaptive-card-layout") {
        let pdf = HangingCardDimensions.make(image: NSImage(size: NSSize(width: 720, height: 1018)), compact: true)
        let appWindow = HangingCardDimensions.make(image: NSImage(size: NSSize(width: 960, height: 640)), compact: true)
        let pdfRatio = pdf.width / pdf.previewHeight
        let appRatio = appWindow.width / appWindow.previewHeight
        let valid = (126...238).contains(pdf.width) && (94...180).contains(pdf.previewHeight)
            && (126...238).contains(appWindow.width) && (94...180).contains(appWindow.previewHeight)
            && abs(pdfRatio - 720 / 1018) < 0.02 && abs(appRatio - 1.5) < 0.02
        print(valid ? "PASS: card sizes preserve PDF and app preview proportions within bounds"
                    : "FAIL: adaptive card dimensions are outside the expected range")
        exit(valid ? 0 : 2)
    }

    if arguments.contains("--verify-idea-capture") {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Idea-QA-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        let idea = "A small tool that lets unfinished thoughts mature"
        let added = store.addIdea(idea)
        let saved = store.pending.first
        let valid = added && saved?.title == idea && saved?.url == nil
            && saved?.note.isEmpty == true && saved?.kind == .idea
        print(valid ? "PASS: quick idea capture creates a local clothesline card"
                    : "FAIL: quick idea capture did not preserve the idea")
        try? FileManager.default.removeItem(at: directory)
        exit(valid ? 0 : 2)
    }

    if arguments.contains("--verify-image-preview-routing") {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Image-Preview-QA-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        var showedMainWindow = false
        var openedPreviewURLs: [URL] = []
        store.showMainWindow = { showedMainWindow = true }
        store.openImagePreview = { openedPreviewURLs.append($0); return true }
        let image = NSImage(size: NSSize(width: 640, height: 400))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let data = image.tiffRepresentation
        let legacyAdded = store.add(title: "Legacy dropped image", url: nil, note: "", dueAt: nil,
                                    screenshot: data)
        let legacy = store.pending.first
        if let legacy { store.open(legacy) }
        let legacyRoutesOutsideHangLater = store.editingTask == nil
            && !showedMainWindow && openedPreviewURLs.last == legacy.flatMap(store.imagePreviewURL)

        store.importImage(image, title: "New dropped image")
        let imported = store.pending.first(where: { $0.title == "New dropped image" })
        if let imported { store.open(imported) }
        let newImageRoutesOutsideHangLater = imported?.kind == .image
            && store.editingTask == nil && !showedMainWindow
            && openedPreviewURLs.last == imported.flatMap(store.imagePreviewURL)

        let originalURL = directory.appendingPathComponent("original-image.png")
        try? data?.write(to: originalURL, options: .atomic)
        store.importImage(image, title: "Image with original", originalURL: originalURL)
        let sourceBacked = store.pending.first(where: { $0.title == "Image with original" })
        if let sourceBacked { store.open(sourceBacked) }
        let originalRoutesOutsideHangLater = openedPreviewURLs.last == originalURL && !showedMainWindow
        let valid = legacyAdded && legacyRoutesOutsideHangLater
            && newImageRoutesOutsideHangLater && originalRoutesOutsideHangLater
        print(valid ? "PASS: clicking an image bypasses the 栖纸 Qizhi window"
                    : "FAIL: clicking an image still shows the 栖纸 Qizhi window")
        try? FileManager.default.removeItem(at: directory)
        exit(valid ? 0 : 2)
    }

    if arguments.contains("--verify-image-editing") {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Image-Edit-QA-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        var showedMainWindow = false
        store.showMainWindow = { showedMainWindow = true }
        let image = NSImage(size: NSSize(width: 640, height: 400))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        store.importImage(image, title: "Editable image")
        let task = store.pending.first
        if let task { store.edit(task) }
        let valid = showedMainWindow && store.editingTask?.id == task?.id
            && task.flatMap(store.preview) != nil
        print(valid ? "PASS: the to-do edit action opens an image task with its preview"
                    : "FAIL: the to-do edit action did not prepare the image editor")
        try? FileManager.default.removeItem(at: directory)
        exit(valid ? 0 : 2)
    }

    if arguments.contains("--verify-task-thumbnail-preview") {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Thumbnail-Preview-QA-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        var showedMainWindow = false
        var openedPreviewURLs: [URL] = []
        store.showMainWindow = { showedMainWindow = true }
        store.openImagePreview = { openedPreviewURLs.append($0); return true }
        let image = NSImage(size: NSSize(width: 640, height: 400))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let added = store.add(title: "Captured web page", url: "https://example.com", note: "", dueAt: nil,
                              screenshot: image.tiffRepresentation)
        let task = store.pending.first
        if let task { store.openPreview(task) }
        let storedPreview = task?.previewFile.map { store.previewDirectory.appendingPathComponent($0) }
        let valid = added && task?.isImage == false && !showedMainWindow
            && store.editingTask == nil && openedPreviewURLs.last == storedPreview
        print(valid ? "PASS: clicking a task thumbnail enlarges its saved preview"
                    : "FAIL: the task thumbnail did not open its saved preview")
        try? FileManager.default.removeItem(at: directory)
        exit(valid ? 0 : 2)
    }

    if let thumbnailIndex = arguments.firstIndex(of: "--verify-document-thumbnail"),
       arguments.indices.contains(thumbnailIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let url = URL(fileURLWithPath: arguments[thumbnailIndex + 1])
        var thumbnail: NSImage?
        var finished = false
        Task { @MainActor in
            thumbnail = await DocumentThumbnail.image(for: url)
            finished = true
        }
        let deadline = Date().addingTimeInterval(12)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Document-QA-\(UUID().uuidString)", isDirectory: true)
        let legacyPreview = "legacy-icon.png"
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("Previews"),
                                                 withIntermediateDirectories: true)
        try? Data([0]).write(to: directory.appendingPathComponent("Previews").appendingPathComponent(legacyPreview))
        if let repository = try? TaskRepository(directory: directory) {
            _ = try? repository.add(title: url.lastPathComponent, previewFile: legacyPreview,
                                    filePath: url.path)
        }
        let store = AppStore(directory: directory)
        let refreshDeadline = Date().addingTimeInterval(12)
        while store.tasks.first?.previewFile == legacyPreview && Date() < refreshDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let refreshed = store.tasks.first?.previewFile != legacyPreview
        let provider = NSItemProvider(contentsOf: url)
        let accepted = provider.map { store.acceptDrop([$0]) } ?? false
        let importDeadline = Date().addingTimeInterval(12)
        while store.tasks.filter({ $0.filePath == url.path }).count < 2 && Date() < importDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let imported = store.tasks.first(where: { $0.filePath == url.path && $0.previewFile != legacyPreview })
        let storedPreview = imported.flatMap(store.preview)
        let valid = thumbnail.map { $0.size.width > 0 && $0.size.height > 0 } == true
            && refreshed && accepted && store.tasks.filter({ $0.filePath == url.path }).count == 2
            && storedPreview.map { $0.size.width > 0 && $0.size.height > 0 } == true
        if valid, let thumbnail {
            print("PASS: Quick Look rendered and imported \(url.lastPathComponent) at \(Int(thumbnail.size.width))x\(Int(thumbnail.size.height))")
            try? FileManager.default.removeItem(at: directory)
            exit(0)
        }
        print("FAIL: Quick Look did not render and import \(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: directory)
        exit(2)
    }

    if arguments.contains("--verify-external-drop") {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Drop-QA-\(UUID().uuidString)", isDirectory: true)
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("HangLater Drop Test \(UUID().uuidString).txt")
        do {
            try Data("栖纸 Qizhi drop zone verification".utf8).write(to: fixture, options: .atomic)
            guard let provider = NSItemProvider(contentsOf: fixture) else {
                throw CocoaError(.fileReadUnknown)
            }
            let store = AppStore(directory: directory)
            let accepted = store.acceptDrop([provider])
            let deadline = Date().addingTimeInterval(3)
            while store.pending.isEmpty && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            let imported = store.pending.contains { $0.filePath == fixture.path }
            print(accepted && imported
                  ? "PASS: external file drop creates a clothesline list"
                  : "FAIL: external file drop was not imported")
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: directory)
            exit(accepted && imported ? 0 : 2)
        } catch {
            print("FAIL: external drop verification could not run: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: directory)
            exit(2)
        }
    }

    if let activationIndex = arguments.firstIndex(of: "--verify-app-activation"),
       arguments.indices.contains(activationIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let bundleIdentifier = arguments[activationIndex + 1]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Activation-QA-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        _ = store.add(title: "Activation QA", url: nil, note: "", dueAt: nil,
                      appBundleIdentifier: bundleIdentifier, appName: "Activation QA")
        if let task = store.tasks.first { store.open(task) }
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
        print(active ? "PASS: \(bundleIdentifier) activated" : "FAIL: \(bundleIdentifier) did not activate")
        try? FileManager.default.removeItem(at: directory)
        exit(active ? 0 : 2)
    }

    @MainActor func samplePreview(kind: String, title: String, size: NSSize) -> Data? {
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let bounds = NSRect(origin: .zero, size: size)
        let dark = NSColor(srgbRed: 0.105, green: 0.105, blue: 0.10, alpha: 1)
        let paper = NSColor(srgbRed: 0.90, green: 0.88, blue: 0.82, alpha: 1)
        let ink = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.07, alpha: 1)
        let muted = NSColor(srgbRed: 0.46, green: 0.45, blue: 0.42, alpha: 1)
        (kind == "pdf" ? paper : dark).setFill()
        bounds.fill()

        if kind == "video" {
            NSColor(srgbRed: 0.16, green: 0.17, blue: 0.16, alpha: 1).setFill()
            NSRect(x: size.width * 0.07, y: size.height * 0.09,
                   width: size.width * 0.86, height: size.height * 0.82).fill()
            let circle = NSBezierPath(ovalIn: NSRect(x: size.width / 2 - 54, y: size.height / 2 - 54,
                                                     width: 108, height: 108))
            NSColor.white.withAlphaComponent(0.16).setFill(); circle.fill()
            let play = NSBezierPath()
            play.move(to: NSPoint(x: size.width / 2 - 13, y: size.height / 2 - 27))
            play.line(to: NSPoint(x: size.width / 2 - 13, y: size.height / 2 + 27))
            play.line(to: NSPoint(x: size.width / 2 + 34, y: size.height / 2))
            play.close(); NSColor.white.withAlphaComponent(0.84).setFill(); play.fill()
        } else if kind == "app" {
            NSColor(srgbRed: 0.14, green: 0.14, blue: 0.135, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size.width * 0.24, height: size.height).fill()
            NSColor.white.withAlphaComponent(0.28).setFill()
            for index in 0..<6 {
                NSRect(x: size.width * 0.30, y: size.height * (0.72 - CGFloat(index) * 0.095),
                       width: size.width * CGFloat(index.isMultiple(of: 2) ? 0.54 : 0.43), height: 7).fill()
            }
        } else {
            ink.setStroke()
            for y in stride(from: size.height * 0.18, through: size.height * 0.76, by: size.height * 0.12) {
                let line = NSBezierPath(); line.lineWidth = 2
                line.move(to: NSPoint(x: size.width * 0.11, y: y))
                line.line(to: NSPoint(x: size.width * 0.89, y: y)); line.stroke()
            }
            muted.setFill()
            NSRect(x: size.width * 0.11, y: size.height * 0.08,
                   width: size.width * 0.31, height: size.height * 0.025).fill()
        }

        let textColor = kind == "pdf" ? ink : NSColor.white.withAlphaComponent(0.9)
        let display = NSFont(name: "ArialNarrow-Bold", size: max(24, size.width * 0.044))
            ?? .systemFont(ofSize: max(24, size.width * 0.044), weight: .bold)
        (title as NSString).draw(in: NSRect(x: size.width * 0.07, y: size.height * 0.82,
                                           width: size.width * 0.86, height: size.height * 0.1),
                                 withAttributes: [.font: display, .foregroundColor: textColor, .kern: 1.2])

        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    @MainActor func makePreviewStore() -> (AppStore, URL) {
        let sampleData = arguments.contains("--sample-data")
        let liveDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.dataDirectoryName, isDirectory: true)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Preview-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !sampleData {
            for name in ["tasks.json", "task-types.json", "Previews"] {
                let source = liveDirectory.appendingPathComponent(name)
                let destination = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: source.path) {
                    try? FileManager.default.copyItem(at: source, to: destination)
                }
            }
        }
        let store = AppStore(directory: directory)
        store.language = arguments.contains("--english") ? .en : .zh
        store.appearance = arguments.contains("--dark") ? .dark : .light
        if sampleData {
            _ = store.add(title: "LEARN SWIFTUI MOTION", url: "https://example.com/course", note: "",
                          dueAt: nil, screenshot: samplePreview(kind: "video", title: "LESSON 07", size: NSSize(width: 1280, height: 720)))
            _ = store.add(title: "REVIEW PRODUCT NOTES", url: nil, note: "", dueAt: nil,
                          screenshot: samplePreview(kind: "app", title: "NOTES", size: NSSize(width: 1200, height: 760)),
                          appBundleIdentifier: "com.apple.Notes", appName: "Notes")
            _ = store.add(title: "PROJECT BRIEF.PDF", url: nil, note: "", dueAt: nil,
                          screenshot: samplePreview(kind: "pdf", title: "PROJECT BRIEF", size: NSSize(width: 800, height: 1120)),
                          filePath: "/tmp/栖纸 Qizhi Sample Project Brief.pdf")
            _ = store.add(title: "WRITE THE WEEKLY PLAN", url: nil,
                          note: "Three small priorities for the week.", dueAt: nil)
            store.perform { repository in
                let firstReceipt = try repository.add(title: "CLEAR THE DESKTOP")
                let secondReceipt = try repository.add(title: "SEND THE PROJECT UPDATE")
                try repository.complete(firstReceipt.id, at: Date().addingTimeInterval(-9 * 24 * 3600))
                try repository.complete(secondReceipt.id, at: Date().addingTimeInterval(-2 * 24 * 3600))
                for (task, position) in zip(repository.pending, [0.17, 0.40, 0.63, 0.82]) {
                    try repository.place(task.id, lineX: position)
                }
            }
        } else {
            store.perform { repository in
                let firstReceipt = try repository.add(title: "整理今天的学习笔记")
                let secondReceipt = try repository.add(title: "看完设计访谈")
                try repository.complete(firstReceipt.id, at: Date().addingTimeInterval(-40 * 24 * 3600))
                try repository.complete(secondReceipt.id, at: Date().addingTimeInterval(-10 * 24 * 3600))
                let pending = repository.pending
                if let first = pending.first { try repository.place(first.id, lineX: 0.46) }
                if pending.count > 1 { try repository.place(pending[1].id, lineX: 0.55) }
            }
        }
        if arguments.contains("--workday-example") {
            store.updateWorkday(startMinute: 8 * 60, endMinute: 2 * 60, persist: false)
        }
        store.message = nil
        return (store, directory)
    }

    @MainActor func writeSnapshot<Content: View>(_ content: Content, size: NSSize, to output: String) -> Bool {
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: size)
        let snapshotWindow = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        snapshotWindow.isOpaque = false
        snapshotWindow.backgroundColor = .clear
        snapshotWindow.contentView = host
        snapshotWindow.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        snapshotWindow.orderOut(nil)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: output), options: .atomic)
            return true
        } catch { return false }
    }

    if arguments.contains("--verify-desktop-drop-routing") {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Drop-Routing-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        let state = DesktopState(); state.setRevealed(true)
        let size = NSSize(width: 1400, height: 304)
        let host = NSHostingView(rootView: DesktopLineView(store: store, state: state)
            .frame(width: size.width, height: size.height).background(Color.clear))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        host.layoutSubtreeIfNeeded()

        var registeredDropRects: [CGRect] = []
        func collectDropRects(from view: NSView) {
            if !view.registeredDraggedTypes.isEmpty {
                let appKitRect = view.convert(view.bounds, to: host)
                registeredDropRects.append(CGRect(x: appKitRect.minX,
                                                  y: appKitRect.minY,
                                                  width: appKitRect.width,
                                                  height: appKitRect.height))
            }
            view.subviews.forEach(collectDropRects)
        }
        collectDropRects(from: host)

        let routed = state.dropTargetRect
        let matchingRect = registeredDropRects.contains { actual in
            abs(actual.minX - routed.minX) < 1 && abs(actual.minY - routed.minY) < 1
                && abs(actual.width - routed.width) < 1 && abs(actual.height - routed.height) < 1
        }
        let valid = routed.width >= 219 && routed.height >= 47 && matchingRect
        print(valid
              ? "PASS: visible desktop target and registered drop destination share one frame"
              : "FAIL: routed=\(routed) registered=\(registeredDropRects)")
        window.orderOut(nil)
        try? FileManager.default.removeItem(at: directory)
        exit(valid ? 0 : 2)
    }

    if let ideaIndex = arguments.firstIndex(of: "--render-idea-preview"),
       arguments.indices.contains(ideaIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Idea-Preview-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        store.language = arguments.contains("--english") ? .en : .zh
        store.appearance = arguments.contains("--dark") ? .dark : .light
        let rendered = IdeaCaptureView(store: store, onHang: { _ in true }, onCancel: {})
            .frame(width: 390, height: 154)
        let succeeded = writeSnapshot(rendered, size: NSSize(width: 390, height: 154),
                                      to: arguments[ideaIndex + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if let ideaCardIndex = arguments.firstIndex(of: "--render-idea-card-preview"),
       arguments.indices.contains(ideaCardIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Idea-Card-Preview-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        store.language = arguments.contains("--english") ? .en : .zh
        store.appearance = arguments.contains("--dark") ? .dark : .light
        _ = store.addIdea("I want to eat")
        if let task = store.pending.first {
            if arguments.contains("--colored-type") {
                let ideaType = TaskTypeDefinition(name: "Personal", colorHex: 0xE8365F)
                _ = store.updateTaskTypes([ideaType])
                store.setTaskType(ideaType.id, for: task)
            }
            if let current = store.pending.first { store.place(current, lineX: 0.25) }
        }
        store.message = nil
        let state = DesktopState(); state.setRevealed(true)
        let rendered = DesktopLineView(store: store, state: state)
            .frame(width: 760, height: 304).background(Color.clear)
        let succeeded = writeSnapshot(rendered, size: NSSize(width: 760, height: 304),
                                      to: arguments[ideaCardIndex + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if let reminderIndex = arguments.firstIndex(where: {
        $0 == "--render-reminder-preview" || $0 == "--render-meeting-preview"
    }), arguments.indices.contains(reminderIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Reminder-Preview-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        store.language = arguments.contains("--english") ? .en : .zh
        store.appearance = arguments.contains("--dark") ? .dark : .light
        let rendered = ReminderCaptureView(
            store: store,
            onHang: { _, _, _ in true },
            onCancel: {},
            initialTitle: store.text("生活提醒", "Everyday reminder"),
            initialLink: ""
        ).frame(width: 440, height: 286)
        let succeeded = writeSnapshot(rendered, size: NSSize(width: 440, height: 286),
                                      to: arguments[reminderIndex + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if let editorIndex = arguments.firstIndex(of: "--render-reminder-editor-preview"),
       arguments.indices.contains(editorIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Reminder-Editor-Preview-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        store.language = arguments.contains("--english") ? .en : .zh
        store.appearance = arguments.contains("--dark") ? .dark : .light
        let task = HangingTask(title: store.text("准备下午的事情", "Prepare the afternoon task"))
        let rendered = ReminderEditorView(store: store, task: task)
            .frame(width: 440, height: 310)
        let succeeded = writeSnapshot(rendered, size: NSSize(width: 440, height: 310),
                                      to: arguments[editorIndex + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if let imageEditorIndex = arguments.firstIndex(of: "--render-image-editor-preview"),
       arguments.indices.contains(imageEditorIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Image-Editor-Preview-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        store.language = arguments.contains("--english") ? .en : .zh
        store.appearance = arguments.contains("--dark") ? .dark : .light
        let image = samplePreview(kind: "app", title: "DROPPED IMAGE", size: NSSize(width: 1200, height: 760))
            .flatMap(NSImage.init(data:)) ?? NSImage(size: NSSize(width: 1200, height: 760))
        store.importImage(image, title: store.text("拖入的图片", "Dropped image"))
        guard let task = store.pending.first else { exit(2) }
        let rendered = TaskEditor(store: store, task: task).frame(width: 540, height: 720)
        let succeeded = writeSnapshot(rendered, size: NSSize(width: 540, height: 720),
                                      to: arguments[imageEditorIndex + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if let spikeIndex = arguments.firstIndex(of: "--render-spike-preview"), arguments.indices.contains(spikeIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let (store, directory) = makePreviewStore()
        let image = ReceiptSpike3DView.previewImage(receipts: Array(store.spiked.prefix(10)),
                                                    highlighted: false, language: store.language,
                                                    appearance: store.appearance,
                                                    taskTypeColors: Dictionary(uniqueKeysWithValues:
                                                        store.taskTypes.map { ($0.id, $0.colorHex) }),
                                                    yaw: 1.15, pitch: -0.12)
        let succeeded: Bool
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            do {
                try png.write(to: URL(fileURLWithPath: arguments[spikeIndex + 1]), options: .atomic)
                succeeded = true
            } catch { succeeded = false }
        } else { succeeded = false }
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if let desktopIndex = arguments.firstIndex(of: "--render-desktop-preview"), arguments.indices.contains(desktopIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let (store, directory) = makePreviewStore()
        let state = DesktopState(); state.setRevealed(true)
        if arguments.contains("--drop-targeted") { state.setExternalDragTargeted(true) }
        let rendered = DesktopLineView(store: store, state: state)
            .frame(width: 1400, height: 304).background(Color.clear)
        let succeeded = writeSnapshot(rendered, size: NSSize(width: 1400, height: 304),
                                      to: arguments[desktopIndex + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if let settingsIndex = arguments.firstIndex(of: "--render-settings-preview"), arguments.indices.contains(settingsIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qizhi-Settings-Preview-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: directory)
        store.language = arguments.contains("--english") ? .en : .zh
        store.appearance = arguments.contains("--dark") ? .dark : .light
        store.updateWorkday(startMinute: 8 * 60, endMinute: 2 * 60, persist: false)
        _ = store.updateTaskTypes([
            TaskTypeDefinition(name: store.text("深度工作", "Deep work"), colorHex: 0x2F87E1),
            TaskTypeDefinition(name: store.text("个人", "Personal"), colorHex: 0xE8365F)
        ])
        let rendered = SettingsView(store: store).frame(width: 820, height: 700)
        let succeeded = writeSnapshot(rendered, size: NSSize(width: 820, height: 700),
                                      to: arguments[settingsIndex + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    if let mainIndex = arguments.firstIndex(of: "--render-main-preview"), arguments.indices.contains(mainIndex + 1) {
        app.setActivationPolicy(.prohibited)
        let (store, directory) = makePreviewStore()
        if arguments.contains("--completed") { store.destination = .completed }
        if arguments.contains("--spike") {
            store.destination = .spike
            let positions = [(-0.62, 1.05, -0.20), (0.52, 1.82, 0.18), (-0.18, 2.48, 0.31)]
            let scales = [0.72, 1.0, 1.35]
            for ((task, position), scale) in zip(zip(store.spiked.prefix(3), positions), scales) {
                _ = store.perform {
                    try $0.moveOnSpike(task.id, x: position.0, y: position.1, z: position.2)
                    try $0.resizeOnSpike(task.id, scale: scale)
                }
            }
        }
        if arguments.contains("--detached"), let task = store.spiked.first {
            _ = store.perform { try $0.setSpikeAttached(false, for: task.id) }
        }
        let rendered = MainView(store: store).frame(width: 1100, height: 720)
        let succeeded = writeSnapshot(rendered, size: NSSize(width: 1100, height: 720),
                                      to: arguments[mainIndex + 1])
        try? FileManager.default.removeItem(at: directory)
        exit(succeeded ? 0 : 2)
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
