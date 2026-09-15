import XCTest
@testable import KanbanCore

/// The card's review verdict (`Approved` / `Resolved` pill) and the numbers behind it.
final class MRReviewStateTests: XCTestCase {
    private typealias Discussion = GitLabClient.RawDiscussion
    private typealias Note = GitLabClient.RawNote

    private func mr(unresolved: Int = 0, resolved: Int = 0,
                    approved: Bool = false, approvedBy: [String] = []) -> MergeRequestRef {
        MergeRequestRef(iid: 1, title: "t", state: "opened", sourceBranch: "f", targetBranch: "develop",
                        mergedAt: nil, webUrl: "https://git/mr/1",
                        unresolvedDiscussions: unresolved, resolvedDiscussions: resolved,
                        approved: approved, approvedBy: approvedBy)
    }

    // MARK: - Precedence

    /// Approved sticht Resolved — bei beidem zeigt die Karte nur „Approved".
    func testApprovedWinsOverResolved() {
        XCTAssertEqual(mr(unresolved: 0, resolved: 3, approved: true).reviewState, .approved)
    }

    /// Auch mit offenen Threads gilt das Approval — die offenen zählt daneben das graue Pill.
    func testApprovedAlsoWinsWithOpenThreads() {
        XCTAssertEqual(mr(unresolved: 2, resolved: 1, approved: true).reviewState, .approved)
    }

    func testResolvedOnlyWhenEveryThreadIsSettled() {
        XCTAssertEqual(mr(unresolved: 0, resolved: 4).reviewState, .resolved)
        XCTAssertEqual(mr(unresolved: 1, resolved: 3).reviewState, .none)
    }

    /// Ein MR, den niemand kommentiert hat, ist nicht „resolved" — sonst trüge jede frische Karte
    /// das grüne Badge.
    func testNoThreadsIsNotResolved() {
        XCTAssertEqual(mr(unresolved: 0, resolved: 0).reviewState, .none)
    }

    func testTotalIsResolvedPlusOpen() {
        XCTAssertEqual(mr(unresolved: 4, resolved: 2).totalDiscussions, 6)
    }

    // MARK: - Thread counting

    func testThreadCountsSplitResolvedAndOpen() {
        let counts = GitLabClient.threadCounts([
            Discussion(notes: [Note(resolvable: true, resolved: false)]),                 // offen
            Discussion(notes: [Note(resolvable: true, resolved: true)]),                  // erledigt
            Discussion(notes: [Note(resolvable: true, resolved: true),
                               Note(resolvable: true, resolved: false)]),                 // offen (eine Note offen)
            Discussion(notes: [Note(resolvable: false, resolved: nil)]),                  // System-Note
            Discussion(notes: nil),
        ])
        XCTAssertEqual(counts.resolved, 1)
        XCTAssertEqual(counts.unresolved, 2)
    }

    // MARK: - Approvals payload

    /// GitLabs `/approvals`-Antwort (auf die relevanten Felder reduziert).
    func testDecodesApprovalsPayload() throws {
        let json = """
        {"user_has_approved": false, "user_can_approve": true, "approved": true,
         "approved_by": [{"user": {"id": 111, "username": "nie", "name": "Ebi Nicholas"}}]}
        """
        let raw = try JSONDecoder().decode(GitLabClient.RawApprovals.self, from: Data(json.utf8))
        XCTAssertTrue(raw.isApproved)
        XCTAssertEqual(raw.approverNames, ["Ebi Nicholas"])
    }

    func testNotApprovedPayload() throws {
        let json = #"{"user_has_approved": false, "user_can_approve": true, "approved": false, "approved_by": []}"#
        let raw = try JSONDecoder().decode(GitLabClient.RawApprovals.self, from: Data(json.utf8))
        XCTAssertFalse(raw.isApproved)
        XCTAssertTrue(raw.approverNames.isEmpty)
    }

    /// Ältere GitLab-Versionen liefern kein `approved` — dann entscheidet `approved_by`.
    func testFallsBackToApproverListWhenFlagIsMissing() throws {
        let json = #"{"approved_by": [{"user": {"name": "Ebi Nicholas"}}]}"#
        let raw = try JSONDecoder().decode(GitLabClient.RawApprovals.self, from: Data(json.utf8))
        XCTAssertTrue(raw.isApproved)
    }
}
