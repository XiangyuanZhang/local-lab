import SwiftUI

struct NotebookPreview: View {
    let text: String
    @State private var markdown = ""
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        Group {
            if loading { ProgressView("正在載入 Notebook…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error { Text(error).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { MarkdownPreview(text: markdown) }
        }
        .accessibilityLabel("Notebook 唯讀預覽")
        .task(id: text) {
            loading = true; error = nil
            do {
                let source = text
                let rendered = try await Task.detached(priority: .userInitiated) { try NotebookMarkdown.render(source) }.value
                guard !Task.isCancelled else { return }
                markdown = rendered; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Notebook 無法預覽：請確認檔案為有效的 nbformat 4 文件。"; loading = false
            }
        }
    }
}
