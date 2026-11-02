import Foundation

enum MarkdownHTML {
    static func template(resourceDirectory: URL? = nil) throws -> String {
        func asset(_ name: String, _ ext: String) throws -> String {
            let path = resourceDirectory?.appendingPathComponent(name + "." + ext) ?? Bundle.main.url(forResource: name, withExtension: ext)
            guard let path else { throw LabError.message("缺少本機 Markdown 渲染資源。") }
            return try String(contentsOf: path, encoding: .utf8)
        }
        let css = try asset("markdown", "css")
        let marked = try asset("marked", "js")
        let purify = try asset("purify", "js")
        return """
        <!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
        <style>\(css)</style></head><body><article id="write" aria-label="Markdown 文件"></article>
        <script>\(marked)</script><script>\(purify)</script><script>
        window.renderMarkdown = function(markdown) {
          const clean = DOMPurify.sanitize(marked.parse(markdown, {gfm:true,breaks:false}), {
            USE_PROFILES:{html:true}, FORBID_TAGS:['style','script','iframe','form','video','audio','object','embed'], FORBID_ATTR:['style']
          });
          document.getElementById('write').innerHTML = clean;
          document.querySelectorAll('#write img').forEach(img => {
            if (!img.getAttribute('src')?.startsWith('data:image/')) { img.replaceWith(document.createTextNode(img.getAttribute('alt') || '[圖片]')); }
          });
          return {headings:document.querySelectorAll('#write h1,#write h2,#write h3').length,tables:document.querySelectorAll('#write table').length};
        };
        </script></body></html>
        """
    }
}
