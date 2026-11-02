import SwiftUI

struct TerminalPane: View {
    @ObservedObject var store: WorkspaceStore
    let location: TerminalLocation
    @State private var input = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.terminalStates[location] ?? "尚未啟動").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("中斷") { Task { await store.sendTerminal("\u{03}", location: location, newline: false) } }.disabled(store.terminals[location] == nil)
                Button("重新連線") { Task { await store.reconnectTerminal(location) } }.disabled(store.terminalBusy.contains(location))
                Button("清除顯示") { store.terminalOutput[location] = "" }
            }.padding(.horizontal, 14).padding(.vertical, 7)
            Divider()
            GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading) {
                        Text(store.terminalOutput[location] ?? "正在啟動 shell…").font(.system(size: 13, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                        Color.clear.frame(height: 1).id("terminal-bottom")
                    }.frame(minWidth: max(0, geometry.size.width - 36), minHeight: max(0, geometry.size.height - 36), alignment: .topLeading).padding(18)
                }.onChange(of: store.terminalOutput[location]) { _, _ in proxy.scrollTo("terminal-bottom", anchor: .bottom) }
            }
            }
            Divider()
            HStack {
                TextField("輸入指令或回覆，按 Return 發送", text: $input).textFieldStyle(.roundedBorder).onSubmit { send() }
                Button("發送") { send() }.disabled(store.terminals[location] == nil || input.isEmpty)
            }.padding(10)

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
