import XCTest
@testable import KanbanCore

final class WorkflowStatusTests: XCTestCase {
    private func mr(_ iid: Int, _ state: String, branch: String, title: String = "",
                    draft: Bool = false) -> MergeRequestRef {
        MergeRequestRef(iid: iid, title: title, state: state, sourceBranch: branch,
                        targetBranch: "main", mergedAt: state == "merged" ? "2026-06-01" : nil,
                        webUrl: "https://git/\(iid)", draft: draft)
    }
    private let worktree = Worktree(path: "/code/even", branch: "feature/EVEN-1_thing")

    func testMergedMRWinsOverEverything() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .inArbeit,
            worktree: worktree, mergeRequests: [mr(42, "merged", branch: "feature/EVEN-1_thing")])
        XCTAssertEqual(r.column, .done)
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 42, draft: false)))
        XCTAssertTrue(r.badges.contains(.file))
        XCTAssertTrue(r.badges.contains(.worktree))
    }

    func testOpenedMRIsReviewEvenWhenInArbeit() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .inArbeit,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")])
        XCTAssertEqual(r.column, .review)
    }

    // MARK: - Draft MRs

    func testDraftMRDoesNotMoveCardToReview() {
        // A draft opened MR must not count as Review; the ticket stays where its work stage puts it.
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .inArbeit,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x", draft: true)])
        XCTAssertEqual(r.column, .inBearbeitung)
        // The MR is still shown, but as a draft badge (🚧) explaining why it's not in Review.
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 7, draft: true)))
    }

    func testDraftMRWithoutMarkerFallsToOffenNotReview() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: nil,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x", draft: true)])
        XCTAssertEqual(r.column, .offen)
    }

    func testANonDraftOpenedMRAlongsideADraftStillReviews() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: nil, worktree: nil,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x", draft: true),
                            mr(8, "opened", branch: "feature/EVEN-1_x")])
        XCTAssertEqual(r.column, .review)
    }

    func testDraftDoesNotAutoSetReviewMarker() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .inArbeit,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x", draft: true)]))
        // A non-draft opened MR still does.
        XCTAssertTrue(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .inArbeit,
            mergeRequests: [mr(8, "opened", branch: "feature/EVEN-1_x")]))
    }

    // MARK: - Auto-set Review marker

    func testAutoSetReviewWhenOpenMRAndInArbeit() {
        XCTAssertTrue(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .inArbeit,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")]))
    }

    func testAutoSetReviewOverridesAbgeschlossen() {
        XCTAssertTrue(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .abgeschlossen,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")]))
    }

    func testNoAutoSetWhenAlreadyReview() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .review,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")]))
    }

    func testNoAutoSetWhenDoneMarker() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .done,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")]))
    }

    func testNoAutoSetWhenMerged() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .inArbeit,
            mergeRequests: [mr(7, "merged", branch: "feature/EVEN-1_x")]))
    }

    func testNoAutoSetWithoutTaskFile() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: false, currentMarker: nil,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")]))
    }

    func testNoAutoSetWhenNoMatchingMR() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .inArbeit,
            mergeRequests: [mr(7, "opened", branch: "feature/OTHER-9_x")]))
    }

    // MARK: - MR source branch

    func testMRSourceBranchPrefersNewestOpened() {
        let mrs = [
            mr(5, "opened", branch: "feature/EVEN-1_old"),
            mr(9, "opened", branch: "feature/EVEN-1_new"),
            mr(3, "merged", branch: "feature/EVEN-1_merged"),
        ]
        XCTAssertEqual(WorkflowStatus.mrSourceBranch(ticketKey: "EVEN-1", mergeRequests: mrs),
                       "feature/EVEN-1_new")
    }

    func testMRSourceBranchFallsBackToMerged() {
        let mrs = [mr(3, "merged", branch: "feature/EVEN-1_merged")]
        XCTAssertEqual(WorkflowStatus.mrSourceBranch(ticketKey: "EVEN-1", mergeRequests: mrs),
                       "feature/EVEN-1_merged")
    }

    func testMRSourceBranchNilWhenNoMatch() {
        let mrs = [mr(3, "opened", branch: "feature/OTHER-9_x")]
        XCTAssertNil(WorkflowStatus.mrSourceBranch(ticketKey: "EVEN-1", mergeRequests: mrs))
    }

    // MARK: - Auto-set Done marker (Jira Erledigt/Geschlossen)

    func testAutoSetDoneWhenJiraDone() {
        XCTAssertTrue(WorkflowStatus.shouldAutoSetDone(
            hasTaskFile: true, currentMarker: .inArbeit, jiraDone: true))
        XCTAssertTrue(WorkflowStatus.shouldAutoSetDone(
            hasTaskFile: true, currentMarker: .review, jiraDone: true))
    }

    func testNoAutoSetDoneWhenNotJiraDone() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetDone(
            hasTaskFile: true, currentMarker: .inArbeit, jiraDone: false))
    }

    func testNoAutoSetDoneWhenAlreadyDone() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetDone(
            hasTaskFile: true, currentMarker: .done, jiraDone: true))
    }

    func testNoAutoSetDoneWithoutTaskFile() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetDone(
            hasTaskFile: false, currentMarker: nil, jiraDone: true))
    }

    func testJiraDoneStatusIsDone() {
        // Resolved/closed in Jira (statusCategory "done") → Done, even mid-work with no merged MR.
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .inArbeit,
            worktree: worktree, mergeRequests: [], jiraState: .done)
        XCTAssertEqual(r.column, .done)
    }

    // MARK: - Wieder aufgemachte Tickets (Jira zurück auf „In Arbeit", MR wieder offen)

    /// Der beobachtete Fall BFEZVM-4569: Jira „In Arbeit", Task-File ✅ Done (Fossil aus der Zeit, als
    /// Jira erledigt war), ein gemergter MR aus der ersten Runde und drei neue, review-reife offene.
    /// Vorher blieb die Karte in Done — weder der gemergte MR noch das ✅ durften sie dort halten.
    func testReopenedTicketWithNewerOpenedMRGoesToReview() {
        let mrs = [mr(1123, "opened", branch: "feature/EVEN-1_old_leftover"),
                   mr(1124, "merged", branch: "feature/EVEN-1_first_round"),
                   mr(1141, "opened", branch: "feature/EVEN-1_second_round")]
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: worktree, mergeRequests: mrs, jiraState: .notDone)
        XCTAssertEqual(r.column, .review)
        // Und das Badge zeigt den MR, der jetzt läuft — nicht den gemergten aus der ersten Runde.
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 1141, draft: false)))
    }

    /// Damit der Marker nicht für immer auf ✅ stehen bleibt (er war der zweite Grund fürs Kleben).
    func testReopenedTicketAutoResetsTheStaleDoneMarker() {
        let mrs = [mr(1124, "merged", branch: "feature/EVEN-1_first_round"),
                   mr(1141, "opened", branch: "feature/EVEN-1_second_round")]
        XCTAssertTrue(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .done,
            mergeRequests: mrs, jiraState: .notDone))
    }

    /// Jira hinkt nach: gemergt, aber niemand hat das Ticket auf Erledigt gezogen. Das ist der
    /// Normalfall und muss in Done bleiben — sonst fiele jedes fertige Ticket wieder heraus.
    func testMergedWithLaggingJiraStatusStaysDone() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: nil, mergeRequests: [mr(9, "merged", branch: "feature/EVEN-1_x")],
            jiraState: .notDone)
        XCTAssertEqual(r.column, .done)
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .done,
            mergeRequests: [mr(9, "merged", branch: "feature/EVEN-1_x")], jiraState: .notDone))
    }

    /// Ein *älterer* offener MR neben dem gemergten ist ein Liegengebliebener, kein Wiederaufmachen.
    func testOlderLeftoverOpenedMRDoesNotReopen() {
        let mrs = [mr(7, "opened", branch: "feature/EVEN-1_leftover"),
                   mr(9, "merged", branch: "feature/EVEN-1_x")]
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: nil, mergeRequests: mrs, jiraState: .notDone)
        XCTAssertEqual(r.column, .done)
    }

    /// Ohne Jira-Auskunft (freier Modus) bleibt alles wie vorher: das ✅ ist final.
    func testDoneMarkerStillWinsWithoutJiraInformation() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")])
        XCTAssertEqual(r.column, .done)
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .done,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")]))
    }

    /// Jira erledigt sticht alles — auch einen offenen MR und ein wieder aufgemachtes Aussehen.
    func testJiraDoneStillWinsOverAnOpenedMR() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .review,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")],
            jiraState: .done)
        XCTAssertEqual(r.column, .done)
    }

    /// Nur ein Draft offen: wieder aufgemacht, aber nicht review-reif → Arbeitsspalte, kein 🔵-Write.
    func testReopenedWithOnlyADraftMRIsInBearbeitung() {
        let mrs = [mr(9, "merged", branch: "feature/EVEN-1_x"),
                   mr(11, "opened", branch: "feature/EVEN-1_y", draft: true)]
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: worktree, mergeRequests: mrs, jiraState: .notDone)
        XCTAssertEqual(r.column, .inBearbeitung)
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 11, draft: true)))
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .done,
            mergeRequests: mrs, jiraState: .notDone))
    }

    /// Jira zurück auf „In Arbeit", offener review-reifer MR, aber nie etwas gemergt (Jira war vor dem
    /// Merge auf Erledigt gezogen worden) — auch das ist ein Wiederaufmachen.
    func testReopenedWithoutAnyMergedMR() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")],
            jiraState: .notDone)
        XCTAssertEqual(r.column, .review)
    }

    func testMergedBeatsOpened() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: nil,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x"),
                            mr(9, "merged", branch: "feature/EVEN-1_y")])
        XCTAssertEqual(r.column, .done)
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 9, draft: false)))  // merged preferred for badge
    }

    func testWorktreeIsInBearbeitung() {
        // Work has started (a worktree exists) and no MR → In Bearbeitung, regardless of the marker.
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .inArbeit,
            worktree: worktree, mergeRequests: [])
        XCTAssertEqual(r.column, .inBearbeitung)
    }

    func testAbgeschlossenMarkerStaysInBearbeitung() {
        // Claude marking the task 🟢 "Abgeschlossen" must NOT move it out of In Bearbeitung — only a
        // real MR or the final ✅ Done moves it on. "Abgeschlossen" ≠ Done.
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .abgeschlossen,
            worktree: worktree, mergeRequests: [])
        XCTAssertEqual(r.column, .inBearbeitung)
    }

    func testAbgeschlossenWithoutWorktreeIsStillInBearbeitung() {
        // Regression: 🟢 "Abgeschlossen" on a ticket without a worktree must stay In Bearbeitung.
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .abgeschlossen,
            worktree: nil, mergeRequests: [])
        XCTAssertEqual(r.column, .inBearbeitung)
    }

    func testDoneMarkerIsDone() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: worktree, mergeRequests: [])
        XCTAssertEqual(r.column, .done)
    }

    func testDoneMarkerBeatsOpenedMR() {
        // The user's explicit ✅ Done wins even while an MR is still open.
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")])
        XCTAssertEqual(r.column, .done)
    }

    func testOffenMarkerIsOffenEvenWithWorktree() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .offen,
            worktree: worktree, mergeRequests: [])
        XCTAssertEqual(r.column, .offen)
    }

    func testReviewMarkerIsReviewEvenWithoutMR() {
        // 🔵 Review is the one marker that moves the column (Claude reviewing its own work).
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .review,
            worktree: worktree, mergeRequests: [])
        XCTAssertEqual(r.column, .review)
    }

    func testOpenedMRBeatsReviewMarker() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .review,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")])
        XCTAssertEqual(r.column, .review)
    }

    func testFileOnlyIsOffen() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: nil, worktree: nil, mergeRequests: [])
        XCTAssertEqual(r.column, .offen)
        XCTAssertEqual(r.badges, [.file])
    }

    func testWorktreeOnlyIsInBearbeitung() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil,
            worktree: worktree, mergeRequests: [])
        XCTAssertEqual(r.column, .inBearbeitung)
    }

    func testNothingIsSprint() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: nil, mergeRequests: [])
        XCTAssertEqual(r.column, .sprint)
        XCTAssertTrue(r.badges.isEmpty)
    }

    // MARK: - „Mir zugewiesen"

    func testAssignedToMeIsOffenInsteadOfSprint() {
        // Verantwortlich heisst offen: ohne Task-File, ohne Worktree, ohne MR — aber mir zugewiesen.
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: nil,
            mergeRequests: [], isAssignedToMe: true)
        XCTAssertEqual(r.column, .offen)
        XCTAssertTrue(r.badges.isEmpty)   // die Zuweisung ist kein lokales Artefakt
    }

    func testAssignedToSomeoneElseStaysSprint() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: nil,
            mergeRequests: [], isAssignedToMe: false)
        XCTAssertEqual(r.column, .sprint)
    }

    func testAssignedToMeDoesNotPullACardOutOfDone() {
        // Die Zuweisung ist die *letzte* Stufe — sie sticht keinen gemergten MR und kein ✅.
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .done,
            worktree: worktree, mergeRequests: [mr(42, "merged", branch: "feature/EVEN-1_thing")],
            isAssignedToMe: true)
        XCTAssertEqual(r.column, .done)
    }

    func testAssignedToMeDoesNotOverrideAWorktree() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: worktree,
            mergeRequests: [], isAssignedToMe: true)
        XCTAssertEqual(r.column, .inBearbeitung)
    }

    func testNonMatchingMRIgnored() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: nil,
            mergeRequests: [mr(5, "merged", branch: "feature/EVEN-999_other")])
        XCTAssertEqual(r.column, .sprint)
    }

    func testTicketKeyBoundaryAvoidsPrefixCollision() {
        // EVEN-1 must NOT pick up MRs/branches belonging to EVEN-10, EVEN-12, EVEN-123…
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: nil,
            mergeRequests: [mr(11, "merged", branch: "feature/EVEN-10_other"),
                            mr(12, "opened", branch: "feature/EVEN-123_x")])
        XCTAssertEqual(r.column, .sprint)  // no genuine match → stays in Sprint
    }

    func testTicketKeyBoundaryMatchesExact() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: nil,
            mergeRequests: [mr(11, "merged", branch: "feature/EVEN-10_other"),
                            mr(13, "opened", branch: "feature/EVEN-1_real")])
        XCTAssertEqual(r.column, .review)
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 13, draft: false)))
    }

    func testTitleMatchAlsoCounts() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: false, statusMarker: nil, worktree: nil,
            mergeRequests: [mr(5, "opened", branch: "random-branch", title: "Fix EVEN-1 bug")])
        XCTAssertEqual(r.column, .review)
    }

    // MARK: - Karten ohne Ticketnummer: erkannt über den Branch

    /// `!130` steht in keinem Branchnamen — ein Ticket ohne Nummer wird über seinen Branch
    /// gefunden. Ohne das fände die Karte weder ihren eigenen MR noch ihre Spalte.
    func testABranchOnlyTicketFindsItsOwnMergeRequest() {
        let mrs = [mr(130, "opened", branch: "feature/playwright", title: "Frontend-Testing")]
        let r = WorkflowStatus.resolve(ticketKey: "!130", hasTaskFile: false, statusMarker: nil,
                                       worktree: nil, mergeRequests: mrs, branch: "feature/playwright")
        XCTAssertEqual(r.column, .review)
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 130, draft: false)))
        XCTAssertEqual(WorkflowStatus.primaryMR(ticketKey: "!130", mergeRequests: mrs,
                                                branch: "feature/playwright")?.iid, 130)
    }

    /// Ein Draft bleibt auch ohne Nummer aus Review heraus — dieselbe Regel wie überall.
    func testADraftBranchTicketStaysInTheWorkColumn() {
        let r = WorkflowStatus.resolve(
            ticketKey: "!133", hasTaskFile: false, statusMarker: nil, worktree: nil,
            mergeRequests: [mr(133, "opened", branch: "feature/e2e", draft: true)],
            branch: "feature/e2e")
        XCTAssertEqual(r.column, .inBearbeitung)
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 133, draft: true)))
    }

    /// Der Branch-Vergleich ist **exakt**. Ein Teilstring-Vergleich zöge `feature/pdf` auch
    /// `feature/pdf_improvements` an sich — in `zba` gibt es beide, und es sind eigene Arbeiten.
    func testBranchMatchingIsExactNotASubstring() {
        let mrs = [mr(85, "opened", branch: "feature/pdf_improvements", title: "PDF Improvements")]
        XCTAssertNil(WorkflowStatus.primaryMR(ticketKey: "!85", mergeRequests: mrs, branch: "feature/pdf"))
        XCTAssertEqual(WorkflowStatus.primaryMR(ticketKey: "!85", mergeRequests: mrs,
                                                branch: "feature/pdf_improvements")?.iid, 85)
    }

    /// Der Worktree hängt am selben Branch — sonst stünde die Karte ohne 🌳 da, obwohl der
    /// Checkout existiert (`feature/e2e-test-sf7` in `zba`).
    func testTheWorktreeIsFoundByBranchToo() {
        let trees = [Worktree(path: "/code/zba-e2e", branch: "feature/e2e-test-sf7"),
                     Worktree(path: "/code/zba", branch: "develop")]
        XCTAssertEqual(WorktreeScanner.worktree(for: "!133", in: trees,
                                                branch: "feature/e2e-test-sf7")?.path, "/code/zba-e2e")
        // Ohne Branch (normales Ticket) gilt weiter die Key-Suche.
        XCTAssertNil(WorktreeScanner.worktree(for: "!133", in: trees))
    }

    /// Ein Branch darf einem nummerierten Ticket nichts wegnehmen: ohne `branch` bleibt alles beim
    /// alten Verhalten.
    func testNumberedTicketsAreUnaffected() {
        let mrs = [mr(42, "opened", branch: "feature/EVEN-1_thing")]
        XCTAssertEqual(WorkflowStatus.primaryMR(ticketKey: "EVEN-1", mergeRequests: mrs)?.iid, 42)
        let r = WorkflowStatus.resolve(ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: nil,
                                       worktree: worktree, mergeRequests: mrs)
        XCTAssertEqual(r.column, .review)
    }

    // MARK: - Hold (⏸️)

    /// Hold pinnt keine Spalte: mit Worktree steht die Karte da, wo die Arbeit steht.
    func testHoldWithWorktreeStaysInBearbeitung() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .hold,
            worktree: worktree, mergeRequests: [])
        XCTAssertEqual(r.column, .inBearbeitung)
    }

    /// Ohne Worktree und ohne MR bleibt nur das Task-File — also Offen, nicht „In Bearbeitung".
    func testHoldWithOnlyATaskFileFallsToOffen() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .hold,
            worktree: nil, mergeRequests: [])
        XCTAssertEqual(r.column, .offen)
    }

    /// Der Normalfall einer Pause: man wartet auf eine Rückfrage am offenen MR. Die Karte gehört
    /// weiterhin nach Review — pausiert ist der Mensch, nicht der Merge Request.
    func testHoldWithAnOpenedReviewReadyMRStillReviews() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .hold,
            worktree: worktree, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_thing")])
        XCTAssertEqual(r.column, .review)
    }

    /// Ein Draft ist nicht review-reif — die Karte bleibt in ihrer Arbeitsspalte, wie bei jedem
    /// anderen Marker auch.
    func testHoldWithADraftMRKeepsTheWorkColumn() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .hold, worktree: worktree,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_thing", draft: true)])
        XCTAssertEqual(r.column, .inBearbeitung)
        XCTAssertTrue(r.badges.contains(.mergeRequest(iid: 7, draft: true)))
    }

    /// Was gemergt ist, ist nicht mehr pausiert: Done sticht den Marker, wie überall.
    func testMergedMRWinsOverHold() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .hold,
            worktree: worktree, mergeRequests: [mr(42, "merged", branch: "feature/EVEN-1_thing")])
        XCTAssertEqual(r.column, .done)
    }

    /// Dasselbe von der anderen Seite: Jira führt das Ticket als erledigt.
    func testJiraDoneWinsOverHold() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .hold,
            worktree: worktree, mergeRequests: [], jiraState: .done)
        XCTAssertEqual(r.column, .done)
    }

    /// **Der Kern des Status:** ein offener, review-reifer MR schreibt Hold nicht auf 🔵 zurück.
    /// Ohne diese Sperre hielte die Pause bis zum nächsten Board-Refresh.
    func testHoldIsNotAutoAdvancedToReview() {
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .hold,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")]))
    }

    /// Gegenprobe: unter genau denselben Bedingungen wird 🟡 weiterhin nachgeführt — die Sperre gilt
    /// dem Hold, nicht der Automatik.
    func testInArbeitIsStillAutoAdvancedToReview() {
        XCTAssertTrue(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .inArbeit,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")]))
    }

    /// Ein „wieder aufgemachtes" Ticket hebt ein veraltetes ✅ auf — ein Hold ist aber nie veraltet,
    /// sondern die aktuelle Absicht eines Menschen. Deshalb sperrt er auch hier.
    func testHoldSurvivesAReopenedTicket() {
        let mrs = [mr(1124, "merged", branch: "feature/EVEN-1_first_round"),
                   mr(1141, "opened", branch: "feature/EVEN-1_second_round")]
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .hold,
            mergeRequests: mrs, jiraState: .notDone))
        // Gegenprobe: dasselbe veraltete ✅ wird sehr wohl zurückgesetzt.
        XCTAssertTrue(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .done,
            mergeRequests: mrs, jiraState: .notDone))
    }

    /// Die Asymmetrie, ausdrücklich festgehalten: „in Jira erledigt" sticht Hold und schreibt ✅.
    /// Sie ist eine Entscheidung, kein Versehen — siehe `shouldAutoSetDone`.
    func testJiraDoneOverwritesTheHoldMarker() {
        XCTAssertTrue(WorkflowStatus.shouldAutoSetDone(
            hasTaskFile: true, currentMarker: .hold, jiraDone: true))
    }

    /// Freier Modus (`usesJira: false`, wie das Kanban-Projekt selbst): ohne Jira-Auskunft ist
    /// `JiraDoneState` `.unknown` — das darf nicht als „nicht erledigt" gelesen werden, und beide
    /// Automatiken lassen den Hold in Ruhe.
    func testHoldIsUntouchedWithoutJiraInformation() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .hold,
            worktree: worktree, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_thing", draft: true)])
        XCTAssertEqual(r.column, .inBearbeitung)
        XCTAssertFalse(WorkflowStatus.shouldAutoSetReview(
            ticketKey: "EVEN-1", hasTaskFile: true, currentMarker: .hold,
            mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_thing")]))
        XCTAssertFalse(WorkflowStatus.shouldAutoSetDone(
            hasTaskFile: true, currentMarker: .hold, jiraDone: false))
    }

    /// Nur `hold` hat keine Spalte — die fünf Pipeline-Status behalten ihre.
    func testOnlyHoldHasNoColumn() {
        XCTAssertNil(TaskStatusMarker.hold.column)
        for marker in TaskStatusMarker.allCases where marker != .hold {
            XCTAssertNotNil(marker.column, "\(marker) muss eine Spalte behalten")
        }
    }
}

