import SwiftUI

struct NotebookEditor: View {
    @Binding var text: String
    let canRun: Bool
    let isRunning: Bool
    let runThrough: (Int) -> Void
    let clearOutputs: () -> Void
    @State private var document: NotebookDocument?
    @State private var snapshot = ""
    @State private var message: String?
    @State private var preview = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Notebook 顯示", selection: $preview) {
                    Text("編輯").tag(false); Text("預覽").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                Spacer()
                Button(action: clearOutputs) { Image(systemName: "eraser").frame(width: 32, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).disabled(isRunning).help("清除 Notebook 輸出，保留題目與程式碼")
                    .accessibilityLabel("清除 Notebook 輸出")
            }.padding(12)
            if let message { Text(message).foregroundStyle(.red).padding(8) }
            if preview { NotebookPreview(text: text) }
            else if let document {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(document.cells.indices, id: \.self) { index in
                            NotebookCellEditor(index: index, kind: document.cells[index]["cell_type"] as? String ?? "raw", source: Binding(
                                get: { self.document?.source(at: index) ?? "" },
                                set: { value in change { $0.updateSource(at: index, text: value) } }
                            ), canRun: canRun, run: { runThrough(index) }, remove: { change { $0.remove(at: index) } })
                        }
                        HStack {
                            Button("新增程式碼", systemImage: "plus") { change { $0.append(kind: "code") } }
                            Button("新增 Markdown", systemImage: "plus") { change { $0.append(kind: "markdown") } }
                        }.disabled(document.cells.count >= 2000)
                    }.padding(12)
                }
            }
        }
        .onAppear { load() }
        .onChange(of: text) { _, _ in if text != snapshot { load() } }
    }
    private func load() {
        do { document = try NotebookDocument(text); snapshot = text; message = nil }
        catch { document = nil; message = error.localizedDescription }
    }
    private func change(_ operation: (inout NotebookDocument) -> Void) {
        guard var updated = document else { return }
        operation(&updated)
        do {
            let json = try updated.serialized()
            document = updated; snapshot = json; text = json; message = nil
        } catch { message = error.localizedDescription }
    }
}

private struct NotebookCellEditor: View {
    let index: Int
    let kind: String
    @Binding var source: String
    let canRun: Bool
    let run: () -> Void
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(index + 1) · \(kind == "code" ? "Python" : kind == "markdown" ? "Markdown" : "Raw")").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if kind == "code" {
                    Button(action: run) { Label("執行至此", systemImage: "play.fill") }
                        .buttonStyle(.borderless).disabled(!canRun)
                        .help("從第一個程式碼單元格執行到這裡；先本機檢查，再伺服器覆核")
                        .accessibilityLabel("執行至單元格 \(index + 1)")
                }
                Button(action: remove) { Image(systemName: "trash").frame(width: 32, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("刪除單元格 \(index + 1)").accessibilityLabel("刪除單元格 \(index + 1)")
            }
            CodeEditor(text: $source, fontSize: 13, python: kind == "code")
                .frame(height: min(420, max(100, CGFloat(source.components(separatedBy: "\n").count) * 20 + 16)))
                .accessibilityLabel("單元格 \(index + 1) \(kind) 原始碼")
        }.padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1)))
    }
}
