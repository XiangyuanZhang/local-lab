import AppKit
import WebKit

@MainActor
final class MarkdownCheck: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var continuation: CheckedContinuation<Bool, Error>?
    func verify(resources: URL) async throws -> Bool {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        web = view; view.navigationDelegate = self
        let html = try MarkdownHTML.template(resourceDirectory: resources)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            view.loadHTMLString(html, baseURL: nil)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if let pending = self?.continuation { self?.continuation = nil; pending.resume(throwing: CheckFailure(message: "Markdown renderer timeout")) }
            }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let sample = "# Heading\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```python\nprint(42)\n```\n\n<script>window.UNSAFE=true</script><img src='https://example.invalid/tracker' onerror='window.UNSAFE=true'>"
        Task { [weak self] in
            do {
                let value = try await webView.callAsyncJavaScript("""
        window.renderMarkdown(markdown);
        return document.querySelectorAll('#write h1').length===1 &&
          document.querySelectorAll('#write table').length===1 &&
          document.querySelector('#write pre code').textContent.includes('print(42)') &&
          !document.querySelector('#write script,#write [onerror],#write img') &&
          window.UNSAFE===undefined;
        """, arguments: ["markdown": sample], in: nil, contentWorld: .page)
                _ = try await webView.evaluateJavaScript("window.renderCalls=0; const originalRenderer=window.renderMarkdown; window.renderMarkdown=(text)=>{window.renderCalls++; return originalRenderer(text);}; true;")
                let renderer = MarkdownPreview.Coordinator(text: sample, hasBackground: false)
                for _ in 0..<480 { renderer.render(webView) }
                for _ in 0..<100 {
                    if (try await webView.evaluateJavaScript("window.renderCalls") as? Int) == 1 { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let unchanged = try await webView.evaluateJavaScript("window.renderCalls") as? Int
                renderer.text = "# Changed"
                renderer.render(webView)
                for _ in 0..<100 {
                    if (try await webView.evaluateJavaScript("window.renderCalls") as? Int) == 2 { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let changed = try await webView.evaluateJavaScript("window.renderCalls===2 && document.querySelector('#write h1').textContent==='Changed'") as? Bool
                guard let pending = self?.continuation else { return }
                self?.continuation = nil
                pending.resume(returning: value as? Bool == true && unchanged == 1 && changed == true)
            } catch {
                guard let pending = self?.continuation else { return }
                self?.continuation = nil
                pending.resume(throwing: error)
            }
        }
    }
}
