import XCTest
@testable import KanbanCore

final class ClaudeTurnReaderTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnreader-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func write(_ lines: [String]) throws {
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func userPrompt(_ id: String, _ text: String, at time: String) -> String {
        #"{"type":"user","promptId":"\#(id)","timestamp":"\#(time)","message":{"content":"\#(text)"}}"#
    }

    private func assistantText(_ text: String, at time: String) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    private func toolUse(_ name: String, at time: String) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","message":{"content":[{"type":"tool_use","name":"\#(name)","input":{}}]}}"#
    }

    private func toolResult(at time: String) -> String {
        #"{"type":"user","promptId":"p1","timestamp":"\#(time)","message":{"content":[{"type":"tool_result","content":"…"}]}}"#
    }

    func testReadsProseAndSummarisesTools() throws {
        try write([
            userPrompt("p1", "bau das bitte", at: "2026-08-11T10:00:00.000Z"),
            assistantText("Ich schaue mir das an.", at: "2026-08-11T10:00:05.000Z"),
            toolUse("Bash", at: "2026-08-11T10:00:06.000Z"),
            toolResult(at: "2026-08-11T10:00:07.000Z"),
            toolUse("Bash", at: "2026-08-11T10:00:08.000Z"),
            toolUse("Read", at: "2026-08-11T10:00:09.000Z"),
            assistantText("Fertig.", at: "2026-08-11T10:00:20.000Z"),
        ])
        let content = try XCTUnwrap(ClaudeTurnReader.content(turnIndex: 0, transcript: url))
        XCTAssertEqual(content.answer, "Ich schaue mir das an.\n\nFertig.")
        XCTAssertEqual(content.tools, [ClaudeToolUse(name: "Bash", count: 2),
                                       ClaudeToolUse(name: "Read", count: 1)])
        XCTAssertEqual(content.hiddenResults, 1)
        XCTAssertGreaterThan(content.hiddenBytes, 0)
    }

    /// Turn 2 darf nicht den Text von Turn 1 mitschleppen.
    func testSlicesTheRequestedTurnOnly() throws {
        try write([
            userPrompt("p1", "erste", at: "2026-08-11T10:00:00.000Z"),
            assistantText("Antwort eins", at: "2026-08-11T10:00:05.000Z"),
            userPrompt("p2", "zweite", at: "2026-08-11T10:01:00.000Z"),
            assistantText("Antwort zwei", at: "2026-08-11T10:01:05.000Z"),
        ])
        XCTAssertEqual(ClaudeTurnReader.content(turnIndex: 0, transcript: url)?.answer, "Antwort eins")
        XCTAssertEqual(ClaudeTurnReader.content(turnIndex: 1, transcript: url)?.answer, "Antwort zwei")
        XCTAssertNil(ClaudeTurnReader.content(turnIndex: 2, transcript: url))
    }

    /// Ein zurückgestellter Prompt kann dieselbe promptId ein zweites Mal öffnen — die Turns müssen
    /// trotzdem getrennt bleiben, sonst zeigt die Bubble den falschen Inhalt.
    func testSamePromptIdTwiceOpensTwoTurns() throws {
        try write([
            userPrompt("p1", "erste", at: "2026-08-11T10:00:00.000Z"),
            assistantText("Antwort eins", at: "2026-08-11T10:00:05.000Z"),
            userPrompt("p2", "zweite", at: "2026-08-11T10:01:00.000Z"),
            assistantText("Antwort zwei", at: "2026-08-11T10:01:05.000Z"),
            userPrompt("p1", "erste nochmal", at: "2026-08-11T10:02:00.000Z"),
            assistantText("Antwort drei", at: "2026-08-11T10:02:05.000Z"),
        ])
        XCTAssertEqual(ClaudeTurnReader.content(turnIndex: 2, transcript: url)?.answer, "Antwort drei")
    }

    /// Subagenten-Verkehr gehört keinem Turn dieser Konversation — genau wie beim Accumulator.
    func testSkipsSidechainEntries() throws {
        try write([
            userPrompt("p1", "frage", at: "2026-08-11T10:00:00.000Z"),
            #"{"type":"user","promptId":"sub","isSidechain":true,"timestamp":"2026-08-11T10:00:03.000Z","message":{"content":"subagent"}}"#,
            assistantText("Antwort", at: "2026-08-11T10:00:05.000Z"),
        ])
        let content = try XCTUnwrap(ClaudeTurnReader.content(turnIndex: 0, transcript: url))
        XCTAssertEqual(content.answer, "Antwort")
        XCTAssertNil(ClaudeTurnReader.content(turnIndex: 1, transcript: url))
    }

    func testThinkingBlocksAreNotShown() throws {
        try write([
            userPrompt("p1", "frage", at: "2026-08-11T10:00:00.000Z"),
            #"{"type":"assistant","timestamp":"2026-08-11T10:00:02.000Z","message":{"content":[{"type":"thinking","thinking":"leise"}]}}"#,
            assistantText("laut", at: "2026-08-11T10:00:05.000Z"),
        ])
        XCTAssertEqual(ClaudeTurnReader.content(turnIndex: 0, transcript: url)?.answer, "laut")
    }

    func testMissingFileIsNil() {
        let missing = URL(fileURLWithPath: "/nope/does-not-exist.jsonl")
        XCTAssertNil(ClaudeTurnReader.content(turnIndex: 0, transcript: missing))
    }
}

