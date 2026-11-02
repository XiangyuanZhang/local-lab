import SwiftUI
import AppKit

/// Keep the workspace behind the native toolbar when AppKit rebuilds it for full screen.
struct WorkspaceWindowChrome: NSViewRepresentable {
    @Binding var inset: CGFloat
    func makeNSView(context: Context) -> Probe { Probe(update: { if inset != $0 { inset = $0 } }) }
    func updateNSView(_ view: Probe, context: Context) { view.update = { if inset != $0 { inset = $0 } } }
    final class Probe: NSView {
        var update: (CGFloat) -> Void
        private var observations: [NSObjectProtocol] = []
        init(update: @escaping (CGFloat) -> Void) { self.update = update; super.init(frame: .zero) }
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
            let value = max(0, window.frame.height - window.contentLayoutRect.height)
            if value > 0 { update(value) }
        }
        deinit { observations.forEach(NotificationCenter.default.removeObserver) }
    }
}
