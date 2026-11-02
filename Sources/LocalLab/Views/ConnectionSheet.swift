import SwiftUI

struct ConnectionSheet: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @FocusState private var focused: Bool

    private var builtIn: Bool { store.hasBuiltInToken }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "network").font(.system(size: 32, weight: .light)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.isReady ? "遠端核心已連線" : "連線到 TUM Python").font(.title2.weight(.semibold))
                    Text(builtIn ? "這個版本已內建 API token，直接建立專用工作階段。" : "用你的個人 API token 建立專用工作階段。").foregroundStyle(.secondary).font(.callout)
                }
            }
            Form {
                LabeledContent("伺服器", value: "lecture.cs.tum.de:9000")
                LabeledContent("帳號", value: "go97lep")
                if let info = store.connection {
                    LabeledContent("核心", value: info.displayName)
                    LabeledContent("專用核心 ID") { Text(info.kernel.id).font(.caption.monospaced()).textSelection(.enabled) }
                }
                if !store.isReady {
                    if builtIn {
                        LabeledContent("憑證", value: "已內建（不經鑰匙圈）")
                    } else {
                        SecureField("API token", text: $token).focused($focused).textContentType(.password)
                        Toggle("保存在本機檔案", isOn: $store.rememberToken)
                        Text("Token 以 0600 權限保存在 Application Support，可在設定中移除；到期後需更新。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped)
            if !store.isReady && !builtIn {
                VStack(alignment: .leading, spacing: 8) {
                    Text("建議權限").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text("access:servers!server=go97lep/").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Link("開啟 JupyterHub token 管理頁", destination: URL(string: "https://lecture.cs.tum.de:9000/hub/token")!)
                }
            }
            if let error = store.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if store.connecting { ProgressView().controlSize(.small); Text("正在建立專用核心…").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(store.isReady ? "完成" : "取消") { token = ""; dismiss() }.keyboardShortcut(.cancelAction).disabled(store.connecting)
                if !store.isReady {
                    if builtIn {
                        Button("連線") {
                            Task { if await store.connectUsingSavedToken() { dismiss() } }
                        }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(store.connecting)
                    } else {
                        Button("修復鑰匙圈授權") { Task { if await store.repairKeychainAccess() { dismiss() } } }.disabled(store.connecting || store.repairingKeychain)
                        if store.hasSavedToken {
                            Button("使用已儲存 token") { Task { if await store.connectUsingSavedToken() { dismiss() } } }.disabled(store.connecting)
                        }
                        Button("連線") {
                            Task {
                                let credential = token; token = ""
                                if await store.connect(token: credential) { dismiss() }
                            }
                        }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.connecting)
                    }
                }
            }
        }.padding(28).frame(width: 530).onAppear { if builtIn { focused = false } else { focused = true } }.onDisappear { token = "" }
    }
}
