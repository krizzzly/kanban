import XCTest
@testable import KanbanCore

final class JiraLineMigrationTests: XCTestCase {
    private var tasksDir: URL!

    override func setUpWithError() throws {
        tasksDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-line-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tasksDir)
    }

    private func project(prefix: String = "EVEN",
                         baseUrl: String = "https://jira.example.com",
                         usesJira: Bool = true) -> ProjectConfig {
        ProjectConfig(key: "even", prefix: prefix, jiraBaseUrl: baseUrl,
                      tasksPathAbsolute: tasksDir.path,
                      repoDir: "/Users/x/code/even", gitlabProjectPath: nil,
                      usesJira: usesJira)
    }

    @discardableResult
    private func write(_ name: String, _ content: String) throws -> URL {
        let url = tasksDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: tasksDir.appendingPathComponent(name), encoding: .utf8)
    }

    /// Der Regelfall: Task-File mit Block → die Zeile steht danach als erste Blockzeile in der Datei.
    func testWritesJiraLineIntoExistingBlock() throws {
        try write("EVEN-3530_status.md", """
        # EVEN-3530 - Ausführungskontrolle

        > 🌳 **WORKTREE**: `/Users/x/code/even-worktree/EVEN-3530`\\
        > 🌿 **BRANCH**: `feature/EVEN-3530_status`

        ## Beschreibung
        """)

        let report = JiraLineMigration.run(for: project(), apply: true)

        XCTAssertNil(report.skippedReason)
        XCTAssertEqual(report.changed.map(\.key), ["EVEN-3530"])
        let out = try read("EVEN-3530_status.md")
        XCTAssertTrue(out.contains(
            "> 🎫 **JIRA**: `https://jira.example.com/browse/EVEN-3530`\\\n> 🌳 **WORKTREE**"), out)
        // Der Rest der Datei bleibt, wie er war.
        XCTAssertTrue(out.hasSuffix("## Beschreibung"))
        XCTAssertEqual(LocalTickets.branch(inHead: out), "feature/EVEN-3530_status")
    }

    /// Ohne Block (`--no-worktree`) entsteht ein eigener Blockquote unter der H1.
    func testWritesOwnBlockWhenFileHasNone() throws {
        try write("EVEN-1_ohne_worktree.md", "# EVEN-1 - Ohne Worktree\n\nTyp: Task\n")

        JiraLineMigration.run(for: project(), apply: true)

        XCTAssertEqual(try read("EVEN-1_ohne_worktree.md"),
                       "# EVEN-1 - Ohne Worktree\n\n> 🎫 **JIRA**: `https://jira.example.com/browse/EVEN-1`\n\nTyp: Task\n")
    }

    /// Eine Datei, die die Zeile schon führt, wird nicht angefasst — auch nicht, wenn eine andere
    /// URL drinsteht. Die Datei gewinnt.
    func testFileWithJiraLineIsLeftAlone() throws {
        let content = "# EVEN-2 - X\n\n> 🎫 **JIRA**: `https://anders.example/browse/EVEN-2`\\\n> 🌿 **BRANCH**: `feature/x`\n"
        try write("EVEN-2_x.md", content)

        let report = JiraLineMigration.run(for: project(), apply: true)

        XCTAssertTrue(report.changed.isEmpty)
        XCTAssertEqual(report.alreadyPresent, 1)
        XCTAssertEqual(try read("EVEN-2_x.md"), content)
    }

    /// Review-Files sind Tabs am Ticket, keine eigenen Karten — und `!<iid>`-Karten haben kein
    /// Jira-Issue. Fremde Präfixe gehören einem anderen Projekt (geteilte Task-Ordner).
    func testReviewFilesMrCardsAndForeignPrefixesAreIgnored() throws {
        try write("EVEN-3_review.md", "# Review EVEN-3\n\nText\n")
        try write("!49_cli_option.md", "# !49 - CLI-Option\n\n> 🌿 **BRANCH**: `feature/x`\n")
        try write("ZVMSUPPORT-7_fremd.md", "# ZVMSUPPORT-7 - Fremd\n\nText\n")

        let report = JiraLineMigration.run(for: project(), apply: true)

        XCTAssertTrue(report.changed.isEmpty)
        XCTAssertEqual(report.ignored, 3)
        XCTAssertFalse(try read("EVEN-3_review.md").contains("JIRA"))
        XCTAssertFalse(try read("!49_cli_option.md").contains("JIRA"))
        XCTAssertFalse(try read("ZVMSUPPORT-7_fremd.md").contains("JIRA"))
    }

    /// Ohne H1 gibt es keine Stelle, unter die der Block gehört.
    func testFileWithoutHeadingIsLeftAlone() throws {
        try write("EVEN-4_kopflos.md", "Typ: Task\n\n## Beschreibung\n")

        let report = JiraLineMigration.run(for: project(), apply: true)

        XCTAssertTrue(report.changed.isEmpty)
        XCTAssertEqual(report.withoutHeading, 1)
        XCTAssertEqual(try read("EVEN-4_kopflos.md"), "Typ: Task\n\n## Beschreibung\n")
    }

    /// Der Trockenlauf meldet, was er schriebe — und schreibt nichts.
    func testDryRunReportsWithoutWriting() throws {
        let content = "# EVEN-5 - X\n\n> 🌿 **BRANCH**: `feature/x`\n"
        try write("EVEN-5_x.md", content)

        let report = JiraLineMigration.run(for: project(), apply: false)

        XCTAssertEqual(report.changed.map(\.url), ["https://jira.example.com/browse/EVEN-5"])
        XCTAssertEqual(try read("EVEN-5_x.md"), content)
    }

    /// Ein Projekt ohne Jira-Anbindung wird gar nicht erst durchlaufen.
    func testProjectWithoutJiraIsSkipped() throws {
        try write("EVEN-6_x.md", "# EVEN-6 - X\n\n> 🌿 **BRANCH**: `feature/x`\n")

        let report = JiraLineMigration.run(for: project(usesJira: false), apply: true)

        XCTAssertEqual(report.skippedReason, "useJira: false")
        XCTAssertFalse(try read("EVEN-6_x.md").contains("JIRA"))
    }

    /// Und eines ohne Basis-URL ebenso — es gäbe nichts zu verlinken.
    func testProjectWithoutBaseUrlIsSkipped() throws {
        try write("EVEN-7_x.md", "# EVEN-7 - X\n\n> 🌿 **BRANCH**: `feature/x`\n")

        let report = JiraLineMigration.run(for: project(baseUrl: ""), apply: true)

        XCTAssertEqual(report.skippedReason, "keine Jira-Basis-URL")
        XCTAssertFalse(try read("EVEN-7_x.md").contains("JIRA"))
    }

    /// `**JIRA**` im Fliesstext ist keine JIRA-Zeile — nur der Block unter der H1 zählt. Sonst hielte
    /// die Migration ausgerechnet die Datei für erledigt, die diese Zeile beschreibt.
    func testJiraMentionInBodyTextDoesNotCountAsBlockLine() throws {
        try write("EVEN-9_doku.md", "# EVEN-9 - X\n\n> 🌿 **BRANCH**: `feature/x`\n\n## Beschreibung\n\nDie Zeile `🎫 **JIRA**: <URL>` gehört in den Block.\n")

        let report = JiraLineMigration.run(for: project(), apply: true)

        XCTAssertEqual(report.changed.map(\.key), ["EVEN-9"])
        XCTAssertTrue(try read("EVEN-9_doku.md").contains(
            "> 🎫 **JIRA**: `https://jira.example.com/browse/EVEN-9`\\\n> 🌿 **BRANCH**"))
    }

    /// Zweimal laufen lassen ändert beim zweiten Mal nichts mehr.
    func testSecondRunIsANoOp() throws {
        try write("EVEN-8_x.md", "# EVEN-8 - X\n\n> 🌿 **BRANCH**: `feature/x`\n")

        JiraLineMigration.run(for: project(), apply: true)
        let afterFirst = try read("EVEN-8_x.md")
        let second = JiraLineMigration.run(for: project(), apply: true)

        XCTAssertTrue(second.changed.isEmpty)
        XCTAssertEqual(second.alreadyPresent, 1)
        XCTAssertEqual(try read("EVEN-8_x.md"), afterFirst)
    }
}
