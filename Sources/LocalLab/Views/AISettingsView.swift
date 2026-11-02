import SwiftUI

struct AISettingsView: View {
    @ObservedObject var store: AIReviewStore
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AIReviewConfiguration
    @State private var key = ""
    @State private var error: String?
    @State private var keyRemoved = false
    init(store: AIReviewStore) { self.store = store; _draft = State(initialValue: store.configuration) }
    private var selectedIndex: Int { draft.personas.firstIndex { $0.id == draft.selectedPersonaID } ?? 0 }
    private var name: Binding<String> {
        Binding(get: { draft.personas[selectedIndex].name }, set: { draft.personas[selectedIndex].name = $0 })
    }
    private var instructions: Binding<String> {
        Binding(get: { draft.personas[selectedIndex].instructions }, set: { draft.personas[selectedIndex].instructions = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(appearance.effectiveAccent)
                Text("AI 審碼設定").font(.title2.weight(.semibold))
                Spacer()
                Aurora.Chip(text: "本機保存", kind: .brand)
            }.padding(22)
            Divider().opacity(0.4)
            Form {
                Section("DeepSeek / 兼容接口") {
                    TextField("API 根網址", text: $draft.baseURL).accessibilityIdentifier("ai-endpoint")
                    TextField("模型", text: $draft.model).accessibilityIdentifier("ai-model")
                    LabeledContent("API Key") {
                        SecureField(storedKey ? "已保存；留空沿用" : "輸入一次並保存", text: $key)
                            .accessibilityLabel("AI API Key").accessibilityIdentifier("ai-api-key")
                    }
                    HStack {
                        Text(storedKey ? "此接口已有 API Key" : "此接口尚未保存 API Key")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("移除已保存 Key") {
                            do { try store.removeKey(for: draft.baseURL); keyRemoved = true; key = "" }
                            catch { self.error = AIReviewError.storage.localizedDescription }
                        }.disabled(!storedKey)
                    }
                    Text("Key 只保存在本機私有檔案，不使用鑰匙圈授權視窗。更換接口不會把原接口的 Key 帶過去。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("人格預設") {
                    Picker("目前人格", selection: $draft.selectedPersonaID) {
                        ForEach(draft.personas) { persona in Text(persona.name).tag(persona.id) }
                    }.accessibilityIdentifier("ai-persona-settings")
                    TextField("人格名稱", text: name).accessibilityIdentifier("ai-persona-name")
                    TextEditor(text: instructions)
                        .font(.system(size: 12)).frame(height: 115)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
                        .accessibilityLabel("人格提示詞").accessibilityIdentifier("ai-persona-instructions")
                    HStack {
                        Button("新增人格", systemImage: "plus") {
                            let p = AIReviewPersona(id: UUID(), name: "自訂人格", instructions: "請簡潔審查程式碼，說明問題與具體建議。")
                            draft.personas.append(p); draft.selectedPersonaID = p.id
                        }.disabled(draft.personas.count >= 20)
                        Button("複製", systemImage: "doc.on.doc") {
                            var p = draft.personas[selectedIndex]; p.id = UUID(); p.name = String(p.name.prefix(34)) + " 副本"
                            draft.personas.append(p); draft.selectedPersonaID = p.id
                        }.disabled(draft.personas.count >= 20)
                        Spacer()
                        Button("刪除此人格", systemImage: "minus") {
                            draft.personas.remove(at: selectedIndex); draft.selectedPersonaID = draft.personas[0].id
                        }.disabled(draft.personas.count <= 1)
                    }
                    Text("人格會自動加入每次請求，不用重貼提示詞；本次要求仍可在審碼面板補充。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                if keyRemoved { Text("已移除此接口的 Key").font(.caption).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            Divider().opacity(0.4)
            HStack {
                Text("人格與接口設定按「儲存」生效").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("儲存設定") {
                    do { try store.save(draft, newKey: key); key = ""; dismiss() }
                    catch { self.error = (error as? AIReviewError)?.localizedDescription ?? AIReviewError.storage.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).accessibilityIdentifier("ai-save-settings")
            }.padding(20)
        }
        .frame(width: 620, height: 680)
        .tint(appearance.effectiveAccent)
    }
    private var storedKey: Bool { store.hasKey(for: draft.baseURL) }
}
