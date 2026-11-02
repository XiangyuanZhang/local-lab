import SwiftUI

struct RemoteBrowserView: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.workspaceHasBackground) private var hasBackground
    @State private var selectedPath: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { Task { await store.showRemoteDirectory("") } } label: { Image(systemName: "house") }
                    .buttonStyle(PressableStyle(scale: 0.93))
                    .help("遠端主目錄").disabled(!store.isReady || store.fileBusy)
                Button {
                    let parent = store.remoteDirectoryPath.split(separator: "/").dropLast().joined(separator: "/")
                    Task { await store.showRemoteDirectory(parent) }
                } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(PressableStyle(scale: 0.93))
                    .help("上一層資料夾").disabled(store.remoteDirectoryPath.isEmpty || store.fileBusy || !store.isReady)

                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.caption).foregroundStyle(.tertiary)
                    Text(store.remoteDirectoryPath.isEmpty ? "主目錄" : store.remoteDirectoryPath)
                        .font(.callout.weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.045)))

                Spacer()
                if store.fileBusy { ProgressView().controlSize(.small) }
                Button { store.createFilePresented = true } label: { Image(systemName: "doc.badge.plus") }
                    .buttonStyle(PressableStyle(scale: 0.93))
                    .help("新增遠端檔案").disabled(!store.isReady || store.fileBusy)
                Button { store.createFolderPresented = true } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(PressableStyle(scale: 0.93))
                    .help("新增遠端資料夾").disabled(!store.isReady || store.fileBusy)
                Button { Task { await store.refreshRemote() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(PressableStyle(scale: 0.93))
                    .help("重新整理遠端目錄").disabled(!store.isReady || store.fileBusy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().opacity(0.45)

            if !store.isReady {
                EmptyStateCard(
                    systemImage: "folder.badge.gearshape",
                    title: "連線後瀏覽遠端檔案",
                    message: "顯示 JupyterLab 的實際目錄，並同步文字檔案。",
                    actionTitle: "連線到 TUM"
                ) { store.showConnection = true }
            } else {
                Table(store.remoteEntries, selection: $selectedPath) {
                    TableColumn("名稱") { entry in Label(entry.name, systemImage: entry.symbol) }.width(min: 180, ideal: 280)
                    TableColumn("類型") { entry in Text(entry.kindLabel).foregroundStyle(.secondary) }.width(90)
                    TableColumn("大小") { entry in Text(entry.type == "directory" ? "—" : ByteCountFormatter.string(fromByteCount: Int64(entry.size ?? 0), countStyle: .file)).foregroundStyle(.secondary) }.width(85)
                    TableColumn("修改時間") { entry in Text(formatted(entry.lastModified)).foregroundStyle(.secondary) }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(hasBackground ? .hidden : .visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contextMenu(forSelectionType: String.self) { paths in
                    if let entry = store.remoteEntries.first(where: { paths.contains($0.path) }) {
                        Button("開啟") { Task { await store.openRemote(entry) } }
                    }
                } primaryAction: { paths in
                    if let entry = store.remoteEntries.first(where: { paths.contains($0.path) }) { Task { await store.openRemote(entry) } }
                }
                HStack(spacing: 8) {
                    Aurora.Chip(text: "\(store.remoteEntries.count) 個項目", systemImage: "tray.full", kind: .neutral)
                    Text("每 15 秒更新").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button("開啟選取項目") {
                        if let entry = store.remoteEntries.first(where: { $0.path == selectedPath }) { Task { await store.openRemote(entry) } }
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .disabled(selectedPath == nil || store.fileBusy)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .transition(.opacity)
    }
    private func formatted(_ value: String) -> String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? value
    }
}

enum RemoteNameAction { case saveCopy, createFolder, createFile }

struct RemoteNameSheet: View {
    @ObservedObject var store: WorkspaceStore
    let action: RemoteNameAction
    private var creatingFolder: Bool { action == .createFolder }
    private var creating: Bool { action != .saveCopy }
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(creatingFolder ? "新增遠端資料夾" : action == .createFile ? "新增遠端檔案" : "另存至遠端")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Aurora.wordmark)
            Text("位置：\(store.remoteDirectoryPath.isEmpty ? "主目錄" : store.remoteDirectoryPath)").font(.callout).foregroundStyle(.secondary)
            TextField(creatingFolder ? "資料夾名稱" : "檔案名稱", text: $name)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(Aurora.coral) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.fileBusy)
                Button(creating ? "建立" : "儲存") {
                    Task {
                        let success: Bool
                        switch action {
                        case .createFolder: success = await store.createFolder(name: name)
                        case .createFile: success = await store.createRemoteDocument(name: name)
                        case .saveCopy: success = await store.saveAsRemote(name: name)
                        }
                        if success { dismiss() }
                    }
                }.buttonStyle(.borderedProminent).tint(Aurora.brand).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.fileBusy)
            }
        }.padding(26).frame(width: 420).onAppear { name = creatingFolder ? "" : action == .createFile ? "untitled.py" : store.selected?.name ?? "script.py"; store.error = nil }
    }
}
