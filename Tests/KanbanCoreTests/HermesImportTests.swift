import XCTest
@testable import KanbanCore

final class HermesImportTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private let hermes = """
    {
      "basePath": "~/code",
      "modules": {
        "jira": { "baseUrl": "https://x.atlassian.net", "email": "a@b.c", "apiToken": "t",
                  "anonymize": true, "backend": "api",
                  "projects": { "even": { "prefix": "EVEN", "tasksPath": "even/docs/tasks" } } },
        "gitlab": { "baseUrl": "https://git.x.io", "apiToken": "glpat-x", "backend": "extension",
                    "projects": { "even": { "path": "applications/even" } } },
        "vertec": { "enabled": true },
        "whatsapp": { "ownNumber": "+41790000000" }
      }
    }
    """

    /// Übernommen werden genau die zwei Module, die Kanban selbst betreibt — Vertec und WhatsApp
    /// gehören Hermes und haben in Kanbans Config nichts zu suchen.
    func testAdoptsOnlyJiraAndGitlab() throws {
        let result = try XCTUnwrap(HermesImport.adopting(json(hermes), into: .object([:])))
        XCTAssertNotNil(result.value(at: ["modules", "jira", "apiToken"]))
        XCTAssertNotNil(result.value(at: ["modules", "gitlab", "projects", "even", "path"]))
        XCTAssertNil(result.value(at: ["modules", "vertec"]))
        XCTAssertNil(result.value(at: ["modules", "whatsapp"]))
    }

    /// Wertgetreu, inklusive Schlüsseln, die Kanban selbst nie liest (`anonymize`): der Import ist
    /// eine Kopie, keine Übersetzung.
    func testCopiesTheSectionVerbatim() throws {
        let source = try json(hermes)
        let result = try XCTUnwrap(HermesImport.adopting(source, into: .object([:])))
        XCTAssertEqual(result.value(at: ["modules", "jira", "anonymize"])?.boolValue, true)
        XCTAssertEqual(result.value(at: ["modules", "jira", "apiToken"])?.stringValue, "t")
        XCTAssertEqual(result.value(at: ["modules", "gitlab", "baseUrl"])?.stringValue, "https://git.x.io")
    }

    /// Die eine Ausnahme: `backend` ist Hermes' Umschalter zwischen REST und Browser-Session. Kanban
    /// kennt nur den API-Token — der Schalter käme sonst als Wahl daher, die es nicht gibt.
    func testDropsTheBackendSwitch() throws {
        let result = try XCTUnwrap(HermesImport.adopting(try json(hermes), into: .object([:])))
        XCTAssertNil(result.value(at: ["modules", "jira", "backend"]))
        XCTAssertNil(result.value(at: ["modules", "gitlab", "backend"]))
    }

    /// Bestehendes bleibt stehen — `terminal` ist beim Import längst da.
    func testKeepsExistingKeys() throws {
        let existing = try json(#"{"terminal": {"theme": "Solarized Dark"}}"#)
        let result = try XCTUnwrap(HermesImport.adopting(json(hermes), into: existing))
        XCTAssertEqual(result.value(at: ["terminal", "theme"])?.stringValue, "Solarized Dark")
        XCTAssertEqual(result.value(at: ["basePath"])?.stringValue, "~/code")
    }

    /// Der Import ist ein Bootstrap, kein Sync: sobald Kanban eigene Module hat, wird nichts mehr
    /// von Hermes überschrieben — sonst käme ein in Kanban geänderter Wert bei jedem Start zurück.
    func testDoesNotRunOnceModulesExist() throws {
        let existing = try json(#"{"modules": {"jira": {"apiToken": "meiner"}}}"#)
        XCTAssertNil(HermesImport.adopting(try json(hermes), into: existing))
    }

    /// Ein eigener Basis-Pfad ist eine Entscheidung und wird nicht übersteuert.
    func testKeepsOwnBasePath() throws {
        let existing = try json(#"{"basePath": "/eigener/pfad"}"#)
        let result = try XCTUnwrap(HermesImport.adopting(json(hermes), into: existing))
        XCTAssertEqual(result.value(at: ["basePath"])?.stringValue, "/eigener/pfad")
    }

    /// Eine Hermes-Config ohne die zwei Module gibt nichts her — dann bleibt Kanban unverändert und
    /// der Aufrufer spart sich den Schreibvorgang.
    func testNothingToAdopt() throws {
        XCTAssertNil(HermesImport.adopting(try json(#"{"modules": {"vertec": {}}}"#), into: .object([:])))
        XCTAssertNil(HermesImport.adopting(try json("{}"), into: .object([:])))
    }

    /// Ohne Hermes auf der Maschine passiert schlicht nichts — kein Fehler, kein Schreibvorgang.
    func testRunIfNeededIsANoOpWithoutHermes() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: target) }

        let written = HermesImport.runIfNeeded(store: ConfigStore(path: target.path),
                                               hermesPath: "/nicht/vorhanden/config.json")
        XCTAssertFalse(written)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    /// Und mit Hermes: die Datei entsteht und trägt danach eine gültige Kanban-Config.
    func testRunIfNeededAdoptsAndWrites() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("hermes.json")
        let target = dir.appendingPathComponent("kanban.json")
        try hermes.write(to: source, atomically: true, encoding: .utf8)

        XCTAssertTrue(HermesImport.runIfNeeded(store: ConfigStore(path: target.path),
                                               hermesPath: source.path))
        let config = try KanbanConfig.load(path: target.path)
        XCTAssertTrue(config.isConfigured)
        XCTAssertEqual(config.projects.first?.prefix, "EVEN")
        XCTAssertEqual(config.projects.first?.gitlabProjectPath, "applications/even")

        // Zweiter Lauf findet eigene Module vor und rührt nichts mehr an.
        XCTAssertFalse(HermesImport.runIfNeeded(store: ConfigStore(path: target.path),
                                                hermesPath: source.path))
    }
}
