import XCTest
@testable import KanbanCore

/// Die Reihenfolge des Backlogs auf dem Brett — Sperren und „als nächstes".
final class TicketOrderTests: XCTestCase {

    private func ticket(_ key: String, rank: Int?, done: Bool = false,
                        type: String = "Story", blockers: [BlockingRef] = []) -> Ticket {
        Ticket(key: key, summary: key,
               status: done ? "Erledigt" : "Zu erledigen",
               statusCategory: done ? "done" : "new",
               type: type, blockedBy: blockers, rankIndex: rank)
    }

    private func offen(_ key: String) -> BlockingRef {
        BlockingRef(key: key, summary: "", statusCategory: "new")
    }
    private func erledigt(_ key: String) -> BlockingRef {
        BlockingRef(key: key, summary: "", statusCategory: "done")
    }

    // MARK: Sperren

    func testErledigteSperrenZaehlenNicht() {
        let t = ticket("A-2", rank: 1, blockers: [erledigt("A-1"), offen("A-9")])
        XCTAssertEqual(TicketOrder.openBlockers(of: t).map(\.key), ["A-9"])
        XCTAssertTrue(TicketOrder.isBlocked(t))
    }

    func testOhneSperrenNichtBlockiert() {
        XCTAssertFalse(TicketOrder.isBlocked(ticket("A-1", rank: 0)))
    }

    /// Ein Blocker ohne Statusauskunft gilt als **offen**. Ihn stillschweigend fallen zu lassen
    /// wäre die gefährlichere Annahme: die Karte sähe frei aus, obwohl niemand das geprüft hat.
    func testUnbekannterStatusGiltAlsOffen() {
        let t = ticket("A-2", rank: 1, blockers: [BlockingRef(key: "A-1")])
        XCTAssertTrue(TicketOrder.isBlocked(t))
    }

    // MARK: Als nächstes

    func testNaechsteIstDieObersteFreie() {
        let liste = [
            ticket("A-1", rank: 0, done: true),                       // erledigt
            ticket("A-2", rank: 1, blockers: [offen("A-1")]),         // gesperrt
            ticket("A-3", rank: 2),                                   // ← die hier
            ticket("A-4", rank: 3)
        ]
        XCTAssertEqual(TicketOrder.nextUp(liste)?.key, "A-3")
    }

    /// Epics sind Behälter, keine Arbeit — sie dürfen nie als „als nächstes" vorgeschlagen werden,
    /// auch wenn sie im Rank ganz oben stehen (was sie regelmässig tun).
    func testEpicWirdUebersprungen() {
        let liste = [
            ticket("A-7", rank: 0, type: "Epic"),
            ticket("A-8", rank: 1)
        ]
        XCTAssertEqual(TicketOrder.nextUp(liste)?.key, "A-8")
    }

    /// Ohne Rank (freier Modus, lokale Tickets) gibt es keine Reihenfolge — dann lieber kein
    /// Vorschlag als ein geratener.
    func testOhneRankKeinVorschlag() {
        let liste = [ticket("A-1", rank: nil), ticket("A-2", rank: nil)]
        XCTAssertNil(TicketOrder.nextUp(liste))
    }

    func testAllesGesperrtErgibtKeinenVorschlag() {
        let liste = [ticket("A-2", rank: 0, blockers: [offen("A-1")])]
        XCTAssertNil(TicketOrder.nextUp(liste))
    }

    // MARK: Verschieben — welcher Anker

    /// Nach unten ziehen: der neue Vorgänger ist der Anker, eingehängt wird **dahinter**.
    func testNachUntenHaengtHinterDenNeuenVorgaenger() {
        let zug = TicketOrder.moveAnchor(keys: ["A", "B", "C", "D"], from: 0, to: 3)
        XCTAssertEqual(zug?.moved, "A")
        XCTAssertEqual(zug?.anchor, "C")
        XCTAssertEqual(zug?.before, false)
    }

    /// Nach oben ziehen — dasselbe Prinzip, solange es einen Vorgänger gibt.
    func testNachObenHaengtHinterDenNeuenVorgaenger() {
        let zug = TicketOrder.moveAnchor(keys: ["A", "B", "C", "D"], from: 3, to: 1)
        XCTAssertEqual(zug?.moved, "D")
        XCTAssertEqual(zug?.anchor, "A")
        XCTAssertEqual(zug?.before, false)
    }

