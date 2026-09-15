import XCTest
@testable import KanbanCore

/// Der Ausschluss einzelner Dateien aus Commit/Amend — gegen ein **echtes** git-Repo.
///
/// Ein Attrappen-Test hätte hier nichts bewiesen: die ganze Frage ist, was `git add -A` und
/// `git restore --staged` miteinander tun, und das beantwortet nur git selbst.
final class CommitExclusionTests: XCTestCase {
    private var repo: URL!
    private let git = GitCommitController()

    override func setUpWithError() throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("commit-exclude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        run("init", "-q", ".")
        run("config", "user.email", "test@example.com")
        run("config", "user.name", "Test")
        run("config", "commit.gpgsign", "false")
        try write("tracked.txt", "eins")
        run("add", "-A")
        run("commit", "-q", "-m", "init")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
    }

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
        let url = repo.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Dateien im letzten Commit.
    private var committedFiles: [String] {
        run("show", "--pretty=format:", "--name-only", "HEAD")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
    }

    private var statusPaths: [String] {
        GitCommitController.parseStatus(run("status", "--porcelain", "-z", "--untracked-files=all"))
            .map(\.path).sorted()
    }

    // MARK: - Commit

    func testExcludedFileStaysOutOfTheCommit() throws {
        try write("tracked.txt", "zwei")
        try write(".claude/project.json", #"{"prefix":"EVEN"}"#)
        try write("src/Neu.php", "<?php")

        try git.commit(dir: repo.path, message: "ohne project.json",
                       excluding: [".claude/project.json"])

        XCTAssertEqual(committedFiles, ["src/Neu.php", "tracked.txt"])
        // Und sie ist **nicht weg**: sie liegt unverändert im Arbeitsverzeichnis, weiter unversioniert.
        XCTAssertEqual(statusPaths, [".claude/project.json"])
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".claude/project.json"),
                                  encoding: .utf8), #"{"prefix":"EVEN"}"#)
    }

    /// Eine abgewählte **Löschung** darf nicht mitcommittet werden — die Datei bleibt in HEAD.
    func testAnExcludedDeletionKeepsTheFileInHead() throws {
        try write("wird_geloescht.txt", "da")
        run("add", "-A"); run("commit", "-q", "-m", "zwei")

        try FileManager.default.removeItem(at: repo.appendingPathComponent("wird_geloescht.txt"))
        try write("tracked.txt", "drei")
        try git.commit(dir: repo.path, message: "Löschung aussen vor",
                       excluding: ["wird_geloescht.txt"])

        XCTAssertEqual(committedFiles, ["tracked.txt"])
        XCTAssertFalse(run("cat-file", "-e", "HEAD:wird_geloescht.txt").contains("fatal"))
    }

    /// Eine abgewählte **Änderung** an einer verfolgten Datei bleibt im Arbeitsverzeichnis stehen.
    func testAnExcludedModificationStaysInTheWorkingTree() throws {
        try write("tracked.txt", "geändert")
        try write("anderes.txt", "neu")
        try git.commit(dir: repo.path, message: "nur das andere", excluding: ["tracked.txt"])

        XCTAssertEqual(committedFiles, ["anderes.txt"])
        XCTAssertEqual(statusPaths, ["tracked.txt"])
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("tracked.txt"),
                                  encoding: .utf8), "geändert")
    }

    /// Ohne Abwahl bleibt es wortgleich beim alten Verhalten: `git add -A` nimmt alles mit.
    func testWithoutExclusionsEverythingIsCommitted() throws {
        try write("tracked.txt", "zwei")
        try write(".claude/project.json", "{}")
        try git.commit(dir: repo.path, message: "alles")
        XCTAssertEqual(committedFiles, [".claude/project.json", "tracked.txt"])
        XCTAssertTrue(statusPaths.isEmpty)
    }

    /// Pfade mit Leerzeichen und Umlauten — sie gehen als eigenes Argument an git, nie durch eine
    /// Shell; ein Quoting-Fehler zeigte sich sonst genau hier.
    func testPathsWithSpacesAndUmlauts() throws {
        try write("Lösung mit Leer.md", "x")
        try write("tracked.txt", "zwei")
        try git.commit(dir: repo.path, message: "nur tracked", excluding: ["Lösung mit Leer.md"])
        XCTAssertEqual(committedFiles, ["tracked.txt"])
        XCTAssertEqual(statusPaths, ["Lösung mit Leer.md"])
    }

    /// Ein Pfad, den es nicht (mehr) gibt, darf den Commit **nicht** verhindern: git meldet dafür
    /// „pathspec did not match" mit Exit 1. Genau deshalb wird jeder Pfad **einzeln** abgeräumt und
    /// sein Fehlschlag geschluckt — in einem Aufruf risse der eine tote Pfad die gültigen mit.
    func testAStalePathDoesNotAbortTheCommit() throws {
        try write("tracked.txt", "zwei")
        try write("bleibt_draussen.txt", "x")
        XCTAssertNoThrow(try git.commit(dir: repo.path, message: "trotzdem",
                                        excluding: ["gibt/es/nicht.txt", "bleibt_draussen.txt"]))
        XCTAssertEqual(committedFiles, ["tracked.txt"])
        XCTAssertEqual(statusPaths, ["bleibt_draussen.txt"])
    }

    /// Alles abgewählt heisst: es bleibt nichts zu committen, und **git weigert sich** („no changes
    /// added to commit"). Das ist richtig so — ein leerer Commit sagt nichts. Deshalb sperrt
    /// `CommitSheet.canSubmit` den Knopf schon vorher, statt den Menschen in diesen Fehler laufen zu
    /// lassen.
    func testExcludingEverythingLeavesNothingToCommit() throws {
        try write("tracked.txt", "zwei")
        XCTAssertThrowsError(try git.commit(dir: repo.path, message: "leer",
                                            excluding: ["tracked.txt"]))
        XCTAssertEqual(statusPaths, ["tracked.txt"])   // nichts verloren
    }

    /// Beim **Amend** ist derselbe Fall gültig: HEAD wird ohnehin neu geschrieben (und danach neu
    /// gepusht), auch ohne eine einzige neue Änderung.
    func testAmendWithEverythingExcludedStillWorks() throws {
        try write("tracked.txt", "zwei")
        XCTAssertNoThrow(try git.amend(dir: repo.path, excluding: ["tracked.txt"]))
        XCTAssertEqual(statusPaths, ["tracked.txt"])
    }

    // MARK: - Amend

    func testAmendHonoursExclusionsToo() throws {
        try write("tracked.txt", "zwei")
        try write(".claude/project.json", "{}")
        try git.amend(dir: repo.path, excluding: [".claude/project.json"])

        XCTAssertEqual(committedFiles, ["tracked.txt"])
        XCTAssertEqual(statusPaths, [".claude/project.json"])
        // Die Message von HEAD bleibt (`--no-edit`).
        XCTAssertEqual(run("log", "-1", "--pretty=%s").trimmingCharacters(in: .whitespacesAndNewlines),
                       "init")
    }
}
