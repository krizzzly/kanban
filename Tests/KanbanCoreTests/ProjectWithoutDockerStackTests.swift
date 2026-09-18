import XCTest
@testable import KanbanCore

/// Ein Projekt **ohne Docker-Stack**: Worktrees, Branches und Task-Files bleiben, die Docker-Hälfte
/// fällt weg. Gebaut nach dem Vorbild von `ProjectWithoutJiraTests` — dasselbe Muster, weil es
/// dieselbe Art Schalter ist (nur die Abschaltung steht in der Config).
final class ProjectWithoutDockerStackTests: XCTestCase {

    private func projekte(_ json: String) throws -> [ProjectConfig] {
        try KanbanConfig.resolve(Data(json.utf8), docsRoot: "/tmp/docs").projects
    }

    // MARK: - Lesen

    /// Der Rückwärtskompatibilitäts-Test: jede bestehende Config kennt den Schlüssel nicht.
    func testFehlenderSchluesselBedeutetMitStack() throws {
        let projects = try projekte("""
            { "modules": { "jira": { "projects": {
                "even": { "prefix": "EVEN", "tasksPath": "/tmp/tasks/even" } } } } }
            """)
        XCTAssertEqual(projects.count, 1)
        XCTAssertTrue(projects[0].usesDockerStack)
    }

    func testAbgeschalteterStackWirdGelesen() throws {
        let projects = try projekte("""
            { "modules": { "jira": { "projects": {
                "kanban": { "prefix": "KANBAN", "tasksPath": "/tmp/tasks/kanban",
                            "dockerStack": false } } } } }
            """)
        XCTAssertEqual(projects.count, 1)
        XCTAssertFalse(projects[0].usesDockerStack)
        // Alles andere bleibt: ohne Präfix und Tasks-Pfad wäre das Projekt für Kanban unsichtbar.
        XCTAssertEqual(projects[0].prefix, "KANBAN")
        XCTAssertEqual(projects[0].tasksPathAbsolute, "/tmp/tasks/kanban")
    }

    /// `dockerStack: true` ausdrücklich hinzuschreiben ist erlaubt und ändert nichts.
    func testAusdruecklichesTrue() throws {
        let projects = try projekte("""
            { "modules": { "jira": { "projects": {
                "even": { "prefix": "EVEN", "tasksPath": "/t", "dockerStack": true } } } } }
            """)
        XCTAssertTrue(projects[0].usesDockerStack)
    }

    /// Die beiden Schalter sind unabhängig: ein Projekt ohne Jira kann sehr wohl einen Stack haben
    /// (und umgekehrt).
    func testBeideSchalterSindUnabhaengig() throws {
        let projects = try projekte("""
            { "modules": { "jira": { "projects": {
                "intern": { "prefix": "INT", "tasksPath": "/t", "useJira": false } } } } }
            """)
        XCTAssertFalse(projects[0].usesJira)
        XCTAssertTrue(projects[0].usesDockerStack)
    }

    // MARK: - Schreiben

    /// Der Normalfall schreibt den Schlüssel **nicht** — er stünde sonst in jedem Projekt herum.
    func testVorgabeWirdNichtGeschrieben() {
        let record = ProjectRecord(prefix: "EVEN", tasksPath: "/tmp/tasks/even")
        let config = ProjectProjection.apply(record, key: "even", to: .object([:]))
        let eintrag = config.value(at: ["modules", "jira", "projects", "even"])?.objectValue
        XCTAssertEqual(eintrag?["prefix"]?.stringValue, "EVEN")
        XCTAssertNil(eintrag?["dockerStack"])
    }

    func testAbschaltungWirdGeschrieben() {
        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/tmp/tasks/kanban")
        record.usesDockerStack = false
        let config = ProjectProjection.apply(record, key: "kanban", to: .object([:]))
        let eintrag = config.value(at: ["modules", "jira", "projects", "kanban"])?.objectValue
        XCTAssertEqual(eintrag?["dockerStack"]?.boolValue, false)
        XCTAssertEqual(eintrag?["prefix"]?.stringValue, "KANBAN")
    }

    /// Hin und zurück: was geschrieben wurde, muss die Registry wieder einlesen — sonst stünde der
    /// Schalter nach dem nächsten Öffnen der Einstellungen wieder auf „an".
    func testRundlauf() {
        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/tmp/tasks/kanban")
        record.usesDockerStack = false
        let config = ProjectProjection.apply(record, key: "kanban", to: .object([:]))
        let registry = ProjectProjection.importing(from: config)
        XCTAssertEqual(registry["kanban"]?.usesDockerStack, false)
        XCTAssertEqual(registry["kanban"]?.prefix, "KANBAN")
    }

