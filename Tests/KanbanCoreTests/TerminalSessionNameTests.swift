import XCTest
@testable import KanbanCore

/// tmux-Sitzungsnamen über Profilgrenzen.
///
/// Zwei Profile mit demselben Ticket-Präfix griffen sonst auf dieselbe Sitzung zu — `kanban-EVEN-1`
/// ist in beiden Welten derselbe Name.
final class TerminalSessionNameTests: XCTestCase {
    override func tearDown() {
        TerminalSessionResolver.profileSlug = nil
        super.tearDown()
    }

    /// Das Vorgabe-Profil behält seine gewohnten Namen — und zwar **immer**, nicht nur solange es
    /// allein ist. Hinge die Regel an der Anzahl der Profile, änderte das Anlegen eines zweiten die
    /// Namen des ersten und liesse jede laufende Sitzung verwaisen.
    func testDasVorgabeProfilBehaeltSeineNamen() {
        TerminalSessionResolver.profileSlug = nil
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "even-1"), "kanban-EVEN-1")
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "EVEN-1", suffix: "wt"),
                       "kanban-EVEN-1-wt")
    }

    func testJedesAndereProfilTraegtSeinenSlug() {
        TerminalSessionResolver.profileSlug = "privat"
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "EVEN-1"),
                       "kanban-privat-EVEN-1")
    }

    /// Alle vier Formen gehen durch dieselbe Stelle — der Namensraum wird nicht an vier Orten
    /// nachgebaut.
    func testDerSlugGiltFuerJedeNebensitzung() {
        TerminalSessionResolver.profileSlug = "privat"
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "EVEN-1", suffix: "wt"),
                       "kanban-privat-EVEN-1-wt")
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "kanban", suffix: "new"),
                       "kanban-privat-KANBAN-new")
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "EVEN-1", suffix: "term-a1b2"),
                       "kanban-privat-EVEN-1-term-a1b2")
    }

    /// Zwei Profile, dasselbe Ticket: verschiedene Sitzungen. Das ist der ganze Punkt.
    func testZweiProfileKollidierenNicht() {
        TerminalSessionResolver.profileSlug = nil
        let arbeit = TerminalSessionResolver.sessionName(forTicket: "EVEN-1")
        TerminalSessionResolver.profileSlug = "privat"
        let privat = TerminalSessionResolver.sessionName(forTicket: "EVEN-1")
        XCTAssertNotEqual(arbeit, privat)
    }

    /// Ein leerer Slug ist kein Slug — sonst entstünde `kanban--EVEN-1`.
    func testLeererSlugFaelltAufDenVorgabeNamenZurueck() {
        TerminalSessionResolver.profileSlug = ""
        XCTAssertEqual(TerminalSessionResolver.sessionName(forTicket: "EVEN-1"), "kanban-EVEN-1")
    }
}
