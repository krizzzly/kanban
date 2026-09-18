import XCTest
@testable import KanbanCore

final class TicketFilterTests: XCTestCase {
    /// Eine echte Karte aus dem CORE-Board.
    private func passt(_ query: String) -> Bool {
        TicketFilter.matches(key: "CORETEST-4237",
                             summary: "Adapt BAZG refund quantity import",
                             query: query)
    }

    /// Der eigentliche Fall: die Nummer tippen, ohne den Präfix zu kennen.
    func testFindetUeberDieBlosseNummer() {
        XCTAssertTrue(passt("4237"))
        XCTAssertTrue(passt("CORETEST-4237"))
        XCTAssertTrue(passt("coretest-4237"))
    }

    func testFindetUeberDenTitel() {
        XCTAssertTrue(passt("refund"))
        XCTAssertTrue(passt("REFUND"))
        XCTAssertTrue(passt("quantity import"))
    }

    /// Nummer und Titelwort stehen im Text weit auseinander — ein einzelner Teilstring über
    /// „Key + Titel" fände das nicht, das Und über die Begriffe schon.
    func testBegriffeDuerfenAusBeidenFeldernKommen() {
        XCTAssertTrue(passt("4237 refund"))
        XCTAssertTrue(passt("refund 4237"))
    }

    /// Und heisst Und: ein Begriff daneben reicht zum Ausschluss.
    func testAlleBegriffeMuessenPassen() {
        XCTAssertFalse(passt("4237 keycloak"))
        XCTAssertFalse(passt("4238"))
        XCTAssertFalse(passt("noga"))
    }

    /// Kein Filter ist kein Filter — sonst stünde das Board beim Leeren des Feldes leer da.
    func testLeereEingabePasstImmer() {
        XCTAssertTrue(passt(""))
        XCTAssertTrue(passt("   "))
    }

    /// Im freien Modus gibt es Tickets ohne Nummer (nur ein Branch als Titel).
    func testTicketOhneKey() {
        XCTAssertTrue(TicketFilter.matches(key: "", summary: "playwright frontend testing",
                                           query: "playwright"))
        XCTAssertFalse(TicketFilter.matches(key: "", summary: "playwright frontend testing",
                                            query: "4237"))
    }
}
