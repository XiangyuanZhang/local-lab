import SwiftUI

@MainActor
final class AIReviewStore: ObservableObject {
    @Published private(set) var configuration: AIReviewConfiguration
    @Published private(set) var hasSavedKey = false
    @Published private(set) var isRunning = false
    @Published private(set) var result: AIReviewResult?
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var lastApplied: AIReviewResult?
    @Published var panelVisible = false
    @Published var showSettings = false
    @Published var instruction = ""
    let repository: AIReviewRepository
    private let service: AIReviewService
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(repository: AIReviewRepository = AIReviewRepository(), service: AIReviewService = AIReviewClient()) {
        self.repository = repository; self.service = service
        do { configuration = try repository.load() }
        catch { configuration = AIReviewConfiguration(); self.error = AIReviewError.storage.localizedDescription }
        refreshKeyState()
    }
    func save(_ settings: AIReviewConfiguration, newKey: String = "") throws {
        let valid = try settings.validated()
        if !newKey.isEmpty { try repository.saveKey(newKey, for: valid.baseURL) }
        try repository.save(valid)
        configuration = valid; error = nil; notice = "AI 設定已儲存在本機"
        refreshKeyState()
    }
    func selectMode(_ mode: AIReviewMode) {
        var next = configuration; next.mode = mode
        do { try save(next) } catch { self.error = safe(error) }
    }
    func selectPersona(_ id: UUID) {
        var next = configuration; next.selectedPersonaID = id
        do { try save(next) } catch { self.error = safe(error) }
    }
    func hasKey(for endpoint: String) -> Bool { (try? repository.key(for: endpoint)) != nil }
    func removeKey(for endpoint: String) throws {
        try repository.removeKey(for: endpoint)
        refreshKeyState(); notice = "已移除此接口的 API Key"
    }
    func start(draft: ScriptDraft?) {
        guard !isRunning else { return }
        guard let draft, !draft.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = AIReviewError.emptyCode.localizedDescription; return }
        do {
            let config = try configuration.validated()
            guard let key = try repository.key(for: config.baseURL), !key.isEmpty else {
                error = AIReviewError.missingKey.localizedDescription; showSettings = true; return
            }
            let request = AIReviewRequest(snapshot: AIReviewSnapshot(draft), persona: config.selectedPersona, mode: config.mode, instruction: instruction)
            // Validate before allocating or sending a network task.
            _ = try AIReviewPrompt.body(request, configuration: config)
            let id = UUID(); generation = id; isRunning = true; error = nil; notice = nil; result = nil
            let client = service
            task = Task { [weak self] in
                do {
                    let response = try await client.review(request, configuration: config, key: key)
                    try Task.checkCancellation()
                    guard let self, generation == id else { return }
                    result = AIReviewResult(request: request, response: response, model: config.model,
                                            provider: try AIEndpoint(config.baseURL).base.host ?? "AI")
                    notice = request.mode == .reviewOnly ? "審碼完成 · 未更改檔案" : "修改建議已就緒 · 尚未套用"
                } catch is CancellationError {
                    guard let self, generation == id else { return }
                    notice = "已取消"
                } catch {
                    guard let self, generation == id else { return }
                    self.error = safe(error)
                }
                guard let self, generation == id else { return }
                isRunning = false; task = nil
            }
        } catch { self.error = safe(error) }
    }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil; isRunning = false; notice = "已取消"; error = nil
    }
    func apply(_ value: AIReviewResult, to workspace: WorkspaceStore) -> Bool {
        // Switching back to review-only disables applying even an older edit result.
        guard configuration.mode == .edit else { error = AIReviewError.reviewOnly.localizedDescription; return false }
        do {
            try workspace.applyAIProposal(value)
            lastApplied = value; notice = "已套用至本機編輯器；遠端檔案需另外儲存"; error = nil
            return true
        } catch { self.error = safe(error); return false }
    }
    func undo(in workspace: WorkspaceStore) {
        guard let lastApplied else { return }
        do {
            try workspace.undoAIProposal(lastApplied)
            self.lastApplied = nil; notice = "已還原套用前的內容"; error = nil
        } catch { self.error = safe(error) }
    }
    func dismissError() { error = nil }
    private func refreshKeyState() { hasSavedKey = hasKey(for: configuration.baseURL) }
    private func safe(_ error: Error) -> String {
        // Never display provider response bodies, URLs, credentials or underlying network diagnostics.
        if let error = error as? AIReviewError { return error.localizedDescription }
        return AIReviewError.storage.localizedDescription
    }
}
