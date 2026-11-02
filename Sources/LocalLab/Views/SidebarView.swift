import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selection) {
                Section("JupyterLab") {
                    Label("遠端檔案", systemImage: "folder").tag(WorkspaceStore.remoteBrowserID)
                    ForEach(store.remoteTreeRoots) { entry in RemoteSidebarRow(store: store, entry: entry) }
                    ForEach(store.uncataloguedRemoteDrafts) { draft in
                        HStack {
                            Label(draft.name, systemImage: "doc.text")
                            if draft.isRemoteDirty { Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.orange).accessibilityLabel("有未儲存修改") }
                        }.tag(draft.id)
                    }
                }
                Section("本機草稿") {
                    ForEach(store.drafts.filter { $0.remotePath == nil }) { draft in
                        Label(draft.name, systemImage: "doc.text").tag(draft.id)
                    }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
            HStack {
                Button { store.newScript() } label: { Label("新增草稿", systemImage: "plus") }.buttonStyle(.plain).help("新增 Python 草稿（⌘ N）")
                Spacer()
            }.padding(.horizontal, 18).padding(.vertical, 14)
            Divider().padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 8) {
                Label("TUM Python", systemImage: "server.rack").font(.callout.weight(.medium))
                Text("go97lep · lecture.cs.tum.de").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle().fill(store.isReady ? .green : .secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }
    }
}


struct RemoteSidebarRow: View {
    @ObservedObject var store: WorkspaceStore
    let entry: RemoteEntry
    var body: some View {
        if entry.type == "directory" {
            DisclosureGroup(isExpanded: Binding(
                get: { store.expandedRemoteFolders.contains(entry.path) },
                set: { store.expandFolder(entry.path, expanded: $0) }
            )) {
                if store.loadingRemoteFolders.contains(entry.path) && store.directoryCache[entry.path] == nil {
                    ProgressView().controlSize(.small).padding(.vertical, 4)
                } else if let children = store.directoryCache[entry.path], children.isEmpty {
                    Text("空資料夾").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.directoryCache[entry.path] ?? []) { child in
                        AnyView(RemoteSidebarRow(store: store, entry: child))
                    }
                }
            } label: { Label(entry.name, systemImage: "folder") }
            .tag(store.remoteSelectionID(entry)).help(entry.path)
        } else {
            HStack {
                Label(entry.name, systemImage: entry.symbol)
                if store.drafts.first(where: { $0.remotePath == entry.path })?.isRemoteDirty == true {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.orange).accessibilityLabel("有未儲存修改")
                }
            }.tag(store.remoteSelectionID(entry)).help(entry.path)
        }
    }
}
