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

    private func linkify() -> String {
        StatusLinks.linkify(
            preamble: preamble,
            ticketKey: "EVEN-3530",
            jiraBaseUrl: "https://jira.example.com/",     // trailing slash trimmed
            gitlabBaseUrl: "https://gitlab.example.com",
            gitlabProjectPath: "applications/even")
    }

    /// Die Überschrift ist eine Überschrift, kein Navigationselement — sie läuft unverändert durch.
    func testTitleStaysPlainText() {
        XCTAssertTrue(linkify().contains("# EVEN-3530 - Ausführungskontrolle Status"))
        XCTAssertFalse(linkify().contains("# ["))
    }

    // MARK: - Die JIRA-Zeile

    /// Steht sie in der Datei, wird sie wie STACK auf sich selbst verlinkt.
    func testJiraLineInFileLinksToItself() {
        let out = StatusLinks.linkify(
            preamble: "# EVEN-1 - X\n\n> 🎫 **JIRA**: `https://jira.example.com/browse/EVEN-1`\\\n> 🌿 **BRANCH**: `feature/x`",
            ticketKey: "EVEN-1", jiraBaseUrl: "https://jira.example.com",
            gitlabBaseUrl: nil, gitlabProjectPath: nil)
        XCTAssertTrue(out.contains(
            "[`https://jira.example.com/browse/EVEN-1`](https://jira.example.com/browse/EVEN-1)"))
    }

    /// Fehlt sie — der Fall aller Bestandsdateien —, wird sie als erste Blockzeile abgeleitet.
    func testJiraLineIsDerivedAsFirstBlockLine() {
        let out = linkify()
        let lines = out.components(separatedBy: "\n")
        let block = lines.firstIndex { $0.hasPrefix(">") }!
        XCTAssertTrue(lines[block].contains("**JIRA**"), lines[block])
        XCTAssertTrue(lines[block].contains(
            "[`https://jira.example.com/browse/EVEN-3530`](https://jira.example.com/browse/EVEN-3530)"))
        // Harter Zeilenumbruch, sonst kollabiert der Blockquote beim Rendern zu einer Zeile.
        XCTAssertTrue(lines[block].hasSuffix("\\"), lines[block])
        // Genau eine Zeile, und der Rest des Blocks steht unverändert darunter.
        XCTAssertEqual(out.components(separatedBy: "**JIRA**").count - 1, 1)
        XCTAssertTrue(lines[block + 1].contains("**WORKTREE**"))
    }

    /// Eine vorhandene Zeile gewinnt — es entsteht keine zweite daneben.
    func testExistingJiraLineIsNotDuplicated() {
        let head = "# EVEN-1 - X\n\n> 🎫 **JIRA**: `https://anders.example/browse/EVEN-1`\\\n> 🌿 **BRANCH**: `feature/x`"
        let out = StatusLinks.linkify(preamble: head, ticketKey: "EVEN-1",
                                      jiraBaseUrl: "https://jira.example.com",
                                      gitlabBaseUrl: nil, gitlabProjectPath: nil)
        XCTAssertEqual(out.components(separatedBy: "**JIRA**").count - 1, 1)
        XCTAssertFalse(out.contains("jira.example.com"))
    }

    /// Ohne Jira-Anbindung (`useJira: false`) entsteht keine Zeile — ein Link auf ein Ticket, das es
    /// nicht gibt, ist schlechter als keiner.
    func testNoJiraLineWithoutJiraProject() {
        let out = StatusLinks.linkify(preamble: preamble, ticketKey: "KANBAN-1",
                                      jiraBaseUrl: "https://jira.example.com",
                                      gitlabBaseUrl: nil, gitlabProjectPath: nil,
                                      usesJira: false)
        XCTAssertFalse(out.contains("**JIRA**"))
        XCTAssertFalse(out.contains("browse"))
    }

    /// Ohne konfigurierte Basis-URL gibt es nichts abzuleiten.
    func testNoJiraLineWithoutBaseUrl() {
        let out = StatusLinks.linkify(preamble: preamble, ticketKey: "EVEN-3530", jiraBaseUrl: nil,
                                      gitlabBaseUrl: nil, gitlabProjectPath: nil)
        XCTAssertFalse(out.contains("**JIRA**"))
    }

    /// Ohne Worktree-Block (`--no-worktree`) entsteht ein eigener Blockquote unter der H1.
    func testJiraLineBecomesItsOwnBlockWhenNoBlockExists() {
        let out = StatusLinks.linkify(preamble: "# EVEN-1 - X\n\nTyp: Task",
                                      ticketKey: "EVEN-1", jiraBaseUrl: "https://jira.example.com",
                                      gitlabBaseUrl: nil, gitlabProjectPath: nil)
        let expected = "# EVEN-1 - X\n\n"
            + "> 🎫 **JIRA**: [`https://jira.example.com/browse/EVEN-1`](https://jira.example.com/browse/EVEN-1)\n\n"
            + "Typ: Task"
        XCTAssertEqual(out, expected)
    }

    /// `LocalTickets.branch(inHead:)` liest `**BRANCH**` aus demselben Block — die neue Zeile davor
    /// darf daran nichts ändern.
    func testDerivedLineLeavesBranchParsingIntact() {
        XCTAssertEqual(LocalTickets.branch(inHead: linkify()), "feature/EVEN-3530_status")
    }

    // MARK: - Die übrigen Zeilen

    func testWorktreeLinksToIdeScheme() {
        XCTAssertTrue(linkify().contains(
            "[`/Users/x/code/even-worktree/even-3530`](kanban-ide://open?path=/Users/x/code/even-worktree/even-3530)"))
    }

    func testWorktreePathWithSpaceIsEncoded() {
        let out = StatusLinks.linkify(preamble: "> 🌳 **WORKTREE**: `/Users/x/my code/wt`",
                                      ticketKey: nil, jiraBaseUrl: nil, gitlabBaseUrl: nil, gitlabProjectPath: nil)
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

    /// Eine `!<iid>`-Karte hat kein Jira-Issue — sie bekommt keine JIRA-Zeile auf `/browse/!49`.
    func testMRCardGetsNoJiraLine() {
        let linked = StatusLinks.linkify(
            preamble: "# !49 - CLI-Option --version",
            ticketKey: "!49",
            jiraBaseUrl: "https://jira.example.com",
            gitlabBaseUrl: "https://gitlab.example.com",
            gitlabProjectPath: "docker/iwf-local-dev")
        XCTAssertEqual(linked, "# !49 - CLI-Option --version")
        XCTAssertFalse(linked.contains("browse"))
    }

    func testGitlabSkippedWhenConfigMissing() {
        let out = StatusLinks.linkify(preamble: preamble, ticketKey: "EVEN-3530",
                                      jiraBaseUrl: "https://jira.example.com",
                                      gitlabBaseUrl: nil, gitlabProjectPath: nil)
        // Branch stays a plain code span (no link) when GitLab isn't configured.
        XCTAssertTrue(out.contains("**BRANCH**: `feature/EVEN-3530_status`"))
        XCTAssertFalse(out.contains("/-/tree/"))
    }

    func testOldStackFormatLinksTheUrlNotThePlainToken() {
        let old = "> 🐳 **STACK**: `even-3530` (URL nach Stack-Start: `https://even-3530.test`)"
        let out = StatusLinks.linkify(preamble: old, ticketKey: nil, jiraBaseUrl: nil,
                                      gitlabBaseUrl: nil, gitlabProjectPath: nil)
        XCTAssertTrue(out.contains("`even-3530` (URL nach Stack-Start: [`https://even-3530.test`](https://even-3530.test))"))
    }
}
