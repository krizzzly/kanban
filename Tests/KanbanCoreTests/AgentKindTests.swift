import XCTest
@testable import KanbanCore

/// Die Unterschiede zwischen den beiden Agents — genau die, auf die sich Board, Console und
/// Asset-Auslieferung verlassen.
final class AgentKindTests: XCTestCase {
    func testPrefixesMatchWhatTheAgentsActuallyAccept() {
        // Claude: Slash-Command. Codex: Skills laufen über `$name` (der `@`-Picker fügt das ein);
        // `/name` gibt es dort nicht mehr, seit Custom Prompts aus dem Menü verschwunden sind.
        XCTAssertEqual(AgentKind.claude.commandPrefix, "/")
        XCTAssertEqual(AgentKind.codex.commandPrefix, "$")
    }

    func testHomesAndAssetLocations() {
        XCTAssertEqual(AgentKind.claude.homeDir.lastPathComponent, ".claude")
        XCTAssertEqual(AgentKind.codex.homeDir.lastPathComponent, ".codex")
        XCTAssertEqual(AgentKind.claude.userSkillsDir.lastPathComponent, "skills")
        XCTAssertEqual(AgentKind.codex.userSkillsDir.lastPathComponent, "skills")
        // Nur Claude kennt Commands als eigene Gattung.
        XCTAssertNotNil(AgentKind.claude.userCommandsDir)
        XCTAssertNil(AgentKind.codex.userCommandsDir)
        XCTAssertEqual(AgentKind.codex.projectDirName, ".codex")
    }

    func testTranscriptAndSessionCapabilities() {
        XCTAssertTrue(AgentKind.claude.supportsPresetSessionId)
        // Codex erfindet seine Id selbst — deshalb läuft die Zuordnung über den Thread-Namen.
        XCTAssertFalse(AgentKind.codex.supportsPresetSessionId)
    }

    /// Der Thread-Name ist die Brücke Ticket → Codex-Session und muss zum tmux-Namen **der
    /// Codex-Sitzung** passen — beide Seiten benutzen dieselbe Zeichenfolge.
    func testCodexThreadNameMatchesTheTmuxSessionName() {
        XCTAssertEqual(CodexSessions.threadName(forTicket: "even-3687"), "kanban-EVEN-3687-codex")
        XCTAssertEqual(CodexSessions.threadName(forTicket: "EVEN-3687"),
                       TerminalSessionResolver.sessionName(forTicket: "EVEN-3687", agent: .codex))
    }

    /// Resume nur mit Rollout — ohne bricht `codex resume` sichtbar ab („no rollout found").
    func testCodexResumesOnlyWithARollout() {
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .codex, sessionId: "abc",
                                                            hasTranscript: true),
                       "codex resume 'abc' -c tui.resume_cwd=current")
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .codex, sessionId: "abc",
                                                            hasTranscript: false), "codex")
    }

    func testConfigValueIsToleratedAndFallsBack() {
        XCTAssertEqual(AgentKind(configValue: "codex"), .codex)
        XCTAssertEqual(AgentKind(configValue: " CODEX "), .codex)
        XCTAssertNil(AgentKind(configValue: nil))
        XCTAssertNil(AgentKind(configValue: ""))
        XCTAssertNil(AgentKind(configValue: "gpt"))          // Tippfehler → Aufrufer nimmt Fallback
        XCTAssertEqual(AgentKind.fallback, .claude)
    }

    func testLaunchCommandPerAgent() {
        let id = "1a2b"
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .claude, sessionId: id),
                       "claude --session-id '1a2b'")
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .claude, sessionId: id,
                                                            hasTranscript: true),
                       "claude --resume '1a2b'")
        // Codex bekommt keine Id mit: `--session-id` gibt es nicht.
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .codex, sessionId: id), "codex")
        XCTAssertEqual(TerminalSessionResolver.launchCommand(agent: .codex, sessionId: nil), "codex")
    }

    func testResolvedPlanLaunchesTheProjectsAgent() {
        let plan = TerminalSessionResolver.resolve(ticketKey: "EVEN-1", repoDir: "/repo",
                                                  worktree: nil, sessionId: "abc",
                                                  agent: .codex, existing: [])
        XCTAssertEqual(plan.name, "kanban-EVEN-1-codex")
        XCTAssertEqual(plan.launchCommand, "codex")
    }

    /// Claude behält den unsuffixierten Namen, Codex bekommt den zusätzlichen: so bleibt jede
    /// bestehende Sitzung erreichbar, und die beiden kommen sich nie ins Gehege.
    func testSessionNamesAreDistinctPerAgent() {
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "even-1", agent: .claude),
                       "kanban-EVEN-1")
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "even-1", agent: .codex),
                       "kanban-EVEN-1-codex")
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "even-1", agent: .claude),
                       TerminalSessionResolver.sessionName(forTicket: "even-1"))
        XCTAssertNil(AgentKind.claude.sessionNameSuffix)
        XCTAssertEqual(AgentKind.claude.other, .codex)
        XCTAssertEqual(AgentKind.codex.other, .claude)
    }

    /// Nebensitzungen tragen den Agent an derselben Stelle wie die Hauptsitzung: direkt hinter dem
    /// Key. Die Projekt-Console hängt daran — sie hängt sich an einen vorhandenen Namen an, ohne zu
    /// prüfen, welcher Agent darin läuft.
    func testSideSessionNamesCarryTheAgentToo() {
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "kanban", suffix: "new",
                                                           agent: .claude), "kanban-KANBAN-new")
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "kanban", suffix: "new",
                                                           agent: .codex), "kanban-KANBAN-codex-new")
    }
}
