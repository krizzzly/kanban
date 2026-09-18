import XCTest
@testable import KanbanCore

final class KanbanConfigTests: XCTestCase {
    private var configURL: URL!

    override func setUpWithError() throws {
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-config-tests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: configURL)
    }

    private func load(_ projects: String) throws -> AppConfig {
        let json = """
        {
          "basePath": "/base",
          "modules": {
            "jira": {
              "baseUrl": "https://x.atlassian.net", "email": "a@b.c", "apiToken": "t",
              "projects": { \(projects) }
            }
          }
        }
        """
        try json.write(to: configURL, atomically: true, encoding: .utf8)
        return try KanbanConfig.load(path: configURL.path)
    }

    private func loadRaw(_ json: String) throws -> AppConfig {
        try json.write(to: configURL, atomically: true, encoding: .utf8)
        return try KanbanConfig.load(path: configURL.path)
    }

    // MARK: - commit.excludeClaudeProjectFile

    /// Vorgabe **an**: `.claude/project.json` erzeugt Kanban selbst bei jedem Projektwechsel. Wo
    /// `.claude/` nicht gitignored ist (auf dieser Maschine: `core`), stuende sie sonst in jedem
    /// Commit. Eine Config ohne den Abschnitt muss deshalb "abwaehlen" bedeuten, nicht "mitnehmen".
    func testClaudeProjectFileIsExcludedByDefault() throws {
        let config = try load(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertTrue(config.excludeClaudeProjectFileFromCommit)
        XCTAssertTrue(AppConfig.empty.excludeClaudeProjectFileFromCommit)
    }

    func testTheSwitchCanBeTurnedOff() throws {
        let config = try loadRaw(#"{"basePath": "/base", "commit": {"excludeClaudeProjectFile": false}, "modules": {"jira": {"baseUrl": "https://x", "email": "a@b.c", "apiToken": "t"}}}"#)
        XCTAssertFalse(config.excludeClaudeProjectFileFromCommit)
    }

    /// Der Pfad ist der, den `git status` meldet - relativ zur Repo-Wurzel, ohne `./`.
    func testTheExcludedPathMatchesGitStatusNotation() {
        XCTAssertEqual(AppConfig.claudeProjectFilePath, ".claude/project.json")
    }

    /// `commit` ist ein Kanban-eigener Abschnitt und darf **nicht** nach Hermes wandern.
    func testTheCommitSectionIsNotAHermesModule() {
        XCTAssertFalse(ProjectProjection.moduleNames.contains("commit"))
    }

    // MARK: - claude.defaultSkillSet

    /// Das Standard-Skill-Set steht in einem Kanban-eigenen Abschnitt — wie `commit` und
    /// `watchdog` und damit ebenfalls kein Hermes-Modul.
    func testDefaultSkillSetFromConfig() throws {
        let config = try loadRaw(#"{"basePath": "/base", "claude": {"defaultSkillSet": "iwf"}, "modules": {"jira": {"baseUrl": "https://x", "email": "a@b.c", "apiToken": "t"}}}"#)
        XCTAssertEqual(config.defaultSkillSet, "iwf")
        XCTAssertFalse(ProjectProjection.moduleNames.contains("claude"))
    }

    /// Ohne Abschnitt entscheidet der Sets-Ordner (`ClaudeAssetStore.defaultSet`), nicht die Config.
    func testDefaultSkillSetIsNilWithoutTheSection() throws {
        let config = try load(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertNil(config.defaultSkillSet)
        XCTAssertNil(AppConfig.empty.defaultSkillSet)
    }

    /// Wo die Sets **gepflegt** werden — genau dorthin zeigen die Symlinks der Projekte. Ohne
    /// Eintrag gilt die Konvention „Kanban-Repo unter dem Basis-Pfad"; der Pfad wird aufgelöst wie
    /// jeder andere (absolut, `~` oder relativ zum Basis-Pfad).
    func testSetsPathDefaultsToTheKanbanRepo() throws {
        let config = try load(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertEqual(config.skillSetsPath,
                       "/base/kanban/Sources/Kanban/Resources/ClaudeAssets/sets")
    }

    func testSetsPathCanBeOverridden() throws {
        let relativ = try loadRaw(#"{"basePath": "/base", "claude": {"setsPath": "meine-sets"}, "modules": {"jira": {"baseUrl": "https://x", "email": "a@b.c", "apiToken": "t"}}}"#)
        XCTAssertEqual(relativ.skillSetsPath, "/base/meine-sets")

        let absolut = try loadRaw(#"{"basePath": "/base", "claude": {"setsPath": "/anderswo/sets"}, "modules": {"jira": {"baseUrl": "https://x", "email": "a@b.c", "apiToken": "t"}}}"#)
        XCTAssertEqual(absolut.skillSetsPath, "/anderswo/sets")
    }

    /// Bisheriges Verhalten ohne Override: Repo = Basis + erstes Segment des Tasks-Pfads.
    func testRepoDirDerivedFromTasksPath() throws {
        let config = try load(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertEqual(config.projects[0].repoDir, "/base/even")
        XCTAssertEqual(config.projects[0].tasksPathAbsolute, "/base/even/docs/tasks")
    }

    // MARK: - Doku-Ordner

    /// Ohne Confluence-Eintrag: der Default-Ordner unter Application Support, je Projekt-Key.
    /// Doku gehört genauso wenig ins Repo wie das Task-File — sie wird dort nie mitcommittet.
    func testDocsPathDefaultsToTheKanbanFolder() throws {
        let config = try resolve(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertEqual(config.projects[0].docsPathAbsolute, "/docs/even")
    }

    /// Mit Eintrag gewinnt er — aufgelöst wie jeder andere Pfad (absolut, `~` oder relativ zur Basis).
    func testDocsPathFromTheConfluenceEntry() throws {
        let config = try resolve(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#,
                                 confluence: #""even": {"space": "EVEN", "path": "even/docs/kb"}"#)
        XCTAssertEqual(config.projects[0].docsPathAbsolute, "/base/even/docs/kb")
    }

    /// `../` ist die Schreibweise, die Hermes' `path.join` braucht — im UI und in
    /// `.claude/project.json` soll sie trotzdem nicht auftauchen.
    func testPathsAreNormalized() throws {
        let config = try resolve(
            #""even": {"prefix": "EVEN", "tasksPath": "../Kanban/tasks/even", "repoDir": "even"}"#)
        XCTAssertEqual(config.projects[0].tasksPathAbsolute, "/Kanban/tasks/even")
        XCTAssertEqual(config.projects[0].repoDir, "/base/even")
    }

    /// Der Confluence-Block allein macht **kein** Projekt: ohne Jira-Präfix gibt es keine Karte.
    /// (Ein reiner Space wie `tech` lebt in der Config, nicht auf dem Board.)
    func testConfluenceOnlyEntryIsNoProject() throws {
        let config = try resolve(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#,
                                 confluence: #""tech": {"space": "tech", "path": "bfezvm/docs/kb"}"#)
        XCTAssertEqual(config.projects.map(\.key), ["even"])
    }

    // MARK: - Knowledgebase

    /// Ohne Eintrag gibt es keinen Pfad — und damit kein `kbPath` in `.claude/project.json`.
    /// Ein erfundener Default-Ordner wäre eine Behauptung über etwas, das der Nutzer nie angelegt hat.
    func testKbPathIsAbsentWithoutAnEntry() throws {
        let config = try resolve(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertNil(config.projects[0].kbPathAbsolute)
    }

    func testKbPathResolvesLikeEveryOtherPath() throws {
        let config = try resolve(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#,
                                 knowledgebase: #""even": {"path": "even-docs/kb"}"#)
        XCTAssertEqual(config.projects[0].kbPathAbsolute, "/base/even-docs/kb")

        let absolute = try resolve(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#,
                                   knowledgebase: #""even": {"path": "/wissen/even"}"#)
        XCTAssertEqual(absolute.projects[0].kbPathAbsolute, "/wissen/even")
    }

    /// Ein leerer Wert ist kein Pfad — sonst zeigte `kbPath` auf den Basis-Pfad.
    func testEmptyKbPathCountsAsUnset() throws {
        let config = try resolve(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#,
                                 knowledgebase: #""even": {"path": ""}"#)
        XCTAssertNil(config.projects[0].kbPathAbsolute)
    }

    private func resolve(_ projects: String, confluence: String? = nil,
                         knowledgebase: String? = nil) throws -> AppConfig {
        let confluenceBlock = confluence.map { ",\n\"confluence\": { \"projects\": { \($0) } }" } ?? ""
        let kbBlock = knowledgebase.map { ",\n\"knowledgebase\": { \"projects\": { \($0) } }" } ?? ""
        let json = """
        {
          "basePath": "/base",
          "modules": {
            "jira": {
              "baseUrl": "https://x.atlassian.net", "email": "a@b.c", "apiToken": "t",
              "projects": { \(projects) }
            }\(confluenceBlock)\(kbBlock)
          }
        }
        """
        return try KanbanConfig.resolve(Data(json.utf8), docsRoot: "/docs")
    }

    /// Der Agent je Projekt: fehlt der Schlüssel, bleibt es bei Claude.
    func testAgentDefaultsToClaude() throws {
        let config = try load(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertEqual(config.projects[0].agent, .claude)
    }

    func testAgentFromConfig() throws {
        let config = try load(
            #""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks", "agent": "codex"}"#)
        XCTAssertEqual(config.projects[0].agent, .codex)
    }

    /// Ein Tippfehler darf ein Projekt nicht unbenutzbar machen — er fällt auf Claude zurück.
    func testUnknownAgentFallsBackInsteadOfFailing() throws {
        let config = try load(
            #""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks", "agent": "kodex"}"#)
        XCTAssertEqual(config.projects[0].agent, .claude)
    }

    /// Das Skill-Set je Projekt wird wie `agent` gelesen: fehlt es, gilt das Standard-Set (nil).
    func testSkillSetIsNilWithoutAnEntry() throws {
        let config = try load(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertNil(config.projects[0].skillSet)
    }

    func testSkillSetFromConfig() throws {
        let config = try load(
            #""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks", "skillSet": "swift"}"#)
        XCTAssertEqual(config.projects[0].skillSet, "swift")
    }

    /// Ein leerer Eintrag ist keiner — der Einstellungs-Editor legt Felder gern an und lässt sie
    /// leer stehen; das darf nicht wie ein nicht auffindbares Set aussehen.
    func testEmptySkillSetCountsAsUnset() throws {
        let config = try load(
            #""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks", "skillSet": "  "}"#)
        XCTAssertNil(config.projects[0].skillSet)
    }

    /// HERMES-034: eigener repoDir entkoppelt das Repo vom Tasks-Pfad — relativ zum Basis-Pfad …
    func testRepoDirOverrideRelative() throws {
        let config = try load(
            #""even": {"prefix": "EVEN", "tasksPath": "kanban-tasks/even", "repoDir": "even"}"#)
        XCTAssertEqual(config.projects[0].repoDir, "/base/even")
        XCTAssertEqual(config.projects[0].tasksPathAbsolute, "/base/kanban-tasks/even")
    }

    /// … oder absolut, dann zählt er unverändert. Auch der Tasks-Pfad darf absolut sein
    /// (Voraussetzung für den Umzug nach Application Support).
    func testRepoDirOverrideAndTasksPathAbsolute() throws {
        let config = try load(
            #""even": {"prefix": "EVEN", "tasksPath": "/apps/Kanban/tasks/even", "repoDir": "/repos/even"}"#)
        XCTAssertEqual(config.projects[0].repoDir, "/repos/even")
        XCTAssertEqual(config.projects[0].tasksPathAbsolute, "/apps/Kanban/tasks/even")
    }

    // MARK: - Erststart ohne Hermes

    /// Die zentrale Zusage der eigenen Config: keine Datei ist **kein Fehler**. Wer Kanban ohne
    /// Hermes installiert, landet im Setup-Schirm, nicht in einer Fehlermeldung.
    func testMissingFileYieldsAnEmptyConfigInsteadOfThrowing() throws {
        let config = try KanbanConfig.load(path: configURL.path)   // nie geschrieben
        XCTAssertFalse(config.isConfigured)
        XCTAssertFalse(config.hasJira)
        XCTAssertTrue(config.projects.isEmpty)
    }

    /// Dasselbe für eine Datei, die es gibt, in der aber noch nichts steht.
    func testEmptyObjectIsNotConfigured() throws {
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertFalse(try KanbanConfig.load(path: configURL.path).isConfigured)
    }

    /// Zugangsdaten allein reichen nicht: ohne Projekt hat das Board nichts zu zeigen.
    func testCredentialsWithoutProjectsAreNotConfigured() throws {
        let config = try load("")
        XCTAssertTrue(config.hasJira)
        XCTAssertFalse(config.isConfigured)
    }

    func testCredentialsWithProjectAreConfigured() throws {
        let config = try load(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertTrue(config.isConfigured)
    }

    /// Kaputtes JSON dagegen ist sehr wohl ein Fehler — stillschweigend zu ignorieren sähe aus wie
    /// Datenverlust.
    func testBrokenJSONThrows() throws {
        try "{ not json".write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try KanbanConfig.load(path: configURL.path))
    }
}
