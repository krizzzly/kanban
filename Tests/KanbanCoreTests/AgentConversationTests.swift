import XCTest
@testable import KanbanCore

/// Welche Id eine Konversation fortsetzt — die Frage, an der `codex resume` / `claude --resume`
/// hängt. Die Sonde ist hier eine Menge statt der Platte, damit die Regel selbst geprüft wird.
final class AgentConversationTests: XCTestCase {
    private func lookup(marker: String?, other: String?, recorded: Set<String>,
                        agent: AgentKind = .codex) -> AgentConversation? {
        AgentConversationLookup.resolve(agent: agent, markerId: marker, otherId: other) {
            recorded.contains($0)
        }
    }

    /// Der Fall, für den es die Probe gibt: die Session wurde neu gestartet und erneut umbenannt —
    /// der Marker zeigt auf den alten Thread, der Index führt den laufenden. Fortgesetzt wird der,
    /// den es gibt.
    func testRecordedIndexIdBeatsAStaleMarker() {
        let found = lookup(marker: "alt", other: "neu", recorded: ["neu"])
        XCTAssertEqual(found?.sessionId, "neu")
        XCTAssertTrue(found?.hasTranscript ?? false)
    }

    /// Tragen beide eine Aufzeichnung, gewinnt das Task-File — dort gehört die Id langfristig hin.
    func testTaskFileWinsWhenBothAreRecorded() {
        XCTAssertEqual(lookup(marker: "ausDatei", other: "ausIndex",
                              recorded: ["ausDatei", "ausIndex"])?.sessionId, "ausDatei")
    }

    /// Nichts aufgezeichnet: die Id bleibt (der Marker geht nicht verloren), aber `hasTranscript`
    /// ist falsch — damit startet der Aufrufer frisch statt ein `resume` zu versuchen, das sichtbar
    /// abbräche („no rollout found for thread id …").
    func testWithoutAnyRecordingNothingIsResumable() {
        let found = lookup(marker: "nie-gelaufen", other: nil, recorded: [])
        XCTAssertEqual(found?.sessionId, "nie-gelaufen")
        XCTAssertFalse(found?.hasTranscript ?? true)
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .codex, sessionId: "nie-gelaufen",
                                                            hasTranscript: false), "codex")
    }

    /// Ein Ticket, an dem dieser Agent nie lief, hat keine Konversation — und bekommt deshalb auch
    /// keinen Reiter.
    func testNoCandidatesMeansNoConversation() {
        XCTAssertNil(lookup(marker: nil, other: nil, recorded: ["irgendwas"]))
        XCTAssertNil(lookup(marker: "", other: "", recorded: []))
    }

    /// Claude nimmt als zweite Fundstelle `sessions.json` — so findet auch ein Ticket ohne Task-File
    /// seine Konversation wieder.
    func testClaudeFallsBackToTheSessionStore() {
        let found = lookup(marker: nil, other: "ausStore", recorded: ["ausStore"], agent: .claude)
        XCTAssertEqual(found?.sessionId, "ausStore")
        XCTAssertEqual(found?.agent, .claude)
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .claude, sessionId: "ausStore",
                                                            hasTranscript: true),
                       "claude --resume 'ausStore'")
    }

    /// Der fortsetzbare Fall, durchgerechnet bis zum Befehl, der in der Console landet.
    func testResumeCommandForARecordedCodexThread() {
        let found = lookup(marker: "01a01e3b", other: nil, recorded: ["01a01e3b"])
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .codex,
                                                            sessionId: found!.sessionId,
                                                            hasTranscript: found!.hasTranscript),
                       "codex resume '01a01e3b' -c tui.resume_cwd=current")
    }
}

/// Der Thread-Index von Codex — die Fundstelle, über die eine Console ohne vorgegebene Id wieder
/// auffindbar wird.
final class CodexThreadIndexTests: XCTestCase {
    private func codexDir(_ lines: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try lines.joined(separator: "\n")
            .write(to: dir.appendingPathComponent("session_index.jsonl"),
                   atomically: true, encoding: .utf8)
        return dir
    }

    func testFindsTheThreadNamedAfterTheCodexSession() throws {
        let dir = try codexDir([
            #"{"id":"01a0","thread_name":"kanban-EVEN-1-codex","updated_at":"2026-09-19T10:00:00Z"}"#,
            #"{"id":"ff00","thread_name":"etwas anderes","updated_at":"2026-09-19T12:00:00Z"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(CodexSessions.sessionId(forTicket: "even-1", codexDir: dir), "01a0")
    }

    /// Ein Thread aus der Zeit vor der Trennung der Agent-Namen bleibt auffindbar.
    func testFallsBackToTheUnsuffixedThreadName() throws {
        let dir = try codexDir([
            #"{"id":"alt99","thread_name":"kanban-EVEN-1","updated_at":"2026-09-01T10:00:00Z"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(CodexSessions.sessionId(forTicket: "EVEN-1", codexDir: dir), "alt99")
    }

    /// Steht beides da, gewinnt der heutige Name — der alte ist Geschichte, nicht Gegenwart.
    func testCurrentNameWinsOverTheLegacyOne() throws {
        let dir = try codexDir([
            #"{"id":"alt99","thread_name":"kanban-EVEN-1","updated_at":"2026-09-19T23:00:00Z"}"#,
            #"{"id":"neu01","thread_name":"kanban-EVEN-1-codex","updated_at":"2026-09-01T08:00:00Z"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(CodexSessions.sessionId(forTicket: "EVEN-1", codexDir: dir), "neu01")
    }

    /// Mehrfach umbenannt: der jüngste Eintrag ist die Konversation, in der gearbeitet wird.
    func testNewestUpdateWinsAmongEqualNames() throws {
        let dir = try codexDir([
            #"{"id":"frueh","thread_name":"kanban-EVEN-1-codex","updated_at":"2026-09-01T08:00:00Z"}"#,
            #"{"id":"spaet","thread_name":"kanban-EVEN-1-codex","updated_at":"2026-09-19T08:00:00Z"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(CodexSessions.sessionId(forTicket: "EVEN-1", codexDir: dir), "spaet")
    }

    func testUnknownTicketHasNoThread() throws {
        let dir = try codexDir([#"{"id":"x","thread_name":"kanban-OTHER-9-codex"}"#])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(CodexSessions.sessionId(forTicket: "EVEN-1", codexDir: dir))
    }
}
