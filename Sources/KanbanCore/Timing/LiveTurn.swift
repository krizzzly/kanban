import Foundation

/// Decides whether a session's open turn is running **right now** — the rule behind the green ⏱
/// counter and the live part of every cumulated total.
///
/// It lives here, in pure logic, because this is the one decision that can book time nobody worked:
/// the transcript cannot tell a running turn from an interrupted one (Claude writes its
/// `turn_duration` record only when it finishes, so an interrupted turn stays open forever), and the
/// counter ticks plain wall clock while the decision says "yes".
///
/// Two outside signals say the console is alive — a transcript written to seconds ago, or the agent's
/// TUI showing its interrupt hint (`PaneAttention.isWorking`) — and one bound says the open turn is
/// what that liveness is *about*.
public enum LiveTurn {
    /// How long a transcript may be untouched before its unfinished last turn stops counting as live
    /// on the strength of its mtime alone. Long tool calls (a build, a test run, a subagent) append
    /// nothing meanwhile, so the tmux "working" signal carries those; this window covers the start of
    /// a turn before the first pane scan.
    public static let freshWindow: TimeInterval = 120

    /// How far the open turn's **own** last entry may be in the past while still counting as the turn
    /// the console is working on.
    ///
    /// Without this bound, liveness evidence about *any* turn kept the *open* one ticking: on
    /// CORETEST-4237 an unanswered prompt from 2026-09-03 counted 85 h of wall clock, because the
    /// console looked busy (there, wrongly — a statusline token counter, see `PaneAttention`). But a
    /// truthful "working" pane does it too: the signal appears the moment a new prompt runs, and
    /// until that prompt reaches the transcript the open turn is still the old one. The same holds
    /// for the mtime path — resuming a session rewrites the transcript without advancing its last
    /// turn (measured on that ticket: mtime 2026-09-05 08:28, last entry 2026-09-03 21:41).
    ///
    /// Two gap caps, because that is exactly how much silence the accounting is willing to keep:
    /// `ClaudeTurn.seconds` allows the reported duration to exceed the observed activity by one
    /// `idleGapCap`, and the estimate itself keeps one capped gap — a live tick beyond that would
    /// count what the settled number then refuses to book. Measured against 1145 finished turns whose
    /// longest silence Claude counts as its own work, 8 (0.7 %) are silent for more than 15 min, so
    /// the bound is above nearly every real build; the case it catches is four orders of magnitude
    /// away. Price: an hour-long silent tool call stops the *live* tick after 20 min — the total
    /// stays right, because Claude's own duration replaces the estimate when the turn ends.
    public static let staleAfter: TimeInterval = 2 * ClaudeTurnAccumulator.idleGapCap

    /// Start of the turn running right now, or nil when nothing runs. `isWorking` is the pane verdict
    /// for this session (`PaneAttention.isWorking`).
    public static func start(timing: ClaudeSessionTiming, isWorking: Bool,
                             now: Date = Date()) -> Date? {
        guard let open = timing.openTurn else { return nil }
        guard now.timeIntervalSince(open.end) < staleAfter else { return nil }
        let fresh = now.timeIntervalSince(timing.lastModified ?? .distantPast) < freshWindow
        guard fresh || isWorking else { return nil }
        return open.start
    }
}
