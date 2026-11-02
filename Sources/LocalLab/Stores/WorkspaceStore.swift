import SwiftUI

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var drafts: [ScriptDraft]
    @Published var selection: UUID?
    @Published var connection: ConnectionInfo?
    @Published var connecting = false
    @Published var closing = false
    @Published var runningID: UUID?
    @Published var outputs: [UUID: [OutputItem]] = [:]
    @Published var runStates: [UUID: String] = [:]
    @Published var durations: [UUID: Double] = [:]
    @Published var error: String?
    static let remoteBrowserID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    @Published var remoteDirectoryPath = ""
    @Published var remoteEntries: [RemoteEntry] = []
    @Published var directoryCache: [String: [RemoteEntry]] = [:]
    @Published var expandedRemoteFolders: Set<String> = []
    @Published var loadingRemoteFolders: Set<String> = []
    @Published var fileBusy = false
    @Published var lastSynced: Date?
    @Published var conflicts: [UUID: RemoteTextFile] = [:]
    @Published var syncNotice: String?
    @Published var saveRemotePresented = false
    @Published var createFolderPresented = false
    @Published var createFilePresented = false
    var syncTask: Task<Void, Never>?
    let remoteFiles: RemoteFileService?
    @Published var bottomPanel: BottomPanel = .local
    @Published var terminalOutput: [TerminalLocation: String] = [:]
    @Published var terminalStates: [TerminalLocation: String] = [:]
    @Published var terminalBusy: Set<TerminalLocation> = []
    var terminals: [TerminalLocation: ShellTerminal] = [:]
    @Published var verifying = false
    @Published var hasSavedToken = false
    @Published var repairingKeychain = false
    @Published var rememberToken = true
    private let vault: TokenVault?
    private var attemptedRestore = false
    @Published var showConnection = false
    @Published var showBackgroundEditor = false
    @Published var isReady = false
    let localPython: LocalPythonService
    let service: KernelService
    private let library: DraftLibrary
    private var runTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var outputSize = 0
    private var outputTruncated = false

    init(service: KernelService, library: DraftLibrary = DraftLibrary(), vault: TokenVault? = nil, localPython: LocalPythonService = LocalPythonRunner()) {
        self.localPython = localPython; self.service = service; self.library = library; self.remoteFiles = service as? RemoteFileService; self.vault = vault
        drafts = library.load(); selection = drafts.first?.id
    }
    convenience init() { self.init(service: JupyterClient(), library: DraftLibrary(), vault: KeychainTokenVault()) }
    func runLiveVerification() {
        guard isReady, !verifying, let client = service as? JupyterClient else { return }
        verifying = true
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("work").path) else {
            verifying = false; error = "找不到功能檢查使用的本機工作區。"; return
        }
        try? FileManager.default.removeItem(at: root.appendingPathComponent("work/live-ui-done.flag"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("work/live-test-ready.json"))
        syncNotice = "正在執行隔離功能檢查…"
        Task {
            let report = await client.runLiveVerification(root: root)
            verifying = false; syncNotice = "功能檢查完成：\(report.lastPathComponent)"
        }
    }
    func restoreSavedConnection() async {
        guard !attemptedRestore else { return }; attemptedRestore = true
        do {
            guard let saved = try vault?.read(), !saved.isEmpty else { return }
            hasSavedToken = true
            if (UserDefaults.standard.object(forKey: "autoConnect") as? Bool) ?? true { _ = await connect(token: saved, saveCredential: false) }
        } catch { self.error = safeError(error) }
    }
    func connectUsingSavedToken() async -> Bool {
        do {
            guard let token = try vault?.read(), !token.isEmpty else { error = "鑰匙圈中沒有可用的 token。"; return false }
            return await connect(token: token, saveCredential: false)
        } catch { self.error = safeError(error); return false }
    }
    func repairKeychainAccess() async -> Bool {
        guard !repairingKeychain, !busy, runningID == nil else { return false }
        repairingKeychain = true; defer { repairingKeychain = false }
        do {
            let vault = self.vault
            guard let token = try await Task.detached(priority: .userInitiated, operation: { try vault?.repairAccess() }).value else { error = "Keychain OSStatus -25300"; return false }
            hasSavedToken = true; error = nil; syncNotice = "鑰匙圈授權已修復"
            if !isReady { return await connect(token: token, saveCredential: false) }
            return true
        } catch { self.error = safeError(error); return false }
    }
    func forgetSavedToken() {
        do { try vault?.remove(); hasSavedToken = false; syncNotice = "已移除鑰匙圈中的 token。" }
        catch { self.error = safeError(error) }
    }
    var selected: ScriptDraft? { drafts.first(where: { $0.id == selection }) }
    var busy: Bool { connecting || closing }
    var canRun: Bool { (selected?.name.lowercased().hasSuffix(".py") ?? false) && isReady && !busy && runningID == nil && !(selected?.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    var status: String {
        if connecting { return "正在連線…" }
        if closing { return "正在關閉核心…" }
        if runningID != nil { return "執行中" }
        return isReady ? "核心就緒" : "尚未連線"
    }
    func updateCode(_ code: String) {
        guard let index = drafts.firstIndex(where: { $0.id == selection }) else { return }
        drafts[index].code = code
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            persist()
        }
    }
    func persist() { do { try library.save(drafts) } catch { self.error = "無法保存本機草稿：\(error.localizedDescription)" } }
    func newScript() {
        var n = drafts.count + 1
        while drafts.contains(where: { $0.name == "scratch-\(n).py" }) { n += 1 }
        let draft = ScriptDraft(name: "scratch-\(n).py", code: "# 新的 Python 草稿\n")
        drafts.append(draft); selection = draft.id; persist()
    }
    func importScript(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 1_048_576, let code = String(data: data, encoding: .utf8) else { throw LabError.message("請選擇小於 1 MB 的 UTF-8 文字檔案。") }
            let draft = ScriptDraft(name: url.lastPathComponent, code: code)
            drafts.append(draft); selection = draft.id; persist()
        } catch { self.error = error.localizedDescription }
    }
    func connect(token: String, saveCredential: Bool = true) async -> Bool {
        guard !busy, runningID == nil else { return false }
        connecting = true; error = nil; isReady = false
        defer { connecting = false }
        do {
            connection = try await service.connect(token: token); isReady = true
            await refreshRemote()
            startSyncing()
            if saveCredential, rememberToken, let vault {
                do { try vault.save(token.trimmingCharacters(in: .whitespacesAndNewlines)); hasSavedToken = true }
                catch { self.error = "已連線，但 token 尚未保存。\n" + safeError(error) }
            }
            return true
        }
        catch { self.error = safeError(error); return false }
    }
    func run() {
        guard canRun, let draft = selected else { return }
        bottomPanel = .output
        outputs[draft.id] = []; runStates[draft.id] = "本機執行中"; runningID = draft.id
        outputSize = 0; outputTruncated = false; error = nil
        runTask = Task { [weak self] in
            guard let self else { return }
            let start = Date()
            do {
                guard let version = connection?.pythonVersion, !version.isEmpty else { throw LabError.message("未取得伺服器 Python 版本；已停止，未送出程式。") }
                let localOK = try await localPython.run(code: draft.code, name: draft.name, version: version) { [weak self] text, isError in
                    await self?.consume(.text(text, isError: isError), id: draft.id)
                }
                try Task.checkCancellation()
                guard localOK else { runStates[draft.id] = "本機錯誤 · 未送出"; durations[draft.id] = Date().timeIntervalSince(start); runningID = nil; return }
                runStates[draft.id] = "伺服器覆核中"
                consume(.text("\n本機成功 → 伺服器覆核\n", isError: false), id: draft.id)
                try await service.execute(code: draft.code) { [weak self] event in
                    await self?.consume(event, id: draft.id)
                }
            } catch {
                if !Task.isCancelled && !closing {
                    self.error = safeError(error); runStates[draft.id] = runStates[draft.id] == "本機執行中" ? "本機環境錯誤 · 未送出" : "連線中斷"
                    if runStates[draft.id] == "連線中斷" { isReady = false }
                }
            }
            durations[draft.id] = Date().timeIntervalSince(start)
            if runningID == draft.id { runningID = nil }
        }
    }
    private func consume(_ event: KernelEvent, id: UUID) {
        guard !closing else { return }
        switch event {
        case .completed(let success): runStates[id] = success ? "本機與伺服器通過" : "伺服器覆核失敗"
        case .clear: outputs[id] = []; outputSize = 0; outputTruncated = false
        case .text(let text, let isError):
            guard outputSize < 1_048_576 else { truncate(id); return }
            let clipped = String(text.prefix(1_048_576 - outputSize)); outputSize += clipped.utf8.count
            var items = outputs[id] ?? []
            if let last = items.last, last.text != nil, last.isError == isError { items[items.count - 1].text! += clipped }
            else { items.append(OutputItem(text: clipped, isError: isError)) }
            outputs[id] = items
        case .image(let data):
            guard outputSize + data.count < 8_388_608, (outputs[id]?.count ?? 0) < 100 else { truncate(id); return }
            outputSize += data.count; outputs[id, default: []].append(OutputItem(image: data))
        }
    }
    private func truncate(_ id: UUID) {
        if !outputTruncated { outputs[id, default: []].append(OutputItem(text: "\n輸出已達顯示上限；核心仍會繼續執行。\n", isError: true)); outputTruncated = true }
    }
    func interrupt() {
        guard let id = runningID else { return }
        if runStates[id] == "本機執行中" { runTask?.cancel(); Task { await localPython.interrupt() }; runStates[id] = "已中斷 · 未送出" }
        else { Task { do { try await service.interrupt() } catch { self.error = safeError(error) } } }
    }
    func disconnect() async -> Bool {
        guard !connecting, !closing else { return false }
        closing = true; isReady = false; defer { closing = false }
        runTask?.cancel(); syncTask?.cancel(); syncTask = nil
        do {
            try await closeTerminals()
            await localPython.interrupt()
            try await service.disconnect()
            if let id = runningID { runStates[id] = "已停止" }
            runningID = nil; connection = nil; return true
        } catch {
            let id = await service.ownedKernelID() ?? "未知"
            self.error = "專用核心的清理尚未確認（\(id)）。請重新輸入有效 token 連線以重試。\n\(safeError(error))"
            return false
        }
    }
    func clearOutput() { if let selection { outputs[selection] = []; runStates[selection] = nil; durations[selection] = nil } }
    func safeError(_ error: Error) -> String {
        if let error = error as? LabError { return error.localizedDescription }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "連線逾時。請檢查 VPN 與遠端伺服器。"
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed: return "TLS 憑證驗證失敗；請檢查系統信任設定。"
            default: return "網路連線失敗（\(error.code.rawValue)）。請確認 VPN 與 JupyterLab 仍可開啟。"
            }
        }
        let diagnostic = error as NSError
        return "連線操作失敗（\(diagnostic.domain)，\(diagnostic.code)）。請重新連線並重試。"
    }
}
