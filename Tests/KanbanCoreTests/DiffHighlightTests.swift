import XCTest
@testable import KanbanCore

final class DiffHighlightTests: XCTestCase {
    /// Two separate change regions in one file — the case that matters for the editor overlay.
    private let twoHunks = """
    diff --git a/src/Foo.php b/src/Foo.php
    --- a/src/Foo.php
    +++ b/src/Foo.php
    @@ -4,7 +4,7 @@ use Something;
     use A;
     use B;
    -use OldThing;
    +use NewThing;
     use C;
    @@ -42,6 +42,8 @@ class Foo
         public function bar(): void
         {
    +        $first = 1;
    +        $second = 2;
             return;
         }
    """

    func testBothChangeRegionsAreReported() {
        let lines = DiffParser.parse(twoHunks)
        XCTAssertEqual(lines.filter { $0.kind == .hunk }.count, 2, "beide Hunks müssen im Diff stehen")

        let highlight = DiffHighlight.from(lines)
        // Hunk 1: the replacement lands on new line 6; hunk 2 adds new lines 44 and 45.
        XCTAssertEqual(highlight.addedLines, [6, 44, 45])
    }

    func testDeletionWithoutReplacementMarksTheFollowingLine() {
        let removedOnly = """
        @@ -10,5 +10,4 @@
         keep
        -weg damit
         danach
        """
        let highlight = DiffHighlight.from(DiffParser.parse(removedOnly))
        XCTAssertTrue(highlight.addedLines.isEmpty)
        // "danach" is new line 11 — the line the deletion sat in front of.
        XCTAssertEqual(highlight.deletionMarkers, [11])
    }

    func testReplacedLineIsGreenNotDoubleMarked() {
        let replaced = """
        @@ -1,3 +1,3 @@
         a
        -alt
        +neu
        """
        let highlight = DiffHighlight.from(DiffParser.parse(replaced))
        XCTAssertEqual(highlight.addedLines, [2])
        XCTAssertTrue(highlight.deletionMarkers.isEmpty,
                      "eine ersetzte Zeile ist grün — kein zusätzlicher Löschmarker")
    }

    func testNewFileHighlightsEveryLine() {
        let added = """
        @@ -0,0 +1,3 @@
        +eins
        +zwei
        +drei
        """
        XCTAssertEqual(DiffHighlight.from(DiffParser.parse(added)).addedLines, [1, 2, 3])
    }

    func testUnchangedFileHasNoHighlight() {
        XCTAssertTrue(DiffHighlight.from([]).isEmpty)
    }
}
