import XCTest
@testable import KanbanCore

/// Der Review-Stand eines Pull Requests: Zustimmung aus der Review-Historie und die Thread-Zähler
/// aus GraphQL. Beide sind bei GitHub **anders gebaut** als bei GitLab, und beide müssen
/// fail-open sein — sie treiben über `MRReviewState` auch die Review-Spalte.
final class GitHubReviewStateTests: XCTestCase {
    private func reviews(_ text: String) throws -> [JSONValue] {
        try JSONDecoder().decode([JSONValue].self, from: Data(text.utf8))
    }

    private func graphQL(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    // MARK: - Zustimmung

    func testASingleApprovalCounts() throws {
        let (approved, by) = GitHubClient.approvalFromReviews(try reviews("""
        [{"state": "APPROVED", "submitted_at": "2026-09-17T10:00:00Z",
          "user": {"login": "krizzzly", "name": "Christian Hiller"}}]
        """))
        XCTAssertTrue(approved)
        XCTAssertEqual(by, ["Christian Hiller"])
    }

    /// **Der Kern des Unterschieds:** GitHub führt eine Historie, keinen Zustand. Dieselbe Person
    /// steht mehrfach drin, und es zählt ihr letzter meinungsstarker Eintrag.
    func testChangesRequestedAfterApprovalCancelsIt() throws {
        let (approved, by) = GitHubClient.approvalFromReviews(try reviews("""
        [{"state": "APPROVED", "submitted_at": "2026-09-17T10:00:00Z", "user": {"login": "a"}},
         {"state": "CHANGES_REQUESTED", "submitted_at": "2026-09-17T11:00:00Z", "user": {"login": "a"}}]
        """))
        XCTAssertFalse(approved)
        XCTAssertTrue(by.isEmpty)
    }

    /// Und umgekehrt: nachgebessert und dann zugestimmt — die Zustimmung gilt.
    func testApprovalAfterChangesRequestedWins() throws {
        let (approved, _) = GitHubClient.approvalFromReviews(try reviews("""
        [{"state": "CHANGES_REQUESTED", "submitted_at": "2026-09-17T10:00:00Z", "user": {"login": "a"}},
         {"state": "APPROVED", "submitted_at": "2026-09-17T12:00:00Z", "user": {"login": "a"}}]
        """))
        XCTAssertTrue(approved)
    }

    /// Ein blosser Kommentar ist keine Meinung und darf eine ältere Zustimmung nicht aufheben —
    /// so wertet GitHub es selbst aus.
    func testACommentDoesNotRevokeAnApproval() throws {
        let (approved, _) = GitHubClient.approvalFromReviews(try reviews("""
        [{"state": "APPROVED", "submitted_at": "2026-09-17T10:00:00Z", "user": {"login": "a"}},
         {"state": "COMMENTED", "submitted_at": "2026-09-17T13:00:00Z", "user": {"login": "a"}}]
        """))
        XCTAssertTrue(approved)
    }

    /// Zwei Personen, eine dagegen: der PR ist trotzdem approved — genau eine Zustimmung reicht,
    /// wie bei GitLabs `/approvals`. Die Namen stehen im Tooltip, sortiert und ohne Dubletten.
    func testOneApprovalAmongSeveralReviewersIsEnough() throws {
        let (approved, by) = GitHubClient.approvalFromReviews(try reviews("""
        [{"state": "CHANGES_REQUESTED", "submitted_at": "2026-09-17T09:00:00Z", "user": {"login": "b"}},
         {"state": "APPROVED", "submitted_at": "2026-09-17T10:00:00Z", "user": {"login": "a", "name": "Anna"}},
         {"state": "APPROVED", "submitted_at": "2026-09-17T11:00:00Z", "user": {"login": "a", "name": "Anna"}}]
        """))
        XCTAssertTrue(approved)
        XCTAssertEqual(by, ["Anna"])
    }

    /// Ohne `name` steht der Login da — eine leere Zeile im Tooltip wäre schlechter als ein Handle.
    func testFallsBackToTheLoginWhenThereIsNoName() throws {
        let (_, by) = GitHubClient.approvalFromReviews(try reviews(
            #"[{"state": "APPROVED", "submitted_at": "2026-09-17T10:00:00Z", "user": {"login": "a"}}]"#))
        XCTAssertEqual(by, ["a"])
    }

    func testNoReviewsMeansNoApproval() throws {
        let (approved, by) = GitHubClient.approvalFromReviews([])
        XCTAssertFalse(approved)
        XCTAssertTrue(by.isEmpty)
    }

    // MARK: - Thread-Zähler (GraphQL)

    func testCountsResolvedAndOpenReviewThreads() throws {
        let counts = GitHubClient.threadCounts(try graphQL("""
        {"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": [
          {"isResolved": true}, {"isResolved": false}, {"isResolved": false}
        ]}}}}}
        """))
        XCTAssertEqual(counts.resolved, 1)
        XCTAssertEqual(counts.unresolved, 2)
    }

    /// **Fail-open.** Fehlt das Recht, antwortet GraphQL mit `errors` und `data.repository: null` —
    /// das sind 0/0, kein Badge und **keine** Spaltenwirkung. Eine Karte wegen einer fehlenden
    /// Antwort zu verschieben wäre der schlechtere Ausgang.
    func testAGraphQLErrorYieldsZeroAndNoColumnEffect() throws {
        let counts = GitHubClient.threadCounts(try graphQL("""
        {"data": {"repository": null},
         "errors": [{"message": "Resource not accessible by personal access token"}]}
        """))
        XCTAssertEqual(counts.resolved, 0)
        XCTAssertEqual(counts.unresolved, 0)

        // Mit 0/0 bleibt der Review-Stand leer — die Karte steht in Review, weil ein offener PR da
        // ist, nicht wegen (oder trotz) der Threads.
        let pr = MergeRequestRef(iid: 1, title: "KANBAN-9", state: "opened",
                                 sourceBranch: "feature/KANBAN-9_x", targetBranch: "main",
                                 mergedAt: nil, webUrl: "", forge: .github)
        XCTAssertEqual(pr.reviewState, .none)
        XCTAssertEqual(WorkflowStatus.resolve(ticketKey: "KANBAN-9", hasTaskFile: true,
                                              statusMarker: nil, worktree: nil,
                                              mergeRequests: [pr]).column, .review)
    }

    /// Eine Antwort ohne Threads ist dasselbe wie keine — 0/0, nicht „alles erledigt".
    func testNoThreadsIsNotResolved() throws {
        let counts = GitHubClient.threadCounts(try graphQL(
            #"{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": []}}}}}"#))
        XCTAssertEqual(counts.resolved, 0)
        XCTAssertEqual(counts.unresolved, 0)

        let pr = MergeRequestRef(iid: 1, title: "t", state: "opened", sourceBranch: "b",
                                 targetBranch: "main", mergedAt: nil, webUrl: "",
                                 resolvedDiscussions: 0, forge: .github)
        XCTAssertEqual(pr.reviewState, .none)
    }

    /// Alle Threads erledigt → die grüne „Resolved"-Pille, dieselbe Regel wie bei GitLab.
    func testAllThreadsResolvedGivesTheResolvedBadge() {
        let pr = MergeRequestRef(iid: 1, title: "t", state: "opened", sourceBranch: "b",
                                 targetBranch: "main", mergedAt: nil, webUrl: "",
                                 unresolvedDiscussions: 0, resolvedDiscussions: 3, forge: .github)
        XCTAssertEqual(pr.reviewState, .resolved)
        XCTAssertEqual(pr.totalDiscussions, 3)
    }

    // MARK: - Ratenbegrenzung

    /// GitHub meldet die Begrenzung als 403/429 **mit Grund im Body**. Ein 403 ohne diesen Hinweis
    /// ist ein fehlendes Recht — daran darf die Runde nicht abbrechen.
    func testRecognisesARateLimitButNotAPlainForbidden() {
        XCTAssertTrue(GitHubClient.isRateLimited(
            APIError.api(module: "github", status: 403, message: "API rate limit exceeded for user")))
        XCTAssertTrue(GitHubClient.isRateLimited(
            APIError.api(module: "github", status: 429, message: "You have exceeded a secondary rate limit")))
        XCTAssertFalse(GitHubClient.isRateLimited(
            APIError.api(module: "github", status: 403, message: "Resource not accessible by personal access token")))
        XCTAssertFalse(GitHubClient.isRateLimited(APIError.api(module: "github", status: 404, message: "Not Found")))
        XCTAssertFalse(GitHubClient.isRateLimited(APIError.decode("kaputt")))
    }

    /// Einmal zu, bleibt zu — für den Rest dieses Durchlaufs.
    func testTheRateLimitGateStaysShutOnceTripped() async {
        let gate = GitHubClient.RateLimitGate()
        let openBefore = await gate.isOpen()
        XCTAssertTrue(openBefore)
        await gate.trip()
        let openAfter = await gate.isOpen()
        XCTAssertFalse(openAfter)
    }
}
