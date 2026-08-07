import Foundation

/// One measured Claude turn: a user prompt plus everything Claude did in response to it.
///
/// Turns are read out of Claude Code's own conversation transcript, so the numbers are derived from
/// real artifacts — nothing is tracked by hand and nothing is lost when the app restarts.
public struct ClaudeTurn: Identifiable, Sendable, Hashable {
    /// Position in the conversation (0-based). Also the identity: a queued prompt can make the same
    /// `promptId` appear twice, so the id must not be the promptId.
    public let index: Int
    public let promptId: String
    /// Timestamp of the prompt entry.
    public let start: Date
    /// Timestamp of the last entry belonging to this turn.
    public let end: Date
    /// Claude Code's own turn clock (`system/turn_duration`), when the transcript recorded one.
    /// It excludes time the turn sat blocked on the user (permission prompts), which is why it wins
    /// over anything derived — a turn that waited an hour for a "yes" did not run for an hour.
    public let reportedSeconds: TimeInterval?
    /// Fallback for turns Claude wrote no duration for: the time between the turn's entries with
    /// every gap capped (see `ClaudeTurnAccumulator.idleGapCap`), so an answer that hung waiting for
    /// the user does not book that wait as work.
    public let estimatedSeconds: TimeInterval
    /// Short, single-line rendering of the prompt (slash commands collapse to `/name args`).
    public let prompt: String

    public var id: Int { index }

    public init(index: Int, promptId: String, start: Date, end: Date,
                reportedSeconds: TimeInterval?, estimatedSeconds: TimeInterval, prompt: String) {
        self.index = index
        self.promptId = promptId
        self.start = start
        self.end = end
        self.reportedSeconds = reportedSeconds
        self.estimatedSeconds = estimatedSeconds
        self.prompt = prompt
    }

    /// Wall-clock span from the prompt to the last entry of its response — including any time the
    /// turn spent waiting for the user.
    public var spanSeconds: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// The turn's duration: Claude's own measurement where available, else the capped estimate.
    ///
    /// Claude's clock is not always free of idle either — a turn left at a permission prompt overnight
    /// came back reported as 11.2 h while its transcript shows 47 min of activity. So the reported
    /// value may exceed the observed activity by at most one more gap cap, which bounds a night to
    /// minutes. The price: a turn that really did sit in one silent 40-minute build counts 20 min of
    /// it (10 from the gap cap, 10 from this allowance) — silence that long is not distinguishable
    /// from an unattended machine. On this Jira's transcripts exactly 1 of 774 reported turns is
    /// affected, and it is the overnight one.
    public var seconds: TimeInterval {
        guard let reportedSeconds else { return estimatedSeconds }
        return min(reportedSeconds, estimatedSeconds + ClaudeTurnAccumulator.idleGapCap)
    }

    /// False when `seconds` is not Claude's own number — either estimated, or clamped because that
    /// number implied hours of silence (UI marks both "≈").
    public var isExact: Bool { reportedSeconds != nil && seconds == reportedSeconds }
}

/// The cumulative timing of one Claude session (one transcript), plus the per-turn breakdown.
public struct ClaudeSessionTiming: Sendable, Hashable {
    public let sessionId: String
    public let turns: [ClaudeTurn]
    /// Σ of every turn's duration — the cumulated prompt→answer time.
    public let total: TimeInterval
    /// Σ of every turn's raw span, i.e. including time a turn spent waiting for the user.
    public let wallTotal: TimeInterval
    /// mtime of the transcript, used to tell a live turn from an abandoned one.
    public let lastModified: Date?

    public init(sessionId: String, turns: [ClaudeTurn], lastModified: Date? = nil) {
        self.sessionId = sessionId
        self.turns = turns
        self.total = turns.reduce(0) { $0 + $1.seconds }
        self.wallTotal = turns.reduce(0) { $0 + $1.spanSeconds }
        self.lastModified = lastModified
    }

    public var turnCount: Int { turns.count }

    public var average: TimeInterval? { turns.isEmpty ? nil : total / Double(turns.count) }

    public var longest: ClaudeTurn? { turns.max { $0.seconds < $1.seconds } }

    public var lastActivity: Date? { turns.last?.end }

    /// The last turn when Claude never wrote a turn-end record for it — so it is either still running
    /// or was interrupted. Deciding which needs a liveness signal the transcript cannot give
    /// (see `AppModel.runningTurnStart`).
    public var openTurn: ClaudeTurn? {
        guard let last = turns.last, !last.isExact else { return nil }
        return last
    }

    /// The cumulated total without the open turn — the fixed part a live counter ticks on top of.
    public var totalExcludingOpenTurn: TimeInterval { total - (openTurn?.seconds ?? 0) }

    /// The cumulated total with a currently running turn counted up to `now` instead of up to its
    /// last transcript entry. `runningSince` is the open turn's start, or nil when nothing runs.
    ///
    /// The live part is plain wall clock — the caller only counts it while the console is verifiably
    /// working (see `AppModel.runningTurnStart`), and the moment the turn ends Claude's own duration
    /// replaces the estimate, so the settled total is exact either way.
    public func total(runningSince: Date?, now: Date = Date()) -> TimeInterval {
        guard let runningSince, let open = openTurn else { return total }
        return totalExcludingOpenTurn + max(open.seconds, now.timeIntervalSince(runningSince))
    }
}

/// Duration rendering shared by badges, chips and the turn list.
public enum TimeFormatting {
    /// Narrow, badge-friendly: `45s` · `1m 30s` · `12m` · `2h 14m`.
    public static func compact(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "\(max(0, total))s" }
        let minutes = total / 60
        if minutes < 10 { return "\(minutes)m \(total % 60)s" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// Stopwatch style for the ticking live turn: `0:42` · `12:30` · `2:14:07`.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
