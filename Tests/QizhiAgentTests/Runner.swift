import Foundation
import HangLaterCore

struct Failure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw Failure(message: message) }
}
func rejects(_ body: () throws -> Void) throws {
    var rejected = false
    do { try body() } catch { rejected = true }
    try expect(rejected, "Invalid operation was accepted")
}
func rejectsAsync(_ body: () async throws -> Void) async throws {
    var rejected = false
    do { try await body() } catch { rejected = true }
    try expect(rejected, "Invalid async operation was accepted")
}
func preparedRun() -> StudyRun {
    var run = StudyRun(goal: "Learn agent tools, recovery and evaluations", budget: 45, sources: StudySamples.sources, isDemo: true)
    run.documents = StudySamples.documents; run.drafts = StudySamples.drafts; run.status = .review
    return run
}
func readCall(_ id: UUID) -> AgentReply {
    AgentReply(message: AgentMessage(role: "assistant", calls: [AgentToolCall(name: "read_source", arguments: "{\"source_id\":\"\(id.uuidString)\"}")]))
}
func submit(_ cards: [ActionDraft]) throws -> AgentReply {
    struct Proposal: Encodable { var cards: [ActionDraft] }
    return AgentReply(message: AgentMessage(role: "assistant", calls: [AgentToolCall(name: "submit_cards", arguments: String(decoding: try JSONEncoder().encode(Proposal(cards: cards)), as: UTF8.self))]))
}
func normalReplies() throws -> [AgentReply] { StudySamples.sources.map { readCall($0.id) } + [try submit(StudySamples.drafts)] }

actor ScriptModel: PlanningModel {
    var responses: [AgentReply]
    var count = 0
    init(_ responses: [AgentReply]) { self.responses = responses }
    func reply(to messages: [AgentMessage]) async throws -> AgentReply {
        count += 1
        guard !responses.isEmpty else { throw Failure(message: "Fixture ran out of responses") }
        return responses.removeFirst()
    }
}
actor FixtureReader: StudyDocumentReading {
    var calls: [UUID] = []
    var failureID: UUID?
    init(failureID: UUID? = nil) { self.failureID = failureID }
    func read(_ source: StudySource) async throws -> StudyDocument {
        calls.append(source.id)
        if source.id == failureID { throw Failure(message: "Source unavailable") }
        return StudyDocument(source: source, passages: [EvidencePassage(id: "p1", text: source.note)])
    }
}
actor Snapshots {
    var values: [StudyRun] = []
    func add(_ value: StudyRun) { values.append(value) }
    var latest: StudyRun? { values.last }
}
struct SlowModel: PlanningModel {
    func reply(to messages: [AgentMessage]) async throws -> AgentReply {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return AgentReply(message: AgentMessage(role: "assistant"))
    }
}

