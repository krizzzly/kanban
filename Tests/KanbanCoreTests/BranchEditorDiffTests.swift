import XCTest
@testable import KanbanCore

/// Der Editor im Reiter „Diff" — gegen ein **echtes** git-Repo.
///
/// Zwei Behauptungen hängen daran, und beide beantwortet nur git selbst:
/// 1. Die Einfärbung im Editor muss der Datei auf der Platte gelten, nicht HEAD — sonst verrutscht
///    sie in dem Moment, in dem man eine Zeile einfügt.
/// 2. Was man dort speichert, muss als Änderung im Arbeitsverzeichnis auftauchen — nur so landet
///    es in „Neuer Commit" / „Amend".
final class BranchEditorDiffTests: XCTestCase {
    private var repo: URL!
    private let git = GitCommitController()

    override func setUpWithError() throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("branch-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        run("init", "-q", "-b", "develop", ".")
        run("config", "user.email", "test@example.com")
        run("config", "user.name", "Test")
        run("config", "commit.gpgsign", "false")
        try write("app.php", "eins\nzwei\ndrei\n")
        // Steht schon in der Basis, damit ein Löschen auf dem Branch als Löschung im Diff auftaucht.
        try write("weg.txt", "wird auf dem Branch gelöscht\n")
        run("add", "-A")
        run("commit", "-q", "-m", "basis")

        // Der Ticket-Branch ändert die Datei in einem Commit — das ist, was der Reiter „Diff" zeigt.
        run("checkout", "-q", "-b", "feature/TEST-1")
        try write("app.php", "eins\nzwei\nDREI aus dem Branch\nvier\n")
        run("add", "-A")
        run("commit", "-q", "-m", "branch-arbeit")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
    }

    private var datei: GitChangedFile { GitChangedFile(path: "app.php", index: "M", worktree: " ") }

    private func mergeBase() throws -> String {
        let diff = try XCTUnwrap(git.branchDiff(dir: repo.path, baseRef: "develop"))
        return diff.mergeBase
    }

    /// Solange nichts Ungespeichertes herumliegt, sind beide Vergleiche gleich — der Editor zeigt
    /// dann dasselbe Grün wie das Diff daneben.
    func testOhneArbeitsstandSindBeideVergleicheGleich() throws {
        let base = try mergeBase()
        XCTAssertEqual(git.diff(dir: repo.path, file: datei, against: base),
                       git.diffWorktree(dir: repo.path, file: datei, against: base))
    }

    /// Der Kern: nach einer Bearbeitung im Editor zeigt nur der Arbeitsstand-Vergleich die neue
    /// Zeile. Gegen HEAD gerechnet fehlte sie — und die Einfärbung im Editor stünde auf der
    /// falschen Zeile.
    func testNachDemBearbeitenZeigtNurDerArbeitsstandDieNeueZeile() throws {
        let base = try mergeBase()
        try write("app.php", "eins\nzwei\nDREI aus dem Branch\nvier\nfuenf frisch getippt\n")

        let gegenHead = git.diff(dir: repo.path, file: datei, against: base)
        let gegenPlatte = git.diffWorktree(dir: repo.path, file: datei, against: base)

        XCTAssertFalse(gegenHead.contains("fuenf frisch getippt"))
        XCTAssertTrue(gegenPlatte.contains("+fuenf frisch getippt"))

        // Und die Einfärbung trifft die richtige Zeile: Zeile 5 ist neu.
        let markierung = DiffHighlight.from(DiffParser.parse(gegenPlatte))
        XCTAssertTrue(markierung.addedLines.contains(5),
                      "erwartet Zeile 5 als neu, markiert: \\(markierung.addedLines.sorted())")
        XCTAssertTrue(markierung.addedLines.contains(3), "die Branch-Zeile bleibt ebenfalls neu")
    }

    /// Was der Editor speichert, steht danach in `git status` — das ist der Weg, auf dem die Datei
    /// in „Neuer Commit" / „Amend" auftaucht.
    func testGespeichertesLandetInDerStatusliste() throws {
        XCTAssertTrue(git.state(dir: repo.path).changedFiles.isEmpty,
                      "frisch committet ist das Arbeitsverzeichnis sauber")

        try write("app.php", "eins\nzwei\nDREI aus dem Branch\nvier\nim Diff-Reiter nachgebessert\n")

        let geaendert = git.state(dir: repo.path).changedFiles
        XCTAssertEqual(geaendert.map(\.path), ["app.php"])
    }

    /// Eine Datei, die der Branch **gelöscht** hat, steht im Branch-Diff — auf der Platte gibt es
    /// sie aber nicht. Der Editor bleibt dort aus (`commitFileExists`), sonst legte ein Speichern
    /// sie wieder an.
    func testVomBranchGeloeschteDateiLiegtNichtAufDerPlatte() throws {
        run("rm", "-q", "weg.txt")
        run("commit", "-q", "-m", "datei weg")

        let diff = try XCTUnwrap(git.branchDiff(dir: repo.path, baseRef: "develop"))
        XCTAssertTrue(diff.files.contains { $0.path == "weg.txt" }, "steht im Branch-Diff")
        XCTAssertFalse(FileManager.default
            .fileExists(atPath: repo.appendingPathComponent("weg.txt").path))
    }

    // MARK: - Hilfen

    @discardableResult
    private func run(_ args: String...) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repo.path] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func write(_ path: String, _ contents: String) throws {
        try contents.write(to: repo.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
}
