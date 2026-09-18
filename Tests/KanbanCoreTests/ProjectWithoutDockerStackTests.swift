import XCTest
@testable import KanbanCore

/// Ein Projekt **ohne Docker-Stack**: Worktrees, Branches und Task-Files bleiben, die Docker-Hälfte
/// fällt weg. Das Muster ist `ProjectWithoutJiraTests` (Vorgabe an, nur die Abschaltung wird
/// geschrieben) — der **Ort** ist ein anderer: eine eigene Section `modules.docker.projects`, denn
/// mit Jira hat der Schalter nichts zu tun.
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
            { "modules": {
                "jira":   { "projects": { "kanban": { "prefix": "KANBAN",
                                                      "tasksPath": "/tmp/tasks/kanban" } } },
                "docker": { "projects": { "kanban": { "stack": false } } } } }
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
            { "modules": {
                "jira":   { "projects": { "even": { "prefix": "EVEN", "tasksPath": "/t" } } },
                "docker": { "projects": { "even": { "stack": true } } } } }
            """)
        XCTAssertTrue(projects[0].usesDockerStack)
    }

    /// Ein Docker-Eintrag **ohne** Jira-Eintrag beschreibt kein Projekt — er darf keins erfinden.
    func testDockerEintragAlleinIstKeinProjekt() throws {
        let projects = try projekte("""
            { "modules": { "docker": { "projects": { "geist": { "stack": false } } } } }
            """)
        XCTAssertTrue(projects.isEmpty)
    }

    /// Die beiden Schalter sind unabhängig: ein Projekt ohne Jira kann sehr wohl einen Stack haben
    /// (und umgekehrt).
    func testJiraAusBedeutetNichtStackAus() throws {
        let projects = try projekte("""
            { "modules": { "jira": { "projects": {
                "intern": { "prefix": "INT", "tasksPath": "/t", "useJira": false } } } } }
            """)
        XCTAssertFalse(projects[0].usesJira)
        XCTAssertTrue(projects[0].usesDockerStack)
    }

    // MARK: - Schreiben

    /// Der Normalfall schreibt gar nichts — ohne Abschaltung entsteht keine Docker-Section.
    func testVorgabeWirdNichtGeschrieben() {
        let record = ProjectRecord(prefix: "EVEN", tasksPath: "/tmp/tasks/even")
        let config = ProjectProjection.applyKanbanOnly(record, key: "even", to: .object([:]))
        XCTAssertNil(config.value(at: ["modules", "docker"]))
    }

    func testAbschaltungWirdGeschrieben() {
        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/tmp/tasks/kanban")
        record.usesDockerStack = false
        let config = ProjectProjection.applyKanbanOnly(record, key: "kanban", to: .object([:]))
        XCTAssertEqual(
            config.value(at: ["modules", "docker", "projects", "kanban", "stack"])?.boolValue, false)
    }

    /// Der Schalter steht **nicht** im Jira-Eintrag — das war der Punkt des Umzugs.
    func testDerJiraEintragBleibtSauber() {
        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        record.usesDockerStack = false
        var config = ProjectProjection.apply(record, key: "kanban", to: .object([:]))
        config = ProjectProjection.applyKanbanOnly(record, key: "kanban", to: config)
        let jira = config.value(at: ["modules", "jira", "projects", "kanban"])?.objectValue
        XCTAssertEqual(jira?["prefix"]?.stringValue, "KANBAN")
        XCTAssertNil(jira?["dockerStack"])
        XCTAssertNil(jira?["stack"])
    }

    /// Hin und zurück: was geschrieben wurde, muss die Registry wieder einlesen — sonst stünde der
    /// Schalter nach dem nächsten Öffnen der Einstellungen wieder auf „an".
    func testRundlauf() {
        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/tmp/tasks/kanban")
        record.usesDockerStack = false
        var config = ProjectProjection.apply(record, key: "kanban", to: .object([:]))
        config = ProjectProjection.applyKanbanOnly(record, key: "kanban", to: config)
        let registry = ProjectProjection.importing(from: config)
        XCTAssertEqual(registry["kanban"]?.usesDockerStack, false)
        XCTAssertEqual(registry["kanban"]?.prefix, "KANBAN")
    }

    /// Wird der Stack wieder eingeschaltet, muss der Eintrag **verschwinden** — bliebe er als
    /// `false` stehen, wäre das Projekt weiterhin abgeschaltet, während der Schalter „an" zeigt.
    func testWiederEinschaltenEntferntDenEintrag() {
        var aus = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        aus.usesDockerStack = false
        var config = ProjectProjection.applyKanbanOnly(aus, key: "kanban", to: .object([:]))
        XCTAssertEqual(
            config.value(at: ["modules", "docker", "projects", "kanban", "stack"])?.boolValue, false)

        var an = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        an.usesDockerStack = nil
        config = ProjectProjection.applyKanbanOnly(an, key: "kanban", to: config)
        XCTAssertNil(config.value(at: ["modules", "docker", "projects", "kanban"]))
    }

    /// Die Projektion ist additiv: ein Schlüssel, den nur jemand anderes kennt, überlebt das
    /// Schreiben — auch im Docker-Eintrag selbst.
    func testFremderSchluesselImSelbenEintragBleibt() {
        var config = JSONValue.object([:])
        config.set(.object(["stack": .bool(true), "irgendwasFremdes": .string("bleibt")]),
                   at: ["modules", "docker", "projects", "kanban"])

        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        record.usesDockerStack = false
        config = ProjectProjection.applyKanbanOnly(record, key: "kanban", to: config)

        let eintrag = config.value(at: ["modules", "docker", "projects", "kanban"])?.objectValue
        XCTAssertEqual(eintrag?["irgendwasFremdes"]?.stringValue, "bleibt")
        XCTAssertEqual(eintrag?["stack"]?.boolValue, false)
    }

    /// Der Grund für den eigenen Aufruf: `apply` läuft über `HermesSync` auch gegen Hermes' Config,
    /// und dort hätte `modules.docker` nichts zu suchen.
    func testDieNormaleProjektionSchreibtKeineDockerSection() {
        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        record.usesDockerStack = false
        let config = ProjectProjection.apply(record, key: "kanban", to: .object([:]))
        XCTAssertNil(config.value(at: ["modules", "docker"]))
    }

    /// Ein gelöschtes Projekt darf keinen verwaisten Docker-Eintrag hinterlassen.
    func testEntfernenRaeumtDieDockerSectionMitAb() {
        var record = ProjectRecord(prefix: "KANBAN", tasksPath: "/t")
        record.usesDockerStack = false
        var config = ProjectProjection.apply(record, key: "kanban", to: .object([:]))
        config = ProjectProjection.applyKanbanOnly(record, key: "kanban", to: config)

        config = ProjectProjection.remove("kanban", from: config)
        XCTAssertNil(config.value(at: ["modules", "docker", "projects", "kanban"]))
        XCTAssertNil(config.value(at: ["modules", "jira", "projects", "kanban"]))
    }

    // MARK: - Schema

    func testSchalterStehtInDerEigenenDockerSektion() {
        let docker = KanbanConfigSchema.sections.first { $0.id == "docker" }
        XCTAssertNotNil(docker, "ohne Sektion gibt es den Schalter in den Einstellungen nicht")
        XCTAssertEqual(docker?.projectMap?.path, ["modules", "docker", "projects"])

        let feld = docker?.projectMap?.fields.first { $0.key == "stack" }
        XCTAssertNotNil(feld)
        XCTAssertFalse(feld?.required ?? true)
        guard case .bool(let defaultOn)? = feld?.kind else {
            return XCTFail("stack sollte ein Schalter sein")
        }
        XCTAssertTrue(defaultOn, "ohne Eintrag muss ein Projekt einen Stack haben")
    }

    /// Und er steht **nicht** mehr unter Jira: mit der Jira-Anbindung hat er nichts zu tun.
    func testUnterJiraStehtKeinStackSchalterMehr() {
        let jira = KanbanConfigSchema.sections.first { $0.id == "jira" }
        XCTAssertNil(jira?.projectMap?.fields.first { $0.key == "dockerStack" })
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
