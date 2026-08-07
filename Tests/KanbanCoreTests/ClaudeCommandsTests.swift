import XCTest
@testable import KanbanCore

final class ClaudeCommandsTests: XCTestCase {
    private var repoDir: URL!
    private var userDir: URL!   // Ersatz für ~/.claude/commands — der echte darf nicht reinspielen

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-cmd-tests-\(UUID().uuidString)")
        repoDir = base.appendingPathComponent("repo")
        userDir = base.appendingPathComponent("user-commands")
        try FileManager.default.createDirectory(
            at: repoDir.appendingPathComponent(".claude/commands"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir.deletingLastPathComponent())
    }

    private func write(_ name: String, _ content: String, user: Bool = false) throws {
        let url = user ? userDir.appendingPathComponent("\(name).md")
                       : repoDir.appendingPathComponent(".claude/commands/\(name).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func scan(only names: [String]? = nil) -> [ClaudeCommand] {
        if let names {
            return ClaudeCommandScanner.scan(repoDir: repoDir.path, only: names,
                                             userCommandsDir: userDir)
        }
        return ClaudeCommandScanner.scan(repoDir: repoDir.path, userCommandsDir: userDir)
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

        let commands = scan()
        XCTAssertEqual(commands.map(\.name), ["solve-task", "start-serena"])
        XCTAssertEqual(commands[0].description, "Setze einen Task um")
        XCTAssertEqual(commands[0].argumentHint, "<TICKET-NUMMER> [--no-worktree]")
        XCTAssertEqual(commands[0].level, .project)
        XCTAssertNil(commands[1].description)
    }

    func testScanOnlyFiltersAndKeepsGivenOrder() throws {
        for name in ["create-task", "get-task", "review-task", "solve-task"] {
            try write(name, "---\ndescription: \(name)\n---\n")
        }

        let commands = scan(only: ["get-task", "start-task", "solve-task", "review-task"])
        // Workflow order, start-task (not defined) skipped, create-task not requested.
        XCTAssertEqual(commands.map(\.name), ["get-task", "solve-task", "review-task"])
    }

    /// Die User-Ebene gilt in jedem Projekt — auch ohne Projektkopie erscheint der Command.
    func testUserLevelCommandsAppear() throws {
        try write("get-task", "---\ndescription: zentral\n---\n", user: true)

        let commands = scan()
        XCTAssertEqual(commands.map(\.name), ["get-task"])
        XCTAssertEqual(commands[0].level, .user)
        XCTAssertNil(commands[0].shadowedProjectURL)
    }

    /// Empirisch verifizierte Präzedenz (CC 2.1.222): User-Ebene überdeckt die Projektkopie.
    func testUserLevelShadowsProjectCopy() throws {
        try write("get-task", "---\ndescription: zentral\n---\n", user: true)
        try write("get-task", "---\ndescription: projektkopie\n---\n")
        try write("testing", "---\ndescription: nur projekt\n---\n")

        let commands = scan()
        XCTAssertEqual(commands.map(\.name), ["get-task", "testing"])
        XCTAssertEqual(commands[0].level, .user)
        XCTAssertEqual(commands[0].description, "zentral")
        XCTAssertNotNil(commands[0].shadowedProjectURL)
        XCTAssertEqual(commands[1].level, .project)
    }

    func testMissingDirectoryYieldsEmpty() {
        let commands = ClaudeCommandScanner.scan(
            repoDir: "/nonexistent/repo",
            userCommandsDir: userDir.appendingPathComponent("gibtsnicht"))
        XCTAssertEqual(commands, [])
    }
}
