import XCTest
@testable import KanbanCore

/// Die Übersetzung der GitHub-Antworten in Domain-Typen. Feldformen aus echten Antworten von
/// `GET /repos/{owner}/{repo}/pulls` und `/pulls/{n}` (auf die benutzten Felder gekürzt).
final class GitHubParsingTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Ein Listeneintrag, wie GitHub ihn liefert — Nummer statt `iid`, `html_url` statt `web_url`,
    /// Branches unter `head`/`base`.
    func testParsesAPullRequestListEntry() throws {
        let pr = GitHubClient.parseListEntry(try json("""
        {
          "number": 42,
          "state": "open",
          "title": "GitHub als zweite Forge",
          "draft": false,
          "merged_at": null,
          "html_url": "https://github.com/krizzzly/kanban/pull/42",
          "head": {"ref": "feature/KANBAN-007_github", "label": "krizzzly:feature/KANBAN-007_github"},
          "base": {"ref": "main"}
        }
        """))

        XCTAssertEqual(pr.iid, 42)
        XCTAssertEqual(pr.title, "GitHub als zweite Forge")
        XCTAssertEqual(pr.sourceBranch, "feature/KANBAN-007_github")
        XCTAssertEqual(pr.targetBranch, "main")
        XCTAssertEqual(pr.webUrl, "https://github.com/krizzzly/kanban/pull/42")
        XCTAssertFalse(pr.draft)
        XCTAssertEqual(pr.forge, .github)
        // Die Karte schreibt die Nummer so, wie GitHub sie schreibt.
        XCTAssertEqual(pr.numberLabel, "#42")
    }

    // MARK: - Zustands-Normalisierung

    /// **„merged" ist bei GitHub kein Zustand.** Alle drei Fälle, weil der mittlere sonst als
    /// „closed" in der Historie verschwände und der letzte fälschlich nach Done liefe.
    func testNormalizesAllThreeStates() {
        XCTAssertEqual(GitHubClient.normalizedState("open", mergedAt: nil), "opened")
        XCTAssertEqual(GitHubClient.normalizedState("closed", mergedAt: "2026-09-18T07:00:00Z"), "merged")
        XCTAssertEqual(GitHubClient.normalizedState("closed", mergedAt: nil), "closed")
    }

    /// Ein geschlossener PR **ohne** Merge darf die Karte nicht nach Done schieben — die Probe
    /// aufs Exempel durch die unveränderte Spaltenlogik.
    func testClosedWithoutMergeDoesNotReachDone() throws {
        let rejected = GitHubClient.parseListEntry(try json("""
        {"number": 7, "state": "closed", "title": "Verworfen", "merged_at": null,
         "html_url": "https://github.com/o/r/pull/7",
         "head": {"ref": "feature/KANBAN-9_x"}, "base": {"ref": "main"}}
        """))
        XCTAssertEqual(rejected.state, "closed")

        let resolution = WorkflowStatus.resolve(ticketKey: "KANBAN-9", hasTaskFile: true,
                                                statusMarker: nil, worktree: nil,
                                                mergeRequests: [rejected])
        XCTAssertNotEqual(resolution.column, .done)
        XCTAssertEqual(resolution.column, .offen)
    }

    /// Und der gemergte gehört dorthin — dieselbe `WorkflowStatus`, ohne eine Zeile GitHub darin.
    func testMergedPullRequestReachesDone() throws {
        let merged = GitHubClient.parseListEntry(try json("""
        {"number": 8, "state": "closed", "title": "KANBAN-9 fertig",
         "merged_at": "2026-09-17T12:00:00Z", "html_url": "https://github.com/o/r/pull/8",
         "head": {"ref": "feature/KANBAN-9_x"}, "base": {"ref": "main"}}
        """))
        XCTAssertEqual(merged.state, "merged")
        XCTAssertEqual(WorkflowStatus.resolve(ticketKey: "KANBAN-9", hasTaskFile: true,
                                              statusMarker: nil, worktree: nil,
                                              mergeRequests: [merged]).column, .done)
    }

    /// Ein Draft ist offen, aber nicht review-reif — wie bei GitLab, nur dass GitHub ein echtes
    /// Feld dafür hat statt eines Titelpräfixes.
    func testDraftStaysOutOfReview() throws {
        let draft = GitHubClient.parseListEntry(try json("""
        {"number": 9, "state": "open", "title": "KANBAN-9 wip", "draft": true, "merged_at": null,
         "html_url": "https://github.com/o/r/pull/9",
         "head": {"ref": "feature/KANBAN-9_x"}, "base": {"ref": "main"}}
        """))
        XCTAssertTrue(draft.draft)
        XCTAssertEqual(WorkflowStatus.resolve(ticketKey: "KANBAN-9", hasTaskFile: false,
                                              statusMarker: nil, worktree: nil,
                                              mergeRequests: [draft]).column, .inBearbeitung)
    }

    // MARK: - Fork

    /// Bei einem Fork-PR steht in `head.label` `owner:branch`. Verglichen wird aber mit lokalen
    /// Branches — es muss der reine Name sein, sonst findet `TicketMatching` den Worktree nicht.
    func testForkBranchLosesTheOwnerPrefix() throws {
        let fromRef = GitHubClient.sourceBranch(try json(
            #"{"head": {"ref": "feature/x", "label": "fremder:feature/x"}}"#))
        XCTAssertEqual(fromRef, "feature/x")

        // Und der Rückfall, falls nur das Label da ist.
        let fromLabel = GitHubClient.sourceBranch(try json(#"{"head": {"label": "fremder:feature/x"}}"#))
        XCTAssertEqual(fromLabel, "feature/x")
    }

    func testForkPullRequestIsRecognised() throws {
        let fork = GitHubClient.parsePullRequest(try json("""
        {"number": 5, "state": "open", "title": "t", "merged_at": null,
         "html_url": "https://github.com/o/r/pull/5",
         "head": {"ref": "patch-1", "sha": "abc", "repo": {"full_name": "fremder/kanban"}},
         "base": {"ref": "main", "sha": "def", "repo": {"full_name": "krizzzly/kanban"}}}
        """))
        XCTAssertTrue(fork.fromFork)
        XCTAssertEqual(fork.sourceBranch, "patch-1")
        XCTAssertEqual(fork.headSha, "abc")
    }

    /// Ohne beide Repo-Angaben ist „kein Fork" die Antwort, die nichts kaputtmacht.
    func testMissingRepoInfoIsNotAFork() throws {
        let pr = GitHubClient.parsePullRequest(try json(
            #"{"number": 1, "state": "open", "title": "t", "head": {"ref": "b"}, "base": {"ref": "main"}}"#))
        XCTAssertFalse(pr.fromFork)
    }

    // MARK: - Diffs

    /// `GET /pulls/{n}/files` führt **einen** Pfad plus `status` — hier in die Form übersetzt, die
    /// die Diff-Logik beider Forges sieht.
    func testParsesAChangedFile() throws {
        let renamed = GitHubClient.parseDiff(try json("""
        {"filename": "Sources/Neu.swift", "previous_filename": "Sources/Alt.swift",
         "status": "renamed", "patch": "@@ -1 +1 @@\\n-alt\\n+neu"}
        """))
        XCTAssertEqual(renamed.oldPath, "Sources/Alt.swift")
        XCTAssertEqual(renamed.newPath, "Sources/Neu.swift")
        XCTAssertTrue(renamed.renamedFile)
        XCTAssertFalse(renamed.newFile)

        let added = GitHubClient.parseDiff(try json(
            #"{"filename": "a.swift", "status": "added", "patch": "@@ -0,0 +1 @@\n+x"}"#))
        XCTAssertTrue(added.newFile)
        XCTAssertEqual(added.oldPath, "a.swift")   // ohne previous_filename derselbe Pfad

        // Binär oder zu gross: GitHub lässt `patch` weg — das ist kein Fehler, nur nicht kommentierbar.
        let binary = GitHubClient.parseDiff(try json(#"{"filename": "logo.png", "status": "modified"}"#))
        XCTAssertEqual(binary.diff, "")
    }

    // MARK: - URLs

    /// GraphQL liegt **neben** REST, nicht darunter — bei Enterprise unter `/api/graphql`.
    func testGraphQLURLSitsBesideTheRESTBase() {
        XCTAssertEqual(GitHubClient.graphQLURL(forApiBase: "https://api.github.com"),
                       "https://api.github.com/graphql")
        XCTAssertEqual(GitHubClient.graphQLURL(forApiBase: "https://api.github.com/"),
                       "https://api.github.com/graphql")
        XCTAssertEqual(GitHubClient.graphQLURL(forApiBase: "https://ghe.firma.io/api/v3"),
                       "https://ghe.firma.io/api/graphql")
    }

    /// Die Web-Basis ist nicht die API-Basis — Branch-Links gingen sonst auf `api.github.com`.
    func testWebBaseIsDerivedFromTheApiBase() {
        XCTAssertEqual(GitHubClient.webBaseURL(forApiBase: "https://api.github.com"),
                       "https://github.com")
        XCTAssertEqual(GitHubClient.webBaseURL(forApiBase: "https://ghe.firma.io/api/v3"),
                       "https://ghe.firma.io")
    }

    func testSplitsOwnerAndRepo() {
        let split = GitHubClient.splitPath("krizzzly/kanban")
        XCTAssertEqual(split?.owner, "krizzzly")
        XCTAssertEqual(split?.repo, "kanban")
        // Ein GitLab-Namespace hat drei Segmente — der wäre hier ein Missverständnis, kein Pfad.
        XCTAssertNil(GitHubClient.splitPath("gruppe/unter/projekt"))
        XCTAssertNil(GitHubClient.splitPath("kanban"))
    }

    /// Der Auth-Header geht nur an die konfigurierten Hosts — dieselbe Zusage wie bei GitLab, nur
    /// muss hier **auch** die GraphQL-URL erlaubt sein.
    func testHostGuardCoversRestAndGraphQL() {
        let client = ModuleHTTPClient.github(
            baseUrls: ["https://ghe.firma.io/api/v3", "https://ghe.firma.io/api/graphql"],
            apiToken: "ghp_x")
        XCTAssertNoThrow(try client.guarded("https://ghe.firma.io/api/v3/repos/o/r/pulls"))
        XCTAssertNoThrow(try client.guarded("https://ghe.firma.io/api/graphql"))
        XCTAssertThrowsError(try client.guarded("https://api.github.com/repos/o/r/pulls")) {
            guard case APIError.forbiddenHost(let module, _) = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
            XCTAssertEqual(module, "github")
        }
    }
}
