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

    /// Steht die Ansicht gerade in einem **anderen** Fenster, zeigt der Container das hier statt
    /// einer leeren Fläche (siehe `TerminalCache.darfZeigen`).
    private var hinweis: NSView?
    private var uebernahmeBeobachter: NSObjectProtocol?

    override var isFlipped: Bool { true }

    deinit {
        if let token = uebernahmeBeobachter { NotificationCenter.default.removeObserver(token) }
    }

    /// Move the cached terminal for `session` under this container, detaching any other terminal
    /// currently shown (without terminating it — it stays live in the cache).
    ///
    /// Vor dem Fenster passiert nichts: ohne Fenster wäre nicht zu entscheiden, ob die Ansicht frei
    /// ist — und ein Container, der sie im Vorbeigehen an sich zieht, nähme sie dem Fenster weg, in
    /// dem sie gerade steht. `viewDidMoveToWindow` holt es nach.
    private func attachCurrentTerminal() {
        guard let session, window != nil else { return }
        guard TerminalCache.shared.darfZeigen(session, in: window) else {
            hinweisZeigen(session)
            return
        }
        hinweisEntfernen()
        let terminal = TerminalCache.shared.terminal(for: session, frame: bounds)
        guard terminal.superview !== self else { return }
        for sub in subviews { sub.removeFromSuperview() }
        addSubview(terminal)
    }

    /// Statt eines leeren Terminals: sagen, wo die Ansicht steht, und anbieten, sie herzuholen.
    private func hinweisZeigen(_ session: String) {
        for sub in subviews where sub !== hinweis { sub.removeFromSuperview() }
        guard hinweis == nil else { return }
        let view = NSHostingView(rootView: TerminalElsewhereView { [weak self] in
            TerminalCache.shared.uebernehmen(session)
            self?.attachCurrentTerminal()
            self?.needsLayout = true
        })
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        hinweis = view
        beobachten()
    }

    private func hinweisEntfernen() {
        hinweis?.removeFromSuperview()
        hinweis = nil
    }

    /// Gibt das andere Fenster die Ansicht her, soll dieser Container sie nehmen können, ohne dass
    /// jemand die Grösse ändert.
    private func beobachten() {
        guard uebernahmeBeobachter == nil else { return }
        uebernahmeBeobachter = NotificationCenter.default.addObserver(
            forName: TerminalCache.uebernommen, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, note.object as? String == self.session else { return }
                    self.attachCurrentTerminal()
                    self.needsLayout = true
                }
            }
    }

    override func layout() {
        super.layout()
        guard let session else { return }
        let inset = bounds.insetBy(dx: 6, dy: 6)
        guard inset.width > 0, inset.height > 0 else { return }

        attachCurrentTerminal()
        guard hinweis == nil else { return }
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
        guard window != nil, let session else { return }
        attachCurrentTerminal()
        if hinweis == nil { TerminalCache.shared.focus(session) }
    }
}

/// Dieselbe tmux-Session steht schon in einem anderen Fenster — möglich nur bei Projekten, die sich
/// ein Repo teilen und damit dieselben `!<iid>`-Karten zeigen. Die lebende Ansicht gibt es nur
/// einmal; dieses Fenster sagt das, statt eine leere Fläche zu zeigen.
private struct TerminalElsewhereView: View {
    let holen: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 8) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("Dieses Terminal steht in einem anderen Fenster")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Dasselbe Ticket ist in zwei Projekten desselben Repos offen. Die Session läuft "
                     + "weiter — sichtbar ist sie immer nur an einer Stelle.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Hierher holen", action: holen)
                    .padding(.top, 2)
            }
            .padding()
        }
        .overlay(alignment: .top) { Divider() }
    }
}
