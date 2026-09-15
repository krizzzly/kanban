import XCTest
@testable import KanbanCore

/// Die Snapshot-Ablage von `iwf db snapshot` — Ordner, Dateinamen, Sortierung.
/// Die Formen stammen aus iwfs Quelltext (`project_compose.db_create_snapshot`) und den echten
/// Dateien auf dieser Maschine (`~/.iwf-dev/snapshots/even/even_dbdata-latest.tar`, 437 MB).
final class DbSnapshotsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDirectoryAndVolumeFollowTheStackName() {
        XCTAssertTrue(DbSnapshots.root.hasSuffix("/.iwf-dev/snapshots"))
        XCTAssertEqual(DbSnapshots.directory(stack: "even-3963"),
                       DbSnapshots.root + "/even-3963")
        XCTAssertEqual(DbSnapshots.defaultVolume(stack: "even"), "even_dbdata")
        XCTAssertEqual(DbSnapshots.defaultVolume(stack: "even-3963"), "even-3963_dbdata")
    }

    /// `latest` erkennt man am Suffix — es ist die Datei, die ein `create` ohne Flag überschreibt
    /// und ein `restore` ohne `-f` nimmt.
    func testLabelAndLatestFlag() {
        let latest = DbSnapshot(name: "even_dbdata-latest.tar", path: "/x", bytes: 1, modified: .now)
        let named = DbSnapshot(name: "even_dbdata-vor-migration.tar", path: "/x", bytes: 1, modified: .now)
        let stamped = DbSnapshot(name: "even_dbdata-2026-9-3--10-5-1.tar", path: "/x", bytes: 1, modified: .now)

        XCTAssertTrue(latest.isLatest)
        XCTAssertFalse(named.isLatest)
        XCTAssertEqual(latest.label(volume: "even_dbdata"), "latest")
        XCTAssertEqual(named.label(volume: "even_dbdata"), "vor-migration")
        XCTAssertEqual(stamped.label(volume: "even_dbdata"), "2026-9-3--10-5-1")
    }

    /// Die Eigenschaft, auf die es ankommt: das Ergebnis ist immer ein **reiner Dateiname** —
    /// kein Trenner, kein Leerzeichen, nie leer. Punkte bleiben erlaubt (`v1.2` will man haben);
    /// ein `..` darin ist harmlos, solange kein `/` danebensteht, denn dann ist es ein Zeichen im
    /// Namen und kein Verzeichniswechsel.
    func testNamesBecomePlainFileNames() {
        XCTAssertEqual(DbSnapshots.fileName(volume: "even_dbdata", label: "vor Migration"),
                       "even_dbdata-vor-Migration.tar")
        XCTAssertEqual(DbSnapshots.fileName(volume: "even_dbdata", label: "v1.2"),
                       "even_dbdata-v1.2.tar")
        XCTAssertEqual(DbSnapshots.fileName(volume: "even_dbdata", label: "  "),
                       "even_dbdata-snapshot.tar")

        for label in ["a/../b", "../../etc/passwd", "mit Leer zeichen", "üml äute", ""] {
            let name = DbSnapshots.fileName(volume: "even_dbdata", label: label)
            XCTAssertFalse(name.contains("/"), name)
            XCTAssertFalse(name.contains(" "), name)
            XCTAssertEqual((name as NSString).lastPathComponent, name)
            XCTAssertTrue(name.hasPrefix("even_dbdata-") && name.hasSuffix(".tar"), name)
        }
    }

    func testListReadsTheFolderNewestFirst() throws {
        let old = dir.appendingPathComponent("even_dbdata-latest.tar")
        let new = dir.appendingPathComponent("even_dbdata-vor-migration.tar")
        try Data(repeating: 0, count: 2048).write(to: old)
        try Data(repeating: 0, count: 1024).write(to: new)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)],
                                              ofItemAtPath: old.path)
        // Fremde Dateien im Ordner gehören nicht dazu — iwf globt ebenfalls nur *.tar.
        try Data().write(to: dir.appendingPathComponent("notiz.txt"))

        let snapshots = DbSnapshots.list(stack: dir.lastPathComponent, root: dir.deletingLastPathComponent().path)
        XCTAssertEqual(snapshots.map(\.name),
                       ["even_dbdata-vor-migration.tar", "even_dbdata-latest.tar"])
        XCTAssertEqual(snapshots.last?.bytes, 2048)
    }

    /// Nach `create -t` steht der neue Snapshot nur über die Differenz fest — iwfs Zeitstempel
    /// (`YYYY-M-D--H-M-S`, ohne führende Nullen) nachzubauen wäre eine Wette auf fremden Code.
    func testAddedFindsTheFreshFile() {
        let before = [DbSnapshot(name: "a.tar", path: "/a", bytes: 1, modified: .now)]
        let after = [DbSnapshot(name: "b.tar", path: "/b", bytes: 1, modified: .now),
                     DbSnapshot(name: "a.tar", path: "/a", bytes: 1, modified: .now)]
        XCTAssertEqual(DbSnapshots.added(before: before, after: after)?.name, "b.tar")
        XCTAssertNil(DbSnapshots.added(before: after, after: after))
    }
}