final class TaskFileParsingTests: XCTestCase {
    func testStatusMarkerAndSections() {
        let content = """
        # EVEN-1 | Some title

        ### Status
        🟡 In Arbeit

        ## Beschreibung
        Hello world.

        ## Analyse
        Some analysis.

        ### Sub heading stays inside Analyse
        more.
        """
        let tf = TaskFileLoader.parse(content: content, url: URL(fileURLWithPath: "/x/EVEN-1.md"))
        XCTAssertEqual(tf.statusMarker, .inArbeit)
        XCTAssertEqual(tf.sections.map(\.title), ["Beschreibung", "Analyse"])
        XCTAssertTrue(tf.sections[1].markdown.contains("### Sub heading"))
    }

    func testSettingStatusReplacesExistingMarkerLine() {
        let content = """
        # EVEN-1 | Title

        ### Status
        🟢 Implementiert – bereit für Commit

        ## Beschreibung
        x
        """
        let out = TaskFileLoader.settingStatus(.inArbeit, in: content)
        XCTAssertTrue(out.contains("### Status\n🟡 In Arbeit\n"))
        XCTAssertFalse(out.contains("🟢"))
        XCTAssertTrue(out.contains("## Beschreibung"))   // rest preserved
    }

    func testSettingStatusInsertsSectionWhenMissing() {
        let content = "# EVEN-1 | Title\n\n## Beschreibung\nx"
        let out = TaskFileLoader.settingStatus(.review, in: content)
        XCTAssertTrue(out.contains("### Status\n🔵 Review"))
        let tf = TaskFileLoader.parse(content: out, url: URL(fileURLWithPath: "/x/EVEN-1.md"))
        XCTAssertEqual(tf.statusMarker, .review)
    }

