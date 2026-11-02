import SwiftUI

struct TerminalPane: View {
    @ObservedObject var store: WorkspaceStore
    let location: TerminalLocation
    @State private var input = ""
    private var connected: Bool { store.terminals[location] != nil }
    private var title: String { location == .local ? "本機 Terminal" : "伺服器 Terminal" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(title, systemImage: location == .local ? "desktopcomputer" : "cloud")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Aurora.Chip(text: store.terminalStates[location] ?? "尚未啟動",
                            systemImage: connected ? "circle.fill" : "circle.dotted",
                            kind: connected ? .mint : .neutral)
                Spacer()
                Button("中斷") { Task { await store.sendTerminal("\u{03}", location: location, newline: false) } }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .disabled(!connected)
                Button("重新連線") { Task { await store.reconnectTerminal(location) } }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .disabled(store.terminalBusy.contains(location))
                Button("清除顯示") { store.terminalOutput[location] = "" }
                    .buttonStyle(PressableStyle(scale: 0.97))
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .animation(Motion.gentle, value: connected)
            Divider().opacity(0.45)

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading) {
                            Text(store.terminalOutput[location] ?? "正在啟動 shell…")
                                .font(.system(size: 13, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                            Color.clear.frame(height: 1).id("terminal-bottom")
                        }
                        .frame(minWidth: max(0, geometry.size.width - 36), minHeight: max(0, geometry.size.height - 36), alignment: .topLeading)
                        .padding(18)
                    }
                    .onChange(of: store.terminalOutput[location]) { _, _ in proxy.scrollTo("terminal-bottom", anchor: .bottom) }
                }
            }

            Divider().opacity(0.45)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Aurora.brand.opacity(0.8))
                    TextField("輸入指令或回覆，按 Return 發送", text: $input)
                        .textFieldStyle(.plain)
                        .onSubmit { send() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.05)))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.7))

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .foregroundStyle(Aurora.brand)
                .disabled(!connected || input.isEmpty)
                .help("發送（Return）")
            }
            .padding(10)
        }
        .task(id: location) { await store.openTerminal(location) }
        .onChange(of: location) { _, _ in input = "" }
    }

    private func send() {
        guard !input.isEmpty else { return }
        let text = input; input = ""
        Task { await store.sendTerminal(text, location: location) }
    }
}
