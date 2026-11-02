import SwiftUI
import UniformTypeIdentifiers

struct PythonDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .sourceCode] }
    var code: String
    init(code: String) { self.code = code }
    init(configuration: ReadConfiguration) throws { code = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(code.utf8)) }
}

struct ContentView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var background: BackgroundStore
    @State private var sidebarVisible = true
    @State private var importing = false
    @State private var exporting = false
    @State private var appeared = false
    @AppStorage("editorFontSize") private var fontSize = 14.0
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var ai: AIReviewStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HSplitView {
            if sidebarVisible {
                SidebarView(store: store, background: background)
                    .frame(minWidth: 180, idealWidth: 215, maxWidth: 280)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if let error = store.error {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Aurora.coral)
                        Text(error).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        if error.contains("OSStatus") {
                            Button("修復授權") { Task { _ = await store.repairKeychainAccess() } }
                                .buttonStyle(PressableStyle(scale: 0.96))
                                .disabled(store.repairingKeychain || store.busy)
                                .help("重新允許這個版本的 App 讀取已儲存的 token")
                        }
                        Button { withAnimation(Motion.quick) { store.error = nil } } label: { Image(systemName: "xmark") }
                            .buttonStyle(PressableStyle(scale: 0.9))
                            .help("關閉提示")
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Aurora.coral.opacity(0.10)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Aurora.coral.opacity(0.24), lineWidth: 0.8))
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                VSplitView {
                    Group {
                        if store.browsingRemote { RemoteBrowserView(store: store) }
                        else { EditorPane(store: store, fontSize: fontSize) }
                    }
                    .frame(minHeight: 230)
                    .cardSurface(radius: appearance.cardRadius, opacity: appearance.cardOpacity)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    BottomPanelView(store: store).frame(minHeight: 180, idealHeight: 260)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                statusBar
            }
            .background(regionOverlay)
            .navigationTitle(store.browsingRemote ? "遠端檔案" : store.selected?.name ?? "Python 工作區")
            .navigationSubtitle("Local Lab · TUM")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { withAnimation(Motion.gentle) { sidebarVisible.toggle() } } label: { Label("侧边栏", systemImage: "sidebar.left") }
                        .buttonStyle(PressableStyle())
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if store.runningID != nil {
                        Button { store.interrupt() } label: { Label("中斷", systemImage: "stop.fill") }.help("中斷 App 專用核心（⌘ .）")
                    }
                    if store.selected?.remotePath != nil {
                        Button { Task { await store.saveSelectedRemote() } } label: { Label("儲存至遠端", systemImage: "icloud.and.arrow.up") }.disabled(!store.isReady || store.fileBusy || store.selected?.isRemoteDirty != true)
                    }
                    Button { withAnimation(reduceMotion ? nil : Motion.gentle) { ai.panelVisible.toggle() } } label: { Label("AI 審碼", systemImage: "sparkles") }
                        .help("AI 審碼（⇧⌘R）").accessibilityIdentifier("ai-toolbar")
                    Button { store.run() } label: { Label("執行", systemImage: "play.fill") }.disabled(!store.canRun).help("執行目前草稿（⌘ Return）")
                    Button { store.showConnection = true } label: { Label(store.isReady ? "連線資訊" : "連線", systemImage: "network") }.disabled(store.busy || store.runningID != nil)
                    Menu {
                        Button("更换背景…", systemImage: "photo") { store.showBackgroundEditor = true }
                        Divider()
                        Button("匯入文字或 Python 檔案…", systemImage: "square.and.arrow.down") { importing = true }
                        Button("匯出目前草稿…", systemImage: "square.and.arrow.up") { exporting = true }.disabled(store.selected == nil)
                        Button("新增遠端檔案…", systemImage: "doc.badge.plus") { store.createFilePresented = true }.disabled(!store.isReady || store.fileBusy)
                        Button("另存至遠端…", systemImage: "icloud.and.arrow.up") { store.saveRemotePresented = true }.disabled(!store.isReady || store.fileBusy || store.selected == nil)
                        Button("重新整理遠端", systemImage: "arrow.clockwise") { Task { await store.refreshRemote() } }.disabled(!store.isReady || store.fileBusy)
                        Divider()
                        Button("關閉專用核心", systemImage: "power") { Task { _ = await store.disconnect() } }.disabled(store.connection == nil || store.busy)
                    } label: { Image(systemName: "ellipsis") }.help("工作區操作")
                }
            }
            if ai.panelVisible {
                AIReviewPane(store: ai, workspace: store)
                    .frame(minWidth: 320, idealWidth: 370, maxWidth: 540)
                    .cardSurface(radius: appearance.cardRadius, opacity: appearance.cardOpacity)
                    .padding(.vertical, 10).padding(.trailing, 10)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: ai.panelVisible ? 1080 : 760, minHeight: 550)
        .tint(Aurora.accent)
        .background(WorkspaceBackdrop(store: background).ignoresSafeArea())
        .environment(\.workspaceHasBackground, background.image != nil)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(isPresented: $store.showBackgroundEditor) { BackgroundEditor(store: background) }
        .sheet(isPresented: $store.showConnection) { ConnectionSheet(store: store) }
        .sheet(isPresented: $store.saveRemotePresented) { RemoteNameSheet(store: store, action: .saveCopy) }
        .sheet(isPresented: $store.createFilePresented) { RemoteNameSheet(store: store, action: .createFile) }
        .sheet(isPresented: $store.createFolderPresented) { RemoteNameSheet(store: store, action: .createFolder) }
        .onChange(of: store.selection) { _, _ in Task { await store.handleSelection() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.sourceCode, .plainText]) { result in
            switch result { case .success(let url): store.importScript(url: url); case .failure(let error): store.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: PythonDocument(code: store.selected?.code ?? ""), contentType: UTType(filenameExtension: (store.selected?.name as NSString?)?.pathExtension ?? "py") ?? .plainText, defaultFilename: store.selected?.name ?? "script.py") { result in
            if case .failure(let error) = result { store.error = error.localizedDescription }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 6)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.993)
        .animation(Motion.entrance, value: appeared)
        .onAppear { appeared = true }
        .animation(Motion.gentle, value: store.error)
        .animation(Motion.gentle, value: sidebarVisible)
    }

    private var statusPhase: StatusOrb.Phase {
        if store.isReady { return .ready }
        if store.connecting { return .connecting }
        return .offline
    }

    private var statusTint: Color {
        switch statusPhase {
        case .ready: return Aurora.mint
        case .connecting: return Aurora.accent
        case .offline: return Color.secondary.opacity(0.55)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            StatusOrb(phase: statusPhase, tint: statusTint)
            Text(store.status).transition(.opacity)
            if store.connection != nil {
                Text("·").foregroundStyle(.tertiary)
                Text("App 專用核心").foregroundStyle(.secondary)
            }
            Spacer()
            if store.runningID != nil {
                Aurora.Chip(text: "執行中", systemImage: "waveform", kind: .coral, animated: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else if let notice = store.syncNotice {
                Text(notice).foregroundStyle(.secondary).lineLimit(1).popOnChange(of: notice)
            } else if let date = store.lastSynced {
                Text("已同步 \(date.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("⌘ Return 執行").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(statusCapsuleFill)
                .overlay(Capsule(style: .continuous).fill(Aurora.panelTint.opacity(appearance.panel == .solid ? 0 : 1)))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.34), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(Motion.gentle, value: store.status)
        .animation(Motion.gentle, value: store.runningID != nil)
    }

    private var statusCapsuleFill: AnyShapeStyle {
        switch appearance.panel {
        case .frosted: return AnyShapeStyle(.ultraThinMaterial)
        case .solid: return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        case .clear: return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var regionOverlay: some View {
        let transparency = background.configuration?.transparency ?? 0
        return Aurora.scrim
            .opacity(background.image == nil ? 0 : 1 - transparency)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

struct EditorPane: View {
    @ObservedObject var store: WorkspaceStore
    let fontSize: Double
    @EnvironmentObject private var appearance: AppearanceStore
    @State private var markdownMode = 0
    @Namespace private var pill
    private var isMarkdown: Bool { ["md", "markdown"].contains((store.selected?.name as NSString?)?.pathExtension.lowercased() ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Aurora.accent.opacity(0.14))
                    Image(systemName: isMarkdown ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Aurora.accent)
                }
                .frame(width: 24, height: 24)
                Text(store.selected?.name ?? "未開啟檔案")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if isMarkdown { markdownControl }
                Aurora.Chip(text: languageLabel, kind: .brand)
                Aurora.Chip(text: syncLabel, kind: store.selected?.isRemoteDirty == true ? .coral : .neutral)
                    .popOnChange(of: syncLabel)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            hairline
            if let id = store.selection, store.conflicts[id] != nil {
                HStack(alignment: .top) {
                    Label("遠端也已修改。已保留你的本機內容。", systemImage: "exclamationmark.triangle").font(.callout)
                    Spacer()
                    Button("保留副本並載入遠端") { store.resolveConflictKeepingCopy() }
                        .buttonStyle(PressableStyle())
                }
                .padding(12)
                .background(Aurora.coral.opacity(0.10))
                .transition(.move(edge: .top).combined(with: .opacity))
                Divider().opacity(0.5)
            }
            if let path = store.selected?.remotePath {
                Text(path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.top, 8)
            }
            if isMarkdown && markdownMode == 0 {
                MarkdownPreview(text: store.selected?.code ?? "")
                    .transition(.opacity)
            } else if isMarkdown && markdownMode == 2 {
                HSplitView {
                    sourceEditor.frame(minWidth: 200)
                    MarkdownPreview(text: store.selected?.code ?? "").frame(minWidth: 250)
                }
                .transition(.opacity)
            } else {
                sourceEditor.transition(.opacity)
            }
        }
        .animation(Motion.gentle, value: markdownMode)
        .animation(Motion.gentle, value: store.conflicts.count)
    }

    /// Soft hairline instead of a flat Divider, so the glass cards blend.
    private var hairline: some View {
        LinearGradient(
            colors: [.clear, Color.primary.opacity(0.12), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 0.8)
    }

    private var languageLabel: String {
        store.selected?.name.lowercased().hasSuffix(".py") == true ? "Python" : (isMarkdown ? "Markdown" : "文字")
    }

    private var syncLabel: String {
        guard let selected = store.selected else { return "未開啟" }
        if selected.remotePath == nil { return "本機草稿" }
        return selected.isRemoteDirty ? "尚未儲存" : "與遠端同步"
    }

    private var markdownControl: some View {
        SlidingPill(ids: [0, 1, 2], selection: markdownMode, namespace: pill) { id in
            Text(["預覽", "編輯", "並排"][id])
                .font(.caption.weight(markdownMode == id ? .semibold : .regular))
                .foregroundStyle(markdownMode == id ? Color.primary : Color.secondary)
                .frame(minWidth: 44)
                .contentShape(Capsule())
                .onTapGesture { markdownMode = id }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown 顯示方式")
    }

    private var sourceEditor: some View {
        CodeEditor(text: Binding(get: { store.selected?.code ?? "" }, set: { store.updateCode($0) }), fontSize: fontSize, python: store.selected?.name.lowercased().hasSuffix(".py") == true)
    }
}
