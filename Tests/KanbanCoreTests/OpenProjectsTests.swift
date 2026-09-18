import XCTest
@testable import KanbanCore

/// Die gemerkten Fenster: aus **einem** Projekt-Key („das Projekt beim letzten Beenden") ist eine
/// Liste geworden, seit jedes Projekt sein eigenes Fenster hat. Der alte Wert muss weiter gelten —
/// niemand soll seine Auswahl verlieren, nur weil das Format gewachsen ist.
final class OpenProjectsTests: XCTestCase {

    private let vorhanden = ["even", "zba", "bfezvm", "kanban"]

    // MARK: - Migration

    func testAlterEinzelwertWirdZurEinelementigenListe() {
        XCTAssertEqual(OpenProjects.wiederherstellen(gespeichert: nil, zuletzt: "zba",
                                                     vorhanden: vorhanden),
                       ["zba"])
    }

    func testOhneAllesDasErsteProjekt() {
        XCTAssertEqual(OpenProjects.wiederherstellen(gespeichert: nil, zuletzt: nil,
                                                     vorhanden: vorhanden),
                       ["even"])
    }

    /// Eine **leere** gespeicherte Liste ist nicht „nie geschrieben": sie entsteht, wenn jemand alle
    /// Fenster zumacht (und die App sich damit beendet). Dann geht das zuletzt benutzte Projekt auf.
    func testLeereListeFaelltAufDasZuletztBenutzteZurueck() {
        XCTAssertEqual(OpenProjects.wiederherstellen(gespeichert: [], zuletzt: "bfezvm",
                                                     vorhanden: vorhanden),
                       ["bfezvm"])
    }

    func testGespeicherteListeGewinntUeberDenEinzelwert() {
        XCTAssertEqual(OpenProjects.wiederherstellen(gespeichert: ["zba", "kanban"], zuletzt: "even",
                                                     vorhanden: vorhanden),
                       ["zba", "kanban"])
    }

    // MARK: - Was nicht mehr gilt

    func testProjektAusDerConfigEntferntOeffnetKeinFenster() {
        XCTAssertEqual(OpenProjects.wiederherstellen(gespeichert: ["zba", "weg"], zuletzt: nil,
                                                     vorhanden: vorhanden),
                       ["zba"])
    }

    /// Bleibt nach dem Sieben nichts übrig, startet Kanban trotzdem mit einem Board.
    func testNurUnbekannteKeysGebenDasErsteProjekt() {
        XCTAssertEqual(OpenProjects.wiederherstellen(gespeichert: ["weg", "auch-weg"], zuletzt: "fort",
                                                     vorhanden: vorhanden),
                       ["even"])
    }

    func testOhneProjekteBleibtDieListeLeer() {
        XCTAssertTrue(OpenProjects.wiederherstellen(gespeichert: ["even"], zuletzt: "even",
                                                    vorhanden: []).isEmpty)
    }

    func testDoppelteStehenNurEinmalDrin() {
        XCTAssertEqual(OpenProjects.wiederherstellen(gespeichert: ["zba", "even", "zba"], zuletzt: nil,
                                                     vorhanden: vorhanden),
                       ["zba", "even"])
    }

    func testMehrAlsDasMaximumWirdGedeckelt() {
        let viele = (1...10).map { "p\($0)" }
        let liste = OpenProjects.wiederherstellen(gespeichert: viele, zuletzt: nil, vorhanden: viele)
        XCTAssertEqual(liste.count, OpenProjects.maximum)
        XCTAssertEqual(liste.first, "p1")
    }
}

/// Welches Fenster ein Ticket meint — die Regel hinter Deep-Link und Benachrichtigungs-Klick.
final class TicketRoutingTests: XCTestCase {

    private func projekt(_ key: String, _ prefix: String) -> ProjectConfig {
        ProjectConfig(key: key, prefix: prefix, jiraBaseUrl: "https://example.atlassian.net",
                      tasksPathAbsolute: "/tmp/\(key)", repoDir: "/tmp/repo/\(key)",
                      forge: nil)
    }

    private lazy var projekte = [projekt("even", "EVEN"), projekt("bfezvm", "BFEZVM"),
                                 projekt("tp1", "TP1"), projekt("support", "SUPPORT")]

    func testFindetDasProjektZumPraefix() {
        XCTAssertEqual(TicketRouting.projekt(fuerTicket: "BFEZVM-4259", in: projekte)?.key, "bfezvm")
    }

    func testKleinschreibungIstEgal() {
        XCTAssertEqual(TicketRouting.projekt(fuerTicket: "even-3687", in: projekte)?.key, "even")
    }

    /// Ohne den Trennstrich zöge `EVEN` die Tickets von `EVENT` an sich.
    func testDerTrennstrichGehoertZurPruefung() {
        let mit = projekte + [projekt("event", "EVENT")]
        XCTAssertEqual(TicketRouting.projekt(fuerTicket: "EVENT-1", in: mit)?.key, "event")
        XCTAssertNil(TicketRouting.projekt(fuerTicket: "EVENTUELL", in: mit))
    }

    /// Karten ohne Ticketnummer gehören zum Repo, nicht zu einem Präfix.
    func testKarteOhneNummerGehoertZuKeinemProjekt() {
        XCTAssertNil(TicketRouting.projekt(fuerTicket: "!130", in: projekte))
    }

    func testUnbekannterPraefixGibtNil() {
        XCTAssertNil(TicketRouting.projekt(fuerTicket: "FREMD-1", in: projekte))
    }
}
