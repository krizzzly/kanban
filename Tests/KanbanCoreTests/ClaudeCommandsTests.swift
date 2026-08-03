import XCTest
@testable import KanbanCore

final class ClaudeCommandsTests: XCTestCase {
    private var repoDir: URL!

    override func setUpWithError() throws {
        repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-cmd-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: repoDir.appendingPathComponent(".claude/commands"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir)
    }

    private func write(_ name: String, _ content: String) throws {
        let url = repoDir.appendingPathComponent(".claude/commands/\(name).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func testScanReadsFrontmatter() throws {
        try write("solve-task", """
        ---
        description: Setze einen Task um
        argument-hint: <TICKET-NUMMER> [--no-worktree]
        ---
        Body $ARGUMENTS
        """)
        try write("start-serena", "No frontmatter at all.")

        let commands = ClaudeCommandScanner.scan(repoDir: repoDir.path)
        XCTAssertEqual(commands.map(\.name), ["solve-task", "start-serena"])
        XCTAssertEqual(commands[0].description, "Setze einen Task um")
        XCTAssertEqual(commands[0].argumentHint, "<TICKET-NUMMER> [--no-worktree]")
        XCTAssertNil(commands[1].description)
    }

    func testScanOnlyFiltersAndKeepsGivenOrder() throws {
        for name in ["create-task", "get-task", "review-task", "solve-task"] {
            try write(name, "---\ndescription: \(name)\n---\n")
        }

        let commands = ClaudeCommandScanner.scan(
            repoDir: repoDir.path,
            only: ["get-task", "start-task", "solve-task", "review-task"])
        // Workflow order, start-task (not defined) skipped, create-task not requested.
        XCTAssertEqual(commands.map(\.name), ["get-task", "solve-task", "review-task"])
    }

    func testMissingDirectoryYieldsEmpty() {
        XCTAssertEqual(ClaudeCommandScanner.scan(repoDir: "/nonexistent/repo"), [])
    }
}
