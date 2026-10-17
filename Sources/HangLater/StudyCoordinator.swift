import Foundation
import Combine
import Security
import HangLaterCore

enum StudyKeychain {
    private static func query(_ endpoint: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: AppIdentity.bundleIdentifier + ".action-studio",
         kSecAttrAccount as String: endpoint]
    }
    static func read(endpoint: String) throws -> String? {
        var request = query(endpoint)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ActionPlanError("无法读取钥匙串中的 API Key。 / Keychain access failed (\(status)).")
        }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String, endpoint: String) throws {
        let q = query(endpoint)
        let data = Data(key.utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw ActionPlanError("API Key 保存失败。 / Could not save API key.") }
        } else if status != errSecSuccess { throw ActionPlanError("API Key 更新失败。 / Could not update API key.") }
    }
    static func remove(endpoint: String) throws {
        let status = SecItemDelete(query(endpoint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ActionPlanError("无法删除 API Key。 / Could not remove API key.") }
    }
}

@MainActor
final class StudyCoordinator: ObservableObject {
    @Published var current: StudyRun?
    @Published private(set) var history: [StudyRun] = []
    @Published var selected = Set<UUID>()
    @Published var goal = "根据这些资料，按时间预算安排今天的学习计划，给出具体步骤和可检查的产出。"
    @Published var budget = 45
    @Published var configuration = PlanningConfiguration()
    @Published var showingConnection = false
    @Published var notice: String?
    @Published private(set) var storageError: String?
    private var journal: StudyRunStore?
    private var worker: Task<Void, Never>?
    private var draftSave: Task<Void, Never>?
    private var generation = UUID()
    private var startedAt = Date()
    private var elapsedBeforeAttempt: Double = 0
    private let configurationFile: URL

    init(directory: URL) {
        configurationFile = directory.appendingPathComponent("ActionStudio/model.json")
        do {
            journal = try StudyRunStore(directory: directory)
            history = journal?.runs ?? []; current = history.first
            if FileManager.default.fileExists(atPath: configurationFile.path) {
                configuration = try JSONDecoder().decode(PlanningConfiguration.self, from: Data(contentsOf: configurationFile))
            }
        } catch { storageError = error.localizedDescription }
    }
    var running: Bool { current?.status == .running }
    var canUseStorage: Bool { journal != nil && storageError == nil }

    func saveConnection(_ config: PlanningConfiguration, newKey: String) throws {
        var clean = config
        clean.endpoint = clean.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.model = clean.model.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try clean.validatedURL()
        guard canUseStorage else { throw ActionPlanError(storageError ?? "无法保存配置。") }
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.contains(where: { $0.isWhitespace }) else { throw ActionPlanError("API Key 中不能包含空白字符。 / Invalid API key whitespace.") }
        if !key.isEmpty { try StudyKeychain.save(key, endpoint: clean.endpoint) }
        try JSONEncoder().encode(clean).write(to: configurationFile, options: .atomic)
        configuration = clean
        notice = "模型连接已保存，API Key 留在本机钥匙串。 / Connection saved; key stays in Keychain."
    }

    func start(sources: [StudySource], demo: Bool = false) {
        guard !running, canUseStorage else { return }
        flushDrafts()
        if demo {
            launch(StudyRun(goal: "基于三份示例资料，安排 45 分钟学习 Agent 的工具、重试与评测。", budget: 45, sources: StudySamples.sources, isDemo: true))
        } else {
            launch(StudyRun(goal: goal, budget: budget, sources: sources))
        }
    }

    func retry() {
        guard var run = current, !running, [.failed, .cancelled, .interrupted].contains(run.status) else { return }
        run.status = .running; run.failure = nil
        run.record("retry", "从已保存的资料快照重新规划。 / Resuming from source snapshots.")
        launch(run)
    }

    func cancel() {
        worker?.cancel()
        guard var run = current, run.status == .running else { return }
        run.elapsedSeconds = elapsedBeforeAttempt + Date().timeIntervalSince(startedAt)
        run.status = .cancelled; run.record("cancelled", "你已取消本次规划，未创建任务。 / Cancelled without creating tasks.")
        persist(run)
    }

