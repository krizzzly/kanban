import XCTest
@testable import KanbanCore

/// Die Regel hinter dem grünen ⏱-Zähler: sie darf nur ticken, solange wirklich gearbeitet wird.
final class LiveTurnTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_757_000_000)

    /// Ein offener Turn (keine gemeldete Dauer) — `end` ist sein letzter Transcript-Eintrag.
    private func openTurn(startedAgo: TimeInterval, lastEntryAgo: TimeInterval) -> ClaudeTurn {
        ClaudeTurn(index: 0, promptId: "p0",
                   start: now.addingTimeInterval(-startedAgo),
                   end: now.addingTimeInterval(-lastEntryAgo),
                   reportedSeconds: nil, estimatedSeconds: startedAgo - lastEntryAgo,
                   prompt: "mach mal")
    }

    private func timing(_ turns: [ClaudeTurn], mtimeAgo: TimeInterval) -> ClaudeSessionTiming {
        ClaudeSessionTiming(sessionId: "s", turns: turns,
                            lastModified: now.addingTimeInterval(-mtimeAgo))
    }

    func testRunsWhileThePaneIsWorking() {
        let t = timing([openTurn(startedAgo: 300, lastEntryAgo: 10)], mtimeAgo: 600)
        XCTAssertEqual(LiveTurn.start(timing: t, isWorking: true, now: now),
                       now.addingTimeInterval(-300))
    }

    /// Der Anfang eines Turns, bevor der erste Pane-Scan lief — das mtime allein trägt ihn.
    func testAFreshTranscriptCarriesTheTurnWithoutAPaneVerdict() {
        let t = timing([openTurn(startedAgo: 30, lastEntryAgo: 5)], mtimeAgo: 5)
        XCTAssertNotNil(LiveTurn.start(timing: t, isWorking: false, now: now))
    }

    func testAnInterruptedTurnDoesNotTick() {
        let t = timing([openTurn(startedAgo: 300, lastEntryAgo: 300)], mtimeAgo: 300)
        XCTAssertNil(LiveTurn.start(timing: t, isWorking: false, now: now))
    }

    /// Ein langer, stiller Werkzeugaufruf (Build, Testlauf, Subagent) bleibt live.
    func testALongSilentToolCallStaysLive() {
        let t = timing([openTurn(startedAgo: 1_000, lastEntryAgo: 900)], mtimeAgo: 900)
        XCTAssertNotNil(LiveTurn.start(timing: t, isWorking: true, now: now))
    }

    /// **Der Fall CORETEST-4237**: unbeantworteter Prompt vom 2026-09-03, Pane meldet „arbeitend"
    /// (dort fälschlich — eine Statuszeile mit Token-Zähler). Ohne die Alters-Schranke buchte der
    /// Zähler 85 h Wanduhr auf einen Turn, an dem niemand arbeitete.
    func testAnAncientOpenTurnDoesNotTickEvenWhenThePaneLooksBusy() {
        let ago: TimeInterval = 85 * 3600
        let t = timing([openTurn(startedAgo: ago, lastEntryAgo: ago)], mtimeAgo: ago)
        XCTAssertNil(LiveTurn.start(timing: t, isWorking: true, now: now))
    }

    /// Dieselbe Schranke gilt dem mtime-Weg: `claude --resume` schreibt das Transcript neu, ohne
    /// den offenen Turn weiterzubringen (an dem Ticket gemessen: mtime 2 Tage jünger als der
    /// letzte Eintrag).
    func testResumeTouchingTheTranscriptDoesNotReviveTheOldTurn() {
        let t = timing([openTurn(startedAgo: 85 * 3600, lastEntryAgo: 85 * 3600)], mtimeAgo: 5)
        XCTAssertNil(LiveTurn.start(timing: t, isWorking: false, now: now))
        XCTAssertNil(LiveTurn.start(timing: t, isWorking: true, now: now))
    }

    /// Ein abgeschlossener Turn (Claude hat seine Dauer gemeldet) ist kein offener.
    func testAFinishedTurnIsNeverLive() {
        let done = ClaudeTurn(index: 0, promptId: "p0", start: now.addingTimeInterval(-300),
                              end: now.addingTimeInterval(-10), reportedSeconds: 290,
                              estimatedSeconds: 290, prompt: "fertig")
        let t = timing([done], mtimeAgo: 5)
        XCTAssertNil(LiveTurn.start(timing: t, isWorking: true, now: now))
    }

    /// Die Schranke wird aus der Kappungslücke abgeleitet, nicht geraten.
    func testStaleBoundMatchesWhatTheAccountingKeeps() {
        XCTAssertEqual(LiveTurn.staleAfter, 2 * ClaudeTurnAccumulator.idleGapCap)
    }
}