    // MARK: - Hold (⏸️) in der Status-Zeile

    func testSettingAndParsingTheHoldStatus() {
        let content = """
        # EVEN-1 | Title

        ### Status
        🟡 In Arbeit

        ## Beschreibung
        x
        """
        let held = TaskFileLoader.settingStatus(.hold, in: content)
        XCTAssertTrue(held.contains("### Status\n⏸️ Hold\n"))
        XCTAssertFalse(held.contains("🟡"))                       // ersetzt, nicht verdoppelt
        XCTAssertTrue(held.contains("## Beschreibung"))           // Rest bleibt stehen
        XCTAssertEqual(TaskFileLoader.parse(content: held,
                                            url: URL(fileURLWithPath: "/x/EVEN-1.md")).statusMarker, .hold)

        // Und wieder zurück: die Pause ist kein Einbahnweg.
        let resumed = TaskFileLoader.settingStatus(.inArbeit, in: held)
        XCTAssertTrue(resumed.contains("### Status\n🟡 In Arbeit\n"))
        XCTAssertFalse(resumed.unicodeScalars.contains("\u{23F8}"))
    }

    /// ⏸️ ist U+23F8 **plus** Variation Selector U+FE0F; Swift vergleicht Graphem-Cluster, also ist
    /// `"⏸️ Hold".contains("⏸")` false. Eine von Hand getippte Zeile ohne Selector muss trotzdem als
    /// Hold gelten — sonst läse sich die Datei stillschweigend als „gar kein Status".
    func testHoldIsRecognisedWithAndWithoutTheVariationSelector() {
        let bare = "# EVEN-1 | Title\n\n### Status\n\u{23F8} Hold\n\n## Beschreibung\nx"
        XCTAssertFalse(bare.contains("⏸️"))                        // die Messung, auf der die Regel steht
        XCTAssertEqual(TaskFileLoader.parse(content: bare,
                                            url: URL(fileURLWithPath: "/x/EVEN-1.md")).statusMarker, .hold)

        // Und die Zeile wird ersetzt, nicht eine zweite darübergesetzt.
        let out = TaskFileLoader.settingStatus(.review, in: bare)
        XCTAssertTrue(out.contains("### Status\n🔵 Review\n"))
        XCTAssertFalse(out.unicodeScalars.contains("\u{23F8}"))
    }

