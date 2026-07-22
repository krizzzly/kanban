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

    func testEnsureSessionIdGeneratesPersistsAndIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EVEN-1-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "# EVEN-1 | Title\n\n## Beschreibung\nHi".write(to: url, atomically: true, encoding: .utf8)

        let id1 = TaskFileLoader.ensureSessionId(url: url)
        XCTAssertNotNil(id1)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("kanban-claude-session: \(id1!)"))

        // Second call returns the same id and does not add a second marker.
        let id2 = TaskFileLoader.ensureSessionId(url: url)
        XCTAssertEqual(id1, id2)
        let onDisk2 = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk2.components(separatedBy: "kanban-claude-session:").count - 1, 1)
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