    func open(_ run: StudyRun) {
        guard !running else { return }
        flushDrafts(); current = history.first { $0.id == run.id } ?? run
    }

    func newPlan() {
        guard !running else { return }
        flushDrafts(); current = nil; notice = nil
    }

    func editCard(_ id: UUID, _ change: (inout ActionDraft) -> Void) {
        guard var run = current, run.status == .review,
              let index = run.drafts.firstIndex(where: { $0.id == id }) else { return }
        change(&run.drafts[index]); current = run
        draftSave?.cancel()
        draftSave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000); self?.flushDrafts() } catch { }
        }
    }
    func removeCard(_ id: UUID) {
        guard var run = current, run.status == .review else { return }
        run.drafts.removeAll { $0.id == id }; persist(run)
    }
    func moveCardUp(_ id: UUID) {
        guard var run = current, run.status == .review,
              let index = run.drafts.firstIndex(where: { $0.id == id }), index > 0 else { return }
        run.drafts.swapAt(index, index - 1); persist(run)
    }
    func flushDrafts() {
        draftSave?.cancel(); draftSave = nil
        if let run = current, run.status == .review { persist(run) }
    }

    private func launch(_ run: StudyRun) {
        draftSave?.cancel(); draftSave = nil
        let token = UUID(); generation = token
        startedAt = Date(); elapsedBeforeAttempt = run.elapsedSeconds
        guard persist(run) else { return }
        let config = configuration
        worker = Task { [weak self] in
            guard let self else { return }
            do {
                let model: any PlanningModel
                if run.isDemo { model = SamplePlanningModel() }
                else {
                    _ = try config.validatedURL()
                    guard let key = try StudyKeychain.read(endpoint: config.endpoint), !key.isEmpty else {
                        throw ActionPlanError("请先在“模型连接”中设置 API Key。离线样例无需配置。 / Configure an API key or try the offline sample.")
                    }
                    model = CompatiblePlanningModel(configuration: config, key: key)
                }
                _ = try await ActionAgent.run(run, model: model, reader: NativeStudyReader()) { [weak self] snapshot in
                    try await self?.checkpoint(snapshot, token: token)
                }
            } catch {
                if self.generation == token, var latest = self.current, latest.status == .running {
                    latest.elapsedSeconds = self.elapsedBeforeAttempt + Date().timeIntervalSince(self.startedAt)
                    latest.status = (error is CancellationError || Task.isCancelled) ? .cancelled : .failed
                    latest.failure = (error is CancellationError || Task.isCancelled) ? nil : Self.safeError(error)
                    latest.record(latest.status.rawValue, latest.failure ?? "已取消。 / Cancelled.")
                    self.persist(latest)
                }
            }
            if self.generation == token { self.worker = nil }
        }
    }

    private func checkpoint(_ snapshot: StudyRun, token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token, current?.id == snapshot.id, current?.status == .running else { throw CancellationError() }
        guard persist(snapshot) else { throw ActionPlanError(storageError ?? "无法保存进度。 / Could not save progress.") }
    }

    @discardableResult
    func persist(_ run: StudyRun) -> Bool {
        do {
            guard let journal else { throw ActionPlanError(storageError ?? "无法读取行动记录。 / Run storage unavailable.") }
            try journal.upsert(run)
            current = run; history = journal.runs
            return true
        } catch {
            storageError = error.localizedDescription
            var visible = run
            if run.status != .completed {
                visible.status = .failed
                visible.failure = "进度保存失败，原记录已保留。 / Checkpoint write failed; previous records were preserved."
            }
            current = visible
            return false
        }
    }

    static func safeError(_ error: Error) -> String {
        if let error = error as? ActionPlanError { return error.message }
        if let error = error as? URLError {
            return "网络连接失败（\(error.code.rawValue)），可重试；未创建任何任务。 / Network request failed; no tasks created."
        }
        return "资料读取或进度保存失败，请检查文件权限后重试。 / Source or checkpoint I/O failed."
    }
}
