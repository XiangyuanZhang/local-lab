import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.workspaceHasBackground) private var hasBackground
    var fontSize: Double
    var python = true
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.masksToBounds = true
        let editor = PythonTextView()
        editor.isRichText = false; editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        editor.textColor = .labelColor; editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 22, height: 18)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("Python 程式編輯器")
        editor.string = text; editor.delegate = context.coordinator
        scroll.drawsBackground = !hasBackground; scroll.contentView.drawsBackground = !hasBackground; editor.drawsBackground = !hasBackground
        scroll.documentView = editor; context.coordinator.highlight(editor)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        scroll.drawsBackground = !hasBackground; scroll.contentView.drawsBackground = !hasBackground; editor.drawsBackground = !hasBackground
        if editor.string != text { editor.string = text; editor.undoManager?.removeAllActions(); context.coordinator.highlight(editor) }
        if editor.font?.pointSize != CGFloat(fontSize) { editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string; highlight(editor)
        }
        func highlight(_ editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let all = NSRange(location: 0, length: (editor.string as NSString).length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: all)
            for rule in (parent.python ? Self.rules : []) {
                for match in rule.regex.matches(in: editor.string, range: all) {
                    storage.addAttribute(.foregroundColor, value: rule.color, range: match.range)
                }
            }
            storage.endEditing()
            editor.typingAttributes[.foregroundColor] = NSColor.labelColor
        }

        /// Compiled once and reused: recolouring on every keystroke no longer
        /// pays for three `NSRegularExpression` compilations.
        private struct Rule {
            let regex: NSRegularExpression
            let color: NSColor
        }

        private static let rules: [Rule] = {
            let specs: [(String, NSColor)] = [
                ("\\b(def|class|import|from|for|in|if|else|elif|return|while|try|except|with|as|True|False|None|print)\\b", .systemPurple),
                ("('([^'\\\\]|\\\\.)*'|\"([^\"\\\\]|\\\\.)*\")", .systemRed),
                ("(?m)#.*$", .secondaryLabelColor)
            ]
            return specs.compactMap { pattern, color in
                (try? NSRegularExpression(pattern: pattern)).map { Rule(regex: $0, color: color) }
            }
        }()
    }
}
final class PythonTextView: NSTextView {
    override func insertTab(_ sender: Any?) { insertText("    ", replacementRange: selectedRange()) }
}
