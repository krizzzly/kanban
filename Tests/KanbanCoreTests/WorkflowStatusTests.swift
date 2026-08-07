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
            worktree: worktree, mergeRequests: [], jiraDone: true)
        XCTAssertEqual(r.column, .done)
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
