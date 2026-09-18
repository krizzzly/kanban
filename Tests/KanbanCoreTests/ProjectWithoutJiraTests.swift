import XCTest
@testable import KanbanCore

/// Ein Projekt **ohne Jira-Anbindung**: Ticket-Präfix und Task-Files bleiben, Board und Sprints
/// fallen weg. Der Unterschied zu „Projekt ohne Präfix" ist der Kern dieser Tests.
final class ProjectWithoutJiraTests: XCTestCase {

    private func projekte(_ json: String) throws -> [ProjectConfig] {
        try KanbanConfig.resolve(Data(json.utf8), docsRoot: "/tmp/docs").projects
    }

    /// Ohne den Schlüssel bleibt alles, wie es war — jede bestehende Config ist ein Jira-Projekt.
    func testFehlenderSchluesselBedeutetMitJira() throws {
        let projects = try projekte("""
            { "modules": { "jira": { "projects": {
                "even": { "prefix": "EVEN", "tasksPath": "/tmp/tasks/even" } } } } }
            """)
        XCTAssertEqual(projects.count, 1)
        XCTAssertTrue(projects[0].usesJira)
    }

    func testAusgeschalteteAnbindungWirdGelesen() throws {
        let projects = try projekte("""
            { "modules": { "jira": { "projects": {
                "intern": { "prefix": "INT", "tasksPath": "/tmp/tasks/intern",
                            "useJira": false } } } } }
            """)
        XCTAssertEqual(projects.count, 1)
        XCTAssertFalse(projects[0].usesJira)
        // Das Entscheidende: der Präfix bleibt, sonst fände das Board keine Task-Files.
        XCTAssertEqual(projects[0].prefix, "INT")
        XCTAssertEqual(projects[0].tasksPathAbsolute, "/tmp/tasks/intern")
    }

    /// `useJira: true` ausdrücklich hinzuschreiben ist erlaubt und ändert nichts.
    func testAusdruecklichesTrue() throws {
        let projects = try projekte("""
            { "modules": { "jira": { "projects": {
                "even": { "prefix": "EVEN", "tasksPath": "/t", "useJira": true } } } } }
            """)
        XCTAssertTrue(projects[0].usesJira)
    }

    // MARK: - Schreiben

    /// Der Normalfall schreibt den Schlüssel **nicht**: er stünde sonst in jedem Projekt herum und
    /// wiederholte nur die Vorgabe.
    func testVorgabeWirdNichtGeschrieben() {
        let record = ProjectRecord(prefix: "EVEN", tasksPath: "/tmp/tasks/even")
        let config = ProjectProjection.apply(record, key: "even", to: .object([:]))
        let eintrag = config.value(at: ["modules", "jira", "projects", "even"])?.objectValue
        XCTAssertEqual(eintrag?["prefix"]?.stringValue, "EVEN")
        XCTAssertNil(eintrag?["useJira"])
    }

    func testAbschaltungWirdGeschrieben() {
        var record = ProjectRecord(prefix: "INT", tasksPath: "/tmp/tasks/intern")
        record.usesJira = false
        let config = ProjectProjection.apply(record, key: "intern", to: .object([:]))
        let eintrag = config.value(at: ["modules", "jira", "projects", "intern"])?.objectValue
        XCTAssertEqual(eintrag?["useJira"]?.boolValue, false)
        XCTAssertEqual(eintrag?["prefix"]?.stringValue, "INT")
    }

    /// Hin und zurück: was geschrieben wurde, muss die Registry wieder einlesen — sonst stünde der
    /// Schalter nach dem nächsten Öffnen der Einstellungen wieder auf „an".
    func testRundlauf() {
        var record = ProjectRecord(prefix: "INT", tasksPath: "/tmp/tasks/intern")
        record.usesJira = false
        let config = ProjectProjection.apply(record, key: "intern", to: .object([:]))
        let registry = ProjectProjection.importing(from: config)
        XCTAssertEqual(registry["intern"]?.usesJira, false)
        XCTAssertEqual(registry["intern"]?.prefix, "INT")
    }

    /// Wird die Anbindung wieder eingeschaltet, muss der Schlüssel **verschwinden** — bliebe er als
    /// `false` stehen, wäre das Projekt weiterhin abgeschaltet, während der Schalter „an" zeigt.
    func testWiederEinschaltenEntferntDenSchluessel() {
        var aus = ProjectRecord(prefix: "INT", tasksPath: "/t")
        aus.usesJira = false
        var config = ProjectProjection.apply(aus, key: "intern", to: .object([:]))
        XCTAssertEqual(config.value(at: ["modules", "jira", "projects", "intern", "useJira"])?.boolValue,
                       false)

        var an = ProjectRecord(prefix: "INT", tasksPath: "/t")
        an.usesJira = nil
        config = ProjectProjection.apply(an, key: "intern", to: config)
        XCTAssertNil(config.value(at: ["modules", "jira", "projects", "intern", "useJira"]))
    }

    // MARK: - Schema

    func testSchalterStehtInDerJiraSektion() {
        let jira = KanbanConfigSchema.sections.first { $0.id == "jira" }
        let feld = jira?.projectMap?.fields.first { $0.key == "useJira" }
        XCTAssertNotNil(feld, "ohne Feld im Schema gibt es den Schalter in den Einstellungen nicht")
        XCTAssertFalse(feld?.required ?? true)
        guard case .bool(let defaultOn)? = feld?.kind else {
            return XCTFail("useJira sollte ein Schalter sein")
        }
        XCTAssertTrue(defaultOn, "ohne Eintrag muss ein Projekt an Jira hängen")
    }
}
