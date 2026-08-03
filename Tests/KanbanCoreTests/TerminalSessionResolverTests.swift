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
}
