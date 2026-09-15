import Foundation

/// One look at a session's tmux pane: where each prompt sits in the scrollback, and how far the view
/// has to travel to put it on screen.
///
/// Always taken fresh, never cached: once the pane hits `history-limit`, every new line drops one off
/// the top and every line index shifts. A capture costs a few milliseconds, a stale index scrolls to
/// the wrong place.
public struct PromptScrollback: Sendable {
    /// turn index → 0-based pane line.
    public let locations: [Int: Int]
    public let totalLines: Int
    public let paneHeight: Int

    public init(locations: [Int: Int], totalLines: Int, paneHeight: Int) {
        self.locations = locations
        self.totalLines = totalLines
        self.paneHeight = paneHeight
    }

    /// Blocking (runs `tmux capture-pane`) — call off the main actor.
    public static func scan(session: String, prompts: [String],
                            tmux: TmuxController = TmuxController()) -> PromptScrollback? {
        guard let lines = tmux.capturePaneLines(session), let height = tmux.paneHeight(session) else {
            return nil
        }
        return PromptScrollback(
            locations: PromptLocator.locate(prompts: prompts, paneLines: lines),
            totalLines: lines.count,
            paneHeight: height)
    }

    /// Lines to scroll up so the turn's prompt lands in the top row; nil when it is not in the
    /// scrollback at all, or already visible without scrolling.
    public func scrollDistance(forTurn index: Int) -> Int? {
        guard let line = locations[index] else { return nil }
        return TmuxController.scrollDistance(toLine: line, totalLines: totalLines, paneHeight: paneHeight)
    }

    public func isReachable(turn index: Int) -> Bool { locations[index] != nil }

    // MARK: - Jumping

    /// Scrolls the pane so the turn's prompt sits in the top row. Blocking — call off the main actor.
    /// Returns false when the prompt is not in the scrollback (the caller falls back to the transcript).
    public static func jump(session: String, prompts: [String], turnIndex: Int,
                            tmux: TmuxController = TmuxController()) -> Bool {
        guard let scan = scan(session: session, prompts: prompts, tmux: tmux),
              scan.isReachable(turn: turnIndex) else { return false }
        guard let distance = scan.scrollDistance(forTurn: turnIndex) else {
            return true   // already on screen — scrolling would only jitter the view
        }
        // Cancel first: re-entering copy-mode keeps the current offset, so scrolling up from a view
        // the user had already scrolled would add up instead of landing on the prompt.
        tmux.cancelCopyMode(session)
        tmux.enterCopyMode(session)
        tmux.copyScroll(session, up: true, lines: distance)
        correct(session: session, prompts: prompts, turnIndex: turnIndex, tmux: tmux)
        return true
    }

    /// How often the landing is re-measured. Two passes settle the normal case; more would only spin
    /// on a console that is writing faster than we can aim.
    private static let corrections = 2

    /// A copy-mode view keeps a fixed distance to the **bottom** of the history, not to the line it
    /// shows: every line Claude appends slides it forward. Measured — a view 20 lines off the bottom
    /// showed `LINE 30`, and three seconds of output later `LINE 83` at the very same
    /// `scroll_position`. So whatever the console wrote between the capture and the scroll lands as
    /// an offset, and the only honest fix is to look again and adjust.
    ///
    /// A turn that is still being answered cannot be pinned at all — it is left wherever it lands.
    private static func correct(session: String, prompts: [String], turnIndex: Int,
                                tmux: TmuxController) {
        for _ in 0..<corrections {
            guard let scan = scan(session: session, prompts: prompts, tmux: tmux),
                  let wanted = scan.scrollDistance(forTurn: turnIndex),
                  let current = tmux.scrollPosition(session).flatMap({ Int($0) })
            else { return }
            let delta = wanted - current
            guard delta != 0 else { return }
            tmux.copyScroll(session, up: delta > 0, lines: abs(delta))
        }
    }
}
