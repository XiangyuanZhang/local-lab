import SwiftUI
struct SettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @AppStorage("autoConnect") private var autoConnect = true
    @AppStorage("localPythonExecutable") private var python = ""
    @AppStorage("localWorkspace") private var workspace = ""
    @AppStorage("editorFontSize") private var fontSize = 14.0
    @AppStorage("auroraMotion") private var auroraMotion = true
    var body: some View {
        Form {
            Section("背景與動效") {
                Button("更换背景…") { store.showBackgroundEditor = true }
                Toggle("極光背景緩慢流動", isOn: $auroraMotion)
                Text("未設定背景圖片時顯示極光背景。系統開啟「減少動態效果」或視窗不在前景時會自動停止流動。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("編輯器") {
                Stepper("字體大小：\(Int(fontSize)) pt", value: $fontSize, in: 11...24)
                Text("草稿自動保存於本機。遠端程式只有在按下「執行」後才會送出。").font(.caption).foregroundStyle(.secondary)
            }
            Section("本機執行") {
                Text("先使用與伺服器完全相同的 Python 版本在本機執行，成功後才送至伺服器覆核。")
                TextField("Python 執行檔（留空自動準備）", text: $python)
                TextField("本機工作目錄（留空使用 App 工作區）", text: $workspace)
                Text("Python：\(store.connection?.pythonVersion ?? "待連線核對")。套件需另行安裝；兩次執行各自使用自己的檔案與環境。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("連線") {
                Toggle("啟動時使用已儲存 token 自動連線", isOn: $autoConnect)
                Text(store.hasSavedToken ? "Token 已安全保存在本機 macOS 鑰匙圈。" : "目前沒有已保存的 token。").font(.caption).foregroundStyle(.secondary)
                Button("修復鑰匙圈授權") { Task { _ = await store.repairKeychainAccess() } }.disabled(store.repairingKeychain || store.busy)
                Button("移除已儲存 token") { store.forgetSavedToken() }.disabled(!store.hasSavedToken)
                Text("結束 App 時會嘗試關閉專用核心。移除 token 不會撤銷伺服器端的 token。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding().frame(width: 440, height: 570)
    }
}
