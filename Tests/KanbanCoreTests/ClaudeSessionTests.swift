import XCTest
@testable import KanbanCore

final class ClaudeSessionTests: XCTestCase {
    func testParseNilWhenAbsent() {
        XCTAssertNil(ClaudeSession.parseSessionId("# Title\n\n## Beschreibung\nHi"))
    }

    func testInsertThenParseRoundtrip() {
        let content = "# EVEN-1 | Title\n\n## Beschreibung\nHi"
        let out = ClaudeSession.contentInserting(sessionId: "4f2c-1", into: content)
        XCTAssertEqual(ClaudeSession.parseSessionId(out), "4f2c-1")
        XCTAssertTrue(out.hasSuffix(content))   // original content preserved verbatim
    }

    func testInsertReplacesExistingMarker() {
        let content = "<!-- kanban-claude-session: OLD -->\n# Title\n\n## A\nx"
        let out = ClaudeSession.contentInserting(sessionId: "NEW", into: content)
        XCTAssertEqual(ClaudeSession.parseSessionId(out), "NEW")
        // Exactly one marker remains.
        XCTAssertEqual(out.components(separatedBy: "kanban-claude-session:").count - 1, 1)
        XCTAssertFalse(out.contains("OLD"))
    }

    func testWriteSessionIdPersistsReplacesAndStaysSingle() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EVEN-1-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "# EVEN-1 | Title\n\n## Beschreibung\nHi".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertNil(TaskFileLoader.sessionId(in: url))
        XCTAssertTrue(TaskFileLoader.writeSessionId("aaa-111", url: url))
        XCTAssertEqual(TaskFileLoader.sessionId(in: url), "aaa-111")

