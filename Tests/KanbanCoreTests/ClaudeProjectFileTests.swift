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
                      repoDir: repoDir.path,
                      gitlabProjectPath: "applications/even")
    }

    func testValuesDeriveWorktreePrefixAndDomain() {
        let values = ClaudeProjectFile.values(for: project)
        XCTAssertEqual(values.prefix, "EVEN")
        XCTAssertEqual(values.worktreePrefix, repoDir.path + "-worktree")
        XCTAssertEqual(values.stackDomain, "test")
        XCTAssertEqual(values.gitlabProjectPath, "applications/even")
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