    /// Ganz nach oben: es gibt keinen Vorgänger, also **vor** den bisherigen Ersten.
    func testGanzNachObenHaengtVorDenErsten() {
        let zug = TicketOrder.moveAnchor(keys: ["A", "B", "C"], from: 2, to: 0)
        XCTAssertEqual(zug?.moved, "C")
        XCTAssertEqual(zug?.anchor, "A")
        XCTAssertEqual(zug?.before, true)
    }

    /// SwiftUIs `onMove` zählt das Ziel **vor** dem Entfernen. Ohne die Korrektur landete jede
    /// Abwärtsbewegung eine Position zu weit oben — `to: 2` aus Position 0 heisst „zwischen B und
    /// C", der Anker ist also B, nicht A.
    func testZielIndexWirdUmDasEntfernenKorrigiert() {
        let zug = TicketOrder.moveAnchor(keys: ["A", "B", "C", "D"], from: 0, to: 2)
        XCTAssertEqual(zug?.anchor, "B")
        XCTAssertEqual(zug?.before, false)
    }

    /// Ein Zug, der nichts ändert, schreibt auch nichts — sonst ginge bei jedem Antippen eine
    /// Schreibanfrage an Jira.
    func testZugOhneWirkungErgibtNil() {
        XCTAssertNil(TicketOrder.moveAnchor(keys: ["A", "B", "C"], from: 1, to: 1))
        XCTAssertNil(TicketOrder.moveAnchor(keys: ["A", "B", "C"], from: 1, to: 2))
        XCTAssertNil(TicketOrder.moveAnchor(keys: ["A"], from: 0, to: 0))
    }

    /// Die Zählweise, auf die sich die ⌘↑/⌘↓-Knöpfe verlassen: **eine** Position nach unten heisst
    /// `to: index + 2` (weil `onMove` vor dem Entfernen zählt), eine nach oben schlicht `index - 1`.
    /// Ohne diesen Test wäre die Arithmetik der Knöpfe eine Behauptung im View-Code.
    func testEinzelschritteTreffenDenNachbarn() {
        let keys = ["A", "B", "C", "D"]
        // B eins nach unten → hinter C
        let runter = TicketOrder.moveAnchor(keys: keys, from: 1, to: 3)
        XCTAssertEqual(runter?.moved, "B")
        XCTAssertEqual(runter?.anchor, "C")
        XCTAssertEqual(runter?.before, false)
        // C eins nach oben → hinter A
        let hoch = TicketOrder.moveAnchor(keys: keys, from: 2, to: 1)
        XCTAssertEqual(hoch?.moved, "C")
        XCTAssertEqual(hoch?.anchor, "A")
        XCTAssertEqual(hoch?.before, false)
        // Der Erste eins nach oben gibt es nicht — der Knopf ist dort aus.
        XCTAssertNil(TicketOrder.moveAnchor(keys: keys, from: 0, to: -1))
    }

    /// Ein Zielindex ausserhalb der Liste darf nicht abstürzen — gefunden, weil der Test oben
    /// genau das tat („Negative Array index is out of range").
    func testZielIndexAusserhalbStuerztNichtAb() {
        let keys = ["A", "B", "C"]
        XCTAssertNil(TicketOrder.moveAnchor(keys: keys, from: 0, to: -5))
        XCTAssertNotNil(TicketOrder.moveAnchor(keys: keys, from: 0, to: 99))
        XCTAssertNil(TicketOrder.moveAnchor(keys: keys, from: 7, to: 1))
    }

    // MARK: Verstösse

    /// Gemeldet wird nur, woran **gearbeitet** wird. Ein gesperrtes Ticket, das ruhig im Backlog
    /// liegt, ist der Normalfall und keine Meldung wert.
    func testNurAngefangeneGesperrteSindVerstoesse() {
        let gesperrt = [offen("A-1")]
        let cards: [(ticket: Ticket, column: KanbanColumn)] = [
            (ticket("A-2", rank: 1, blockers: gesperrt), .sprint),          // wartet — in Ordnung
            (ticket("A-3", rank: 2, blockers: gesperrt), .offen),           // wartet — in Ordnung
            (ticket("A-4", rank: 3, blockers: gesperrt), .inBearbeitung),   // ← Verstoss
            (ticket("A-5", rank: 4, blockers: gesperrt), .review),          // ← Verstoss
            (ticket("A-6", rank: 5), .inBearbeitung)                        // frei — in Ordnung
        ]
        XCTAssertEqual(TicketOrder.violations(cards).map(\.key), ["A-4", "A-5"])
    }
}
