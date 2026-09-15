import XCTest
@testable import KanbanCore

final class ClaudeCommandsTests: XCTestCase {
    private var repoDir: URL!
    private var userSkillsDir: URL!     // Ersatz für ~/.claude/skills bzw. ~/.codex/skills
    private var userCommandsDir: URL!   // Ersatz für ~/.claude/commands (Altbestand)

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-cmd-tests-\(UUID().uuidString)")
        repoDir = base.appendingPathComponent("repo")
        userSkillsDir = base.appendingPathComponent("user-skills")
        userCommandsDir = base.appendingPathComponent("user-commands")
        for dir in [repoDir.appendingPathComponent(".claude/commands"),
                    repoDir.appendingPathComponent(".claude/skills"),
                    userSkillsDir!, userCommandsDir!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir.deletingLastPathComponent())
    }

    // MARK: Schreibhilfen

    /// Alt-Command: eine .md-Datei.
    private func write(_ name: String, _ content: String, user: Bool = false) throws {
        let url = user ? userCommandsDir.appendingPathComponent("\(name).md")
                       : repoDir.appendingPathComponent(".claude/commands/\(name).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Skill: ein Ordner mit SKILL.md — die Gattung, die Kanban ausliefert.
    private func writeSkill(_ name: String, _ content: String, user: Bool = false,
                            agentDir: String = ".claude") throws {
        let dir = user ? userSkillsDir.appendingPathComponent(name, isDirectory: true)
                       : repoDir.appendingPathComponent("\(agentDir)/skills/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func scan(only names: [String]? = nil, agent: AgentKind = .claude) -> [ClaudeCommand] {
        if let names {
            return ClaudeCommandScanner.scan(repoDir: repoDir.path, only: names, agent: agent,
                                             userSkillsDir: userSkillsDir,
                                             userCommandsDir: userCommandsDir)
        }
        return ClaudeCommandScanner.scan(repoDir: repoDir.path, agent: agent,
                                         userSkillsDir: userSkillsDir,
                                         userCommandsDir: userCommandsDir)
    }

    // MARK: Alt-Commands (weiter lesbar)

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
            userSkillsDir: userSkillsDir.appendingPathComponent("gibtsnicht"),
            userCommandsDir: userCommandsDir.appendingPathComponent("gibtsnicht"))
        XCTAssertEqual(commands, [])
    }

    // MARK: Skills — die Gattung, die Kanban ausliefert

    func testSkillsAreFoundLikeCommands() throws {
        try writeSkill("get-task", """
        ---
        name: get-task
        description: Lade ein JIRA-Ticket
        argument-hint: <TICKET-NUMMER>
        disable-model-invocation: true
        ---
        Lies $ARGUMENTS
        """, user: true)

        let commands = scan()
        XCTAssertEqual(commands.map(\.name), ["get-task"])
        XCTAssertEqual(commands[0].description, "Lade ein JIRA-Ticket")
        XCTAssertEqual(commands[0].argumentHint, "<TICKET-NUMMER>")
        XCTAssertEqual(commands[0].level, .user)
    }

    /// Der Name ist der **Ordner**, nicht das Frontmatter — so ruft man den Skill in beiden Agents auf.
    func testSkillNameComesFromTheDirectory() throws {
        try writeSkill("get-task", "---\nname: voelliger-unsinn\ndescription: x\n---\n", user: true)
        XCTAssertEqual(scan().map(\.name), ["get-task"])
    }

    /// Ein Ordner ohne SKILL.md ist kein Skill (z. B. ein Beiwerk-Verzeichnis).
    func testDirectoryWithoutSkillFileIsIgnored() throws {
        try FileManager.default.createDirectory(
            at: userSkillsDir.appendingPathComponent("references"), withIntermediateDirectories: true)
        XCTAssertEqual(scan(), [])
    }

    /// Nach dem Umzug kann beides herumliegen; der Skill ist die neue Wahrheit.
    func testSkillBeatsLegacyCommandOnTheSameLevel() throws {
        try write("get-task", "---\ndescription: alt\n---\n", user: true)
        try writeSkill("get-task", "---\nname: get-task\ndescription: neu\n---\n", user: true)

        let commands = scan()
        XCTAssertEqual(commands.map(\.name), ["get-task"])
        XCTAssertEqual(commands[0].description, "neu")
    }

    /// Codex liest `~/.codex/skills` und `<repo>/.codex/skills` — und hat keine Commands.
    func testCodexReadsItsOwnProjectDirAndNoCommands() throws {
        try write("nur-claude", "---\ndescription: alt\n---\n")                  // .claude/commands
        try writeSkill("nur-claude-skill", "---\ndescription: x\n---\n")         // .claude/skills
        try writeSkill("codex-skill", "---\ndescription: y\n---\n", agentDir: ".codex")

        let codex = ClaudeCommandScanner.scan(repoDir: repoDir.path, agent: .codex,
                                              userSkillsDir: userSkillsDir)
        XCTAssertEqual(codex.map(\.name), ["codex-skill"])

        let claude = scan()
        XCTAssertEqual(claude.map(\.name), ["nur-claude", "nur-claude-skill"])
    }
}
