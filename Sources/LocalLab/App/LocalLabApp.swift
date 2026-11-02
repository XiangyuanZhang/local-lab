import SwiftUI
import AppKit

@main
struct LocalLabApp: App {
    @NSApplicationDelegateAdaptor(LabDelegate.self) private var delegate
    @StateObject private var store = WorkspaceStore()
    @StateObject private var background = BackgroundStore()
    @StateObject private var appearance = AppearanceStore()
    @StateObject private var ai = AIReviewStore()
    var body: some Scene {
        Window("Local Lab", id: "workspace") {
            ContentView(store: store, background: background)
                .environmentObject(appearance)
                .environmentObject(ai)
                .onAppear { delegate.store = store; delegate.ai = ai }
                .task { await store.restoreSavedConnection() }
        }
        .defaultSize(width: 1080, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新增 Python 草稿") { store.newScript() }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .saveItem) {
                Button("儲存至遠端") {
                    if store.selected?.remotePath != nil { Task { await store.saveSelectedRemote() } }
                    else { store.saveRemotePresented = true }
                }.keyboardShortcut("s").disabled(!store.isReady || store.fileBusy || store.selected == nil)
            }
            CommandMenu("AI") {
                Button("AI 審碼面板") { ai.panelVisible.toggle() }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("API 與人格設定…") { ai.panelVisible = true; ai.showSettings = true }
                Divider()
                Button("僅審碼") { ai.selectMode(.reviewOnly) }
                Button("審碼並修改") { ai.selectMode(.edit) }
                Divider()
                Button("取消 AI 請求") { ai.cancel() }.disabled(!ai.isRunning)
            }
            CommandMenu("核心") {
                Button("連線…") { store.showConnection = true }.disabled(store.busy || store.runningID != nil)
                Button("執行程式") { store.run() }.keyboardShortcut(.return, modifiers: .command).disabled(!store.canRun)
                Button("中斷執行") { store.interrupt() }.keyboardShortcut(".", modifiers: .command).disabled(store.runningID == nil)
                Divider()
                Button("執行完整功能測試") { store.runLiveVerification() }.disabled(!store.isReady || store.verifying)
                Divider()
                Button("關閉專用核心") { Task { _ = await store.disconnect() } }.disabled(store.connection == nil || store.busy)
            }
        }
        Settings { SettingsView(store: store).environmentObject(appearance).environmentObject(ai) }
    }
}

@MainActor
final class LabDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkspaceStore?
    weak var ai: AIReviewStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        ai?.cancel()
        store.persist()
        if store.connecting || store.closing { store.error = "請等目前的連線操作完成，再結束 App。"; return .terminateCancel }
        Task {
            let clean = await store.disconnect()
            if clean { sender.reply(toApplicationShouldTerminate: true) }
            else {
                let alert = NSAlert()
                alert.messageText = "遠端核心尚未確認關閉"
                alert.informativeText = "可能是 token 到期或網路中斷。留在 App 可重新連線並重試清理；若仍要結束，請稍後在 JupyterLab 關閉 App 的專用核心。"
                alert.addButton(withTitle: "留在 App")
                alert.addButton(withTitle: "仍要結束")
                let reply = alert.runModal()
                sender.reply(toApplicationShouldTerminate: reply == .alertSecondButtonReturn)
            }
        }
        return .terminateLater
    }
}
