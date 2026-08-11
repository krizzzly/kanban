import XCTest
@testable import KanbanCore

final class ProjectRegistryTests: XCTestCase {

    /// Nachbau der echten Config-Form: sieben Jira-Projekte, vier GitLab, drei Confluence, drei
    /// Vertec — inklusive der Sonderfälle (fremder Host, geteiltes Repo, Confluence-only) und
    /// Feldern, die die Registry nicht besitzt.
    private func realShapedConfig() throws -> JSONValue {
        let json = """
        {
          "basePath": "/Users/x/code",
          "modules": {
            "jira": {
              "baseUrl": "https://acme.atlassian.net",
              "apiToken": "geheim",
              "projects": {
                "bfezvm":     { "prefix": "BFEZVM", "tasksPath": "bfezvm/docs/tasks" },
                "even":       { "prefix": "EVEN", "tasksPath": "even/docs/tasks" },
                "reactbp":    { "prefix": "REACTBP", "tasksPath": "reactbp/.claude/tasks" },
                "support":    { "prefix": "SUPPORT", "tasksPath": "even/docs/support" },
                "tp1":        { "prefix": "TP1", "tasksPath": "bfezvm/docs/support" },
                "zba":        { "prefix": "ZBA", "tasksPath": "zba/.claude/tasks" },
                "zvmsupport": { "prefix": "ZVMSUPPORT", "tasksPath": "bfezvm/docs/support",
                                "baseUrl": "https://support-energie.atlassian.net" }
              }
            },
            "gitlab": {
              "apiToken": "glpat-geheim",
              "projects": {
                "bfezvm":  { "path": "applications/bfezvm" },
                "even":    { "path": "applications/even" },
                "reactbp": { "path": "applications/reactbp" },
                "zba":     { "path": "applications/zba" }
              }
            },
            "confluence": {
              "projects": {
                "bfezvm": { "path": "bfezvm/docs/kb", "space": "VOLLZUGZV" },
                "even":   { "path": "even/docs/kb", "space": "EVEN" },
                "tech":   { "path": "bfezvm/docs/kb", "space": "tech" }
              }
            },
            "vertec": {
              "projects": {
                "bfezvm": { "additionalKeys": ["bfezvm-config"], "phase": "ZVM 2026",
                            "project": "8100 - BFE - ZVM-Tool", "task": "PROGRAMMIERUNG" },
                "even":   { "additionalKeys": [], "phase": "EVEN 2026",
                            "project": "8100 - EVEN Basisprodukt", "task": "PROGRAMMIERUNG" },
                "zba":    { "additionalKeys": [], "phase": "MIGRATION BL",
                            "project": "8100 - ZBA", "task": "PROGRAMMIERUNG" }
              }
            },
            "jenkins": {
              "baseUrl": "https://jenkins.acme.io",
              "projects": {
                "bfezvm": { "jobs": ["bfezvm - DEV - Build", "bfezvm - DEV - Tests"] },
                "even":   { "jobs": ["even - DEV - Build"] }
              }
            },
            "dockerhub": {
              "projects": {
                "bfezvm": { "namespace": "iwfwebsolutions", "repository": "bfezvm" }
              }
            },
            "anonymization": { "ner": { "zefix": true } }
          }
        }
        """
        return try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private func entry(_ config: JSONValue, _ module: String, _ key: String) -> [String: JSONValue]? {
        config.value(at: ["modules", module, "projects", key])?.objectValue
    }

    // MARK: - Werterhalt

    /// Die zentrale Zusage: die Registry aus dem Ist-Zustand zu bauen und sofort zurückzuschreiben
    /// darf die Config **nicht** verändern. Sonst würde der Bootstrap Projekte umkonfigurieren.
    func testImportThenApplyIsIdentity() throws {
        let config = try realShapedConfig()
        let registry = ProjectProjection.importing(from: config)
        let projected = ProjectProjection.apply(registry, to: config)
        XCTAssertEqual(projected, config)
    }

    func testImportCoversUnionOfAllModules() throws {
        let registry = ProjectProjection.importing(from: try realShapedConfig())
        // sieben Jira-Keys plus `tech`, das es nur in Confluence gibt
        XCTAssertEqual(registry.keys,
                       ["bfezvm", "even", "reactbp", "support", "tech", "tp1", "zba", "zvmsupport"])
    }

    /// Jenkins und DockerHub keyen auf dieselben Projektnamen — ein Projekt ist heute über **sechs**
    /// Sections verstreut, nicht über vier.
    func testImportCoversJenkinsAndDockerhub() throws {
        let registry = ProjectProjection.importing(from: try realShapedConfig())
        XCTAssertEqual(registry["even"]?.jenkins?.jobs, ["even - DEV - Build"])
        XCTAssertEqual(registry["bfezvm"]?.dockerhub?.repository, "bfezvm")
        XCTAssertNil(registry["zba"]?.jenkins)
    }

    func testImportKeepsHostOverrideAndSharedRepo() throws {
        let registry = ProjectProjection.importing(from: try realShapedConfig())
        let support = try XCTUnwrap(registry["zvmsupport"])
        XCTAssertEqual(support.jiraBaseUrl, "https://support-energie.atlassian.net")
        XCTAssertEqual(support.tasksPath, "bfezvm/docs/support")
        XCTAssertNil(support.gitlab)      // Support-Projekt ohne eigenes GitLab-Repo
        XCTAssertNil(support.vertec)
    }

    /// `tech` ist ein reiner Confluence-Space: kein Präfix, also auch kein Jira-Eintrag.
    func testConfluenceOnlyProjectStaysJiraLess() throws {
        let config = try realShapedConfig()
        let registry = ProjectProjection.importing(from: config)
        let tech = try XCTUnwrap(registry["tech"])
        XCTAssertNil(tech.prefix)
        XCTAssertEqual(tech.confluence?.space, "tech")

        let projected = ProjectProjection.apply(registry, to: config)
        XCTAssertNil(entry(projected, "jira", "tech"))
    }

    /// `[]` ist ein Wert, kein fehlendes Feld — sonst kippt der Identity-Test bei `even`/`zba`.
    func testEmptyAdditionalKeysSurviveRoundTrip() throws {
        let config = try realShapedConfig()
        let registry = ProjectProjection.importing(from: config)
        XCTAssertEqual(registry["even"]?.vertec?.additionalKeys, [])

        let projected = ProjectProjection.apply(registry, to: config)
        XCTAssertEqual(entry(projected, "vertec", "even")?["additionalKeys"], .array([]))
    }

    // MARK: - Additiv, nie destruktiv

    func testForeignFieldsInsideAnEntrySurvive() throws {
        var config = try realShapedConfig()
        config.set(.string("wert"), at: ["modules", "jira", "projects", "even", "handgepflegt"])

        var registry = ProjectProjection.importing(from: config)
        registry["even"]?.tasksPath = "even/docs/neu"
        let projected = ProjectProjection.apply(registry, to: config)

        XCTAssertEqual(entry(projected, "jira", "even")?["handgepflegt"], .string("wert"))
        XCTAssertEqual(entry(projected, "jira", "even")?["tasksPath"], .string("even/docs/neu"))
    }

    func testUnknownProjectKeyIsNotRemoved() throws {
        let config = try realShapedConfig()
        var registry = ProjectRegistry()
        registry["even"] = ProjectRecord(prefix: "EVEN", tasksPath: "even/docs/tasks")

        let projected = ProjectProjection.apply(registry, to: config)
        XCTAssertNotNil(entry(projected, "jira", "bfezvm"))       // nicht in der Registry, bleibt
        XCTAssertNotNil(entry(projected, "vertec", "zba"))
    }

    func testModuleCredentialsAreUntouched() throws {
        let config = try realShapedConfig()
        let projected = ProjectProjection.apply(ProjectProjection.importing(from: config), to: config)
        XCTAssertEqual(projected.value(at: ["modules", "gitlab", "apiToken"]), .string("glpat-geheim"))
        XCTAssertEqual(projected.value(at: ["modules", "anonymization", "ner", "zefix"]), .bool(true))
    }

    // MARK: - Änderungen

    func testNewProjectLandsInEveryConfiguredModule() throws {
        let config = try realShapedConfig()
        var registry = ProjectProjection.importing(from: config)
        registry["neu"] = ProjectRecord(
            prefix: "NEU",
            tasksPath: "neu/docs/tasks",
            gitlab: .init(path: "applications/neu"),
            vertec: .init(project: "8100 - Neu", task: "PROGRAMMIERUNG"))

        let projected = ProjectProjection.apply(registry, to: config)
        XCTAssertEqual(entry(projected, "jira", "neu")?["prefix"], .string("NEU"))
        XCTAssertEqual(entry(projected, "gitlab", "neu")?["path"], .string("applications/neu"))
        XCTAssertEqual(entry(projected, "vertec", "neu")?["project"], .string("8100 - Neu"))
        XCTAssertNil(entry(projected, "confluence", "neu"))       // kein Block → kein Eintrag
    }

    /// Nimmt der User einem bekannten Projekt den GitLab-Block weg, verschwindet der Eintrag —
    /// für die Keys, die sie kennt, ist die Registry Owner.
    func testDroppingAModuleBlockRemovesItsEntry() throws {
        let config = try realShapedConfig()
        var registry = ProjectProjection.importing(from: config)
        registry["even"]?.gitlab = nil

        let projected = ProjectProjection.apply(registry, to: config)
        XCTAssertNil(entry(projected, "gitlab", "even"))
        XCTAssertNotNil(entry(projected, "gitlab", "bfezvm"))
    }

    func testClearingAnOwnedFieldRemovesTheKey() throws {
        let config = try realShapedConfig()
        var registry = ProjectProjection.importing(from: config)
        registry["zvmsupport"]?.jiraBaseUrl = nil

        let projected = ProjectProjection.apply(registry, to: config)
        XCTAssertNil(entry(projected, "jira", "zvmsupport")?["baseUrl"])
        XCTAssertEqual(entry(projected, "jira", "zvmsupport")?["prefix"], .string("ZVMSUPPORT"))
    }

    /// Ohne Jira-Section in der Config darf die Projektion keine leeren Modul-Objekte erzeugen.
    func testNoEmptySectionsForUnconfiguredModules() throws {
        let config = JSONValue.object([:])
        var registry = ProjectRegistry()
        registry["even"] = ProjectRecord(prefix: "EVEN", tasksPath: "even/docs/tasks")

        let projected = ProjectProjection.apply(registry, to: config)
        XCTAssertNotNil(entry(projected, "jira", "even"))
        XCTAssertNil(projected.value(at: ["modules", "gitlab"]))
        XCTAssertNil(projected.value(at: ["modules", "vertec"]))
    }

    /// Dieselbe Zusage gegen die **echte** Config dieser Maschine — die Fixture kann nur, was ihr
    /// Autor bedacht hat. Übersprungen, wo keine Config liegt (CI, frische Checkouts).
    func testImportThenApplyIsIdentityOnTheRealConfig() throws {
        let path = HermesConfigLoader.defaultPath
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path),
                          "keine ~/.hermes/config.json auf dieser Maschine")

