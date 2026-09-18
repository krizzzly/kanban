import AppKit
import SwiftTerm
import KanbanCore

/// Owns the live `KanbanTerminalView`s, keyed by tmux session name, so they survive SwiftUI view
/// rebuilds and ticket switches. Switching tickets reparents the cached view (see
/// `TerminalContainerView`) instead of tearing down and re-attaching tmux.
@MainActor
final class TerminalCache {
    static let shared = TerminalCache()
    private init() {}

    private var terminals: [String: KanbanTerminalView] = [:]
    private var started: Set<String> = []

    /// Resolved once; reused for every attach command.
    private let tmuxPath = TmuxController().resolvedTmuxPath

    /// Called when the user clicks inside a terminal. The click is **not** consumed — the terminal
    /// still takes it (focus, selection); this only lets the UI react, e.g. close the prompt overlay.
    ///
    /// Mit dem Fenster, in dem geklickt wurde: den Cache gibt es einmal im Prozess, Board-Fenster
    /// aber mehrere — ohne die Zuordnung (`ProjectWindows`) tickte ein Klick in Fenster A das Model
    /// von Fenster B.
    var onTerminalClick: ((NSWindow?) -> Void)?

    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var copyModeSessions: Set<String> = []
    private var copyModeExitTime: [String: ContinuousClock.Instant] = [:]

    /// Get or create the terminal for a session. The process is **not** started here — call
    /// `startProcessIfNeeded` after layout so the view has a non-zero frame (a 0×0 start makes tmux
    /// clear the pane on the first SIGWINCH).
    func terminal(for name: String, frame: NSRect) -> KanbanTerminalView {
        installScrollMonitors()
        if let existing = terminals[name] { return existing }
        let terminal = KanbanTerminalView(frame: frame)
        terminal.autoresizingMask = []   // frame managed explicitly in layout()
        terminal.applyFont()             // must be set post-construction, not in init
        terminals[name] = terminal
        return terminal
    }

    func has(_ name: String) -> Bool { terminals[name] != nil }

    /// Nach dem Speichern der Einstellungen: Farben, Schrift und Schalter an den **bestehenden**
    /// Ansichten nachziehen. Der laufende tmux-Prozess bleibt, wo er ist — deshalb hier und nicht
    /// über ein Neuanlegen der Ansichten.
    func reapplyAppearance() {
        for terminal in terminals.values {
            terminal.applyAppearance()
            terminal.applyFont()
        }
    }

    /// Attach to the tmux session once — via a login shell that waits for the session to exist
    /// (it may still be spawning) and then `exec`s `tmux attach`, so no lingering shell remains.
    func startProcessIfNeeded(for name: String) {
        guard let terminal = terminals[name], !started.contains(name) else { return }
        guard terminal.frame.width > 0, terminal.frame.height > 0 else { return }
        started.insert(name)
        terminal.applyFont()   // re-assert font now that the view has a real frame + window

        let esc = name.replacingOccurrences(of: "'", with: "'\\''")
        let tmux = tmuxPath
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let script = "for i in $(seq 1 50); do '\(tmux)' has-session -t '\(esc)' 2>/dev/null && break; sleep 0.1; done; exec '\(tmux)' attach-session -t '\(esc)'"
        terminal.startProcess(executable: shell, args: ["-l", "-c", script],
                              environment: nil, execName: nil, currentDirectory: nil)
    }

