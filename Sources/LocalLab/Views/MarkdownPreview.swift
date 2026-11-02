import SwiftUI
import WebKit
import AppKit

struct MarkdownPreview: NSViewRepresentable {
    var text: String
    @Environment(\.workspaceHasBackground) private var hasBackground
    func makeCoordinator() -> Coordinator { Coordinator(text: text, hasBackground: hasBackground) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.underPageBackgroundColor = hasBackground ? .clear : .textBackgroundColor
        web.setAccessibilityLabel("Markdown 文件預覽")
        do { web.loadHTMLString(try MarkdownHTML.template(), baseURL: nil) }
        catch { web.loadHTMLString("<p>本機渲染資源無法載入。</p>", baseURL: nil) }
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.text = text; context.coordinator.hasBackground = hasBackground
        web.underPageBackgroundColor = hasBackground ? .clear : .textBackgroundColor
        if context.coordinator.ready { context.coordinator.render(web) }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var text: String; var hasBackground: Bool; var ready = false
        private var lastMarkdown: String?
        private var lastTransparency: Bool?
        init(text: String, hasBackground: Bool) { self.text = text; self.hasBackground = hasBackground }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(webView) }
        func render(_ web: WKWebView) {
            // Pass document text as a typed argument, never concatenate it into script source.
            let markdown = text; let transparent = hasBackground
            guard lastMarkdown != markdown || lastTransparency != transparent else { return }
            lastMarkdown = markdown; lastTransparency = transparent
            Task { _ = try? await web.callAsyncJavaScript("document.body.style.background = transparent ? 'transparent' : ''; return window.renderMarkdown(markdown)", arguments: ["markdown": markdown, "transparent": transparent], in: nil, contentWorld: .page) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}
