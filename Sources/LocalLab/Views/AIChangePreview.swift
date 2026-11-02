import SwiftUI
import AppKit

struct AIChangePreview: View {
    let result: AIReviewResult
    @ObservedObject var store: AIReviewStore
    @ObservedObject var workspace: WorkspaceStore
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    private let diff: AIReviewDiff
    init(result: AIReviewResult, store: AIReviewStore, workspace: WorkspaceStore) {
        self.result = result; self.store = store; self.workspace = workspace
        diff = AIReviewDiff(before: result.request.snapshot.code, after: result.proposedCode ?? result.request.snapshot.code)
    }
    private var canApply: Bool {
        store.configuration.mode == .edit && result.request.mode == .edit && result.hasChanges &&
        result.request.snapshot.matches(workspace.selected) && workspace.runningID == nil && !workspace.fileBusy
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("修改預覽", systemImage: "doc.text.magnifyingglass").font(.title2.weight(.semibold))
                Spacer()
                Text(result.request.snapshot.filename).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }.padding(22)
            HStack {
                Picker("預覽方式", selection: $tab) {
                    Text("變更區塊").tag(0); Text("原始內容").tag(1); Text("建議內容").tag(2)
                }.pickerStyle(.segmented).frame(width: 320)
                Spacer()
                Text("− 移除    + 新增").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.bottom, 14)
            Divider().opacity(0.4)
            Group {
                if tab == 0 {
                    GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(diff.lines) { line in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(line.kind == .removed ? "−" : line.kind == .added ? "+" : " ")
                                        .foregroundStyle(line.kind == .removed ? Color.red : line.kind == .added ? Color.green : Color.secondary)
                                    Text(line.text.isEmpty ? " " : line.text).textSelection(.enabled)
                                }.font(.system(size: 12, design: .monospaced))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 14).padding(.vertical, 3)
                                    .background(line.kind == .removed ? Color.red.opacity(0.08) : line.kind == .added ? Color.green.opacity(0.08) : .clear)
                            }
                            if diff.omitted > 0 {
                                Text("預覽省略 \(diff.omitted) 行；可切換至完整原始／建議內容。").font(.caption).foregroundStyle(.secondary).padding(14)
                            }
                        }.frame(minWidth: geometry.size.width, minHeight: max(0, geometry.size.height - 20), alignment: .topLeading)
                            .padding(.vertical, 10)
                    }
                    }
                } else {
                    AIReadonlyCode(text: tab == 1 ? result.request.snapshot.code : (result.proposedCode ?? result.request.snapshot.code))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 8) {
                if !result.request.snapshot.matches(workspace.selected) {
                    Text("目前檔案與審碼時不同，不能套用；請重新審碼。").font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Text("只套用至編輯器，不自動上傳或執行。").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("套用至編輯器") { if store.apply(result, to: workspace) { dismiss() } }
                        .buttonStyle(.borderedProminent).disabled(!canApply).accessibilityIdentifier("ai-apply")
                }
            }.padding(20)
        }.frame(width: 800, height: 600).tint(appearance.effectiveAccent)
    }
}

/// A read-only text bridge: no syntax highlighting work, undo stack, or editing side effects.
private struct AIReadonlyCode: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let view = NSTextView(); view.isEditable = false; view.isSelectable = true
        view.isRichText = false; view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular); view.textColor = .labelColor
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = true
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.string = text; view.setAccessibilityLabel("唯讀程式碼預覽")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
    }
}
