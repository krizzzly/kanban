import XCTest
@testable import KanbanCore

final class ClaudeProjectFileTests: XCTestCase {
    private var repoDir: URL!

    override func setUpWithError() throws {
        repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-file-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir)
    }

    private var project: ProjectConfig {
        ProjectConfig(key: "even", prefix: "EVEN",
                      jiraBaseUrl: "https://jira.example",
                      tasksPathAbsolute: "/Users/x/code/even/docs/tasks",
                      docsPathAbsolute: "/Users/x/Library/Application Support/Kanban/docs/even",
                      repoDir: repoDir.path,
                      forge: ForgeRef(kind: .gitlab, path: "applications/even"))
    }

    /// Ein Projekt ohne Stack — dasselbe Repo, nur `usesDockerStack: false`.
    private var projectOhneStack: ProjectConfig {
        ProjectConfig(key: "kanban", prefix: "KANBAN",
                      jiraBaseUrl: "",
                      tasksPathAbsolute: "/Users/x/Library/Application Support/Kanban/tasks/kanban",
                      docsPathAbsolute: "/Users/x/Library/Application Support/Kanban/docs/kanban",
                      repoDir: repoDir.path,
                      forge: nil,
                      usesJira: false,
                      usesDockerStack: false)
    }

    func testValuesDeriveWorktreePrefixAndDomain() {
        let values = ClaudeProjectFile.values(for: project)
        XCTAssertEqual(values.prefix, "EVEN")
        XCTAssertEqual(values.worktreePrefix, repoDir.path + "-worktree")
        XCTAssertTrue(values.dockerStack)
        XCTAssertEqual(values.stackDomain, "test")
        XCTAssertEqual(values.forge, "gitlab")
        XCTAssertEqual(values.forgeProjectPath, "applications/even")
        // Übergangsweise weitergeführt, damit nichts bricht, was den alten Schlüssel liest.
        XCTAssertEqual(values.gitlabProjectPath, "applications/even")
        // Der Doku-Ordner steht mit in der Datei: sonst kennte kein Skill den Ort, an den die
        // Confluence-Exporte gehen (Platzhalter `<docsPath>`, wie `<tasksPath>`).
        XCTAssertEqual(values.docsPath, "/Users/x/Library/Application Support/Kanban/docs/even")
        // Ohne konfigurierte Knowledgebase steht der Schlüssel gar nicht in der Datei.
        XCTAssertNil(values.kbPath)
    }

    /// Mit Knowledgebase: `kbPath` steht drin — der Platzhalter `<kbPath>` der Skills löst darauf auf.
    func testKbPathIsWrittenWhenConfigured() throws {
        let withKB = ProjectConfig(key: "even", prefix: "EVEN",
                                   jiraBaseUrl: "https://jira.example",
                                   tasksPathAbsolute: "/tasks/even",
                                   docsPathAbsolute: "/docs/even",
                                   kbPathAbsolute: "/wissen/even",
                                   repoDir: repoDir.path,
                                   forge: nil)
        try ClaudeProjectFile.write(for: withKB)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("\"kbPath\""), text)
        XCTAssertEqual(ClaudeProjectFile.read(repoDir: repoDir.path)?.kbPath, "/wissen/even")
    }

    /// Und ohne: kein leerer Schlüssel, sondern gar keiner.
    func testKbPathIsOmittedWhenUnset() throws {
        try ClaudeProjectFile.write(for: project)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("kbPath"), text)
    }

    // MARK: - Docker-Stack ja/nein

    /// Mit Stack: `dockerStack: true` **und** `stackDomain` stehen in der Datei — die Skills brauchen
    /// beides, der eine Wert entscheidet über den Weg, der andere baut die URL.
    func testMitStackStehenBeideSchluesselInDerDatei() throws {
        try ClaudeProjectFile.write(for: project)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("\"dockerStack\" : true"), text)
        XCTAssertTrue(text.contains("\"stackDomain\""), text)
    }

    /// Ohne Stack: `dockerStack: false` steht drin (der Skill muss den Fall **sehen**), `stackDomain`
    /// nicht — eine TLD ohne Stack dahinter wäre eine Behauptung.
    func testOhneStackFehltStackDomainAberNichtDasFlag() throws {
        try ClaudeProjectFile.write(for: projectOhneStack)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("\"dockerStack\" : false"), text)
        XCTAssertFalse(text.contains("stackDomain"), text)
        XCTAssertNil(ClaudeProjectFile.read(repoDir: repoDir.path)?.stackDomain)
        XCTAssertEqual(ClaudeProjectFile.read(repoDir: repoDir.path)?.dockerStack, false)
    }

    /// `worktreePrefix` bleibt in **beiden** Fällen: Worktrees gibt es auch ohne Stack, sie werden dann
    /// nur mit `git worktree add` statt `iwf worktree create` angelegt.
    func testWorktreePrefixStehtInBeidenFaellen() {
        XCTAssertEqual(ClaudeProjectFile.values(for: project).worktreePrefix,
                       repoDir.path + "-worktree")
        XCTAssertEqual(ClaudeProjectFile.values(for: projectOhneStack).worktreePrefix,
                       repoDir.path + "-worktree")
    }

    // MARK: - Jira ja/nein

    /// Die Skills bauen daraus die JIRA-Zeile des Status-Blocks — ohne beides können sie sie weder
    /// schreiben noch korrekt weglassen.
    func testJiraBaseUrlAndUsesJiraAreWritten() throws {
        try ClaudeProjectFile.write(for: project)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("\"jiraBaseUrl\""), text)
        XCTAssertTrue(text.contains("\"usesJira\" : true"), text)
        let values = ClaudeProjectFile.read(repoDir: repoDir.path)
        XCTAssertEqual(values?.jiraBaseUrl, "https://jira.example")
        XCTAssertEqual(values?.usesJira, true)
    }

    /// Projekt ohne Jira-Anbindung: `usesJira: false` steht in der Datei, die Basis-URL fehlt.
    /// `projectOhneStack` ist das echte Beispiel — `kanban` hat weder Stack noch Jira.
    func testProjectWithoutJiraIsMarkedAndHasNoBaseUrl() throws {
        try ClaudeProjectFile.write(for: projectOhneStack)
        let values = ClaudeProjectFile.read(repoDir: repoDir.path)
        XCTAssertEqual(values?.usesJira, false)
        XCTAssertNil(values?.jiraBaseUrl)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("jiraBaseUrl"), text)
    }

    func testWriteReadRoundtripAndIdempotence() throws {
        XCTAssertTrue(try ClaudeProjectFile.write(for: project))
        XCTAssertEqual(ClaudeProjectFile.read(repoDir: repoDir.path),
                       ClaudeProjectFile.values(for: project))
        // Unverändert → kein zweiter Write (kein mtime-Rauschen für File-Watcher).
        XCTAssertFalse(try ClaudeProjectFile.write(for: project))
    }

    /// Ein GitHub-Projekt führt `forge`/`forgeProjectPath` — und **keinen** `gitlabProjectPath`:
    /// der alte Schlüssel behauptete sonst einen GitLab-Pfad, den es nicht gibt.
    func testGithubProjectWritesForgeAndNoGitlabPath() throws {
        let onGithub = ProjectConfig(key: "kanban", prefix: "KANBAN",
                                     jiraBaseUrl: "",
                                     tasksPathAbsolute: "/tasks/kanban",
                                     docsPathAbsolute: "/docs/kanban",
                                     repoDir: repoDir.path,
                                     forge: ForgeRef(kind: .github, path: "krizzzly/kanban"),
                                     usesJira: false)
        let values = ClaudeProjectFile.values(for: onGithub)
        XCTAssertEqual(values.forge, "github")
        XCTAssertEqual(values.forgeProjectPath, "krizzzly/kanban")
        XCTAssertNil(values.gitlabProjectPath)

        try ClaudeProjectFile.write(for: onGithub)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("gitlabProjectPath"), text)
    }

    func testWriteIsStableJSONWithTrailingNewline() throws {
        try ClaudeProjectFile.write(for: project)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertTrue(text.contains("\"generatedBy\""))
        // sortedKeys → deterministische Reihenfolge, diff-freundlich
        let gitlabPos = text.range(of: "gitlabProjectPath")!.lowerBound
        let prefixPos = text.range(of: "\"prefix\"")!.lowerBound
        XCTAssertLessThan(gitlabPos, prefixPos)
    }
}
