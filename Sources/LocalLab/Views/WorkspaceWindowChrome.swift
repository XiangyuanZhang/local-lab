import SwiftUI
import AppKit

/// Keep the workspace behind the native toolbar when AppKit rebuilds it for full screen.
struct WorkspaceWindowChrome: NSViewRepresentable {
    @Binding var inset: CGFloat
    @Binding var fullScreen: Bool
    func makeNSView(context: Context) -> Probe { Probe(update: { value, mode in
        if value > 0, inset != value { inset = value }
        if fullScreen != mode { fullScreen = mode }
    }) }
    func updateNSView(_ view: Probe, context: Context) { view.update = { value, mode in
        if value > 0, inset != value { inset = value }
        if fullScreen != mode { fullScreen = mode }
    } }
    final class Probe: NSView {
        var update: (CGFloat, Bool) -> Void
        private var windowedToolbarStyle: NSWindow.ToolbarStyle?
        private var observations: [NSObjectProtocol] = []
        init(update: @escaping (CGFloat, Bool) -> Void) { self.update = update; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
            guard let window else { return }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didResizeNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    DispatchQueue.main.async { self?.configure() }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.configure() }
        }
        private func configure() {
            guard let window else { return }
            if !window.styleMask.contains(.fullScreen), !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            let mode = window.styleMask.contains(.fullScreen)
            if mode {
                if windowedToolbarStyle == nil { windowedToolbarStyle = window.toolbarStyle }
                if window.toolbarStyle != .unifiedCompact { window.toolbarStyle = .unifiedCompact }
            } else if let previous = windowedToolbarStyle {
                window.toolbarStyle = previous
                windowedToolbarStyle = nil
            }
            let visibility: NSWindow.TitleVisibility = mode ? .hidden : .visible
            if window.titleVisibility != visibility { window.titleVisibility = visibility }
            let value = max(0, window.frame.height - window.contentLayoutRect.height)
            update(value, mode)
        }
        deinit { observations.forEach(NotificationCenter.default.removeObserver) }
    }
}
