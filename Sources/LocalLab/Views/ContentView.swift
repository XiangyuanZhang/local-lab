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
    @AppStorage("editorFontSize") private var fontSize = 14.0
    var body: some View {
        HSplitView {
            if sidebarVisible {
                SidebarView(store: store).frame(minWidth: 180, idealWidth: 215, maxWidth: 280)
                    .background(regionOverlay(sidebar: true))
            }
            VStack(spacing: 0) {
                if let error = store.error {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("關閉提示")
                    }.padding(14).background(.orange.opacity(0.08))
                    Divider()
                }
                VSplitView {
                    Group {
                        if store.browsingRemote { RemoteBrowserView(store: store) }
                        else { EditorPane(store: store, fontSize: fontSize) }
                    }.frame(minHeight: 230)
                    BottomPanelView(store: store).frame(minHeight: 180, idealHeight: 260)
                }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: store.isReady ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(store.isReady ? .green : .secondary)
                    Text(store.status)
                    if store.connection != nil { Text("·").foregroundStyle(.tertiary); Text("App 專用核心").foregroundStyle(.secondary) }
                    Spacer()
                    if let notice = store.syncNotice { Text(notice).foregroundStyle(.secondary).lineLimit(1) }
                    else if let date = store.lastSynced { Text("已同步 \(date.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary) }
                    else { Text("⌘ Return 執行").foregroundStyle(.secondary) }
                }.font(.caption).padding(.horizontal, 18).padding(.vertical, 9)
            }
            .background(regionOverlay(sidebar: false))
            .navigationTitle(store.browsingRemote ? "遠端檔案" : store.selected?.name ?? "Python 工作區")
            .navigationSubtitle("Local Lab · TUM")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { sidebarVisible.toggle() } label: { Label("侧边栏", systemImage: "sidebar.left") }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if store.runningID != nil {
                        Button { store.interrupt() } label: { Label("中斷", systemImage: "stop.fill") }.help("中斷 App 專用核心（⌘ .）")
                    }
                    if store.selected?.remotePath != nil {
                        Button { Task { await store.saveSelectedRemote() } } label: { Label("儲存至遠端", systemImage: "icloud.and.arrow.up") }.disabled(!store.isReady || store.fileBusy || store.selected?.isRemoteDirty != true)
                    }
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
        }
        .frame(minWidth: 760, minHeight: 550)
        .background(WorkspaceBackground(store: background).ignoresSafeArea())
        .environment(\.workspaceHasBackground, background.image != nil)
        .toolbarBackground(background.image == nil ? .automatic : .hidden, for: .windowToolbar)
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
    }

    private func regionOverlay(sidebar: Bool) -> some View {
        let settings = background.configuration
        let transparency = sidebar ? (settings?.sidebarTransparency ?? settings?.transparency ?? 0) : (settings?.transparency ?? 0)
        return Color(nsColor: .windowBackgroundColor)
            .opacity(background.image == nil ? 0 : transparency)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

struct EditorPane: View {
    @ObservedObject var store: WorkspaceStore
    let fontSize: Double
    @State private var markdownMode = 0
    private var isMarkdown: Bool { ["md", "markdown"].contains((store.selected?.name as NSString?)?.pathExtension.lowercased() ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(isMarkdown ? "文件" : "程式", systemImage: isMarkdown ? "doc.richtext" : "chevron.left.forwardslash.chevron.right").font(.headline)
                Spacer()
                if isMarkdown {
                    Picker("Markdown 顯示方式", selection: $markdownMode) { Text("預覽").tag(0); Text("編輯").tag(1); Text("並排").tag(2) }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                Text(isMarkdown ? "Markdown" : store.selected?.name.lowercased().hasSuffix(".py") == true ? "Python" : "文字").foregroundStyle(.secondary)
                Text(store.selected?.remotePath == nil ? "· 本機草稿" : store.selected?.isRemoteDirty == true ? "· 尚未儲存至遠端" : "· 與遠端同步").foregroundStyle(.secondary)
            }.font(.caption).padding(.horizontal, 22).padding(.vertical, 14)
            Divider()
            if let id = store.selection, store.conflicts[id] != nil {
                HStack(alignment: .top) {
                    Label("遠端也已修改。已保留你的本機內容。", systemImage: "exclamationmark.triangle").font(.callout)
                    Spacer()
                    Button("保留副本並載入遠端") { store.resolveConflictKeepingCopy() }
                }.padding(14).background(.orange.opacity(0.08))
                Divider()
            }
            if let path = store.selected?.remotePath { Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 10) }
            if isMarkdown && markdownMode == 0 {
                MarkdownPreview(text: store.selected?.code ?? "")
            } else if isMarkdown && markdownMode == 2 {
                HSplitView {
                    sourceEditor.frame(minWidth: 200)
                    MarkdownPreview(text: store.selected?.code ?? "").frame(minWidth: 250)
                }
            } else { sourceEditor }
        }
    }
    private var sourceEditor: some View {
        CodeEditor(text: Binding(get: { store.selected?.code ?? "" }, set: { store.updateCode($0) }), fontSize: fontSize, python: store.selected?.name.lowercased().hasSuffix(".py") == true)
    }
}
