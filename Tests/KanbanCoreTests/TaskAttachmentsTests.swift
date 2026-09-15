import XCTest
@testable import KanbanCore

final class TaskAttachmentsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("task-attachments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relativePath: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func tree(_ key: String) -> [KBNode] {
        TaskAttachments.tree(ticketKey: key, in: root.path)
    }

    // MARK: - Welcher Ordner gehört zum Ticket

    /// Die drei Schreibweisen, die auf dieser Maschine wirklich vorkommen: 191 × `<KEY>`, einmal der
    /// ganze Datei-Stamm, einmal eine angehängte Zahl (zweiter Export desselben Tickets).
    func testAcceptsTheFolderNamesThatOccurInPractice() {
        XCTAssertTrue(TaskAttachments.belongsToTicket("EVEN-3282", keyPrefix: "EVEN-3282"))
        XCTAssertTrue(TaskAttachments.belongsToTicket("EVEN-3282-1", keyPrefix: "EVEN-3282"))
        XCTAssertTrue(TaskAttachments.belongsToTicket("EVEN-3457_fire_nachweisverfassung",
                                                      keyPrefix: "EVEN-3457"))
    }

    /// Der Grund für die Ziffern-Schranke: ohne sie zöge ein Ticket die Bilder jedes Tickets an
    /// sich, dessen Nummer mit seiner anfängt.
    func testRejectsALongerTicketNumber() {
        XCTAssertFalse(TaskAttachments.belongsToTicket("EVEN-32820", keyPrefix: "EVEN-3282"))
        XCTAssertFalse(TaskAttachments.belongsToTicket("EVEN-3282-1", keyPrefix: "EVEN-328"))
        XCTAssertFalse(TaskAttachments.belongsToTicket("BFEZVM-3282", keyPrefix: "EVEN-3282"))
    }

    func testFindsTheFolderRegardlessOfCase() throws {
        try write("even-3282/bild.png")
        XCTAssertEqual(TaskAttachments.folders(ticketKey: "EVEN-3282", in: root.path).count, 1)
    }

    /// Eine **Datei**, die so heisst wie der Ordner hiesse, ist kein Task-Ordner.
    func testIgnoresFilesWithTheTicketName() throws {
        try write("EVEN-3282", "kein ordner")
        XCTAssertTrue(TaskAttachments.folders(ticketKey: "EVEN-3282", in: root.path).isEmpty)
    }

    func testMissingTasksDirectoryIsEmptyNotAnError() {
        XCTAssertTrue(TaskAttachments.tree(ticketKey: "EVEN-1", in: "/nope/nirgends").isEmpty)
    }

    // MARK: - Der Baum

    /// Ein Ordner steht als sein **Inhalt** da — der Ordnername ist die Ticketnummer und stünde
    /// sonst über jeder Zeile nochmal.
    func testSingleFolderIsFlattenedToItsContents() throws {
        try write("EVEN-3282/1-bild.png")
        try write("EVEN-3282/comments.json")
        try write("EVEN-3282/avatars/Frank.png")

        let nodes = tree("EVEN-3282")
        // Ordner zuerst, dann Dateien — die Sortierung von `KnowledgebaseTree`.
        XCTAssertEqual(nodes.map(\.name), ["avatars", "1-bild.png", "comments.json"])
        XCTAssertEqual(TaskAttachments.fileCount(nodes), 3)
    }

    /// Bei **mehreren** Ordnern bekommt jeder seine Zeile: flach wäre nicht mehr zu sehen, welches
    /// Bild aus welchem Export stammt.
    func testSeveralFoldersEachKeepTheirOwnRow() throws {
        try write("EVEN-3282/1-bild.png")
        try write("EVEN-3282-1/1-bild.png")

        let nodes = tree("EVEN-3282")
        XCTAssertEqual(nodes.map(\.name), ["EVEN-3282", "EVEN-3282-1"])
        XCTAssertTrue(nodes.allSatisfy(\.isDirectory))
        XCTAssertEqual(TaskAttachments.fileCount(nodes), 2)
    }

    /// Der leere Ordner ist der Normalfall nach einem `get-task` ohne Anhänge — er darf den Knopf
    /// nicht einschalten, sonst schlägt er ein leeres Feld auf.
    func testAnEmptyFolderCountsAsNothing() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("EVEN-3282"), withIntermediateDirectories: true)
        XCTAssertTrue(tree("EVEN-3282").isEmpty)
        XCTAssertEqual(TaskAttachments.fileCount(tree("EVEN-3282")), 0)
    }

    /// Der Baum trägt die Dateiart mit, sonst müsste die Vorschau sie erneut raten.
    func testCarriesTheFileKind() throws {
        try write("EVEN-3282/1-bild.png")
        try write("EVEN-3282/notiz.md")
        let byName = Dictionary(uniqueKeysWithValues: tree("EVEN-3282").map { ($0.name, $0.kind) })
        XCTAssertEqual(byName["1-bild.png"], .binary)
        XCTAssertEqual(byName["notiz.md"], .markdown)
    }
}
