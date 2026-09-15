import XCTest
@testable import KanbanCore

/// `MRDiffPosition` — Port von Hermes' `position.js`. Die Zusagen hier wurden beim Portieren gegen
/// das JS-Original auf einem echten MR-Diff (5 Dateien, 19 Hunks) verglichen: Hunk-Grenzen und alle
/// aufgelösten Positionen stimmten überein.
final class MRDiffPositionTests: XCTestCase {
    /// Ein Diff mit allen drei Zeilenarten und zwei Hunks.
    private let diff = """
    @@ -10,6 +10,7 @@ class Foo
     kontext a
     kontext b
    -entfernt
    +hinzu 1
    +hinzu 2
     kontext c
    @@ -30,3 +31,3 @@
     kontext d
    -alt
    +neu
    """

    private var diffs: [GitLabDiff] {
        [GitLabDiff(oldPath: "src/Foo.php", newPath: "src/Foo.php", diff: diff,
                    newFile: false, renamedFile: false, deletedFile: false)]
    }

    func testParsesHunkBoundaries() {
        let hunks = MRDiffPosition.parseHunks(diff)
        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks[0].oldStart, 10)
        XCTAssertEqual(hunks[0].newStart, 10)
        XCTAssertEqual(hunks[0].oldEnd, 13)   // 2 Kontext + 1 entfernt + 1 Kontext
        XCTAssertEqual(hunks[0].newEnd, 14)   // 2 Kontext + 2 hinzu + 1 Kontext
        XCTAssertEqual(hunks[1].oldStart, 30)
        XCTAssertEqual(hunks[1].newStart, 31)
    }

    /// GitLabs Regel — daran hängt, ob der POST angenommen wird:
    /// hinzugefügt → nur `new_line`, entfernt → nur `old_line`, Kontext → **beide**.
    func testAddedLineCarriesOnlyTheNewNumber() throws {
        let position = try MRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 12, side: .new)
        XCTAssertEqual(position.newLine, 12)
        XCTAssertNil(position.oldLine)
    }

    func testRemovedLineCarriesOnlyTheOldNumber() throws {
        let position = try MRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 12, side: .old)
        XCTAssertEqual(position.oldLine, 12)
        XCTAssertNil(position.newLine)
    }

    func testContextLineCarriesBoth() throws {
        let position = try MRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 10, side: .new)
        XCTAssertEqual(position.oldLine, 10)
        XCTAssertEqual(position.newLine, 10)
    }

    /// Nicht kommentierbare Zeilen scheitern **vor** dem POST — GitLab würde sie mit 400 abweisen,
    /// und die Meldung nennt die Bereiche, die gehen.
    func testLineOutsideTheDiffIsRefusedWithRanges() {
        XCTAssertThrowsError(try MRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 500)) {
            guard case MRDiffPosition.PositionError.lineOutsideDiff(_, _, _, let ranges) = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
            XCTAssertEqual(ranges, "10-14, 31-32")
        }
    }

    func testUnknownFileNamesTheChangedOnes() {
        XCTAssertThrowsError(try MRDiffPosition.resolve(diffs: diffs, file: "src/Bar.php", line: 1)) {
            guard case MRDiffPosition.PositionError.fileNotInDiff(_, let known) = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
            XCTAssertEqual(known, ["src/Foo.php"])
        }
    }

    func testBinaryOrRenameOnlyFileHasNothingToCommentOn() {
        let renamed = [GitLabDiff(oldPath: "a.php", newPath: "b.php", diff: "",
                                  newFile: false, renamedFile: true, deletedFile: false)]
        XCTAssertThrowsError(try MRDiffPosition.resolve(diffs: renamed, file: "b.php", line: 1)) {
            guard case MRDiffPosition.PositionError.noCommentableLines = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
        }
    }

    func testRejectsNonsenseLineNumbers() {
        XCTAssertThrowsError(try MRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 0)) {
            XCTAssertEqual($0 as? MRDiffPosition.PositionError, .invalidLine(0))
        }
    }

    /// „\ No newline at end of file" ist keine Zeile und darf die Zählung nicht verschieben.
    func testIgnoresTheNoNewlineMarker() {
        let hunks = MRDiffPosition.parseHunks("@@ -1,2 +1,2 @@\n-alt\n+neu\n\\ No newline at end of file")
        XCTAssertEqual(hunks.first?.lines.count, 2)
        XCTAssertEqual(hunks.first?.newEnd, 1)
    }

    /// Der POST-Body braucht Position **und** das SHA-Tripel des MR — fehlt eins, lehnt GitLab ab.
    func testPositionBodyCarriesShasAndLines() throws {
        let position = try MRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 12, side: .new)
        let body = MRDiffPosition.body(position, refs: GitLabDiffRefs(baseSha: "b", startSha: "s", headSha: "h"))

        XCTAssertEqual(body["position_type"] as? String, "text")
        XCTAssertEqual(body["base_sha"] as? String, "b")
        XCTAssertEqual(body["start_sha"] as? String, "s")
        XCTAssertEqual(body["head_sha"] as? String, "h")
        XCTAssertEqual(body["new_path"] as? String, "src/Foo.php")
        XCTAssertEqual(body["new_line"] as? Int, 12)
        XCTAssertNil(body["old_line"])   // hinzugefügte Zeile hat keine alte Nummer
    }
}
