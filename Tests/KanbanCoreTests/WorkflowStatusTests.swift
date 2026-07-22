import XCTest
@testable import KanbanCore

final class WorkflowStatusTests: XCTestCase {
    private func mr(_ iid: Int, _ state: String, branch: String, title: String = "") -> MergeRequestRef {
        MergeRequestRef(iid: iid, title: title, state: state, sourceBranch: branch,
                        targetBranch: "main", mergedAt: state == "merged" ? "2026-06-01" : nil,
                        webUrl: "https://git/\(iid)")
    }
    private let worktree = Worktree(path: "/code/even", branch: "feature/EVEN-1_thing")

    func testMergedMRWinsOverEverything() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .inArbeit,
            worktree: worktree, mergeRequests: [mr(42, "merged", branch: "feature/EVEN-1_thing")])
        XCTAssertEqual(r.column, .done)
        XCTAssertTrue(r.badges.contains(.mergeRequest(42)))
        XCTAssertTrue(r.badges.contains(.file))
        XCTAssertTrue(r.badges.contains(.worktree))
    }

    func testOpenedMRIsReviewEvenWhenInArbeit() {
        let r = WorkflowStatus.resolve(
            ticketKey: "EVEN-1", hasTaskFile: true, statusMarker: .inArbeit,
            worktree: nil, mergeRequests: [mr(7, "opened", branch: "feature/EVEN-1_x")])
        XCTAssertEqual(r.column, .review)
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
        XCTAssertTrue(r.badges.contains(.mergeRequest(9)))  // merged preferred for badge
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
        XCTAssertTrue(r.badges.contains(.mergeRequest(13)))
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
