import SwiftUI

struct BottomPanelView: View {
    @ObservedObject var store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(BottomPanel.allCases) { panel in
                    Button { store.bottomPanel = panel } label: {
                        Text(panel.rawValue).font(.callout.weight(store.bottomPanel == panel ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(store.bottomPanel == panel ? Color.accentColor.opacity(0.12) : Color.clear)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(.horizontal, 10)
            Divider()
            switch store.bottomPanel {
            case .output: OutputPane(store: store)
            case .local: TerminalPane(store: store, location: .local)
            case .remote: TerminalPane(store: store, location: .remote)
            }
        }
    }
}
