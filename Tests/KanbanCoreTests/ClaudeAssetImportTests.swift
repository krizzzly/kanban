import XCTest
@testable import KanbanCore

/// Inhalt aus einer Markdown-Datei von der Platte übernehmen — und dabei nicht das Frontmatter
/// verlieren, von dem ein Skill lebt.
final class ClaudeAssetImportTests: XCTestCase {
    private var ordner: URL!

    override func setUpWithError() throws {
        ordner = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    private func datei(_ name: String, _ inhalt: String) throws -> URL {
        let url = ordner.appendingPathComponent(name)
        try inhalt.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let mitKopf = """
    ---
    name: solve-task
    description: löst ein Ticket
    disable-model-invocation: true
    ---

    # solve-task

    alter Rumpf
    """

    // MARK: - Frontmatter

    /// Der Kern: eine beliebige Markdown-Datei hat keinen Kopf. Sie einfach hineinzukopieren machte
    /// aus einem funktionierenden Skill eine Datei, die kein Agent mehr anbietet — lautlos.
    func testKopfBleibtStehenWennDieDateiKeinenHat() {
        let ergebnis = ClaudeAssetImport.zusammengefuegt(bisher: mitKopf, eingelesen: "# Neu\n\nneuer Rumpf\n")
        XCTAssertTrue(ergebnis.hasPrefix("---\nname: solve-task"))
        XCTAssertTrue(ergebnis.contains("disable-model-invocation: true"))
        XCTAssertTrue(ergebnis.contains("neuer Rumpf"))
        XCTAssertFalse(ergebnis.contains("alter Rumpf"))
    }

    /// Wer selbst ein Frontmatter mitbringt, meint es auch — zwei Köpfe übereinander wären in
    /// beiden Agents ungültig.
    func testEigenesFrontmatterGiltUnveraendert() {
        let eingelesen = "---\nname: anders\ndescription: etwas anderes\n---\n\n# anders\n"
        let ergebnis = ClaudeAssetImport.zusammengefuegt(bisher: mitKopf, eingelesen: eingelesen)
        XCTAssertEqual(ergebnis, eingelesen)
        XCTAssertFalse(ergebnis.contains("solve-task"))
    }

    /// Eine Rule hat keinen Kopf — dann gibt es auch nichts zu bewahren.
    func testOhneBisherigenKopfWirdEinfachErsetzt() {
        let ergebnis = ClaudeAssetImport.zusammengefuegt(bisher: "# alte Regel\n", eingelesen: "# neue Regel\n")
        XCTAssertEqual(ergebnis, "# neue Regel\n")
    }

    /// `---` als **Trennlinie** mitten im Text ist kein Frontmatter; ein offener Block auch nicht.
    func testTrennlinieIstKeinFrontmatter() {
        XCTAssertNil(ClaudeAssetImport.frontmatterBlock("# Titel\n\n---\n\nText"))
        XCTAssertNil(ClaudeAssetImport.frontmatterBlock("---\nname: x\nkein Ende"))
        XCTAssertEqual(ClaudeAssetImport.frontmatterBlock("---\nname: x\n---\nRumpf"),
                       "---\nname: x\n---")
    }

    func testKopfUndRumpfWerdenNichtVerklebt() {
        let ergebnis = ClaudeAssetImport.zusammengefuegt(bisher: "---\na: 1\n---\nalt",
                                                         eingelesen: "\n\n\nneu")
        XCTAssertEqual(ergebnis, "---\na: 1\n---\nneu")
    }

    // MARK: - Lesen

    func testDateiWirdGelesenUndZusammengefuegt() throws {
        let url = try datei("quelle.md", "# Aus der Datei\n")
        let ergebnis = try ClaudeAssetImport.lesen(url, bisher: mitKopf)
        XCTAssertTrue(ergebnis.contains("name: solve-task"))
        XCTAssertTrue(ergebnis.contains("# Aus der Datei"))
    }

    func testZuGrosseDateiWirdAbgelehnt() throws {
        let url = try datei("riesig.md",
                            String(repeating: "x", count: ClaudeAssetImport.maxBytes + 1))
        XCTAssertThrowsError(try ClaudeAssetImport.lesen(url, bisher: "")) { fehler in
            guard case .zuGross = fehler as? ClaudeAssetImport.Fehler ?? .keinText("") else {
                return XCTFail("falscher Fehler: \(fehler)")
            }
        }
    }

    func testBinaerdateiWirdAbgelehnt() throws {
        let url = ordner.appendingPathComponent("binaer.md")
        try Data([0xFF, 0xFE, 0x00, 0x01, 0xC3, 0x28]).write(to: url)
        XCTAssertThrowsError(try ClaudeAssetImport.lesen(url, bisher: "")) { fehler in
            XCTAssertEqual(fehler as? ClaudeAssetImport.Fehler, .keinText("binaer.md"))
        }
    }

    func testUmlauteUeberlebenDenWeg() throws {
        let url = try datei("umlaute.md", "# Grüße\n\nGebäude, Lösung, Straße\n")
        let ergebnis = try ClaudeAssetImport.lesen(url, bisher: "")
        XCTAssertTrue(ergebnis.contains("Gebäude, Lösung, Straße"))
    }
}
