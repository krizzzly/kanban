import XCTest
@testable import KanbanCore

/// Die von Hand gelegte Reihenfolge für Projekte ohne Jira.
final class LocalOrderTests: XCTestCase {

    // MARK: Einsortieren

    func testGemerkteReihenfolgeGewinnt() {
        let keys = ["C", "A", "B"]                     // so kommen sie vom Board herein
        XCTAssertEqual(LocalOrder.arrange(keys, stored: ["A", "B", "C"]), ["A", "B", "C"])
    }

    /// Ein neues Ticket rutscht **nie** ungefragt nach vorn — wer es vorn haben will, zieht es
    /// dorthin. Sonst stünde nach jedem `create-task` etwas Unfertiges an erster Stelle.
    func testNeueHaengenHintenAn() {
        XCTAssertEqual(LocalOrder.arrange(["A", "B", "NEU"], stored: ["B", "A"]),
                       ["B", "A", "NEU"])
    }

    /// Mehrere neue behalten die Reihenfolge, in der sie hereinkamen.
    func testMehrereNeueBehaltenIhreReihenfolge() {
        XCTAssertEqual(LocalOrder.arrange(["X", "A", "Y"], stored: ["A"]), ["A", "X", "Y"])
    }

    /// Verschwundene Tickets fallen aus der Anzeige — im Speicher dürfen sie stehen bleiben, ein
    /// Task-File kann kurz weg sein, während ein Worktree umzieht.
    func testVerschwundeneFallenWeg() {
        XCTAssertEqual(LocalOrder.arrange(["A", "C"], stored: ["A", "B", "C"]), ["A", "C"])
    }

    func testOhneGemerktesBleibtDieEingangsreihenfolge() {
        XCTAssertEqual(LocalOrder.arrange(["B", "A"], stored: []), ["B", "A"])
    }

    // MARK: Ziehen

    func testZugNachUnten() {
        XCTAssertEqual(LocalOrder.moved(["A", "B", "C"], from: 0, to: 2), ["B", "A", "C"])
    }

    func testZugNachOben() {
        XCTAssertEqual(LocalOrder.moved(["A", "B", "C"], from: 2, to: 0), ["C", "A", "B"])
    }

    /// Ein Zug ohne Wirkung schreibt nichts — sonst ginge bei jedem Antippen eine Datei raus.
    func testZugOhneWirkungErgibtNil() {
        XCTAssertNil(LocalOrder.moved(["A", "B", "C"], from: 1, to: 1))
        XCTAssertNil(LocalOrder.moved(["A", "B", "C"], from: 1, to: 2))
        XCTAssertNil(LocalOrder.moved(["A"], from: 0, to: 0))
    }

    /// Kein Absturz bei unmöglichen Indizes — dieselbe Lehre wie bei `TicketOrder.moveAnchor`.
    func testUnmoeglicheIndizesStuerzenNichtAb() {
        XCTAssertNil(LocalOrder.moved(["A", "B"], from: 0, to: -9))
        XCTAssertNotNil(LocalOrder.moved(["A", "B"], from: 0, to: 99))
        XCTAssertNil(LocalOrder.moved(["A", "B"], from: 5, to: 0))
    }

    // MARK: Speicher

    func testSpeicherHaeltJeProjektGetrennt() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("order-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = LocalOrderStore(fileURL: tmp)
        store.setOrder(["A", "B"], forProject: "eins")
        store.setOrder(["X"], forProject: "zwei")

        XCTAssertEqual(store.order(forProject: "eins"), ["A", "B"])
        XCTAssertEqual(store.order(forProject: "zwei"), ["X"])
        XCTAssertEqual(store.order(forProject: "gibtsnicht"), [])
        // Neu gelesen: die Reihenfolge überlebt den Neustart.
        XCTAssertEqual(LocalOrderStore(fileURL: tmp).order(forProject: "eins"), ["A", "B"])
    }

    /// Eine kaputte Datei darf nicht abstürzen — dann ist die Reihenfolge eben leer.
    func testKaputteDateiErgibtLeereReihenfolge() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("order-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "kein json".write(to: tmp, atomically: true, encoding: .utf8)
        XCTAssertEqual(LocalOrderStore(fileURL: tmp).order(forProject: "eins"), [])
    }
}
