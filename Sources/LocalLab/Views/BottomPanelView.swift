import SwiftUI

struct BottomPanelView: View {
    @ObservedObject var store: WorkspaceStore
    var scrimOpacity: Double = 0
    @Environment(\.workspaceHasBackground) private var hasBackground
    @EnvironmentObject private var appearance: AppearanceStore
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(BottomPanel.allCases) { panel in
                    Button { store.bottomPanel = panel } label: {
                        Text(panel.rawValue)
                            .font(.callout.weight(store.bottomPanel == panel ? .semibold : .regular))
                            .foregroundStyle(store.bottomPanel == panel ? Color.primary : Color.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background {
                                if store.bottomPanel == panel {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.62))
                                        .overlay(Capsule(style: .continuous).strokeBorder(Aurora.accent.opacity(0.24), lineWidth: 0.7))
                                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                                        .matchedGeometryEffect(id: "bottom-pill", in: pill)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.bottomPanel == panel ? .isSelected : [])
                }
                Spacer()
                if store.runningID != nil {
                    Aurora.Chip(text: "執行中", systemImage: "waveform", kind: .coral, animated: true)
                        .padding(.trailing, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .animation(Motion.snappy, value: store.bottomPanel)
            .animation(Motion.gentle, value: store.runningID != nil)

            Divider().opacity(0.45)

            Group {
                switch store.bottomPanel {
                case .output: OutputPane(store: store)
                case .local: TerminalPane(store: store, location: .local)
                case .remote: TerminalPane(store: store, location: .remote)
                }
            }
            .transition(.opacity)
            .animation(Motion.quick, value: store.bottomPanel)
        }
        .background(Aurora.scrim.opacity(hasBackground ? scrimOpacity : 0))
        .cardSurface(radius: appearance.cardRadius, opacity: hasBackground ? 0 : appearance.cardOpacity)
    }
}