        // Rewriting with the live id replaces the stale one instead of adding a second marker.
        XCTAssertTrue(TaskFileLoader.writeSessionId("bbb-222", url: url))
        XCTAssertEqual(TaskFileLoader.sessionId(in: url), "bbb-222")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk.components(separatedBy: "kanban-claude-session:").count - 1, 1)
        XCTAssertTrue(onDisk.contains("## Beschreibung"))
    }

    /// The marker sits in the preamble (before the first H2), so it never becomes a tab and never
    /// reaches rendered content.
    func testMarkerNeverReachesRenderedSections() {
        let content = "<!-- kanban-claude-session: secret-id -->\n# EVEN-1 | Title\n\n## Beschreibung\nHallo"
        let tf = TaskFileLoader.parse(content: content, url: URL(fileURLWithPath: "/x/EVEN-1.md"))
        XCTAssertEqual(tf.sections.map(\.title), ["Beschreibung"])
        XCTAssertFalse(tf.sections.contains { $0.markdown.contains("secret-id") })
    }

    // MARK: - Zwei Agents, zwei Marker

    /// Der Kern: jeder Marker gehört seinem Agent. Wer den einen schreibt, lässt den anderen
    /// zeichengleich stehen — sonst verlöre ein Ticket beim Agent-Wechsel seine halbe Geschichte.
    func testBothMarkersLiveSideBySide() {
        var content = "# EVEN-1 | Title\n\n## Beschreibung\nHi"
        content = ClaudeSession.contentInserting(sessionId: "claude-1", agent: .claude, into: content)
        content = ClaudeSession.contentInserting(sessionId: "codex-1", agent: .codex, into: content)

        XCTAssertEqual(ClaudeSession.parseSessionId(content, agent: .claude), "claude-1")
        XCTAssertEqual(ClaudeSession.parseSessionId(content, agent: .codex), "codex-1")
        XCTAssertTrue(content.hasSuffix("# EVEN-1 | Title\n\n## Beschreibung\nHi"))
    }

    func testReplacingOneMarkerLeavesTheOtherUntouched() {
        var content = "# T\n\n## A\nx"
        content = ClaudeSession.contentInserting(sessionId: "claude-1", agent: .claude, into: content)
        content = ClaudeSession.contentInserting(sessionId: "codex-1", agent: .codex, into: content)
        let updated = ClaudeSession.contentInserting(sessionId: "codex-2", agent: .codex, into: content)

        XCTAssertEqual(ClaudeSession.parseSessionId(updated, agent: .codex), "codex-2")
        XCTAssertEqual(ClaudeSession.parseSessionId(updated, agent: .claude), "claude-1")
        XCTAssertFalse(updated.contains("codex-1"))
        // Genau ein Marker je Agent, egal wie oft geschrieben wird.
        XCTAssertEqual(updated.components(separatedBy: "kanban-codex-session:").count - 1, 1)
        XCTAssertEqual(updated.components(separatedBy: "kanban-claude-session:").count - 1, 1)
    }

    /// Die Reihenfolge hängt am Agent, nicht an der Schreibfolge: eine Datei, die zweimal
    /// geschrieben wird, kommt nicht mit einer anderen Sortierung zurück.
    func testMarkerOrderIsStableWhicheverIsWrittenFirst() {
        let body = "# T\n\n## A\nx"
        var codexFirst = ClaudeSession.contentInserting(sessionId: "c", agent: .codex, into: body)
        codexFirst = ClaudeSession.contentInserting(sessionId: "a", agent: .claude, into: codexFirst)

        var claudeFirst = ClaudeSession.contentInserting(sessionId: "a", agent: .claude, into: body)
        claudeFirst = ClaudeSession.contentInserting(sessionId: "c", agent: .codex, into: claudeFirst)

        XCTAssertEqual(codexFirst, claudeFirst)
        let claudeLine = codexFirst.range(of: "kanban-claude-session:")!
        let codexLine = codexFirst.range(of: "kanban-codex-session:")!
        XCTAssertTrue(claudeLine.lowerBound < codexLine.lowerBound)   // Claude oben
    }

    /// Der Bestand: eine Datei mit nur dem Claude-Marker wird unverändert gelesen, und ein
    /// Codex-Marker kommt hinzu, ohne sie anzufassen.
    func testExistingClaudeOnlyFileKeepsWorking() {
        let content = "<!-- kanban-claude-session: OLD -->\n# T\n\n## A\nx"
        XCTAssertEqual(ClaudeSession.parseSessionId(content), "OLD")
        XCTAssertNil(ClaudeSession.parseSessionId(content, agent: .codex))

        let updated = ClaudeSession.contentInserting(sessionId: "NEW-CODEX", agent: .codex, into: content)
        XCTAssertEqual(ClaudeSession.parseSessionId(updated, agent: .claude), "OLD")
        XCTAssertEqual(ClaudeSession.parseSessionId(updated, agent: .codex), "NEW-CODEX")
        XCTAssertTrue(updated.hasSuffix("# T\n\n## A\nx"))
    }

    /// Ein Marker, der im Status-Tab stünde, wäre der sichtbarste Teil dieses Umbaus — und der
    /// falsche. `parsePreamble` muss beide wegwerfen.
    func testNoMarkerSurvivesIntoTheRenderedPreamble() {
        let content = """
        <!-- kanban-claude-session: aaa -->
        <!-- kanban-codex-session: bbb -->
        # EVEN-1 - Titel

        > 🎫 **JIRA**: `https://example.test/browse/EVEN-1`

        ## Beschreibung
        Text
        """
        let preamble = TaskFileLoader.parsePreamble(content, directory: URL(fileURLWithPath: "/tmp"))
        XCTAssertFalse(preamble.contains("kanban-claude-session"))
        XCTAssertFalse(preamble.contains("kanban-codex-session"))
        XCTAssertTrue(preamble.contains("# EVEN-1 - Titel"))
        XCTAssertTrue(preamble.contains("JIRA"))
    }

    /// Über die Datei hinweg: beide Ids landen im Task-File und lesen sich einzeln wieder heraus.
    func testWriteSessionIdPerAgentOnDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EVEN-2-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "# EVEN-2 | Title\n\n## Beschreibung\nHi".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertTrue(TaskFileLoader.writeSessionId("claude-id", url: url))
        XCTAssertTrue(TaskFileLoader.writeSessionId("codex-id", url: url, agent: .codex))

        XCTAssertEqual(TaskFileLoader.sessionId(in: url), "claude-id")
        XCTAssertEqual(TaskFileLoader.sessionId(in: url, agent: .codex), "codex-id")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("## Beschreibung"))
    }
}