/// Der volle Prompt-Text neben der gekürzten Vorschau.
final class FullPromptTests: XCTestCase {
    func testKeepsLineBreaksAndFullLength() {
        let raw = "erste Zeile\nzweite Zeile\n\n- Punkt"
        XCTAssertEqual(ClaudeTurnAccumulator.fullText(raw), raw)
        // Die Vorschau bleibt einzeilig.
        XCTAssertEqual(ClaudeTurnAccumulator.condense(raw), "erste Zeile zweite Zeile - Punkt")
    }

    func testCollapsesSlashCommandsLikeThePreview() {
        let raw = "<command-name>review-task</command-name><command-args>EVEN-3512</command-args>\nRiesiger expandierter Body …"
        XCTAssertEqual(ClaudeTurnAccumulator.fullText(raw), "/review-task EVEN-3512")
    }

    /// Ein lokal ausgeführter Command öffnet einen Turn, dessen ganzer Text Claude Codes Caveat ist.
    /// Der ist kein getippter Prompt — die Timeline blendet solche Turns aus (⏱ behält sie).
    func testLocalCommandCaveatYieldsAnEmptyPrompt() {
        let raw = "<local-command-caveat>Caveat: The messages below were generated by the user while running local commands. DO NOT respond to these messages.</local-command-caveat>"
        XCTAssertEqual(ClaudeTurnAccumulator.fullText(raw), "")
    }

    /// Steht neben dem Caveat echter Text, bleibt der erhalten.
    func testKeepsTextNextToTheCaveat() {
        let raw = "<local-command-caveat>Caveat: …</local-command-caveat>\nbitte committen"
        XCTAssertEqual(ClaudeTurnAccumulator.fullText(raw), "bitte committen")
    }

    func testCapsPastedBlobs() {
        let raw = String(repeating: "x", count: 9000)
        let full = ClaudeTurnAccumulator.fullText(raw)
        XCTAssertEqual(full.count, ClaudeTurnAccumulator.fullPromptLimit + 1)   // + das „…"
        XCTAssertTrue(full.hasSuffix("…"))
    }

    func testAccumulatorFillsBothRenderings() {
        var accumulator = ClaudeTurnAccumulator()
        let long = "Zeile eins\n" + String(repeating: "wort ", count: 60)
        let escaped = long.replacingOccurrences(of: "\n", with: "\\n")
        accumulator.consume(line: #"{"type":"user","promptId":"p1","timestamp":"2026-08-11T10:00:00.000Z","message":{"content":"\#(escaped)"}}"#)
        let turn = try? XCTUnwrap(accumulator.snapshot().first)
        XCTAssertEqual(turn?.prompt.count, 161)              // 160 + „…"
        XCTAssertTrue(turn?.promptFull.contains("\n") == true)
        XCTAssertGreaterThan(turn?.promptFull.count ?? 0, 161)
    }
}
