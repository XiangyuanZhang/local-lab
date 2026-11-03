import SwiftUI
import AppKit

struct NotebookEditor: View {
    @Binding var text: String
    @ObservedObject var store: WorkspaceStore
    @State private var document: NotebookDocument?
    @State private var snapshot = ""
    @State private var message: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Run all", systemImage: "play.square") { store.runAllNotebook() }.disabled(!store.canExecuteNotebookCode)
                Spacer()
                Text("⌘ Enter: Run cell · ⇧ Enter: Run and advance").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button { store.clearNotebookOutputs() } label: { Image(systemName: "eraser").frame(width: 32, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).disabled(store.runningID != nil).help("Clear outputs; keep source code").accessibilityLabel("Clear notebook outputs")
            }.padding(12)
            if let message { Text(message).foregroundStyle(.red).padding(8) }
            if let document {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(document.cells.indices, id: \.self) { index in
                                NotebookCellView(index: index, document: document, store: store,
                                    source: Binding(get: { self.document?.source(at: index) ?? "" }, set: { value in change { $0.updateSource(at: index, text: value) }; store.selectNotebookCell(index, editing: true) }),
                                    remove: { change { $0.remove(at: index) }; if let id = store.selection { store.notebookSelection[id] = nil; store.notebookEditing[id] = nil; store.notebookRecentCode[id] = nil } })
                                    .id(index)
                            }
                            HStack {
                                Button("Add code", systemImage: "plus") { change { $0.append(kind: "code") }; if let doc = self.document { store.selectNotebookCell(doc.cells.count - 1, editing: true) } }
                                Button("Add Markdown", systemImage: "plus") { change { $0.append(kind: "markdown") }; if let doc = self.document { store.selectNotebookCell(doc.cells.count - 1, editing: true) } }
                            }.disabled(document.cells.count >= 2000)
                        }.padding(12)
                    }
                    .onChange(of: store.notebookSelection[store.selection ?? UUID()]) { old, next in
                        // Keyboard advance is in command mode; mouse editing keeps its current viewport.
                        if old != next, let next, store.notebookEditing[store.selection ?? UUID()] == nil { proxy.scrollTo(next, anchor: .center) }
                    }
                }
            }
        }.onAppear { load() }
            .onChange(of: text) { _, _ in if text != snapshot { load() } }
    }
    private func load() {
        do { document = try NotebookDocument(text); snapshot = text; message = nil }
        catch { document = nil; message = "Unable to open notebook: invalid nbformat 4 document." }
    }
    private func change(_ operation: (inout NotebookDocument) -> Void) {
        guard var updated = document else { return }; operation(&updated)
        do { let json = try updated.serialized(); document = updated; snapshot = json; text = json; message = nil }
        catch { message = "Notebook exceeds the 8 MB limit." }
    }
}

private struct NotebookCellView: View {
    let index: Int
    let document: NotebookDocument
    @ObservedObject var store: WorkspaceStore
    @Binding var source: String
    let remove: () -> Void
    @State private var markdownHeight = 90.0
    var kind: String { document.cells[index]["cell_type"] as? String ?? "raw" }
    var selected: Bool { (store.notebookSelection[store.selection ?? UUID()] ?? 0) == index }
    var editing: Bool { store.notebookEditing[store.selection ?? UUID()] == index }
    var count: String { (document.cells[index]["execution_count"] as? Int).map(String.init) ?? " " }
    var running: Bool { store.runningID == store.selection && store.runningNotebookCell == index }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if kind == "markdown" && !editing {
                MarkdownPreview(text: source, compact: true, onHeightChange: { height in if abs(height - markdownHeight) > 1 { markdownHeight = height } })
                    .frame(height: markdownHeight)
                    .onTapGesture(count: 2) { store.selectNotebookCell(index, editing: true) }
                    .accessibilityLabel("Cell \(index + 1) rendered Markdown")
            } else {
                CodeEditor(text: $source, fontSize: 13, python: kind == "code",
                    onFocus: { store.selectNotebookCell(index, editing: true) },
                    onRun: { advance in store.selectNotebookCell(index); store.runCurrentNotebookCell(advance: advance) },
                    onEscape: { store.notebookEditing[store.selection ?? UUID()] = nil }, focusRequested: editing, accessibilityName: "Cell \(index + 1) source")
                    .frame(height: min(560, max(90, CGFloat(source.components(separatedBy: "\n").count) * 20 + 24)))
                    .accessibilityLabel("Cell \(index + 1) source")
            }
            if kind == "code" { NotebookCellOutputs(outputs: document.cells[index]["outputs"] as? [[String: Any]] ?? [], count: count) }
        }.padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Aurora.accent.opacity(0.8) : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
            .simultaneousGesture(TapGesture().onEnded { store.selectNotebookCell(index) })
    }
    private var header: some View {
        HStack {
            Text(String(format: "Cell %02d", index + 1)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(kind == "code" ? "In [\(running ? "*" : count)]" : kind.capitalized).font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
            if kind == "code" {
                Button { NSApp.keyWindow?.makeFirstResponder(nil); store.selectNotebookCell(index); store.runCurrentNotebookCell() } label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.borderless).disabled(!store.canExecuteNotebookCode).help("Run this cell only (⌘ Enter)").accessibilityLabel("Run cell \(index + 1)")
            } else if kind == "markdown" {
                Button(editing ? "Render" : "Edit", systemImage: editing ? "checkmark" : "pencil") {
                    if editing { NSApp.keyWindow?.makeFirstResponder(nil); store.selectNotebookCell(index); store.runCurrentNotebookCell() }
                    else { store.selectNotebookCell(index, editing: true) }
                }.buttonStyle(.borderless).accessibilityLabel("\(editing ? "Render" : "Edit") Markdown cell \(index + 1)")
            }
            Menu {
                if kind == "code" { Button("Run all above and this cell") { store.run(notebookThrough: index) }.disabled(!store.canExecuteNotebookCode) }
                Button("Delete cell", role: .destructive, action: remove)
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 28).contentShape(Rectangle()) }.menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Cell \(index + 1) actions")
        }
    }
}

private struct NotebookCellOutputs: View {
    let outputs: [[String: Any]]
    let count: String
    var body: some View {
        if !outputs.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Out [\(count)]").font(.caption.monospaced()).foregroundStyle(.secondary)
                ForEach(outputs.indices, id: \.self) { index in
                    let output = outputs[index]
                    let data = output["data"] as? [String: Any] ?? [:]
                    let value = text(output["text"]) + text(data["text/plain"]) + text(output["traceback"], separator: "\n")
                    if !value.isEmpty { Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled).foregroundStyle(output["name"] as? String == "stderr" || output["output_type"] as? String == "error" ? Color.red : Color.primary).frame(maxWidth: .infinity, alignment: .leading) }
                    if let encoded = data["image/png"] as? String, encoded.utf8.count <= 7_000_000, let bytes = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), NotebookMarkdown.validPNG(bytes), let image = NSImage(data: bytes) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 600).accessibilityLabel("Cell output image")
                    }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func text(_ value: Any?, separator: String = "") -> String {
        let raw = value as? String ?? (value as? [String])?.joined(separator: separator) ?? ""
        return raw.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }
}