    /// Wird der Stack wieder eingeschaltet, muss der Schlüssel **verschwinden** — bliebe er als
    /// `false` stehen, wäre das Projekt weiterhin abgeschaltet, während der Schalter „an" zeigt.
    func testWiederEinschaltenEntferntDenSchluessel() {
        var aus = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        aus.usesDockerStack = false
        var config = ProjectProjection.apply(aus, key: "kanban", to: .object([:]))
        XCTAssertEqual(
            config.value(at: ["modules", "jira", "projects", "kanban", "dockerStack"])?.boolValue,
            false)

        var an = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        an.usesDockerStack = nil
        config = ProjectProjection.apply(an, key: "kanban", to: config)
        XCTAssertNil(config.value(at: ["modules", "jira", "projects", "kanban", "dockerStack"]))
    }

    /// Die Projektion ist additiv: ein Schlüssel, den nur Hermes kennt, überlebt das Schreiben.
    /// (Ein Hermes ohne `dockerStack` darf von dem Schalter nichts merken — und umgekehrt.)
    func testFremderSchluesselImSelbenEintragBleibt() {
        var config = JSONValue.object([:])
        config.set(.object(["prefix": .string("KANBAN"),
                            "tasksPath": .string("/t"),
                            "irgendwasVonHermes": .string("bleibt")]),
                   at: ["modules", "jira", "projects", "kanban"])

        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        record.usesDockerStack = false
        config = ProjectProjection.apply(record, key: "kanban", to: config)

        let eintrag = config.value(at: ["modules", "jira", "projects", "kanban"])?.objectValue
        XCTAssertEqual(eintrag?["irgendwasVonHermes"]?.stringValue, "bleibt")
        XCTAssertEqual(eintrag?["dockerStack"]?.boolValue, false)
    }

    // MARK: - Schema

    func testSchalterStehtInDerJiraSektion() {
        let jira = KanbanConfigSchema.sections.first { $0.id == "jira" }
        let feld = jira?.projectMap?.fields.first { $0.key == "dockerStack" }
        XCTAssertNotNil(feld, "ohne Feld im Schema gibt es den Schalter in den Einstellungen nicht")
        XCTAssertFalse(feld?.required ?? true)
        guard case .bool(let defaultOn)? = feld?.kind else {
            return XCTFail("dockerStack sollte ein Schalter sein")
        }
        XCTAssertTrue(defaultOn, "ohne Eintrag muss ein Projekt einen Stack haben")
    }

    // MARK: - Vorschlag beim Anlegen

    /// Liegt eine `.iwf.yml` im vorgeschlagenen Repo-Ordner, schlägt der Editor „mit Stack" vor —
    /// und schreibt den Schlüssel dann gar nicht.
    func testVorschlagMitIwfYml() {
        var config = JSONValue.object([:])
        config.set(.string("/basis"), at: ["basePath"])
        let record = ProjectSuggestion.record(for: "neu", from: config,
                                              fileExists: { $0 == "/basis/neu/.iwf.yml" })
        XCTAssertNil(record.usesDockerStack)
    }

    /// Ohne `.iwf.yml` ist der Vorschlag „ohne Stack" — genau der Fall, für den es den Schalter gibt.
    func testVorschlagOhneIwfYml() {
        var config = JSONValue.object([:])
        config.set(.string("/basis"), at: ["basePath"])
        let record = ProjectSuggestion.record(for: "neu", from: config, fileExists: { _ in false })
        XCTAssertEqual(record.usesDockerStack, false)
    }

    /// Nachgesehen wird im **vorgeschlagenen** Repo-Ordner, nicht irgendwo: erstes Segment des
    /// vorgeschlagenen Tasks-Pfads, aufgelöst gegen `basePath`. Genau die Ableitung, die auch
    /// `KanbanConfig.resolve` benutzt — sonst läge der Vorschlag am falschen Ort.
    func testVorschlagPrueftDenAbgeleitetenRepoOrdner() {
        var config = JSONValue.object([:])
        config.set(.string("/basis"), at: ["basePath"])
        config.set(.object(["prefix": .string("EVEN"),
                            "tasksPath": .string("even/docs/tasks")]),
                   at: ["modules", "jira", "projects", "even"])

        var geprueft: [String] = []
        let record = ProjectSuggestion.record(for: "neu", from: config,
                                              fileExists: { geprueft.append($0); return false })
        // Das Muster ergibt `neu/docs/tasks` → Repo-Ordner `/basis/neu`.
        XCTAssertEqual(record.tasksPath, "neu/docs/tasks")
        XCTAssertEqual(geprueft, ["/basis/neu/.iwf.yml"])
    }
}
