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

    func testStatusRecordParsing() {
        let modified = GitCommitController.parseStatusRecord(" M src/Foo.php")
        XCTAssertEqual(modified?.path, "src/Foo.php")
        XCTAssertEqual(modified?.marker, "M")
        XCTAssertFalse(modified?.isUntracked ?? true)

        let untracked = GitCommitController.parseStatusRecord("?? docs/new.md")
        XCTAssertTrue(untracked?.isUntracked ?? false)
        XCTAssertEqual(untracked?.marker, "?")

        XCTAssertNil(GitCommitController.parseStatusRecord(""))
    }

    func testStatusParsesUntrackedFilesWithSpacesAndUmlauts() {
        // `-z` hands the path over raw — no quoting, no octal escaping to undo.
        let files = GitCommitController.parseStatus("?? docs/Lösung.md\0?? mit leer.md\0 M src/Foo.php\0")
        XCTAssertEqual(files.map(\.path), ["docs/Lösung.md", "mit leer.md", "src/Foo.php"])
        XCTAssertEqual(files.filter(\.isUntracked).count, 2)
    }

    func testStatusSkipsTheSourcePathOfARename() {
        // A rename is two records: `R  <new>` then the source path on its own.
        let files = GitCommitController.parseStatus("R  new.php\0old.php\0?? docs/new.md\0")
        XCTAssertEqual(files.map(\.path), ["new.php", "docs/new.md"])
        XCTAssertEqual(files.first?.marker, "R")
    }

    func testStatusListsEveryFileOfANewDirectory() {
        // `--untracked-files=all` is what makes these separate records instead of one `newdir/` entry.
        let files = GitCommitController.parseStatus("?? newdir/a.txt\0?? newdir/sub/b.txt\0")
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy(\.isUntracked))
    }

    // MARK: - git diff --name-status -z (Reiter „Diff“)

    /// Der Formatunterschied, an dem ein Parser scheitert, der von `--name-status` **ohne** `-z`
    /// ausgeht: dort trennt ein **Tab** Status und Pfad, mit `-z` ist es ein NUL wie zwischen den
    /// Einträgen. Am echten git abgelesen, nicht der Doku entnommen.
    func testNameStatusFieldsAreNulSeparatedNotTabSeparated() {
        let files = GitCommitController.parseNameStatus("M\0CLAUDE.md\0A\0src/Neu.php\0D\0alt.md\0")
        XCTAssertEqual(files.map(\.path), ["CLAUDE.md", "src/Neu.php", "alt.md"])
        XCTAssertEqual(files.map(\.marker), ["M", "A", "D"])
    }

    /// Ein Umbenennen trägt seine Ähnlichkeit im Statusfeld (`R095`) und **zwei** Pfade dahinter.
    /// Gezeigt wird der neue — wie in der Status-Liste. Wer den zweiten Pfad nicht verbraucht,
    /// liest ihn als nächsten Status und die ganze restliche Liste verrutscht.
    func testNameStatusTakesTheTargetPathOfARename() {
        let files = GitCommitController.parseNameStatus(
            "R095\0commands/create-task.md\0skills/create-task/SKILL.md\0M\0CLAUDE.md\0")
        XCTAssertEqual(files.map(\.path), ["skills/create-task/SKILL.md", "CLAUDE.md"])
        XCTAssertEqual(files.map(\.marker), ["R", "M"])
    }

    func testNameStatusHandlesCopiesLikeRenames() {
        let files = GitCommitController.parseNameStatus("C070\0a.php\0b.php\0")
        XCTAssertEqual(files.map(\.path), ["b.php"])
        XCTAssertEqual(files.first?.marker, "C")
    }

    /// Pfade kommen mit `-z` roh — keine Anführungszeichen, keine Oktal-Escapes zurückzurechnen.
    func testNameStatusKeepsRawPaths() {
        let files = GitCommitController.parseNameStatus("M\0docs/Lösung.md\0M\0mit leer.md\0")
        XCTAssertEqual(files.map(\.path), ["docs/Lösung.md", "mit leer.md"])
    }

    /// Ein Branch ohne eigene Änderung ist kein Fehler — die leere Ausgabe endet auf einem NUL und
    /// darf keinen Geister-Eintrag ergeben.
    func testNameStatusOfAnUnchangedBranchIsEmpty() {
        XCTAssertTrue(GitCommitController.parseNameStatus("").isEmpty)
        XCTAssertTrue(GitCommitController.parseNameStatus("\0").isEmpty)
    }

    /// Nichts aus dem Branch-Diff ist „unversioniert": gegen einen Commit hat jede Datei zwei
    /// Seiten. Sonst liefe die Anzeige in den `--no-index`-Sonderweg des Arbeitsverzeichnisses.
    func testNameStatusEntriesAreNeverUntracked() {
        let files = GitCommitController.parseNameStatus("A\0neu.php\0M\0alt.php\0")
        XCTAssertTrue(files.allSatisfy { !$0.isUntracked })
    }
}