        let config = try JSONDecoder().decode(JSONValue.self,
                                              from: Data(contentsOf: URL(fileURLWithPath: path)))
        let registry = ProjectProjection.importing(from: config)
        XCTAssertFalse(registry.keys.isEmpty, "Registry-Import fand keine Projekte")
        XCTAssertEqual(ProjectProjection.apply(registry, to: config), config)
    }

    /// Entfernen ist eine ausdrückliche Aktion und räumt alle sechs Sections ab — im Gegensatz zur
    /// Projektion, die einen unbekannten Key stehen lässt.
    func testRemoveClearsEverySection() throws {
        let config = try realShapedConfig()
        let stripped = ProjectProjection.remove("even", from: config)

        for module in ProjectProjection.moduleNames {
            XCTAssertNil(entry(stripped, module, "even"), "\(module) hat den Eintrag behalten")
        }
        XCTAssertNotNil(entry(stripped, "jira", "bfezvm"))
        XCTAssertEqual(stripped.value(at: ["modules", "gitlab", "apiToken"]), .string("glpat-geheim"))
    }

    // MARK: - Vorschläge fürs Anlegen

    /// Der Kern des zentralen Anlegens: die Muster stehen schon in der Config, man muss sie nur
    /// lesen. Ein Wert, der den Key seines Projekts enthält, ist eine Schablone.
    func testSuggestionDerivesPatternsFromExistingProjects() throws {
        let suggestion = ProjectSuggestion.record(for: "neu", from: try realShapedConfig())

        XCTAssertEqual(suggestion.prefix, "NEU")
        XCTAssertEqual(suggestion.tasksPath, "neu/docs/tasks")          // Mehrheitsmuster
        XCTAssertEqual(suggestion.gitlab?.path, "applications/neu")
        XCTAssertEqual(suggestion.confluence?.space, "NEU")
        XCTAssertEqual(suggestion.confluence?.path, "neu/docs/kb")
        XCTAssertEqual(suggestion.jenkins?.jobs, ["neu - DEV - Build", "neu - DEV - Tests"])
        XCTAssertEqual(suggestion.dockerhub?.namespace, "iwfwebsolutions")
        XCTAssertEqual(suggestion.dockerhub?.repository, "neu")
    }

    /// Vertec-Projekt/Phase folgen keinem ableitbaren Muster — lieber leer lassen als raten.
    func testSuggestionLeavesUnderivableFieldsEmpty() throws {
        let suggestion = ProjectSuggestion.record(for: "neu", from: try realShapedConfig())
        XCTAssertNil(suggestion.vertec)
        XCTAssertNil(suggestion.repoDir)
        XCTAssertNil(suggestion.jiraBaseUrl)
    }

    func testSuggestionOnEmptyConfigFallsBackToConventions() {
        let suggestion = ProjectSuggestion.record(for: "neu", from: .object([:]))
        XCTAssertEqual(suggestion.prefix, "NEU")
        XCTAssertEqual(suggestion.tasksPath, "neu/docs/tasks")
        XCTAssertNil(suggestion.gitlab)        // ohne Vorbild kein geratener Namespace
        XCTAssertNil(suggestion.jenkins)
    }

    func testSuggestionSkipsTakenKeys() throws {
        let config = try realShapedConfig()
        XCTAssertTrue(ProjectSuggestion.isTaken("even", in: config))
        XCTAssertTrue(ProjectSuggestion.isTaken("tech", in: config))    // nur Confluence, zählt auch
        XCTAssertFalse(ProjectSuggestion.isTaken("neu", in: config))
    }
}
