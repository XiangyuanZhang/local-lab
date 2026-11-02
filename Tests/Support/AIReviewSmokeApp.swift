import SwiftUI
import AppKit

private final class SmokeKernel: KernelService {
    func connect(token: String) async throws -> ConnectionInfo { throw AIReviewError.network(0) }
    func execute(code: String, onEvent: @escaping @Sendable (KernelEvent) async -> Void) async throws {}
    func interrupt() async throws {}
    func disconnect() async throws {}
    func ownedKernelID() async -> String? { nil }
}

@main struct AIReviewSmokeApp: App {
    @NSApplicationDelegateAdaptor(SmokeDelegate.self) private var delegate
    @StateObject private var workspace: WorkspaceStore
    @StateObject private var background: BackgroundStore
    @StateObject private var appearance = AppearanceStore()
    @StateObject private var ai: AIReviewStore
    init() {
        guard let rootString = ProcessInfo.processInfo.environment["LOCAL_LAB_UI_ROOT"],
              let endpoint = ProcessInfo.processInfo.environment["LOCAL_LAB_UI_ENDPOINT"],
              (try? AIEndpoint(endpoint).base.host) == "127.0.0.1" else { fatalError("Loopback fixture configuration required") }
        let root = URL(fileURLWithPath: rootString)
        let ws = WorkspaceStore(service: SmokeKernel(), library: DraftLibrary(root: root.appendingPathComponent("Workspace")))
        let draft = ScriptDraft(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000010")!, name: "ai-demo.py", code: "print(1 / 0)\n")
        ws.drafts = [draft]; ws.selection = draft.id; ws.bottomPanel = .output
        if let scenario = ProcessInfo.processInfo.environment["LOCAL_LAB_UI_CASE"], ["layout", "markdown"].contains(scenario) {
            let long = ScriptDraft(name: "很长的文件名称_用于检查窗口收窄与标题截断_Unicode_测试.py", code: "# 中文、Unicode 与长行换行检查\n" + String(repeating: "print('Layout QA — 中文 1234567890') # trailing comment ", count: 12) + "\n" + (1...80).map { "value_\($0) = \($0)" }.joined(separator: "\n"))
            let md = ScriptDraft(name: "渲染检查.md", code: "# Markdown UI QA\n\n**粗体**、*斜体*、`code` 与中文。\n\n|项目|结果|\n|---|---|\n|表格|可读|\n\n```python\nprint('中文渲染')\n```\n\n> 引用区块\n\n- 列表第一项\n- 列表第二项\n")
            ws.drafts += [long, md]
            ws.selection = scenario == "markdown" ? md.id : long.id
            ws.outputs[long.id] = [OutputItem(text: "UI fixture stdout: 中文 Unicode ✓\n"), OutputItem(text: "UI fixture error: division by zero\n", isError: true)]
            ws.runStates[long.id] = "執行失敗（UI fixture）"
            let entries = [RemoteEntry(name: "测试文件夹", path: "测试文件夹", type: "directory", writable: true, lastModified: "2026-11-02T12:00:00Z", size: nil), RemoteEntry(name: "长名称远端文件_Unicode_测试.md", path: "长名称远端文件_Unicode_测试.md", type: "file", writable: true, lastModified: "2026-11-02T12:00:00Z", size: 128)]
            ws.remoteEntries = entries; ws.directoryCache[""] = entries
        }

        _workspace = StateObject(wrappedValue: ws)
        _background = StateObject(wrappedValue: BackgroundStore(directory: root.appendingPathComponent("Background")))
        let repo = AIReviewRepository(directory: root.appendingPathComponent("AIReview"))
        if !FileManager.default.fileExists(atPath: repo.directory.appendingPathComponent("settings.json").path) {
            var config = AIReviewConfiguration(); config.baseURL = endpoint; config.model = "review-fixture"
            try! repo.save(config)
        }
        let store = AIReviewStore(repository: repo); store.panelVisible = true
        _ai = StateObject(wrappedValue: store)
    }
    var body: some Scene {
        Window("AI Review Test", id: "ai-test") {
            ContentView(store: workspace, background: background).environmentObject(appearance).environmentObject(ai)
                .preferredColorScheme(ProcessInfo.processInfo.environment["LOCAL_LAB_UI_SCHEME"] == "light" ? .light : ProcessInfo.processInfo.environment["LOCAL_LAB_UI_SCHEME"] == "dark" ? .dark : nil)
        }.defaultSize(width: CGFloat(Double(ProcessInfo.processInfo.environment["LOCAL_LAB_UI_WIDTH"] ?? "") ?? 1200), height: CGFloat(Double(ProcessInfo.processInfo.environment["LOCAL_LAB_UI_HEIGHT"] ?? "") ?? 740))
        Settings { SettingsView(store: workspace).environmentObject(appearance).environmentObject(ai) }
    }
}
@MainActor private final class SmokeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
