import SwiftUI
import AppKit

struct OutputPane: View {
    @ObservedObject var store: WorkspaceStore
    @EnvironmentObject private var appearance: AppearanceStore
    var items: [OutputItem] { store.outputs[store.selection ?? UUID()] ?? [] }
    var runState: String? { store.runStates[store.selection ?? UUID()] }
    private var failed: Bool { runState?.contains("錯誤") == true || runState?.contains("失敗") == true }
    private var running: Bool { store.runningID == store.selection && store.runningID != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("結果", systemImage: "terminal").font(.headline)
                if let state = runState {
                    Aurora.Chip(text: state,
                                systemImage: failed ? "exclamationmark.triangle.fill" : running ? "waveform" : "checkmark.circle",
                                kind: failed ? .coral : running ? .brand : .mint,
                                animated: running)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                if let id = store.selection, let duration = store.durations[id] {
                    Text(String(format: "%.2f 秒", duration)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    let text = items.compactMap(\.text).joined()
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .help("複製文字結果").disabled(items.isEmpty)
                Button { store.clearOutput() } label: { Image(systemName: "trash") }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .help("清除顯示結果").disabled(items.isEmpty || store.runningID == store.selection)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .animation(Motion.gentle, value: runState)
            Divider().opacity(0.45)

            if items.isEmpty {
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Aurora.signature.opacity(0.14)).frame(width: 62, height: 62)
                        PulseRing(active: running, tint: Aurora.accent, lineWidth: 1.2)
                            .frame(width: 62, height: 62)
                        Image(systemName: "terminal").font(.system(size: 24, weight: .light)).foregroundStyle(Aurora.signature)
                    }
                    Text(running ? "等待執行結果…" : "結果會顯示在這裡").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    Text(store.isReady ? "執行程式，查看文字與圖表。" : "連線後，按 ⌘ Return 執行程式。").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(items) { item in
                                Group {
                                if let text = item.text {
                                    Text(text)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(item.isError ? Aurora.coral : .primary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if let data = item.image, let image = NSImage(data: data) {
                                    Image(nsImage: image)
                                        .resizable().scaledToFit().frame(maxWidth: 640)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8))
                                        .accessibilityLabel("Python 程式產生的圖表")
                                }
                                }
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .opacity))
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(18)
                        .animation(Motion.gentle, value: items.count)
                    }
                    .onChange(of: items.reduce(0) { $0 + ($1.text?.count ?? 1) }) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .animation(Motion.gentle, value: items.isEmpty)
    }
}