    /// Erster Treffer gewinnt, und Hold steht zuoberst: eine Zeile, die den Wechsel beschreibt,
    /// meint den Status, in den gewechselt wurde.
    func testHoldWinsOnALineThatNamesTwoMarkers() {
        let content = "# EVEN-1 | Title\n\n### Status\n🟡 → ⏸️ Hold (wartet auf Rückfrage)\n"
        XCTAssertEqual(TaskFileLoader.parse(content: content,
                                            url: URL(fileURLWithPath: "/x/EVEN-1.md")).statusMarker, .hold)
    }

    /// Das Wort „Hold" im Fliesstext ist kein Marker — gesucht werden Emojis, und zuerst im
    /// `### Status`-Block.
    func testTheWordHoldInProseIsNotAMarker() {
        let content = "# EVEN-1 | Title\n\n### Status\n🟡 In Arbeit\n\n## Analyse\nHold bedeutet pausiert.\n"
        XCTAssertEqual(TaskFileLoader.parse(content: content,
                                            url: URL(fileURLWithPath: "/x/EVEN-1.md")).statusMarker, .inArbeit)
    }

    func testReviewFileExcludedFromFindButFoundSeparately() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Main file sorts AFTER "review" alphabetically → without the exclusion, find() would wrongly
        // pick the review file.
        try "# main".write(to: dir.appendingPathComponent("BFEZVM-4569_show_stuff.md"), atomically: true, encoding: .utf8)
        try "# Code-Review\n\nBody.".write(to: dir.appendingPathComponent("BFEZVM-4569_review.md"), atomically: true, encoding: .utf8)

