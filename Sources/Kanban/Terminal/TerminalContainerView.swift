import SwiftUI
import AppKit

/// SwiftUI wrapper that shows the terminal for one tmux session. The live `KanbanTerminalView` is
/// owned by `TerminalCache` and reparented here, so switching tickets (and back) keeps the session
/// alive without re-attaching tmux.
struct TerminalContainerView: NSViewRepresentable {
    let session: String

    func makeNSView(context: Context) -> TerminalContainerNSView {
        let view = TerminalContainerNSView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: TerminalContainerNSView, context: Context) {
        nsView.session = session
    }
}

/// Container that reparents and sizes the cached terminal for its current `session`.
@MainActor
final class TerminalContainerNSView: NSView {
    var session: String? {
        didSet {
            guard session != oldValue else { return }
            attachCurrentTerminal()
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    /// Move the cached terminal for `session` under this container, detaching any other terminal
    /// currently shown (without terminating it — it stays live in the cache).
    private func attachCurrentTerminal() {
        guard let session else { return }
        let terminal = TerminalCache.shared.terminal(for: session, frame: bounds)
        guard terminal.superview !== self else { return }
        for sub in subviews { sub.removeFromSuperview() }
        addSubview(terminal)
    }

    override func layout() {
        super.layout()
        guard let session else { return }
        let inset = bounds.insetBy(dx: 6, dy: 6)
        guard inset.width > 0, inset.height > 0 else { return }

        attachCurrentTerminal()
        let terminal = TerminalCache.shared.terminal(for: session, frame: inset)

        // Only resize on a meaningful delta — sub-pixel jitter during animations would trigger
        // needless tmux redraws.
        let f = terminal.frame
        let delta = abs(f.origin.x - inset.origin.x) + abs(f.origin.y - inset.origin.y)
                  + abs(f.width - inset.width) + abs(f.height - inset.height)
        if delta >= 1.0 { terminal.frame = inset }

        TerminalCache.shared.startProcessIfNeeded(for: session)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let session { TerminalCache.shared.focus(session) }
    }
}