    /// Give the terminal keyboard focus, retrying once in case a SwiftUI re-render steals it.
    func focus(_ name: String) {
        guard let terminal = terminals[name] else { return }
        DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak terminal] in
            guard let terminal, terminal.window?.firstResponder !== terminal else { return }
            terminal.window?.makeFirstResponder(terminal)
        }
    }

    /// Terminate and drop a terminal. Kills only the attach shell — the tmux session (and Claude)
    /// keeps running, so it can be re-attached later.
    func remove(_ name: String) {
        started.remove(name)
        if let terminal = terminals.removeValue(forKey: name) {
            terminal.removeFromSuperview()
            terminal.terminate()
        }
    }

    /// Jede gehaltene Ansicht loslassen — beim Profilwechsel.
    ///
    /// Die tmux-Sitzungen laufen weiter; hier endet nur die Ansicht darauf. Sie hängt an einem
    /// Sitzungsnamen, und der gehört ab dem Wechsel einem anderen Namensraum — eine stehengebliebene
    /// Ansicht zeigte auf die Konsole der anderen Welt.
    func leeren() {
        for name in Array(terminals.keys) { remove(name) }
        copyModeSessions.removeAll()
        copyModeExitTime.removeAll()
    }

    // MARK: - Scroll handling (tmux copy-mode + hidden caret)

    /// Claude keeps no scrollback of its own — output scrolls into tmux's scrollback — so the only way
    /// to scroll it is tmux copy-mode. SwiftTerm's `scrollWheel` is `public` (not `open`), so we can't
    /// override it; instead we intercept scroll at the app level and drive copy-mode's `scroll-up`/
    /// `scroll-down`. copy-mode shows a cursor, so we **hide the green caret** while scrolling and
    /// restore it on exit. A keyDown monitor leaves copy-mode on any keypress so typing isn't trapped.
    private func installScrollMonitors() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { TerminalCache.shared.handleScroll(event) }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { TerminalCache.shared.handleKeyDown(event) }
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated { TerminalCache.shared.handleClick(event) }
        }
    }

    /// Passes every click through untouched and only reports the ones that landed in a terminal.
    private func handleClick(_ event: NSEvent) -> NSEvent? {
        if let window = event.window, sessionUnderPoint(event.locationInWindow, in: window) != nil {
            onTerminalClick?(window)
        }
        return event
    }

    // MARK: - Eine lebende Ansicht, mehrere Fenster

    /// Darf dieses Fenster die Ansicht der Session zeigen?
    ///
    /// Der Cache hält je Session **eine** `KanbanTerminalView`, und eine `NSView` hat genau einen
    /// Superview. Mit einem Fenster je Projekt kann dasselbe Ticket normalerweise nicht zweimal
    /// offen stehen — ausser bei Projekten, die sich ein Repo und damit ihre `!<iid>`-Karten teilen
    /// (`tp1`/`zvmsupport`/`bfezvm`, `support`/`even`): deren Session heisst in beiden Fenstern
    /// `kanban-!130`. Ohne diese Frage wanderte die Ansicht beim Fensterwechsel hin und her und das
    /// Fenster, aus dem sie verschwand, zeigte eine leere Fläche.
    ///
    /// Frei ist eine Session, deren Ansicht in keinem Fenster hängt — auch die des Fensters, das
    /// gerade geschlossen wurde.
    func darfZeigen(_ name: String, in window: NSWindow?) -> Bool {
        guard let window else { return false }   // noch nicht im Fenster: erst einhängen, dann holen
        guard let belegt = terminals[name]?.window, belegt.isVisible else { return true }
        return belegt === window
    }

    /// Die Ansicht aus dem anderen Fenster herholen. Das dortige `TerminalContainerNSView` erfährt
    /// es über die Benachrichtigung und zeigt seinerseits den Hinweis, statt leer zu bleiben.
    func uebernehmen(_ name: String) {
        terminals[name]?.removeFromSuperview()
        NotificationCenter.default.post(name: Self.uebernommen, object: name)
    }

    /// „Eine Terminal-Ansicht hat das Fenster gewechselt" — `object` ist der Session-Name.
    static let uebernommen = Notification.Name("KanbanTerminalUebernommen")

    private func setCaretHidden(_ hidden: Bool, session: String) {
        terminals[session]?.caretColor = hidden ? .clear : KanbanTerminalView.themedCaretColor
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        // `scrollingDeltaY` (not `deltaY`, which is 0 on trackpads) carries the real delta.
        let delta = event.scrollingDeltaY
        guard delta != 0, let window = event.window,
              let session = sessionUnderPoint(event.locationInWindow, in: window) else {
            return event
        }
        // Cooldown after exiting copy-mode so residual trackpad momentum doesn't re-enter it.
        if let exit = copyModeExitTime[session], exit.duration(to: .now) < .milliseconds(400) {
            return nil
        }

        let inCopyMode = copyModeSessions.contains(session)
        let lines = max(1, Int(abs(delta).rounded()))
        let tmux = TmuxController()

        if delta > 0 {                                     // scroll up → enter/continue copy-mode
            if !inCopyMode {
                copyModeSessions.insert(session)
                setCaretHidden(true, session: session)     // hide the green copy-mode cursor
            }
            let enter = !inCopyMode
            Task.detached {
                if enter { tmux.enterCopyMode(session) }
                tmux.copyScroll(session, up: true, lines: lines)
            }
        } else if inCopyMode {                             // scroll down → toward the bottom
            Task.detached {
                tmux.copyScroll(session, up: false, lines: lines)
                try? await Task.sleep(for: .milliseconds(50))
                if tmux.scrollPosition(session) == "0" {   // back at the bottom → leave copy-mode
                    await MainActor.run { TerminalCache.shared.exitCopyMode(session, viaTmux: tmux) }
                }
            }
        }
        return nil   // consume — never let SwiftTerm turn this into arrow keys
    }

    // MARK: - Jump to a prompt

    /// Scrolls the session's pane so the prompt of `turnIndex` sits in the top row.
    ///
    /// The scrollback is re-scanned here rather than reused from the timeline: at `history-limit` the
    /// pane drops a line off the top for every line Claude appends, so an index taken a minute ago
    /// points somewhere else by now.
    ///
    /// Returns false when the prompt has scrolled out of the history — the caller then falls back to
    /// reading the turn out of the transcript.
    func jump(session: String, prompts: [String], turnIndex: Int) async -> Bool {
        installScrollMonitors()
        // Register the state the wheel/key monitors work from *before* the scroll, so the user can
        // keep scrolling with the wheel from where they land and any keypress leaves copy-mode.
        copyModeSessions.insert(session)
        setCaretHidden(true, session: session)

        let jumped = await Task.detached(priority: .userInitiated) {
            PromptScrollback.jump(session: session, prompts: prompts, turnIndex: turnIndex)
        }.value

        if !jumped { exitCopyMode(session, viaTmux: TmuxController()) }
        return jumped
    }

    /// Which of the session's prompts are still in the scrollback (for greying out the timeline).
    func reachablePrompts(session: String, prompts: [String]) async -> Set<Int> {
        let tmux = TmuxController()
        let scan = await Task.detached(priority: .utility) {
            PromptScrollback.scan(session: session, prompts: prompts, tmux: tmux)
        }.value
        guard let scan else { return [] }
        return Set(scan.locations.keys)
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let responder = event.window?.firstResponder as? NSView,
              let session = session(forResponder: responder) else { return event }

        if copyModeSessions.contains(session) {
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }

            let chars = event.keyCode == 53 ? "" : (event.characters ?? "")   // Esc only dismisses
            let tmux = TmuxController()
            exitCopyMode(session, viaTmux: nil)
            Task.detached {
                tmux.cancelCopyMode(session)
                if !chars.isEmpty { tmux.sendKeys(session, chars) }
            }
            return nil   // consume — the key is re-sent via tmux after leaving copy-mode
        }

        // Wortweises Bearbeiten (⌥← / ⌥→ / ⌥⌫) — hier statt in `KanbanTerminalView.keyDown`, weil
        // SwiftTerms `keyDown` `public` und nicht `open` ist (wie `scrollWheel`). Nur im Normalfall:
        // in copy-mode gilt weiter die Regel oben, dass ⌥/⌘/⌃-Kombinationen durchgereicht werden.
        if let terminal = terminals[session], terminal.handleWordEditingKey(event) { return nil }
        return event
    }

    /// Leave copy-mode: clear state, restore the caret, and (optionally) tell tmux to cancel.
    private func exitCopyMode(_ session: String, viaTmux tmux: TmuxController?) {
        guard copyModeSessions.remove(session) != nil else { return }
        copyModeExitTime[session] = .now
        setCaretHidden(false, session: session)
        if let tmux { Task.detached { tmux.cancelCopyMode(session) } }
    }

    /// The session whose terminal is actually under the pointer — `hitTest`, not a bounds check:
    /// anything drawn *over* the terminal (the prompt timeline) must keep its own scrolling. A bounds
    /// check would hand every wheel event inside the terminal's rectangle to tmux copy-mode, and the
    /// panel on top of it could not be scrolled at all.
    private func sessionUnderPoint(_ windowPoint: NSPoint, in window: NSWindow) -> String? {
        guard let hit = window.contentView?.hitTest(windowPoint) else { return nil }
        return session(forResponder: hit)
    }

    private func session(forResponder responder: NSView) -> String? {
        var view: NSView? = responder
        while let v = view {
            if let term = v as? KanbanTerminalView {
                return terminals.first(where: { $0.value === term })?.key
            }
            view = v.superview
        }
        return nil
    }
}