@main struct QizhiAgentChecks {
    struct Result: Codable { var name: String; var passed: Bool; var detail: String; var seconds: Double }
    static func main() async {
        if let index = CommandLine.arguments.firstIndex(of: "--http-fixture"), CommandLine.arguments.indices.contains(index + 1) {
            do { try await httpFixture(CommandLine.arguments[index + 1]); exit(0) }
            catch { print("FAIL HTTP fixture: \(error.localizedDescription)"); exit(1) }
        }
        var results: [Result] = []
        func check(_ name: String, _ body: (URL) async throws -> Void) async {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Qizhi-Agent-\(UUID().uuidString)")
            let started = Date()
            defer { try? FileManager.default.removeItem(at: folder) }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await body(folder)
                results.append(Result(name: name, passed: true, detail: "", seconds: Date().timeIntervalSince(started)))
                print("PASS: \(name)")
            } catch {
                results.append(Result(name: name, passed: false, detail: error.localizedDescription, seconds: Date().timeIntervalSince(started)))
                print("FAIL: \(name): \(error.localizedDescription)")
            }
        }
        await check("Three-source tool workflow stops for human review without writing tasks") { folder in
            let run = StudyRun(goal: "Make a concrete learning plan", budget: 45, sources: StudySamples.sources)
            let result = try await ActionAgent.run(run, model: ScriptModel(normalReplies()), reader: FixtureReader()) { _ in }
            try expect(result.status == .review && result.documents.count == 3 && result.drafts.count == 3, "Review state missing")
            try expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("tasks.json").path), "Unconfirmed task write")
        }
        let invalid: [(String, ([ActionDraft]) -> [ActionDraft])] = [
            ("Missing evidence is rejected", { var c = $0; c[0].citations = []; return c }),
            ("Unselected source citations are rejected", { var c = $0; c[0].citations[0].sourceID = UUID(); return c }),
            ("Unknown passage citations are rejected", { var c = $0; c[0].citations[0].passageID = "p999"; return c }),
            ("Fabricated quotations are rejected", { var c = $0; c[0].citations[0].quote = "This sentence never appeared in the source."; return c }),
            ("Meaninglessly short quotes are rejected", { var c = $0; c[0].citations[0].quote = "工具"; return c }),
            ("Plans beyond the time budget are rejected", { var c = $0; c[0].minutes = 100; return c }),
            ("Nonpositive durations are rejected", { var c = $0; c[0].minutes = 0; return c }),
            ("Empty titles are rejected", { var c = $0; c[0].title = " \n "; return c }),
            ("Empty expected outcomes are rejected", { var c = $0; c[0].outcome = ""; return c }),
            ("More than six cards are rejected", { $0 + $0 + [$0[0]] }),
            ("Repeated card IDs are rejected", { [$0[0], $0[0], $0[2]] }),
            ("Omitting a selected source is rejected", { Array($0.prefix(2)) }),
            ("Empty plans are rejected", { _ in [] })
        ]
        for (name, transform) in invalid {
            await check(name) { _ in
                try rejects { try ActionValidation.validate(transform(StudySamples.drafts), documents: StudySamples.documents, budget: 45) }
            }
        }
        await check("Whitespace-only citation normalization preserves verifiable quotations") { _ in
            var docs = StudySamples.documents
            let original = docs[0].passages[0].text
            docs[0] = StudyDocument(source: docs[0].source, passages: [EvidencePassage(id: "p1", text: " \n" + original + "\n ")])
            try ActionValidation.validate(StudySamples.drafts, documents: docs, budget: 45)
        }
        await check("Confirmed cards retain provenance and outcomes after restart") { folder in
            let run = preparedRun(), repository = try TaskRepository(directory: folder)
            try expect(try repository.applyActionPlan(run, cards: run.drafts) == 3, "Wrong batch size")
            let restored = try TaskRepository(directory: folder)
            try expect(restored.tasks.map(\.id) == run.drafts.map(\.id), "Card order or IDs changed")
            try expect(restored.tasks.first?.actionOrigin?.citations.first?.fingerprint == run.documents.first?.fingerprint, "Provenance lost")
        }
        await check("Replay after completion preserves edits without duplicating tasks") { folder in
            let run = preparedRun(), repo = try TaskRepository(directory: folder)
            try repo.applyActionPlan(run, cards: run.drafts)
            var edited = repo.tasks[0]; edited.title = "My edited task"; try repo.update(edited)
            try repo.complete(edited.id)
            try expect(try repo.applyActionPlan(run, cards: run.drafts) == 0, "Replay added tasks")
            try expect(repo.tasks.count == 3 && repo.tasks[0].title == "My edited task" && repo.tasks[0].isCompleted, "Replay overwrote user edits")
        }
        await check("Legacy tasks without action metadata still decode") { folder in
            let repo = try TaskRepository(directory: folder)
            _ = try repo.add(title: "Existing task")
            let restored = try TaskRepository(directory: folder)
            try expect(restored.tasks.count == 1 && restored.tasks[0].actionOrigin == nil, "Legacy decoding failed")
        }
        await check("A bad second draft causes zero partial writes") { folder in
            let repo = try TaskRepository(directory: folder); _ = try repo.add(title: "Keep this")
            let original = try Data(contentsOf: repo.dataFile)
            var run = preparedRun(); run.drafts[1].citations[0].quote = "A forged quote that should fail validation."
            try rejects { try repo.applyActionPlan(run, cards: run.drafts) }
            try expect(try Data(contentsOf: repo.dataFile) == original && repo.tasks.count == 1, "Partial batch was written")
        }
        await check("Atomic write failure preserves the existing in-memory tasks") { folder in
            let repo = try TaskRepository(directory: folder); _ = try repo.add(title: "Keep this")
            let before = repo.tasks
            try FileManager.default.removeItem(at: repo.dataFile)
            try FileManager.default.createDirectory(at: repo.dataFile, withIntermediateDirectories: false)
            let run = preparedRun()
            try rejects { try repo.applyActionPlan(run, cards: run.drafts) }
            try expect(repo.tasks == before, "Failed disk write mutated memory")
        }
        await check("An unrelated task ID collision never overwrites data") { folder in
            let repo = try TaskRepository(directory: folder); let existing = try repo.add(title: "Unrelated")
            var run = preparedRun(); run.drafts[1].id = existing.id
            try rejects { try repo.applyActionPlan(run, cards: run.drafts) }
            try expect(repo.tasks == [existing], "Collision caused a partial write")
        }
        await check("App restart pauses an in-flight run with its source checkpoints intact") { folder in
            let journal = try StudyRunStore(directory: folder)
            var run = preparedRun(); run.status = .running
            try journal.upsert(run)
            let reopened = try StudyRunStore(directory: folder)
            try expect(reopened.runs[0].status == .interrupted && reopened.runs[0].documents == run.documents, "Restart lost checkpoints")
        }
        await check("Corrupt journals are preserved instead of silently reset") { folder in
            let journal = try StudyRunStore(directory: folder)
            let corrupt = Data("not a journal".utf8); try corrupt.write(to: journal.file)
            try rejects { _ = try StudyRunStore(directory: folder) }
            try expect(try Data(contentsOf: journal.file) == corrupt, "Corrupt journal was overwritten")
        }
        await check("Retry uses frozen source snapshots without fetching them again") { _ in
            var run = preparedRun(); run.status = .interrupted
            let reader = FixtureReader(failureID: StudySamples.sources[0].id)
            let result = try await ActionAgent.run(run, model: ScriptModel(normalReplies()), reader: reader) { _ in }
            let calls = await reader.calls
            try expect(result.status == .review && calls.isEmpty, "Retry unnecessarily refetched documents")
        }
        await check("A failed source read keeps the last successful checkpoint") { _ in
            let snapshots = Snapshots()
            let run = StudyRun(goal: "Learn", budget: 45, sources: StudySamples.sources)
            try await rejectsAsync {
                _ = try await ActionAgent.run(run, model: ScriptModel(normalReplies()), reader: FixtureReader(failureID: StudySamples.sources[1].id)) { await snapshots.add($0) }
            }
            let latest = await snapshots.latest
            try expect(latest?.documents.count == 1 && latest?.drafts.isEmpty == true, "Partial source progress lost")
        }
        await check("Cancelling a waiting model never produces review cards") { _ in
            let snapshots = Snapshots()
            let run = StudyRun(goal: "Learn", budget: 45, sources: StudySamples.sources)
            let worker = Task { try await ActionAgent.run(run, model: SlowModel(), reader: FixtureReader()) { await snapshots.add($0) } }
            try await Task.sleep(nanoseconds: 15_000_000); worker.cancel()
            var cancelled = false
            do { _ = try await worker.value } catch is CancellationError { cancelled = true }
            try expect(cancelled, "Cancellation was swallowed")
            let latest = await snapshots.latest
            try expect(latest?.status != .review, "Cancelled result was accepted")
        }
        await check("Premature submission is rejected and repaired through tool feedback") { _ in
            let replies = [try submit(StudySamples.drafts)] + (try normalReplies())
            let run = StudyRun(goal: "Learn", budget: 45, sources: StudySamples.sources)
            let result = try await ActionAgent.run(run, model: ScriptModel(replies), reader: FixtureReader()) { _ in }
            try expect(result.status == .review && result.events.contains { $0.kind == "validation" }, "Premature plan bypassed validation")
        }
        await check("A fabricated quote can be repaired before human review") { _ in
            var bad = StudySamples.drafts; bad[0].citations[0].quote = "Invented evidence should not pass the validator."
            let replies = StudySamples.sources.map { readCall($0.id) } + [try submit(bad), try submit(StudySamples.drafts)]
            let result = try await ActionAgent.run(StudyRun(goal: "Learn", budget: 45, sources: StudySamples.sources), model: ScriptModel(replies), reader: FixtureReader()) { _ in }
            try expect(result.status == .review && result.events.filter { $0.kind == "validation" }.count == 1, "Invalid evidence reached review")
        }
        await check("Injected unknown tools have no executor and cannot write tasks") { folder in
            let injected = AgentReply(message: AgentMessage(role: "assistant", calls: [AgentToolCall(name: "delete_all_tasks", arguments: "{}")]))
            let replies = [injected] + (try normalReplies())
            let result = try await ActionAgent.run(StudyRun(goal: "Learn", budget: 45, sources: StudySamples.sources), model: ScriptModel(replies), reader: FixtureReader()) { _ in }
            try expect(result.events.contains { $0.kind == "blocked" }, "Unknown tool was not blocked")
            try expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("tasks.json").path), "Tool escaped into the task store")
        }
        await check("Unselected read requests never reach the document reader") { _ in
            let reader = FixtureReader()
            let replies = [readCall(UUID())] + (try normalReplies())
            let result = try await ActionAgent.run(StudyRun(goal: "Learn", budget: 45, sources: StudySamples.sources), model: ScriptModel(replies), reader: reader) { _ in }
            let calls = await reader.calls
            try expect(calls.count == 3 && result.events.contains { $0.kind == "blocked" }, "Unselected data was read")
        }
        await check("Unproductive agents stop at the turn bound") { _ in
            let call = AgentReply(message: AgentMessage(role: "assistant", calls: [AgentToolCall(name: "unknown", arguments: "{}")]))
            let model = ScriptModel(Array(repeating: call, count: 12))
            try await rejectsAsync { _ = try await ActionAgent.run(StudyRun(goal: "Learn", budget: 45, sources: StudySamples.sources), model: model, reader: FixtureReader()) { _ in } }
            let count = await model.count
            try expect(count == 8, "Round bound did not stop the agent")
        }
        await check("A review-checkpoint disk failure propagates instead of reporting success") { _ in
            var failed = false
            do {
                _ = try await ActionAgent.run(StudyRun(goal: "Learn", budget: 45, sources: StudySamples.sources), model: ScriptModel(normalReplies()), reader: FixtureReader()) { run in
                    if run.status == .review { throw Failure(message: "Journal disk full") }
                }
            } catch let error as Failure { failed = error.message == "Journal disk full" }
            try expect(failed, "Checkpoint failure was swallowed as a model validation issue")
        }
        await check("Provider credentials cannot be embedded in URLs or sent over public HTTP") { _ in
            for endpoint in ["http://example.com/v1/chat/completions", "https://user:secret@example.com/", "https://example.com/?key=secret", "file:///tmp/key"] {
                try rejects { _ = try PlanningConfiguration(endpoint: endpoint, model: "fixture").validatedURL() }
            }
            _ = try PlanningConfiguration(endpoint: "http://127.0.0.1:8080/chat/completions", model: "fixture").validatedURL()
        }
        let failures = results.filter { !$0.passed }.count
        print("\(results.count - failures) passed, \(failures) failed — deterministic fixture checks, not a live-model quality score")
        if let i = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.indices.contains(i + 1) {
            struct Report: Codable { var kind: String; var modelCalls: String; var results: [Result] }
            let report = Report(kind: "deterministic regression fixtures", modelCalls: "No real provider calls; this is not a model quality benchmark", results: results)
            do { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; try e.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
            catch { print("Could not write report: \(error.localizedDescription)"); exit(1) }
        }
        exit(failures == 0 ? 0 : 1)
    }

    static func httpFixture(_ endpoint: String) async throws {
        let config = PlanningConfiguration(endpoint: endpoint, model: "fixture-model")
        let model = CompatiblePlanningModel(configuration: config, key: "qizhi-fixture-key-not-a-secret")
        let result = try await ActionAgent.run(StudyRun(goal: "Learn agent engineering", budget: 45, sources: StudySamples.sources), model: model, reader: FixtureReader()) { _ in }
        try expect(result.status == .review && result.drafts.count == 3, "HTTP workflow did not reach review")
        try expect(result.inputTokens > 0 && result.outputTokens > 0, "Provider usage was not recorded")
        print("PASS: real HTTP adapter, tool messages, evidence validation and provider usage (local fixture)")
    }
}
