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
        }.defaultSize(width: 1200, height: 740)
        Settings { SettingsView(store: workspace).environmentObject(appearance).environmentObject(ai) }
    }
}
@MainActor private final class SmokeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
