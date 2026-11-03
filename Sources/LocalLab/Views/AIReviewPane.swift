import SwiftUI

struct AIReviewPane: View {
    @ObservedObject var store: AIReviewStore
    @ObservedObject var workspace: WorkspaceStore
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentCellOnly = true
    @State private var preview: AIReviewResult?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    if let error = store.error {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error).textSelection(.enabled)
                            Spacer(minLength: 0)
                            Button { store.dismissError() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("關閉 AI 提示")
                        }.font(.callout).foregroundStyle(Aurora.coral).padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Aurora.coral.opacity(0.10)))
                    }
                    if store.isRunning {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("正在審查程式碼…").font(.callout.weight(.medium))
                                Text("可繼續編輯；套用前會再次比對內容。").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 12).accessibilityIdentifier("ai-running")
                    }
                    if let result = store.result { results(result) }
                    else if !store.isRunning { emptyState }
                    if let notice = store.notice {
                        Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).accessibilityIdentifier("ai-notice")
                    }
                    if store.lastApplied != nil {
                        Button("還原上次 AI 套用", systemImage: "arrow.uturn.backward") { store.undo(in: workspace) }
                            .buttonStyle(PressableStyle()).accessibilityIdentifier("ai-undo")
                    }
                }.padding(16)
            }
        }
        .animation(reduceMotion ? nil : Motion.quick, value: store.isRunning)
        .sheet(item: $preview) { result in AIChangePreview(result: result, store: store, workspace: workspace) }
        .sheet(isPresented: $store.showSettings) { AISettingsView(store: store) }
    }
    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles").foregroundStyle(Aurora.accent)
            Text("AI 審碼").font(.headline)
            Spacer()
            Button { store.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(PressableStyle()).help("API 與人格設定").accessibilityLabel("AI 設定")
            Button { store.panelVisible = false } label: { Image(systemName: "xmark") }
                .buttonStyle(PressableStyle()).help("收起 AI 審碼").accessibilityLabel("收起 AI 審碼")
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(workspace.selected?.name ?? "尚未選取檔案", systemImage: "doc.text")
                .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
            if workspace.isNotebookSelected {
                Picker("審碼範圍", selection: $currentCellOnly) {
                    Text("目前／剛執行的程式碼單元格").tag(true)
                    Text("整份 Notebook").tag(false)
                }.disabled(store.isRunning).accessibilityIdentifier("ai-scope")
                if currentCellOnly {
                    Text(workspace.reviewNotebookCellIndex.map { "Cell \($0 + 1) · Only this cell will be sent" } ?? "Select or run a code cell first")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("ai-cell-target")
                }
            }
            Picker("審碼模式", selection: Binding(get: { store.configuration.mode }, set: store.selectMode)) {
                ForEach(AIReviewMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented).labelsHidden().disabled(store.isRunning).accessibilityIdentifier("ai-mode")
            HStack {
                Picker("人格", selection: Binding(get: { store.configuration.selectedPersonaID }, set: store.selectPersona)) {
                    ForEach(store.configuration.personas) { p in Text(p.name).tag(p.id) }
                }.disabled(store.isRunning).accessibilityIdentifier("ai-persona")
                Button { store.showSettings = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(PressableStyle()).help("編輯人格")
            }
            TextField("本次要求（可留空）", text: $store.instruction, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4).disabled(store.isRunning)
                .accessibilityIdentifier("ai-instruction")
            HStack {
                if store.isRunning {
                    Button("取消請求", role: .cancel) { store.cancel() }.buttonStyle(PressableStyle()).accessibilityIdentifier("ai-cancel")
                } else {
                    Button { store.start(draft: workspace.selected, notebookCellIndex: workspace.isNotebookSelected && currentCellOnly ? workspace.reviewNotebookCellIndex : nil) } label: { Label(store.configuration.mode.actionTitle, systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent)
                        .disabled(workspace.selected == nil || workspace.selected?.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true || (workspace.isNotebookSelected && currentCellOnly && workspace.reviewNotebookCellIndex == nil))
                        .accessibilityIdentifier("ai-start")
                }
                Spacer()
                Text(store.configuration.model).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Text("只會發送選定範圍的程式碼、人格與本次要求至 \(provider)。不會自動儲存到遠端或執行程式。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var provider: String { (try? AIEndpoint(store.configuration.baseURL).base.host) ?? "設定的 API" }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "text.magnifyingglass").font(.system(size: 24, weight: .light)).foregroundStyle(Aurora.accent)
            Text("讓另一雙眼睛看看程式碼").font(.callout.weight(.semibold))
            Text("僅審碼會列出問題；修改模式會先產生預覽，確認後才套用。")
                .font(.callout).foregroundStyle(.secondary)
            if !store.hasSavedKey {
                Button("設定 DeepSeek API", systemImage: "key") { store.showSettings = true }.buttonStyle(PressableStyle())
            }
        }.padding(.vertical, 12)
    }
    private func results(_ result: AIReviewResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Aurora.Chip(text: result.request.mode.title, kind: .brand)
                Text(result.request.persona.name).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if let cell = result.request.snapshot.notebookCellIndex { Text("Reviewed: Cell \(cell + 1)").font(.caption).foregroundStyle(.secondary) }
            Text(result.response.summary).font(.callout).textSelection(.enabled).accessibilityIdentifier("ai-summary")
            if !result.request.snapshot.matches(workspace.selected) {
                Label("這份結果的檔案內容已變更，需重新審碼才能套用。", systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(result.response.findings) { finding in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Aurora.Chip(text: finding.severity.title, kind: finding.severity == .high ? .coral : .brand)
                        if let line = finding.line { Text("第 \(line) 行").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                    Text(finding.title).font(.callout.weight(.semibold)).textSelection(.enabled)
                    Text(finding.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
            }
            if result.request.mode == .edit {
                if result.hasChanges {
                    Button("預覽修改", systemImage: "doc.text.magnifyingglass") { preview = result }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("ai-preview")
                    if store.configuration.mode == .reviewOnly {
                        Text("目前為僅審碼模式，無法套用先前的修改。").font(.caption).foregroundStyle(.secondary)
                    }
                } else { Text("AI 未提出程式碼修改。").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
