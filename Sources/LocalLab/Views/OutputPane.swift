import SwiftUI
import AppKit

struct OutputPane: View {
    @ObservedObject var store: WorkspaceStore
    var items: [OutputItem] { store.outputs[store.selection ?? UUID()] ?? [] }
    var runState: String? { store.runStates[store.selection ?? UUID()] }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("結果", systemImage: "terminal").font(.headline)
                if let state = runState {
                    Text(state).font(.caption).foregroundStyle((state.contains("錯誤") || state.contains("失敗")) ? .red : .secondary)
                }
                if let id = store.selection, let duration = store.durations[id] { Text(String(format: "%.2f 秒", duration)).font(.caption).foregroundStyle(.tertiary) }
                Spacer()
                Button {
                    let text = items.compactMap(\.text).joined()
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("複製文字結果").disabled(items.isEmpty)
                Button { store.clearOutput() } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("清除顯示結果").disabled(items.isEmpty || store.runningID == store.selection)
            }.padding(.horizontal, 22).padding(.vertical, 14)
            Divider()
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "terminal").font(.system(size: 27, weight: .light)).foregroundStyle(.tertiary)
                    Text(store.runningID == store.selection && store.runningID != nil ? "等待執行結果…" : "結果會顯示在這裡").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    Text(store.isReady ? "執行程式，查看文字與圖表。" : "連線後，按 ⌘ Return 執行程式。").font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(items) { item in
                                if let text = item.text { Text(text).font(.system(size: 13, design: .monospaced)).foregroundStyle(item.isError ? .red : .primary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                if let data = item.image, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 640).accessibilityLabel("Python 程式產生的圖表") }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(22)
                    }.onChange(of: items.reduce(0) { $0 + ($1.text?.count ?? 1) }) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }
}
