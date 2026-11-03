import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.workspaceHasBackground) private var hasBackground
    var fontSize: Double
    var python = true
    var onFocus: (() -> Void)? = nil
    var onRun: ((Bool) -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var focusRequested = false
    var accessibilityName = "Python 程式編輯器"
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WrappingCodeScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layerContentsRedrawPolicy = .duringViewResize
        scroll.layer?.cornerRadius = 12
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.masksToBounds = true
        let editor = PythonTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
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
        editor.setAccessibilityLabel(accessibilityName)
        editor.onFocus = onFocus; editor.onRun = onRun; editor.onEscape = onEscape
        editor.string = text; editor.delegate = context.coordinator
        scroll.drawsBackground = !hasBackground; scroll.contentView.drawsBackground = !hasBackground; editor.drawsBackground = !hasBackground
        scroll.documentView = editor; context.coordinator.highlight(editor)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PythonTextView else { return }
        editor.onFocus = onFocus; editor.onRun = onRun; editor.onEscape = onEscape
        if focusRequested && !context.coordinator.focusRequested {
            DispatchQueue.main.async { [weak editor] in if let editor { editor.window?.makeFirstResponder(editor) } }
        }
        context.coordinator.focusRequested = focusRequested
        scroll.drawsBackground = !hasBackground; scroll.contentView.drawsBackground = !hasBackground; editor.drawsBackground = !hasBackground
        if editor.string != text { editor.string = text; editor.undoManager?.removeAllActions(); context.coordinator.highlight(editor) }
        if editor.font?.pointSize != CGFloat(fontSize) { editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var focusRequested = false
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
    var onFocus: (() -> Void)?
    var onRun: ((Bool) -> Void)?
    var onEscape: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocus?() }; return result
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if [36, 76].contains(event.keyCode), let onRun, modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.shift) {
            window?.makeFirstResponder(nil)
            onRun(modifiers.contains(.shift)); return
        }
        if event.keyCode == 53, let onEscape { onEscape(); return }
        super.keyDown(with: event)
    }
    override func insertTab(_ sender: Any?) { insertText("    ", replacementRange: selectedRange()) }
}

/// A wrapping editor must track the viewport during animated sidebar/inspector changes.
/// Otherwise an oversized document can retain an off-screen horizontal scroll offset.
private final class WrappingCodeScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let editor = documentView as? NSTextView else { return }
        let viewport = contentSize
        let minimum = NSSize(width: 0, height: max(0, viewport.height))
        if editor.minSize != minimum { editor.minSize = minimum }
        let size = NSSize(width: max(0, viewport.width), height: max(editor.frame.height, viewport.height))
        if editor.frame.size != size {
            editor.setFrameSize(size)
            editor.needsDisplay = true
        }
        let y = min(max(0, contentView.bounds.minY), max(0, editor.frame.height - viewport.height))
        if contentView.bounds.minX != 0 || contentView.bounds.minY != y {
            contentView.scroll(to: NSPoint(x: 0, y: y))
            reflectScrolledClipView(contentView)
        }
    }
}
