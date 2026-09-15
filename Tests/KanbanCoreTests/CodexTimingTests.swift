import XCTest
@testable import KanbanCore

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

final class CodexTimingTests: XCTestCase {
    private func turns(_ lines: [String]) -> [ClaudeTurn] {
        var acc = CodexTurnAccumulator()
        for line in lines { acc.consume(line: line) }
        return acc.snapshot()
    }

    /// Feldnamen wie in echten Rollouts: Unix-Sekunden + `duration_ms`.
    private func started(_ id: String, _ unix: Int) -> String {
        #"{"timestamp":"2026-08-18T19:08:42.250Z","type":"event_msg","payload":{"type":"task_started","turn_id":"\#(id)","started_at":\#(unix)}}"#
    }
    private func completed(_ id: String, _ unix: Int, _ durationMs: Int,
                           type: String = "task_complete") -> String {
        #"{"timestamp":"2026-08-18T19:13:31.256Z","type":"event_msg","payload":{"type":"\#(type)","turn_id":"\#(id)","started_at":\#(unix),"completed_at":\#(unix + durationMs / 1000),"duration_ms":\#(durationMs)}}"#
    }
    private func userMessage(_ text: String, _ ts: String = "2026-08-18T19:08:42.584Z") -> String {
        let escaped = text.replacingOccurrences(of: "\n", with: "\\n")
        return #"{"timestamp":"\#(ts)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"\#(escaped)"}]}}"#
    }

    /// Ein Paar `task_started`/`task_complete` ist ein Turn — Dauer ist Codex' eigene Messung,
    /// deshalb exakt (kein „≈" wie bei geschätzten Claude-Turns).
    func testTurnFromStartedCompletePair() {
        let result = turns([
            started("t1", 1_786_080_522),
            userMessage("bitte schau dir das bundle an"),
            completed("t1", 1_786_080_522, 289_006),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].promptId, "t1")
        XCTAssertEqual(result[0].prompt, "bitte schau dir das bundle an")
        XCTAssertEqual(result[0].seconds, 289.006, accuracy: 0.01)
        XCTAssertTrue(result[0].isExact)
        XCTAssertEqual(result[0].start, Date(timeIntervalSince1970: 1_786_080_522))
    }

    /// Codex' eigener Kontext-Block ist auch eine User-Nachricht — er darf nicht als Prompt gelten.
    func testEnvironmentContextIsNotAPrompt() {
        let result = turns([
            started("t1", 1_786_080_522),
            userMessage("<environment_context>\n  <cwd>/repo</cwd>\n</environment_context>"),
            userMessage("echte Frage"),
            completed("t1", 1_786_080_522, 60_000),
        ])
        XCTAssertEqual(result.map(\.prompt), ["echte Frage"])
    }

    /// Mehrere Turns hintereinander, jeder mit eigener Dauer; die Wartezeit dazwischen zählt nicht.
    func testConsecutiveTurnsExcludeTheGapBetweenThem() {
        let result = turns([
            started("t1", 1_786_080_000),
            userMessage("erste"),
            completed("t1", 1_786_080_000, 60_000),
            started("t2", 1_786_083_600),   // eine Stunde Pause des Menschen
            userMessage("zweite"),
            completed("t2", 1_786_083_600, 120_000),
        ])
        XCTAssertEqual(result.map(\.prompt), ["erste", "zweite"])
        XCTAssertEqual(result.map(\.seconds), [60, 120])
        // Kumuliert wird nur die Arbeitszeit, nicht die Spanne.
        XCTAssertEqual(result.reduce(0) { $0 + $1.seconds }, 180)
    }

    /// Ein Turn ohne Abschluss (Console noch am Arbeiten, oder Datei mitten im Turn abgeschnitten)
    /// hat keine gemessene Dauer und wird verworfen, statt geschätzt zu werden.
    func testUnfinishedTurnIsDropped() {
        let result = turns([
            started("t1", 1_786_080_000),
            userMessage("läuft noch"),
            started("t2", 1_786_080_300),
            userMessage("zweite"),
            completed("t2", 1_786_080_300, 60_000),
        ])
        XCTAssertEqual(result.map(\.prompt), ["zweite"])
    }

