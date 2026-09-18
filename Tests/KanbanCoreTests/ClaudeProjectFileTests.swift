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
                      gitlabProjectPath: "applications/even")
    }

    func testValuesDeriveWorktreePrefixAndDomain() {
        let values = ClaudeProjectFile.values(for: project)
        XCTAssertEqual(values.prefix, "EVEN")
        XCTAssertEqual(values.worktreePrefix, repoDir.path + "-worktree")
        XCTAssertEqual(values.stackDomain, "test")
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
                                   gitlabProjectPath: nil)
        try ClaudeProjectFile.write(for: withKB)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("\"kbPath\""), text)
        XCTAssertEqual(ClaudeProjectFile.read(repoDir: repoDir.path)?.kbPath, "/wissen/even")
    }

    /// Das **aufgelöste** Set steht in der Datei — ein Skill soll wissen, mit welchem Satz er
    /// gerade läuft, nicht, was jemand einmal in die Config geschrieben hat.
    func testSkillSetIsWrittenWhenResolved() throws {
        try ClaudeProjectFile.write(for: project, skillSet: "iwf")
        XCTAssertEqual(ClaudeProjectFile.read(repoDir: repoDir.path)?.skillSet, "iwf")

        // Gibt es gar kein Set, fehlt der Schlüssel — wie bei `kbPath`.
        try FileManager.default.removeItem(at: repoDir.appendingPathComponent(".claude/project.json"))
        try ClaudeProjectFile.write(for: project)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("skillSet"), text)
    }

    /// Und ohne: kein leerer Schlüssel, sondern gar keiner.
    func testKbPathIsOmittedWhenUnset() throws {
        try ClaudeProjectFile.write(for: project)
        let text = try String(contentsOf: repoDir.appendingPathComponent(".claude/project.json"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("kbPath"), text)
    }

    func testWriteReadRoundtripAndIdempotence() throws {
        XCTAssertTrue(try ClaudeProjectFile.write(for: project))
        XCTAssertEqual(ClaudeProjectFile.read(repoDir: repoDir.path),
                       ClaudeProjectFile.values(for: project))
        // Unverändert → kein zweiter Write (kein mtime-Rauschen für File-Watcher).
        XCTAssertFalse(try ClaudeProjectFile.write(for: project))
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
