import XCTest
@testable import KanbanCore

/// Exercises the transcript → turn-timing derivation on synthetic Claude Code transcripts.
final class ClaudeTurnTimingTests: XCTestCase {

    // MARK: - Fixtures

    private func prompt(_ id: String, _ timestamp: String, text: String = "mach was") -> String {
        #"{"type":"user","promptId":"\#(id)","message":{"role":"user","content":"\#(text)"},"isSidechain":false,"timestamp":"\#(timestamp)"}"#
    }

    private func assistant(_ timestamp: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}],"stop_reason":"tool_use"},"isSidechain":false,"timestamp":"\#(timestamp)"}"#
    }

    private func toolResult(_ id: String, _ timestamp: String) -> String {
        #"{"type":"user","promptId":"\#(id)","message":{"role":"user","content":[{"type":"tool_result","content":"done"}]},"isSidechain":false,"timestamp":"\#(timestamp)"}"#
    }

    private func turnDuration(_ millis: Int, _ timestamp: String) -> String {
        #"{"type":"system","subtype":"turn_duration","durationMs":\#(millis),"isSidechain":false,"timestamp":"\#(timestamp)"}"#
    }

    private func turns(_ lines: [String]) -> [ClaudeTurn] {
        var accumulator = ClaudeTurnAccumulator()
        for line in lines { accumulator.consume(line: line) }
        return accumulator.snapshot()
    }

    // MARK: - Turn grouping

    func testToolResultsStayInsideTheirTurn() {
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:00:05.000Z"),
            toolResult("p1", "2026-08-05T10:00:20.000Z"),
            assistant("2026-08-05T10:00:30.000Z"),
            turnDuration(30_000, "2026-08-05T10:00:30.500Z"),
            prompt("p2", "2026-08-05T10:05:00.000Z"),
            assistant("2026-08-05T10:05:10.000Z"),
            turnDuration(10_000, "2026-08-05T10:05:10.200Z"),
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].promptId, "p1")
        XCTAssertEqual(result[0].seconds, 30, accuracy: 0.01)
        XCTAssertEqual(result[1].seconds, 10, accuracy: 0.01)
        // The idle 4.5 min between the turns belongs to neither.
        XCTAssertEqual(ClaudeSessionTiming(sessionId: "s", turns: result).total, 40, accuracy: 0.01)
    }

    func testReportedDurationWinsOverSpanBlockedOnTheUser() {
        // A turn that waited an hour for a permission answer did not run for an hour.
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:00:05.000Z"),
            toolResult("p1", "2026-08-05T11:00:00.000Z"),
            turnDuration(12_000, "2026-08-05T11:00:01.000Z"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].seconds, 12, accuracy: 0.01)
        XCTAssertEqual(result[0].spanSeconds, 3601, accuracy: 0.01)
        XCTAssertTrue(result[0].isExact)
    }

    func testOvernightTurnReportedByClaudeIsClampedToItsObservedActivity() {
        // Real case (BFEZVM-4462): Claude reported one turn as 11.2 h because it sat at a permission
        // prompt all night, while its transcript shows minutes of activity.
        let result = turns([
            prompt("p1", "2026-08-05T20:37:00.000Z"),
            assistant("2026-08-05T20:38:00.000Z"),
            toolResult("p1", "2026-08-06T07:48:00.000Z"),   // answered the next morning
            assistant("2026-08-06T07:50:00.000Z"),
            turnDuration((11 * 3600 + 13 * 60) * 1000, "2026-08-06T07:50:05.000Z"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isExact, "a clamped turn must not claim to be Claude's own number")
        // 1 min + capped gap + 2 min + 5 s of activity, plus at most one more gap cap.
        XCTAssertLessThan(result[0].seconds, 3600)
        XCTAssertEqual(result[0].seconds,
                       result[0].estimatedSeconds + ClaudeTurnAccumulator.idleGapCap, accuracy: 0.01)
    }

    func testALongSilentToolCallIsCountedOnlyUpToOneExtraGapCap() {
        // A 40-minute build appends nothing meanwhile. The turn keeps 10 min of that silence from the
        // gap cap and 10 min more from the reported-duration allowance; beyond that, silence is not
        // distinguishable from an unattended machine, so the remaining 20 min are not counted.
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:01:00.000Z"),
            toolResult("p1", "2026-08-05T10:41:00.000Z"),
            turnDuration(41 * 60 * 1000, "2026-08-05T10:41:02.000Z"),
        ])
        let cap = ClaudeTurnAccumulator.idleGapCap
        XCTAssertEqual(result[0].seconds, 60 + cap + 2 + cap, accuracy: 0.01)
        XCTAssertFalse(result[0].isExact)
    }

    func testAReportedDurationWithinTheAllowanceIsKeptExactly() {
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:04:00.000Z"),
            turnDuration(4 * 60 * 1000 + 500, "2026-08-05T10:04:01.000Z"),
        ])
        XCTAssertEqual(result[0].seconds, 240.5, accuracy: 0.01)
        XCTAssertTrue(result[0].isExact)
    }

    func testTurnWithoutReportedDurationFallsBackToItsEntryGaps() {
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:00:42.000Z"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].seconds, 42, accuracy: 0.01)
        XCTAssertFalse(result[0].isExact)
    }

    func testUnmeasuredTurnDoesNotBookTimeSpentWaitingForTheUser() {
        // Claude asked something and the answer came 90 minutes later. Without a turn_duration record
        // only the capped gap may count — the wait is not work.
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:00:20.000Z"),
            toolResult("p1", "2026-08-05T11:30:20.000Z"),
            assistant("2026-08-05T11:30:30.000Z"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isExact)
        XCTAssertEqual(result[0].seconds, 20 + ClaudeTurnAccumulator.idleGapCap + 10, accuracy: 0.01)
        // The full wall clock stays available for the "incl. waiting" line.
        XCTAssertEqual(result[0].spanSeconds, 90 * 60 + 30, accuracy: 0.01)
    }

    func testEntriesWrittenOutOfOrderNeverSubtractTime() {
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:00:20.000Z"),
            assistant("2026-08-05T10:00:19.998Z"),   // same batch, milliseconds reversed
            assistant("2026-08-05T10:00:30.000Z"),
        ])
        XCTAssertEqual(result[0].seconds, 30, accuracy: 0.01)
    }

    func testSidechainEntriesAreIgnored() {
        let sidechain = #"{"type":"user","promptId":"sub","message":{"role":"user","content":"subagent"},"isSidechain":true,"timestamp":"2026-08-05T10:00:10.000Z"}"#
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            sidechain,
            assistant("2026-08-05T10:00:20.000Z"),
        ])
        XCTAssertEqual(result.count, 1, "a subagent prompt must not open a turn of its own")
        XCTAssertEqual(result[0].seconds, 20, accuracy: 0.01)
    }

    func testUnrelatedEntriesNeitherOpenNorExtendTurns() {
        let result = turns([
            #"{"type":"file-history-snapshot","messageId":"x","snapshot":{"big":"payload"}}"#,
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:00:10.000Z"),
            // An attachment written much later must not inflate the turn.
            #"{"type":"attachment","attachment":{"kind":"x"},"isSidechain":false,"timestamp":"2026-08-05T10:30:00.000Z"}"#,
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].seconds, 10, accuracy: 0.01)
    }

    func testQueuedPromptReusingItsIdStaysASeparateTurn() {
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            assistant("2026-08-05T10:00:10.000Z"),
            prompt("p2", "2026-08-05T10:01:00.000Z"),
            assistant("2026-08-05T10:01:10.000Z"),
            prompt("p1", "2026-08-05T10:02:00.000Z"),
            assistant("2026-08-05T10:02:30.000Z"),
        ])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Set(result.map(\.id)).count, 3, "ids must stay unique when a promptId repeats")
    }

    // MARK: - Session summary

    func testSessionSummaryAndRunningTurn() {
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            turnDuration(60_000, "2026-08-05T10:01:00.000Z"),
            prompt("p2", "2026-08-05T10:02:00.000Z"),
            turnDuration(120_000, "2026-08-05T10:04:00.000Z"),
            prompt("p3", "2026-08-05T10:05:00.000Z"),   // no turn-end record yet → still open
            assistant("2026-08-05T10:05:30.000Z"),
        ])
        let timing = ClaudeSessionTiming(sessionId: "s", turns: result)
        XCTAssertEqual(timing.turnCount, 3)
        XCTAssertEqual(timing.total, 60 + 120 + 30, accuracy: 0.01)
        XCTAssertEqual(timing.average ?? 0, 70, accuracy: 0.01)
        XCTAssertEqual(timing.longest?.promptId, "p2")
        XCTAssertEqual(timing.openTurn?.promptId, "p3")

        // A live turn counts up to now, replacing its last-entry span.
        let start = TranscriptTime.parse("2026-08-05T10:05:00.000Z")!
        let live = timing.total(runningSince: start, now: start.addingTimeInterval(300))
        XCTAssertEqual(live, 60 + 120 + 300, accuracy: 0.01)
    }

    func testClosedSessionHasNoOpenTurn() {
        let timing = ClaudeSessionTiming(sessionId: "s", turns: turns([
            prompt("p1", "2026-08-05T10:00:00.000Z"),
            turnDuration(60_000, "2026-08-05T10:01:00.000Z"),
        ]))
        XCTAssertNil(timing.openTurn)
        XCTAssertEqual(timing.total(runningSince: nil), 60, accuracy: 0.01)
    }

    // MARK: - Prompt preview

    func testSlashCommandCollapsesToCommandAndArguments() {
        let raw = """
        <command-message>start-task</command-message>
        <command-name>/start-task</command-name>
        <command-args>BFEZVM-4259</command-args>
        # START TASK — eine sehr lange Arbeitsanweisung, die niemand in der Liste sehen will …
        """
        XCTAssertEqual(ClaudeTurnAccumulator.condense(raw), "/start-task BFEZVM-4259")
    }

    func testPromptPreviewCollapsesWhitespaceAndTruncates() {
        XCTAssertEqual(ClaudeTurnAccumulator.condense("bitte\n\n  das  hier\tfixen"), "bitte das hier fixen")
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(ClaudeTurnAccumulator.condense(long, limit: 10), String(repeating: "a", count: 10) + "…")
    }

    func testPromptIsTakenFromTheOpeningEntryWhenItHasOne() {
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.000Z", text: "warum ist das langsam?"),
            assistant("2026-08-05T10:00:10.000Z"),
        ])
        XCTAssertEqual(result.first?.prompt, "warum ist das langsam?")
    }

    // MARK: - Prompts behind an interrupt

    /// Ein Text-Block als User-Eintrag — so schreibt Claude Code den Abbruch-Marker.
    private func textBlock(_ id: String, _ timestamp: String, text: String) -> String {
        #"{"type":"user","promptId":"\#(id)","message":{"role":"user","content":[{"type":"text","text":"\#(text)"}]},"isSidechain":false,"timestamp":"\#(timestamp)"}"#
    }

    /// Esc mitten in der Antwort, dann sofort weitertippen: Claude Code legt den Abbruch-Marker unter
    /// die promptId des **folgenden** Prompts, und die Datei führt ihn zuerst. Ohne Nachziehen stand
    /// „[Request interrupted by user]" in der Bubble statt dessen, was getippt wurde (38 von 974
    /// Turns im gemessenen Korpus).
    func testAnInterruptedTurnShowsWhatWasTypedAfterIt() {
        let result = turns([
            textBlock("p2", "2026-08-05T10:00:00.000Z", text: "[Request interrupted by user]"),
            prompt("p2", "2026-08-05T10:00:00.400Z", text: "ok ein commit pro stufe"),
            assistant("2026-08-05T10:00:12.000Z"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.promptFull, "ok ein commit pro stufe")
        XCTAssertEqual(result.first?.prompt, "ok ein commit pro stufe")
    }

    /// Abgelehnter Werkzeugaufruf: der Turn öffnet mit einem `tool_result` ganz ohne Text, dann folgt
    /// der Marker, dann der Prompt. Diese Bubbles fehlten in der Liste komplett — sie filtert Turns
    /// ohne Text (33 von 974).
    func testARejectedToolUseDoesNotSwallowTheNextPrompt() {
        let result = turns([
            toolResult("p2", "2026-08-05T10:00:00.000Z"),
            textBlock("p2", "2026-08-05T10:00:00.100Z", text: "[Request interrupted by user for tool use]"),
            prompt("p2", "2026-08-05T10:00:05.000Z", text: "was genau machst du gerade ?"),
            assistant("2026-08-05T10:00:20.000Z"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.promptFull, "was genau machst du gerade ?")
    }

    /// Ein Abbruch **ohne** neuen Prompt ist kein Prompt: der Turn behält seine Zeit (⏱-Liste), hat
    /// aber keinen Text und fällt damit aus der Prompt-Liste.
    func testAPlainInterruptIsNoPrompt() {
        let result = turns([
            textBlock("p2", "2026-08-05T10:00:00.000Z", text: "[Request interrupted by user]"),
            assistant("2026-08-05T10:00:04.000Z"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.promptFull, "")
        XCTAssertEqual(result.first?.seconds ?? 0, 4, accuracy: 0.01)
    }

    /// Lokale Commands: die Datei führt das Caveat-Geschwätz **vor** dem `<command-name>`-Eintrag
    /// (der eine Millisekunde früher entstand), also stand dort bisher gar nichts.
    func testALocalCommandIsNamedEvenWhenTheCaveatComesFirst() {
        let caveat = "<local-command-caveat>Caveat: The messages below were generated by the user while running local commands.</local-command-caveat>"
        let result = turns([
            prompt("p1", "2026-08-05T10:00:00.418Z", text: caveat),
            prompt("p1", "2026-08-05T10:00:00.417Z",
                   text: "<command-name>/exit</command-name> <command-message>exit</command-message>"),
            prompt("p1", "2026-08-05T10:00:00.419Z", text: "<local-command-stdout>Bye!</local-command-stdout>"),
        ])
        XCTAssertEqual(result.first?.promptFull, "/exit")
    }

    /// Claude Codes eigene Einschübe sind kein Ersatz-Prompt — sie kommen als Tag, nie als Prosa.
    func testInjectedTagsNeverStandInForAPrompt() {
        let result = turns([
            textBlock("p2", "2026-08-05T10:00:00.000Z", text: "[Request interrupted by user]"),
            prompt("p2", "2026-08-05T10:00:02.000Z",
                   text: "<task-notification><task-id>abc</task-id></task-notification>"),
        ])
        XCTAssertEqual(result.first?.promptFull, "")
    }

    // MARK: - Timestamps

    func testTimestampParsing() {
        let withMillis = TranscriptTime.parse("2026-07-22T11:59:37.779Z")
        XCTAssertEqual(withMillis?.timeIntervalSince1970 ?? 0, 1784721577.779, accuracy: 0.001)
        let withoutMillis = TranscriptTime.parse("2026-07-22T11:59:37Z")
        XCTAssertEqual(withoutMillis?.timeIntervalSince1970 ?? 0, 1784721577, accuracy: 0.001)
        XCTAssertNil(TranscriptTime.parse("nonsense"))
        // Offsets are rare in transcripts but must not silently become a wrong date.
        XCTAssertEqual(TranscriptTime.parse("2026-07-22T13:59:37+02:00")?.timeIntervalSince1970 ?? 0,
                       1784721577, accuracy: 0.001)
    }

    // MARK: - Formatting

    func testCompactFormatting() {
        XCTAssertEqual(TimeFormatting.compact(0), "0s")
        XCTAssertEqual(TimeFormatting.compact(45), "45s")
        XCTAssertEqual(TimeFormatting.compact(90), "1m 30s")
        XCTAssertEqual(TimeFormatting.compact(12 * 60 + 30), "12m")
        XCTAssertEqual(TimeFormatting.compact(2 * 3600 + 14 * 60), "2h 14m")
    }

    func testClockFormatting() {
        XCTAssertEqual(TimeFormatting.clock(42), "0:42")
        XCTAssertEqual(TimeFormatting.clock(750), "12:30")
        XCTAssertEqual(TimeFormatting.clock(2 * 3600 + 14 * 60 + 7), "2:14:07")
    }

    // MARK: - Incremental tailing

    func testTailParsesOnlyAppendedLines() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = [prompt("p1", "2026-08-05T10:00:00.000Z"),
                     turnDuration(60_000, "2026-08-05T10:01:00.000Z")].joined(separator: "\n") + "\n"
        try first.write(to: url, atomically: true, encoding: .utf8)

        var tail = TranscriptTail()
        var accumulator = ClaudeTurnAccumulator()
        XCTAssertTrue(tail.consumeNewLines(url: url) { accumulator.consume(line: $0) })
        XCTAssertEqual(accumulator.snapshot().count, 1)

        // Append a second turn, plus a partial line that must wait for its newline.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let second = [prompt("p2", "2026-08-05T10:02:00.000Z"),
                      turnDuration(30_000, "2026-08-05T10:02:30.000Z")].joined(separator: "\n") + "\n"
        try handle.write(contentsOf: Data((second + #"{"type":"user","promptId":"p3""#).utf8))
        try handle.close()

        XCTAssertTrue(tail.consumeNewLines(url: url) { accumulator.consume(line: $0) })
        let result = accumulator.snapshot()
        XCTAssertEqual(result.count, 2, "the truncated line must not be parsed yet")
        XCTAssertEqual(ClaudeSessionTiming(sessionId: "s", turns: result).total, 90, accuracy: 0.01)
    }

    func testTailReportsRewrittenFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try (prompt("p1", "2026-08-05T10:00:00.000Z") + "\n").write(to: url, atomically: true, encoding: .utf8)

        var tail = TranscriptTail()
        XCTAssertTrue(tail.consumeNewLines(url: url) { _ in })
        try "".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(tail.consumeNewLines(url: url) { _ in },
                       "a shrunken file invalidates the cached parse state")
    }
}