    /// `turn_aborted` trägt dieselbe Uhr — die Arbeit hat stattgefunden, also zählt sie.
    func testAbortedTurnCounts() {
        let result = turns([
            started("t1", 1_786_080_000),
            userMessage("abgebrochen"),
            completed("t1", 1_786_080_000, 27_237, type: "turn_aborted"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].seconds, 27.237, accuracy: 0.001)
        XCTAssertEqual(result[0].prompt, "abgebrochen")
    }

    /// Nachgeschriebene Rollouts (Fork/Resume) stempeln jede Zeile mit der Schreibzeit — die Dauer
    /// muss trotzdem stimmen, weil sie aus dem Payload kommt.
    func testDurationIgnoresLineTimestamps() {
        let sameStamp = "2026-08-10T09:27:03.331Z"
        let lines = [
            #"{"timestamp":"\#(sameStamp)","type":"event_msg","payload":{"type":"task_started","turn_id":"t1","started_at":1786351142}}"#,
            #"{"timestamp":"\#(sameStamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"frage"}]}}"#,
            #"{"timestamp":"\#(sameStamp)","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","started_at":1786351142,"completed_at":1786351227,"duration_ms":84878}}"#,
        ]
        let result = turns(lines)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].seconds, 84.878, accuracy: 0.001)
        XCTAssertTrue(result[0].isExact)
    }

    func testGarbageLinesAreIgnored() {
        XCTAssertTrue(turns(["", "kein json", #"{"type":"world_state"}"#]).isEmpty)
    }

    // MARK: Turn-Inhalt (Bubble-Fallback)

    /// Der Leser muss denselben Index treffen wie die ⏱-Liste — sonst zeigt die Bubble den
    /// Inhalt eines anderen Turns.
    func testReaderMatchesAccumulatorIndices() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        let lines = [
            started("t1", 1_786_080_000),
            userMessage("erste frage"),
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"erste Antwort"}]}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"ls"}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call_output","output":[{"type":"input_text","text":"0123456789"}]}}"#,
            completed("t1", 1_786_080_000, 60_000),
            started("t2", 1_786_080_300),
            userMessage("zweite frage"),
            #"{"type":"response_item","payload":{"type":"reasoning","summary":[]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"<skills_instructions>…"}]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"zweite Antwort"}]}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"x"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","name":"wait","arguments":"{}"}}"#,
            completed("t2", 1_786_080_300, 30_000),
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let first = CodexTurnReader.content(turnIndex: 0, rollout: file)
        XCTAssertEqual(first?.answer, "erste Antwort")
        XCTAssertEqual(first?.tools, [ClaudeToolUse(name: "exec", count: 1)])
        XCTAssertEqual(first?.hiddenResults, 1)
        XCTAssertEqual(first?.hiddenBytes, 10)

        let second = CodexTurnReader.content(turnIndex: 1, rollout: file)
        XCTAssertEqual(second?.answer, "zweite Antwort")   // Reasoning und developer bleiben draussen
        XCTAssertEqual(second?.tools, [ClaudeToolUse(name: "exec", count: 1),
                                       ClaudeToolUse(name: "wait", count: 1)])
        XCTAssertNil(CodexTurnReader.content(turnIndex: 2, rollout: file))
    }

    /// Ein abgebrochener Turn ohne geschriebene Antwort fällt auf Codex' `last_agent_message` zurück.
    func testReaderFallsBackToLastAgentMessage() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        let lines = [
            started("t1", 1_786_080_000),
            userMessage("frage"),
            #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","started_at":1786080000,"completed_at":1786080060,"duration_ms":60000,"last_agent_message":"Kurzantwort"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(CodexTurnReader.content(turnIndex: 0, rollout: file)?.answer, "Kurzantwort")
    }

    // MARK: Gegen echte Rollouts

    /// Der Parser gegen die Dateien auf dieser Maschine: jeder Turn muss eine positive, plausible
    /// Dauer haben und die Summe unter der Spanne der Session liegen.
    func testAgainstRealRollouts() throws {
        let root = AgentKind.codex.homeDir.appendingPathComponent("sessions")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.path), "keine Codex-Sessions")

        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("rollout-") } ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(8)
        try XCTSkipUnless(!files.isEmpty, "keine Rollout-Dateien")

        var total = 0
        for file in files {
            var acc = CodexTurnAccumulator()
            for line in (try String(contentsOf: file, encoding: .utf8)).split(separator: "\n") {
                acc.consume(line: String(line))
            }
            let turns = acc.snapshot()
            total += turns.count
            for turn in turns {
                XCTAssertGreaterThan(turn.seconds, 0, "\(file.lastPathComponent) Turn \(turn.index)")
                XCTAssertLessThan(turn.seconds, 6 * 3600, "unplausibel lang")
                XCTAssertTrue(turn.isExact)
                XCTAssertFalse(turn.prompt.hasPrefix("<environment_context"))
            }
            if let first = turns.first, let last = turns.last {
                let span = last.end.timeIntervalSince(first.start)
                XCTAssertLessThanOrEqual(turns.reduce(0) { $0 + $1.seconds }, span + 1)
            }
        }
        print("ECHTDATEN: \(total) Turns aus \(files.count) Rollouts geparst")
        XCTAssertGreaterThan(total, 0)

        // Und der Leser liefert für jeden dieser Turns etwas — Prosa oder Werkzeuge.
        var withContent = 0
        for file in files {
            var acc = CodexTurnAccumulator()
            for line in (try String(contentsOf: file, encoding: .utf8)).split(separator: "\n") {
                acc.consume(line: String(line))
            }
            // Stichprobe statt aller Turns: der Leser macht pro Aufruf einen Datei-Durchlauf (wie
            // der Claude-Leser), 215 Aufrufe über mehrere MB dauerten im Test 83 s.
            let all = acc.snapshot()
            let sample = [all.first, all[safe: all.count / 2], all.last].compactMap { $0 }
            for turn in sample {
                guard let content = CodexTurnReader.content(turnIndex: turn.index, rollout: file) else {
                    XCTFail("kein Inhalt für Turn \(turn.index) in \(file.lastPathComponent)")
                    continue
                }
                XCTAssertEqual(content.turnIndex, turn.index)
                if !content.isEmpty { withContent += 1 }
            }
        }
        print("ECHTDATEN: \(withContent) Stichproben-Turns mit Inhalt gelesen")
        XCTAssertGreaterThan(withContent, 0)
    }
}
