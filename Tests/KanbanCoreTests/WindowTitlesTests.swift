import XCTest
@testable import KanbanCore

/// Die Namen der Board-Fenster im Fenster-Menü. Ohne sie stehen mehrere Boards dort namenlos
/// nebeneinander — genau der Zustand, den KANBAN-006 hinterliess.
final class WindowTitlesTests: XCTestCase {

    func testJedesFensterTraegtSeinenProjektKeyInGrossbuchstaben() {
        XCTAssertEqual(WindowTitles.titel(fuer: ["even", "zba", "kanban"]),
                       ["EVEN", "ZBA", "KANBAN"])
    }

    /// Dasselbe Projekt darf zweimal offen stehen (das Projekt-Menü schaltet **im** Fenster um).
    /// Zwei gleiche Einträge im Menü wären nicht auseinanderzuhalten.
    func testZweitesFensterDesselbenProjektsBekommtEineNummer() {
        XCTAssertEqual(WindowTitles.titel(fuer: ["even", "zba", "even", "even"]),
                       ["EVEN", "ZBA", "EVEN (2)", "EVEN (3)"])
    }

    /// Eine „(1)" am einzigen Fenster eines Projekts behauptete ein zweites, das es nicht gibt.
    func testDasErsteBleibtOhneNummer() {
        XCTAssertEqual(WindowTitles.titel(fuer: ["even"]), ["EVEN"])
    }

    /// Geht das nummerierte Fenster zu, heisst das übrige wieder schlicht `EVEN` — gezählt wird
    /// über die ganze Liste, nicht einmalig je Fenster.
    func testNachDemSchliessenFaelltDieNummerWeg() {
        XCTAssertEqual(WindowTitles.titel(fuer: ["even", "even"]), ["EVEN", "EVEN (2)"])
        XCTAssertEqual(WindowTitles.titel(fuer: ["even"]), ["EVEN"])
    }

    /// Erststart, Setup-Schirm, Projekt aus der Config verschwunden: das Fenster steht trotzdem im
    /// Menü und braucht einen Namen.
    func testFensterOhneProjektHeisstKanban() {
        XCTAssertEqual(WindowTitles.titel(fuer: [nil, "even", "   "]),
                       ["Kanban", "EVEN", "Kanban"])
    }

    /// Fenster ohne Projekt zählen nicht mit: zwei davon sind beide „Kanban", nicht „Kanban (2)" —
    /// nummeriert wird ein Projekt, das zweimal dasteht, und keins ist hier keins.
    func testFensterOhneProjektWerdenNichtNummeriert() {
        XCTAssertEqual(WindowTitles.titel(fuer: [nil, nil]), ["Kanban", "Kanban"])
    }

    func testLeereListe() {
        XCTAssertEqual(WindowTitles.titel(fuer: []), [])
    }
}
