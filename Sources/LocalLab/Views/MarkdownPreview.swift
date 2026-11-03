import SwiftUI
import WebKit
import AppKit

struct MarkdownPreview: NSViewRepresentable {
    var text: String
    var compact = false
    var onHeightChange: ((Double) -> Void)? = nil
    @Environment(\.workspaceHasBackground) private var hasBackground
    func makeCoordinator() -> Coordinator { Coordinator(text: text, hasBackground: hasBackground, height: onHeightChange) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = SizingMarkdownWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.widthChanged = { [weak coordinator = context.coordinator, weak web] in if let web { coordinator?.measure(web) } }
        web.underPageBackgroundColor = hasBackground ? .clear : .textBackgroundColor
        web.setAccessibilityLabel("Markdown 文件預覽")
        do {
            var html = try MarkdownHTML.template()
            if compact { html = html.replacingOccurrences(of: "</head>", with: "<style>body{background:transparent!important}#write{max-width:none;padding:4px 10px 8px;margin:0}#write>:first-child{margin-top:0}.Info,.info{border-left:3px solid var(--link);padding:.5em .8em;background:var(--code)}</style></head>") }
            web.loadHTMLString(html, baseURL: nil)
        }
        catch { web.loadHTMLString("<p>本機渲染資源無法載入。</p>", baseURL: nil) }
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.height = onHeightChange; context.coordinator.text = text; context.coordinator.hasBackground = hasBackground
        web.underPageBackgroundColor = hasBackground ? .clear : .textBackgroundColor
        if context.coordinator.ready { context.coordinator.render(web) }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var text: String; var hasBackground: Bool; var ready = false
        private var lastMarkdown: String?
        private var lastTransparency: Bool?
        var height: ((Double) -> Void)?
        init(text: String, hasBackground: Bool, height: ((Double) -> Void)? = nil) { self.text = text; self.hasBackground = hasBackground; self.height = height }
        func measure(_ web: WKWebView) {
            guard ready, height != nil else { return }
            Task { [weak self, weak web] in
                guard let self, let web else { return }
                if let value = try? await web.evaluateJavaScript("document.getElementById('write').scrollHeight + 12") as? Double {
                    await MainActor.run { self.height?(min(1600, max(36, value))) }
                }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(webView) }
        func render(_ web: WKWebView) {
            // Pass document text as a typed argument, never concatenate it into script source.
            let markdown = text; let transparent = hasBackground
            guard lastMarkdown != markdown || lastTransparency != transparent else { return }
            lastMarkdown = markdown; lastTransparency = transparent
            Task { [weak self] in _ = try? await web.callAsyncJavaScript("document.body.style.background = transparent ? 'transparent' : ''; return window.renderMarkdown(markdown)", arguments: ["markdown": markdown, "transparent": transparent], in: nil, contentWorld: .page); self?.measure(web) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}

private final class SizingMarkdownWebView: WKWebView {
    var widthChanged: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 1
        super.setFrameSize(newSize)
        if changed { widthChanged?() }
    }
}
