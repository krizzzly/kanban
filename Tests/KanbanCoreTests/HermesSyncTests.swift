import XCTest
@testable import KanbanCore

final class HermesSyncTests: XCTestCase {
    private var dir: URL!
    private var hermesPath: String { dir.appendingPathComponent("hermes.json").path }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func writeHermes(_ text: String) throws {
        try text.write(to: URL(fileURLWithPath: hermesPath), atomically: true, encoding: .utf8)
    }

    private func readHermes() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: hermesPath)))
    }

    private let kanban = """
    {"modules": {
       "jira": {"apiToken": "kanban-token",
                "projects": {"even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"},
                             "neu":  {"prefix": "NEU",  "tasksPath": "neu/docs/tasks"}}},
       "gitlab": {"projects": {"even": {"path": "applications/even"}}}}}
    """

    /// Der Kern: ein in Kanban angelegtes Projekt taucht in der Hermes-Config auf.
    func testProjectsAreProjectedIntoHermes() throws {
        try writeHermes(#"{"modules": {"jira": {"apiToken": "hermes-token", "projects": {}}}}"#)

        XCTAssertEqual(HermesSync.run(kanban: try json(kanban), hermesPath: hermesPath),
                       .synced(projects: 2))

        let hermes = try readHermes()
        XCTAssertEqual(hermes.value(at: ["modules", "jira", "projects", "neu", "prefix"])?.stringValue, "NEU")
        XCTAssertEqual(hermes.value(at: ["modules", "gitlab", "projects", "even", "path"])?.stringValue,
                       "applications/even")
    }

    /// Additiv: was Kanban nicht besitzt, bleibt unangetastet — vor allem Hermes' eigener Token.
    func testLeavesForeignValuesAlone() throws {
        try writeHermes("""
        {"modules": {
           "jira": {"apiToken": "hermes-token", "baseUrl": "https://x.atlassian.net", "anonymize": true,
                    "projects": {"even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks",
                                          "handgepflegt": "bleibt"}}},
           "vertec": {"enabled": true, "projects": {"even": {"project": "8100"}}}}}
        """)

        XCTAssertEqual(HermesSync.run(kanban: try json(kanban), hermesPath: hermesPath),
                       .synced(projects: 2))

        let hermes = try readHermes()
        XCTAssertEqual(hermes.value(at: ["modules", "jira", "apiToken"])?.stringValue, "hermes-token")
        XCTAssertEqual(hermes.value(at: ["modules", "jira", "anonymize"])?.boolValue, true)
        XCTAssertEqual(hermes.value(at: ["modules", "jira", "projects", "even", "handgepflegt"])?.stringValue,
                       "bleibt")
        XCTAssertEqual(hermes.value(at: ["modules", "vertec", "projects", "even", "project"])?.stringValue,
                       "8100")
    }

    /// Ein Projekt, das nur Hermes kennt, wird nie gelöscht — die Projektion ergänzt, sie räumt nicht auf.
    func testForeignProjectSurvives() throws {
        try writeHermes("""
        {"modules": {"jira": {"projects": {"nur-hermes": {"prefix": "NH", "tasksPath": "nh"}}}}}
        """)

        _ = HermesSync.run(kanban: try json(kanban), hermesPath: hermesPath)

        XCTAssertNotNil(try readHermes().value(at: ["modules", "jira", "projects", "nur-hermes"]))
    }

    /// Zweimal dasselbe schreiben heisst: beim zweiten Mal nichts tun (kein mtime-Rauschen für den
    /// Daemon, der die Datei beobachtet).
    func testSecondRunIsAnNoOp() throws {
        try writeHermes(#"{"modules": {"jira": {"projects": {}}}}"#)
        XCTAssertEqual(HermesSync.run(kanban: try json(kanban), hermesPath: hermesPath),
                       .synced(projects: 2))
        XCTAssertEqual(HermesSync.run(kanban: try json(kanban), hermesPath: hermesPath), .unchanged)
    }

    /// Ohne Hermes auf der Maschine: still übersprungen, keine Datei, kein Fehler.
    func testWithoutHermesNothingHappens() throws {
        XCTAssertEqual(HermesSync.run(kanban: try json(kanban), hermesPath: hermesPath),
                       .skipped(reason: "keine Hermes-Config"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hermesPath))
    }

    /// Abschaltbar, für wen die Hermes-Config von Hand pflegt.
    func testCanBeSwitchedOff() throws {
        try writeHermes(#"{"modules": {"jira": {"projects": {}}}}"#)
        var document = try json(kanban)
        document.set(.bool(false), at: ["hermes", "syncProjects"])

        XCTAssertEqual(HermesSync.run(kanban: document, hermesPath: hermesPath),
                       .skipped(reason: "abgeschaltet"))
        XCTAssertNil(try readHermes().value(at: ["modules", "jira", "projects", "even"]))
    }

    /// Der Grund für das Mischen, als eigene Zusage: Kanban kennt Vertec & Co. nicht, darf ihre
    /// Einträge aber auch nicht wegräumen.
    func testKeepsModulesKanbanDoesNotKnow() throws {
        let hermes = ProjectRegistry(projects: [
            "even": ProjectRecord(prefix: "EVEN", vertec: .init(project: "8100"),
                                  jenkins: .init(jobs: ["even-build"]))])
        let kanban = ProjectRegistry(projects: [
            "even": ProjectRecord(prefix: "EVEN", tasksPath: "even/docs/tasks",
                                  gitlab: .init(path: "applications/even"))])

        let merged = HermesSync.merged(kanban: kanban, hermes: hermes)
        XCTAssertEqual(merged["even"]?.tasksPath, "even/docs/tasks")     // Kanban gewinnt
        XCTAssertEqual(merged["even"]?.gitlab?.path, "applications/even")
        XCTAssertEqual(merged["even"]?.vertec?.project, "8100")          // Hermes bleibt
        XCTAssertEqual(merged["even"]?.jenkins?.jobs, ["even-build"])
    }

    /// Was der Nutzer im Projekt-Editor eingetragen hat, sticht den Hermes-Stand.
    func testKanbanValuesWinWhereTheyExist() {
        let hermes = ProjectRegistry(projects: ["even": ProjectRecord(vertec: .init(project: "alt"))])
        let kanban = ProjectRegistry(projects: ["even": ProjectRecord(vertec: .init(project: "neu"))])
        XCTAssertEqual(HermesSync.merged(kanban: kanban, hermes: hermes)["even"]?.vertec?.project, "neu")
    }

    // MARK: - Hermes' path.join

    /// Der Kern der Falle: Hermes rechnet `path.join(basePath, wert)`. Ein absoluter Task-Ordner
    /// landete dort **unter** dem Basis-Pfad (`~/code/Users/…`) — und `generate-claude-task` legte
    /// Task-Files in einem Phantom-Ordner ab, ohne Fehler. Also wird relativiert.
    func testAbsolutePathsAreWrittenRelativeToHermesBase() throws {
        try writeHermes(#"{"basePath": "~/code", "modules": {"jira": {"projects": {}}}}"#)
        let home = NSHomeDirectory()
        let kanban = """
        {"modules": {"jira": {"projects": {"even": {"prefix": "EVEN",
            "tasksPath": "\(home)/Library/Application Support/Kanban/tasks/even"}}},
          "confluence": {"projects": {"even": {"space": "EVEN",
            "path": "\(home)/Library/Application Support/Kanban/docs/even"}}}}}
        """
        XCTAssertEqual(HermesSync.run(kanban: try json(kanban), hermesPath: hermesPath),
                       .synced(projects: 1))

        let hermes = try readHermes()
        XCTAssertEqual(hermes.value(at: ["modules", "jira", "projects", "even", "tasksPath"])?.stringValue,
                       "../Library/Application Support/Kanban/tasks/even")
        XCTAssertEqual(hermes.value(at: ["modules", "confluence", "projects", "even", "path"])?.stringValue,
                       "../Library/Application Support/Kanban/docs/even")
        // Der Space gehört der Projektion mit — würde er nicht mitgeschrieben, nähme sie ihn weg.
        XCTAssertEqual(hermes.value(at: ["modules", "confluence", "projects", "even", "space"])?.stringValue,
                       "EVEN")
    }

    /// Relative Werte bleiben, wie sie sind: sie sind entweder schon Hermes' Schreibweise oder
    /// gegen denselben Basis-Pfad gemeint. Umrechnen hiesse raten.
    func testRelativePathsAreLeftAlone() throws {
        try writeHermes(#"{"basePath": "~/code", "modules": {"jira": {"projects": {}}}}"#)
        XCTAssertEqual(HermesSync.run(kanban: try json(kanban), hermesPath: hermesPath),
                       .synced(projects: 2))
        XCTAssertEqual(try readHermes()
            .value(at: ["modules", "jira", "projects", "even", "tasksPath"])?.stringValue,
                       "even/docs/tasks")
    }

    func testRelativeComputation() {
        XCTAssertEqual(HermesPath.relative("/a/b/c/d", to: "/a/b"), "c/d")
        XCTAssertEqual(HermesPath.relative("/a/x/y", to: "/a/b"), "../x/y")
        XCTAssertEqual(HermesPath.relative("/a/b", to: "/a/b"), ".")
        XCTAssertEqual(HermesPath.relative("/a/b/../x", to: "/a/b"), "../x")
        XCTAssertEqual(HermesPath.relative("relativ/bleibt", to: "/a/b"), "relativ/bleibt")
    }

    /// Ohne `basePath` in der Hermes-Config wird nichts umgerechnet — geraten wird nicht.
    func testWithoutHermesBasePathNothingIsRewritten() {
        let registry = ProjectRegistry(projects: ["even": ProjectRecord(tasksPath: "/abs/tasks")])
        XCTAssertEqual(HermesPath.relativizing(registry, hermesBase: nil)["even"]?.tasksPath,
                       "/abs/tasks")
    }

    func testEnabledByDefault() throws {
        XCTAssertTrue(HermesSync.isEnabled(in: try json("{}")))
        XCTAssertTrue(HermesSync.isEnabled(in: try json(#"{"hermes": {"syncProjects": true}}"#)))
        XCTAssertFalse(HermesSync.isEnabled(in: try json(#"{"hermes": {"syncProjects": false}}"#)))
    }
}
