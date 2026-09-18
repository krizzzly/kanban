import XCTest
@testable import KanbanCore

final class StatusLinksTests: XCTestCase {
    private let preamble = """
    # EVEN-3530 - Ausführungskontrolle Status

    > 🌳 **WORKTREE**: `/Users/x/code/even-worktree/even-3530`
    > 🌿 **BRANCH**: `feature/EVEN-3530_status`
    > 🐳 **STACK**: `https://even-3530.test`
    >
    > 🧭 Routing bla

    ### Status
    🟢 Fertig
    """

    private let gitlab = ForgeLocation(kind: .gitlab, webBaseUrl: "https://gitlab.example.com",
                                       projectPath: "applications/even")
    private let github = ForgeLocation(kind: .github, webBaseUrl: "https://github.com",
                                       projectPath: "krizzzly/kanban")

    private func linkify() -> String {
        StatusLinks.linkify(
            preamble: preamble,
            ticketKey: "EVEN-3530",
            jiraBaseUrl: "https://jira.example.com/",     // trailing slash trimmed
            forge: gitlab)
    }

    func testTitleLinksToJira() {
        XCTAssertTrue(linkify().contains(
            "# [EVEN-3530 - Ausführungskontrolle Status](https://jira.example.com/browse/EVEN-3530)"))
    }

    func testWorktreeLinksToIdeScheme() {
        XCTAssertTrue(linkify().contains(
            "[`/Users/x/code/even-worktree/even-3530`](kanban-ide://open?path=/Users/x/code/even-worktree/even-3530)"))
    }

    func testWorktreePathWithSpaceIsEncoded() {
        let out = StatusLinks.linkify(preamble: "> 🌳 **WORKTREE**: `/Users/x/my code/wt`",
                                      ticketKey: nil, jiraBaseUrl: nil, forge: nil)
        XCTAssertTrue(out.contains("path=/Users/x/my%20code/wt"))   // space encoded, slashes kept
    }

    func testBranchLinksToGitlabTree() {
        XCTAssertTrue(linkify().contains(
            "[`feature/EVEN-3530_status`](https://gitlab.example.com/applications/even/-/tree/feature/EVEN-3530_status)"))
    }

    func testStackLinksToItself() {
        XCTAssertTrue(linkify().contains("[`https://even-3530.test`](https://even-3530.test)"))
    }

    func testStatusHeadingUntouched() {
        // The `### Status` line must not be turned into a title link.
        XCTAssertTrue(linkify().contains("\n### Status\n"))
    }

    /// GitHub hat GitLabs `/-/` nicht — derselbe Branch, ein anderer Pfad.
    func testBranchLinksToGithubTree() {
        let out = StatusLinks.linkify(preamble: preamble, ticketKey: "EVEN-3530",
                                      jiraBaseUrl: nil, forge: github)
        XCTAssertTrue(out.contains(
            "[`feature/EVEN-3530_status`](https://github.com/krizzzly/kanban/tree/feature/EVEN-3530_status)"))
        XCTAssertFalse(out.contains("/-/tree/"))
    }

    /// Eine `!<iid>`-Karte hat kein Jira-Issue — ihre H1 darf nicht auf `/browse/!49` verlinken.
    func testMRCardTitleGetsNoJiraLink() {
        let linked = StatusLinks.linkify(
            preamble: "# !49 - CLI-Option --version",
            ticketKey: "!49",
            jiraBaseUrl: "https://jira.example.com",
            forge: ForgeLocation(kind: .gitlab, webBaseUrl: "https://gitlab.example.com",
                                 projectPath: "docker/iwf-local-dev"))
        XCTAssertEqual(linked, "# !49 - CLI-Option --version")
        XCTAssertFalse(linked.contains("browse"))
    }

    /// Dasselbe für GitHubs Schreibweise: `#49` ist auch keine Jira-Nummer.
    func testPRCardTitleGetsNoJiraLink() {
        let linked = StatusLinks.linkify(preamble: "# #49 - CLI-Option --version",
                                         ticketKey: "#49",
                                         jiraBaseUrl: "https://jira.example.com",
                                         forge: github)
        XCTAssertEqual(linked, "# #49 - CLI-Option --version")
        XCTAssertFalse(linked.contains("browse"))
    }

    func testForgeSkippedWhenConfigMissing() {
        let out = StatusLinks.linkify(preamble: preamble, ticketKey: "EVEN-3530",
                                      jiraBaseUrl: "https://jira.example.com", forge: nil)
        // Branch stays a plain code span (no link) when no forge is configured.
        XCTAssertTrue(out.contains("**BRANCH**: `feature/EVEN-3530_status`"))
        XCTAssertFalse(out.contains("/-/tree/"))
    }

    /// Ohne Projekt-Pfad (oder ohne Basis) gibt es keine `ForgeLocation` — die Stelle, an der der
    /// Branch-Link ausfällt, statt eine halbe URL zu bauen.
    func testForgeLocationNeedsBaseAndPath() {
        XCTAssertNil(ForgeLocation(kind: .gitlab, webBaseUrl: "https://gitlab.example.com",
                                   projectPath: nil))
        XCTAssertNil(ForgeLocation(kind: .github, webBaseUrl: nil, projectPath: "owner/repo"))
    }

    func testOldStackFormatLinksTheUrlNotThePlainToken() {
        let old = "> 🐳 **STACK**: `even-3530` (URL nach Stack-Start: `https://even-3530.test`)"
        let out = StatusLinks.linkify(preamble: old, ticketKey: nil, jiraBaseUrl: nil, forge: nil)
        XCTAssertTrue(out.contains("`even-3530` (URL nach Stack-Start: [`https://even-3530.test`](https://even-3530.test))"))
    }
}
