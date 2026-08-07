import XCTest
@testable import KanbanCore

final class DiffParserTests: XCTestCase {
    private let diff = """
    diff --git a/src/Foo.php b/src/Foo.php
    index 1a2b3c4..5d6e7f8 100644
    --- a/src/Foo.php
    +++ b/src/Foo.php
    @@ -10,6 +10,7 @@ class Foo
         public function bar(): void
         {
    -        $old = 1;
    +        $new = 2;
    +        $extra = 3;
         }
    """

    func testAdditionsAndDeletionsAreClassified() {
        let lines = DiffParser.parse(diff)
        XCTAssertEqual(lines.filter { $0.kind == .addition }.count, 2)
        XCTAssertEqual(lines.filter { $0.kind == .deletion }.count, 1)
        XCTAssertEqual(lines.filter { $0.kind == .hunk }.count, 1)
    }

    func testFileHeaderNoiseIsDroppedByDefault() {
        let lines = DiffParser.parse(diff)
        XCTAssertFalse(lines.contains { $0.text.contains("diff --git") })
        XCTAssertFalse(lines.contains { $0.kind == .meta })
        XCTAssertTrue(DiffParser.parse(diff, includeMeta: true).contains { $0.kind == .meta })
    }

    func testMarkersAreStrippedFromTheText() {
        let added = DiffParser.parse(diff).first { $0.kind == .addition }
        XCTAssertEqual(added?.text, "        $new = 2;")
    }

    func testLineNumbersFollowBothSidesOfTheHunk() {
        let lines = DiffParser.parse(diff)
        // Hunk starts at old 10 / new 10; two context lines precede the change.
        let firstContext = lines.first { $0.kind == .context }
        XCTAssertEqual(firstContext?.oldNumber, 10)
        XCTAssertEqual(firstContext?.newNumber, 10)

        let deletion = lines.first { $0.kind == .deletion }
        XCTAssertEqual(deletion?.oldNumber, 12)
        XCTAssertNil(deletion?.newNumber, "a deleted line has no line number on the new side")

        let additions = lines.filter { $0.kind == .addition }
        XCTAssertEqual(additions.map(\.newNumber), [12, 13])
        XCTAssertTrue(additions.allSatisfy { $0.oldNumber == nil })
    }

    func testHunkHeaderParsing() {
        XCTAssertEqual(DiffParser.hunkStart("@@ -10,6 +12,7 @@ class Foo").old, 10)
        XCTAssertEqual(DiffParser.hunkStart("@@ -10,6 +12,7 @@ class Foo").new, 12)
        // Single-line hunks omit the count.
        XCTAssertEqual(DiffParser.hunkStart("@@ -1 +1 @@").old, 1)
    }

    func testNoNewlineMarkerIsIgnored() {
        let lines = DiffParser.parse("@@ -1 +1 @@\n-a\n+b\n\\ No newline at end of file")
        XCTAssertEqual(lines.filter { $0.kind == .addition || $0.kind == .deletion }.count, 2)
    }

    func testEmptyDiffYieldsNoLines() {
        XCTAssertTrue(DiffParser.parse("").isEmpty)
    }

    // MARK: - git status parsing

    func testStatusLineParsing() {
        let modified = GitCommitController.parseStatusLine(" M src/Foo.php")
        XCTAssertEqual(modified?.path, "src/Foo.php")
        XCTAssertEqual(modified?.marker, "M")
        XCTAssertFalse(modified?.isUntracked ?? true)

        let untracked = GitCommitController.parseStatusLine("?? docs/new.md")
        XCTAssertTrue(untracked?.isUntracked ?? false)
        XCTAssertEqual(untracked?.marker, "?")

        // A rename lists both paths — the new one is what the dialog shows.
        XCTAssertEqual(GitCommitController.parseStatusLine("R  old.php -> new.php")?.path, "new.php")
        XCTAssertNil(GitCommitController.parseStatusLine(""))
    }
}
