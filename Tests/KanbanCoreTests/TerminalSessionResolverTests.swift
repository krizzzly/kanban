import XCTest
@testable import KanbanCore

final class TerminalSessionResolverTests: XCTestCase {
    private let repo = "/Users/x/code/even"

    func testSessionNameIsUppercasedAndPrefixed() {
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "even-1"), "kanban-EVEN-1")
    }

    func testCreatesOwnSessionWhenNothingExists() {
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: nil, sessionId: "abc-123", existing: [])
        XCTAssertEqual(plan.name, "kanban-EVEN-1")
        XCTAssertEqual(plan.cwd, repo)              // main tree
        XCTAssertTrue(plan.needsCreate)
        // No transcript yet → create the conversation with exactly this id.
        XCTAssertEqual(plan.launchCommand, "claude --session-id 'abc-123'")
    }

    func testResumesWhenTranscriptExists() {
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: nil, sessionId: "abc-123",
            hasTranscript: true, existing: [])
        XCTAssertEqual(plan.launchCommand, "claude --resume 'abc-123'")
    }

    func testOwnSessionExistsAttachesWithoutCommand() {
        let existing = [TmuxSession(name: "kanban-EVEN-1", path: "/somewhere", attached: false)]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: nil, sessionId: "abc", existing: existing)
        XCTAssertEqual(plan.name, "kanban-EVEN-1")
        XCTAssertNil(plan.launchCommand)            // attach, never re-inject
        XCTAssertFalse(plan.needsCreate)
    }

    func testWorktreeMatchByExactPath() {
        let wt = Worktree(path: "/Users/x/code/even-worktree/EVEN-1", branch: "feature/EVEN-1_foo")
        let existing = [TmuxSession(name: "some-session", path: wt.path, attached: true)]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: wt, sessionId: "abc", existing: existing)
        XCTAssertEqual(plan.name, "some-session")
        XCTAssertEqual(plan.cwd, wt.path)
        XCTAssertNil(plan.launchCommand)
    }

    func testWorktreeMatchByDirName() {
        let wt = Worktree(path: "/Users/x/code/even-worktree/EVEN-1", branch: nil)
        let existing = [TmuxSession(name: "EVEN-1", path: "/other", attached: false)]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: wt, sessionId: "abc", existing: existing)
        XCTAssertEqual(plan.name, "EVEN-1")
        XCTAssertNil(plan.launchCommand)
    }

    func testWorktreeMatchByDashedBranch() {
        let wt = Worktree(path: "/Users/x/code/even-worktree/EVEN-1", branch: "feature/EVEN-1_foo")
        let existing = [TmuxSession(name: "feature-EVEN-1_foo", path: "/other", attached: false)]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: wt, sessionId: "abc", existing: existing)
        XCTAssertEqual(plan.name, "feature-EVEN-1_foo")
        XCTAssertNil(plan.launchCommand)
    }

    func testOwnSessionWinsOverWorktreeMatch() {
        let wt = Worktree(path: "/wt/EVEN-1", branch: nil)
        let existing = [
            TmuxSession(name: "EVEN-1", path: "/wt/EVEN-1", attached: false),   // worktree match
            TmuxSession(name: "kanban-EVEN-1", path: repo, attached: false),    // our own
        ]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: wt, sessionId: "abc", existing: existing)
        XCTAssertEqual(plan.name, "kanban-EVEN-1")   // priority 1
    }

    func testLaunchCommandFallsBackToPlainClaudeWithoutId() {
        XCTAssertEqual(TerminalSessionResolver.claudeLaunchCommand(sessionId: nil), "claude")
        XCTAssertEqual(TerminalSessionResolver.claudeLaunchCommand(sessionId: ""), "claude")
    }

    // MARK: - Zwei Agents nebeneinander

    /// Die Falle, die den zweiten Sitzungsnamen erst gefährlich macht: das Worktree-Terminal (`-wt`)
    /// läuft **im Worktree** und besteht damit die Pfad-Prüfung der Kompatibilitätsstufe. Übernähme
    /// der Resolver es, zeigte der Agent-Reiter eine nackte Shell — angehängt wird ja, nie bestückt,
    /// und der Agent startete nie.
    func testOwnSideSessionIsNotAdoptedAsAgentConsole() {
        let wt = Worktree(path: "/wt/EVEN-1", branch: "feature/EVEN-1_foo")
        let existing = [TmuxSession(name: "kanban-EVEN-1-wt", path: wt.path, attached: false)]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: wt, sessionId: nil,
            agent: .codex, existing: existing)

        XCTAssertEqual(plan.name, "kanban-EVEN-1-codex")
        XCTAssertEqual(plan.cwd, repo)
        XCTAssertEqual(plan.launchCommand, "codex")
    }

    /// Dasselbe für Claude: auch seine Console darf nicht im Worktree-Terminal landen, wenn die
    /// eigene Sitzung einmal beendet wurde.
    func testOwnSideSessionIsNotAdoptedForClaudeEither() {
        let wt = Worktree(path: "/wt/EVEN-1", branch: nil)
        let existing = [TmuxSession(name: "kanban-EVEN-1-wt", path: wt.path, attached: false)]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: wt, sessionId: "abc", existing: existing)

        XCTAssertEqual(plan.name, "kanban-EVEN-1")
        XCTAssertEqual(plan.launchCommand, "claude --session-id \'abc\'")
    }

    /// Sitzungen **fremder** Werkzeuge bleiben Kandidaten — dafür gibt es die Stufe.
    func testForeignWorktreeSessionIsStillAdopted() {
        let wt = Worktree(path: "/wt/EVEN-1", branch: nil)
        let existing = [TmuxSession(name: "EVEN-1", path: wt.path, attached: false)]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: wt, sessionId: "abc",
            agent: .codex, existing: existing)

        XCTAssertEqual(plan.name, "EVEN-1")
        XCTAssertNil(plan.launchCommand)
    }

    /// Umgestelltes Projekt, alte Sitzung läuft noch: Codex legt seine eigene an, statt sich in die
    /// laufende Claude-Console zu setzen.
    func testCodexDoesNotAttachToTheRunningClaudeSession() {
        let existing = [TmuxSession(name: "kanban-EVEN-1", path: repo, attached: true)]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: nil, sessionId: nil,
            agent: .codex, existing: existing)

        XCTAssertEqual(plan.name, "kanban-EVEN-1-codex")
        XCTAssertTrue(plan.needsCreate)
    }

    /// Und die Gegenrichtung: die Claude-Console eines Codex-Projekts hängt sich an ihre eigene
    /// Sitzung, nicht an die von Codex.
    func testClaudeAttachesToItsOwnSessionNextToCodex() {
        let existing = [
            TmuxSession(name: "kanban-EVEN-1", path: repo, attached: false),
            TmuxSession(name: "kanban-EVEN-1-codex", path: repo, attached: true),
        ]
        let plan = TerminalSessionResolver.resolve(
            ticketKey: "EVEN-1", repoDir: repo, worktree: nil, sessionId: "abc", existing: existing)

        XCTAssertEqual(plan.name, "kanban-EVEN-1")
        XCTAssertNil(plan.launchCommand)
    }
}
