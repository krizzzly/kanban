import XCTest
@testable import KanbanCore

/// `PRDiffPosition` — das GitHub-Gegenstück zu `MRDiffPosition`. **Bewusst derselbe Diff und
/// dieselben Fälle wie in `MRDiffPositionTests`**: die Eingabe ist identisch, nur die Zielform ist
/// eine andere (`path`/`line`/`side` statt `old_line`/`new_line`). Läuft eine Seite grün und die
/// andere nicht, liegt es an der Übersetzung und nicht am Hunk-Parser — den teilen sich beide.
final class PRDiffPositionTests: XCTestCase {
    /// Ein Diff mit allen drei Zeilenarten und zwei Hunks (Zeile für Zeile der aus
    /// `MRDiffPositionTests`).
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

    private var diffs: [GitHubDiff] {
        [GitHubDiff(oldPath: "src/Foo.php", newPath: "src/Foo.php", diff: diff,
                    newFile: false, renamedFile: false, deletedFile: false)]
    }

    /// GitHubs Regel — daran hängt, ob der POST angenommen wird: die Zeile plus die **Seite**,
    /// auf der sie existiert. Eine hinzugefügte Zeile gibt es nur rechts.
    func testAddedLineIsOnTheRight() throws {
        let position = try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 12)
        XCTAssertEqual(position.path, "src/Foo.php")
        XCTAssertEqual(position.line, 12)
        XCTAssertEqual(position.side, .right)
        XCTAssertNil(position.startLine)
    }

    /// Eine entfernte Zeile gibt es nur links — dieselbe Nummer, die andere Seite.
    func testRemovedLineIsOnTheLeft() throws {
        let position = try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php",
                                                  line: 12, side: .left)
        XCTAssertEqual(position.line, 12)
        XCTAssertEqual(position.side, .left)
    }

    /// Eine Kontextzeile steht auf beiden Seiten; es gilt die gefragte.
    func testContextLineWorksOnBothSides() throws {
        XCTAssertEqual(try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 10).side,
                       .right)
        XCTAssertEqual(try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php",
                                                  line: 10, side: .left).side, .left)
    }

    /// Die hinzugefügte Zeile 12 gibt es links **nicht** — der Fall, den GitLab durch das leere
    /// `old_line`-Feld ausdrückt und GitHub durch eine Absage.
    func testAddedLineIsNotCommentableOnTheLeft() {
        XCTAssertThrowsError(try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php",
                                                        line: 14, side: .left)) {
            guard case PRDiffPosition.PositionError.lineOutsideDiff = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
        }
    }

    /// Nicht kommentierbare Zeilen scheitern **vor** dem POST — GitHub würde sie mit 422 abweisen,
    /// und die Meldung nennt die Bereiche, die gehen (dieselben wie bei GitLab).
    func testLineOutsideTheDiffIsRefusedWithRanges() {
        XCTAssertThrowsError(try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 500)) {
            guard case PRDiffPosition.PositionError.lineOutsideDiff(_, _, _, let ranges) = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
            XCTAssertEqual(ranges, "10-14, 31-32")
        }
    }

    func testUnknownFileNamesTheChangedOnes() {
        XCTAssertThrowsError(try PRDiffPosition.resolve(diffs: diffs, file: "src/Bar.php", line: 1)) {
            guard case PRDiffPosition.PositionError.fileNotInDiff(_, let known) = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
            XCTAssertEqual(known, ["src/Foo.php"])
        }
    }

    /// Ein reiner Rename hat keinen Patch — und eine Datei, deren `patch` GitHub weggelassen hat
    /// (binär oder zu gross), sieht genauso aus.
    func testFileWithoutAPatchHasNothingToCommentOn() {
        let renamed = [GitHubDiff(oldPath: "a.php", newPath: "b.php", diff: "",
                                  newFile: false, renamedFile: true, deletedFile: false)]
        XCTAssertThrowsError(try PRDiffPosition.resolve(diffs: renamed, file: "b.php", line: 1)) {
            guard case PRDiffPosition.PositionError.noCommentableLines = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
        }
    }

    func testRejectsNonsenseLineNumbers() {
        XCTAssertThrowsError(try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 0)) {
            XCTAssertEqual($0 as? PRDiffPosition.PositionError, .invalidLine(0))
        }
    }

    /// Der Mehrzeilen-Kommentar, für den GitLab kein Gegenstück hat: beide Enden müssen im Diff
    /// liegen, und der Anfang vor dem Ende.
    func testMultiLineCommentCarriesStartLineAndSide() throws {
        let position = try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php",
                                                  line: 14, startLine: 12)
        XCTAssertEqual(position.startLine, 12)
        XCTAssertEqual(position.startSide, .right)

        XCTAssertThrowsError(try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php",
                                                        line: 12, startLine: 14)) {
            XCTAssertEqual($0 as? PRDiffPosition.PositionError, .startAfterEnd(start: 14, line: 12))
        }
    }

    /// Anfang == Ende ist eine einzelne Zeile — `start_line` mitzuschicken lehnt GitHub ab.
    func testStartEqualToLineCollapsesToASingleLine() throws {
        let position = try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php",
                                                  line: 12, startLine: 12)
        XCTAssertNil(position.startLine)
        XCTAssertNil(position.startSide)
    }

    /// Der POST-Body braucht Position **und** den Commit — fehlt einer, lehnt GitHub ab. Das ist
    /// GitHubs Gegenstück zu GitLabs SHA-Tripel, nur eben ein einzelner Wert.
    func testPositionBodyCarriesCommitAndSide() throws {
        let position = try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php", line: 12)
        let body = PRDiffPosition.body(position, commitId: "abc123")

        XCTAssertEqual(body["commit_id"] as? String, "abc123")
        XCTAssertEqual(body["path"] as? String, "src/Foo.php")
        XCTAssertEqual(body["line"] as? Int, 12)
        XCTAssertEqual(body["side"] as? String, "RIGHT")
        XCTAssertNil(body["start_line"])   // einzelne Zeile
        XCTAssertNil(body["start_side"])
    }

    func testMultiLineBodyCarriesTheStartFields() throws {
        let position = try PRDiffPosition.resolve(diffs: diffs, file: "src/Foo.php",
                                                  line: 14, startLine: 12)
        let body = PRDiffPosition.body(position, commitId: "abc123")
        XCTAssertEqual(body["start_line"] as? Int, 12)
        XCTAssertEqual(body["start_side"] as? String, "RIGHT")
    }

    /// Die Übersetzung zwischen den beiden Seiten-Vokabularen, damit ein Aufrufer nur eines kennen
    /// muss.
    func testSideTranslatesFromGitLabsVocabulary() {
        XCTAssertEqual(PRDiffPosition.Side(MRDiffPosition.Side.new), .right)
        XCTAssertEqual(PRDiffPosition.Side(MRDiffPosition.Side.old), .left)
    }
}
