import XCTest
@testable import KanbanCore

/// Seit im Anlege-Formular ein Schalter je Modul entscheidet, ob es den Block gibt, kann ein
/// eingeschalteter Block leer bleiben. Genau der darf nicht in die Config.
final class ProjectRecordStrippingTests: XCTestCase {

    private var basis: ProjectRecord {
        ProjectRecord(prefix: "EVEN", tasksPath: "/tmp/tasks/even")
    }

    /// Ein GitLab-Eintrag mit leerem Pfad wäre später eine Abfrage gegen das Projekt „" — er muss
    /// weg, nicht mitgeschrieben.
    func testLeererGitlabPfadFliegtRaus() {
        var record = basis
        record.gitlab = .init(path: "")
        XCTAssertNil(record.strippingEmptyModules().gitlab)

        record.gitlab = .init(path: "   ")
        XCTAssertNil(record.strippingEmptyModules().gitlab, "nur Leerzeichen ist auch leer")
    }

    func testGefuellterGitlabPfadBleibt() {
        var record = basis
        record.gitlab = .init(path: "applications/even")
        XCTAssertEqual(record.strippingEmptyModules().gitlab?.path, "applications/even")
    }

    func testLeereBloeckeFliegenRaus() {
        var record = basis
        record.confluence = .init()
        record.vertec = .init()
        record.dockerhub = .init()
        record.jenkins = .init(jobs: [])

        let sauber = record.strippingEmptyModules()
        XCTAssertNil(sauber.confluence)
        XCTAssertNil(sauber.vertec)
        XCTAssertNil(sauber.dockerhub)
        XCTAssertNil(sauber.jenkins)
    }

    /// Ein einziges ausgefülltes Feld hält den Block — halb ausgefüllt ist gewollt (ein Confluence
    /// mit Space, aber ohne eigenen Pfad, ist der Normalfall).
    func testTeilweiseGefuellterBlockBleibt() {
        var record = basis
        record.confluence = .init(space: "EVEN")
        record.vertec = .init(project: nil, phase: "WEITERENTWICKLUNGEN 2026")

        let sauber = record.strippingEmptyModules()
        XCTAssertEqual(sauber.confluence?.space, "EVEN")
        XCTAssertNil(sauber.confluence?.path)
        XCTAssertEqual(sauber.vertec?.phase, "WEITERENTWICKLUNGEN 2026")
    }

    /// Die Grunddaten fasst das Aufräumen nicht an — nur Modulblöcke.
    func testGrunddatenBleibenUnberuehrt() {
        var record = basis
        record.repoDir = "even"
        record.usesJira = false

        let sauber = record.strippingEmptyModules()
        XCTAssertEqual(sauber.prefix, "EVEN")
        XCTAssertEqual(sauber.tasksPath, "/tmp/tasks/even")
        XCTAssertEqual(sauber.repoDir, "even")
        XCTAssertEqual(sauber.usesJira, false)
    }

    /// Der Anlegen-Knopf hängt daran: ein Entwurf, von dem nach dem Aufräumen nichts übrig ist,
    /// darf kein Projekt erzeugen.
    func testNurLeereBloeckeErgebenKeinProjekt() {
        var record = ProjectRecord()
        record.confluence = .init()
        record.jenkins = .init(jobs: [])
        XCTAssertFalse(record.isEmpty, "ungeputzt sieht der Entwurf gefüllt aus")
        XCTAssertTrue(record.strippingEmptyModules().isEmpty)
    }

    /// Was durchs Aufräumen ging, darf auch beim Schreiben keinen leeren Eintrag hinterlassen.
    func testGeputzterRecordSchreibtKeinenLeerenBlock() {
        var record = basis
        record.confluence = .init()
        record.gitlab = .init(path: "")

        let config = ProjectProjection.apply(record.strippingEmptyModules(), key: "even",
                                             to: .object([:]))
        XCTAssertNil(config.value(at: ["modules", "confluence", "projects", "even"]))
        XCTAssertNil(config.value(at: ["modules", "gitlab", "projects", "even"]))
        XCTAssertNotNil(config.value(at: ["modules", "jira", "projects", "even"]))
    }
}
