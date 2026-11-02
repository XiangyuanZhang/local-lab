import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var background: BackgroundStore
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selection) {
                sectionHeader("JUPYTERLAB")
                Label("遠端檔案", systemImage: "folder").tag(WorkspaceStore.remoteBrowserID)
                ForEach(store.remoteTreeRoots) { entry in RemoteSidebarRow(store: store, entry: entry) }
                ForEach(store.uncataloguedRemoteDrafts) { draft in
                    HStack {
                        Label(draft.name, systemImage: "doc.text")
                        if draft.isRemoteDirty { DirtyDot() }
                    }.tag(draft.id)
                }
                sectionHeader("本機草稿")
                ForEach(store.drafts.filter { $0.remotePath == nil }) { draft in
                    Label(draft.name, systemImage: "doc.text").tag(draft.id)
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 24)
            .tint(Aurora.accent)
            .padding(.top, 4)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 6)

            newDraftButton
            footer
        }
        .background(sidebarBackdrop)

    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .selectionDisabled()
            .accessibilityAddTraits(.isHeader)
    }

    /// With a user background image the sidebar is dimmed by the per-region
    /// transparency value from the background settings (same maths as the editor
    /// preview). Without an image the aurora panel material is used instead.
    @ViewBuilder
    private var sidebarBackdrop: some View {
        if background.image != nil, let settings = background.configuration {
            Aurora.scrim
                .opacity(1 - (settings.sidebarTransparency ?? settings.transparency))
        } else {
            PanelBackdrop(finish: appearance.panel)
        }
    }

    private var newDraftButton: some View {
        Button { store.newScript() } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("新增草稿")
                Spacer()
                Text("⌘N").font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Aurora.accent.opacity(0.14))
                    .overlay(Capsule(style: .continuous).strokeBorder(Aurora.accent.opacity(0.24), lineWidth: 0.7))
            )
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .hoverLift(scale: 1.012, shadowRadius: 9)
        .help("新增 Python 草稿（⌘ N）")
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("TUM Python", systemImage: "server.rack").font(.callout.weight(.medium))
                Spacer()
                PulseDot(
                    active: store.connecting || store.runningID != nil,
                    tint: store.isReady ? Aurora.mint : Color.secondary.opacity(0.6),
                    size: 6
                )
            }
            Text("go97lep · lecture.cs.tum.de")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassPanel(radius: max(10, appearance.panelRadius - 4))
        .hoverLift(scale: 1.006, shadowRadius: 12)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .animation(Motion.gentle, value: store.isReady)
    }
}

/// Small orange dot marking a draft with unsaved remote changes.
struct DirtyDot: View {
    var body: some View {
        Circle()
            .fill(Aurora.coral)
            .frame(width: 6, height: 6)
            .shadow(color: Aurora.coral.opacity(0.6), radius: 3)
            .accessibilityLabel("有未儲存修改")
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
                    DirtyDot()
                }
            }.tag(store.remoteSelectionID(entry)).help(entry.path)
        }
    }
}