        // A second review file for the same ticket.
        try "# Prong B".write(to: dir.appendingPathComponent("BFEZVM-4569_review_prong_b.md"), atomically: true, encoding: .utf8)
        // A different ticket whose key shares a prefix — must NOT be attributed to BFEZVM-4569.
        try "# other".write(to: dir.appendingPathComponent("BFEZVM-45690_review.md"), atomically: true, encoding: .utf8)

        let main = TaskFileLoader.find(ticketKey: "BFEZVM-4569", in: dir.path)
        XCTAssertEqual(main?.lastPathComponent, "BFEZVM-4569_show_stuff.md")

        let reviews = TaskFileLoader.reviewFiles(ticketKey: "bfezvm-4569", in: dir.path)   // case-insensitive
        XCTAssertEqual(reviews.map(\.lastPathComponent),
                       ["BFEZVM-4569_review.md", "BFEZVM-4569_review_prong_b.md"])   // sorted → stable numbering

        XCTAssertEqual(TaskFileLoader.loadReviewMarkdown(reviews[0]), "# Code-Review\n\nBody.")
        XCTAssertTrue(TaskFileLoader.reviewFiles(ticketKey: "BFEZVM-9999", in: dir.path).isEmpty)
    }

    func testImagePathRewrite() throws {
        // A real local image next to the task file is inlined as a data: URI (WKWebView can't load
        // file:// resources from loadHTMLString); remote and missing images are left untouched.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-parse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("EVEN-1"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        try png.write(to: root.appendingPathComponent("EVEN-1/pic.png"))

        let content = """
        ## Beschreibung
        ![shot](EVEN-1/pic.png) and ![remote](https://x/y.png) and ![miss](EVEN-1/nope.png)
        """
        let tf = TaskFileLoader.parse(content: content, url: root.appendingPathComponent("EVEN-1.md"))
        let md = tf.sections[0].markdown
        XCTAssertTrue(md.contains("data:image/png;base64,"), md)   // existing local file → inlined
        XCTAssertFalse(md.contains("EVEN-1/pic.png"), md)          // original path replaced
        XCTAssertTrue(md.contains("https://x/y.png"), md)          // remote untouched
        XCTAssertTrue(md.contains("EVEN-1/nope.png"), md)          // missing local file untouched
    }
}
