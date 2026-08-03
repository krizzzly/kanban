import XCTest
@testable import KanbanCore

final class ClaudeTranscriptsTests: XCTestCase {
    private var claudeDir: URL!

    override func setUpWithError() throws {
        claudeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-claude-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: claudeDir)
    }

    func testProjectDirNameReplacesNonAlphanumerics() {
        XCTAssertEqual(
            ClaudeTranscripts.projectDirName(forCwd: "/Users/x/code/mv-cc.statusline_2"),
            "-Users-x-code-mv-cc-statusline-2")
    }

    func testProjectDirNameResolvesSymlinks() {
        // /tmp is a symlink to /private/tmp on macOS — Claude stores under the resolved path.
        XCTAssertEqual(ClaudeTranscripts.projectDirName(forCwd: "/tmp"), "-private-tmp")
    }

    func testTranscriptExists() throws {
        let cwd = "/Users/x/code/even"
        let slug = ClaudeTranscripts.projectDirName(forCwd: cwd)
        let id = "a88a4670-6d58-4342-a84d-76b5b66b8df7"

        XCTAssertFalse(ClaudeTranscripts.transcriptExists(
            sessionId: id, cwd: cwd, claudeDir: claudeDir.path))

        let dir = claudeDir.appendingPathComponent("projects/\(slug)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{}".write(to: dir.appendingPathComponent("\(id).jsonl"), atomically: true, encoding: .utf8)

        XCTAssertTrue(ClaudeTranscripts.transcriptExists(
            sessionId: id, cwd: cwd, claudeDir: claudeDir.path))
    }
}
