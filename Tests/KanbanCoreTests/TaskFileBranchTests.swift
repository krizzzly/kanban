import XCTest
@testable import KanbanCore

final class TaskFileBranchTests: XCTestCase {
    private let preamble = """
    # BFEZVM-4575 | Pagination
    > 🌳 **WORKTREE**: `/Users/x/code/bfezvm-worktree/bfezvm-4575`\\
    > 🌿 **BRANCH**: `feature/BFEZVM-4575_old_name`\\
    > 🐳 **STACK**: `https://stack.example`

    ## Analyse
    Text.
    """

    func testSettingBranchReplacesCodeSpanOnly() {
        let out = TaskFileLoader.settingBranch("feature/BFEZVM-4575_from_mr", in: preamble)
        XCTAssertTrue(out.contains("`feature/BFEZVM-4575_from_mr`"), out)
        XCTAssertFalse(out.contains("old_name"), out)
        // Everything else on the line (blockquote, emoji, trailing backslash) is preserved.
        XCTAssertTrue(out.contains("> 🌿 **BRANCH**: `feature/BFEZVM-4575_from_mr`\\"), out)
        // Other lines untouched.
        XCTAssertTrue(out.contains("**WORKTREE**"), out)
        XCTAssertTrue(out.contains("**STACK**"), out)
    }

    func testSettingBranchIdempotentWhenSame() {
        let same = TaskFileLoader.settingBranch("feature/BFEZVM-4575_old_name", in: preamble)
        XCTAssertEqual(same, preamble)
    }

    func testSettingBranchInsertsUnderTitleWhenAbsent() {
        let md = "# ZBA-489 | PDF access\n\n## Analyse\nText."
        let out = TaskFileLoader.settingBranch("feature/ZBA-489_pdf_access_of_archived_dossiers", in: md)
        let lines = out.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "# ZBA-489 | PDF access")
        XCTAssertEqual(lines[1], "> 🌿 **BRANCH**: `feature/ZBA-489_pdf_access_of_archived_dossiers`")
        XCTAssertTrue(out.contains("## Analyse"), out)
    }

    func testSettingBranchInsertThenUpdateIsStable() {
        let md = "# Ticket\n\n## Analyse\nText."
        let inserted = TaskFileLoader.settingBranch("feature/A", in: md)
        // Re-running with the same branch is a no-op; a new branch updates in place (no duplicate line).
        XCTAssertEqual(TaskFileLoader.settingBranch("feature/A", in: inserted), inserted)
        let updated = TaskFileLoader.settingBranch("feature/B", in: inserted)
        XCTAssertEqual(updated.components(separatedBy: "**BRANCH**").count - 1, 1, "genau eine BRANCH-Zeile")
        XCTAssertTrue(updated.contains("`feature/B`"), updated)
    }

    // MARK: - Merge Request line

    func testSettingMergeRequestAppendsThenUpdatesInPlace() {
        let md = "# Ticket\n\n## Analyse\nText."
        let a = TaskFileLoader.settingMergeRequest("https://git/x/-/merge_requests/1", in: md)
        XCTAssertTrue(a.contains("**Merge Request:** https://git/x/-/merge_requests/1"), a)
        XCTAssertEqual(TaskFileLoader.settingMergeRequest("https://git/x/-/merge_requests/1", in: a), a)  // idempotent
        let b = TaskFileLoader.settingMergeRequest("https://git/x/-/merge_requests/2", in: a)
        XCTAssertEqual(b.components(separatedBy: "**Merge Request:**").count - 1, 1, "genau eine MR-Zeile")
        XCTAssertTrue(b.contains("merge_requests/2"), b)
    }

    // MARK: - Filename from branch

    func testFileNameForBranch() {
        XCTAssertEqual(TaskFileLoader.fileName(forBranch: "feature/ZBA-489_pdf_access"),
                       "ZBA-489_pdf_access.md")
        XCTAssertEqual(TaskFileLoader.fileName(forBranch: "ZBA-1_x"), "ZBA-1_x.md")
        XCTAssertNil(TaskFileLoader.fileName(forBranch: ""))
    }

    func testRenameToMatchBranchRenamesWhenBelongsToTicket() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let old = dir.appendingPathComponent("ZBA-489_old_slug.md")
        try "content".write(to: old, atomically: true, encoding: .utf8)

        let new = TaskFileLoader.renameToMatchBranch(
            currentURL: old, branch: "feature/ZBA-489_pdf_access_of_archived_dossiers", ticketKey: "ZBA-489")
        XCTAssertEqual(new?.lastPathComponent, "ZBA-489_pdf_access_of_archived_dossiers.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new!.path))
    }

    func testRenameSkippedWhenNewNameWouldNotBelongToTicket() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-rename2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let old = dir.appendingPathComponent("ZBA-489_slug.md")
        try "content".write(to: old, atomically: true, encoding: .utf8)
        // Branch without the ticket key → renaming would orphan the file, so it must be skipped.
        XCTAssertNil(TaskFileLoader.renameToMatchBranch(
            currentURL: old, branch: "feature/cleanup_logs", ticketKey: "ZBA-489"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
    }
}
