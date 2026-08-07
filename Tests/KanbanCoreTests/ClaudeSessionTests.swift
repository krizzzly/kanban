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
}
