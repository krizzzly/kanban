import Foundation

/// Generiert `<repo>/.claude/project.json` — die Übersetzung von Kanbans Config in die Projektwerte,
/// die die kanonischen (projektunabhängigen) Skills/Rules zur Laufzeit nachschlagen.
///
/// Die Datei ist bewusst **generiert, nicht gepflegt**: Quelle der Wahrheit ist Kanbans Config;
/// Kanban schreibt sie beim Projektwechsel neu. `.claude/` ist in den Projekt-Repos gitignored, der
/// Write betrifft also keine Kollegen.
///
/// Teilen sich zwei Projekte ein Repo (`support` lebt in `even`), teilen sie sich auch diese Datei —
/// es gewinnt das zuletzt gewählte. Das war schon so, fällt mit `docsPath` aber mehr auf.
public enum ClaudeProjectFile {
    public struct Values: Codable, Equatable, Sendable {
        public let prefix: String            // Jira-Präfix, z.B. "EVEN"
        public let tasksPath: String         // absoluter Task-File-Ordner
        public let docsPath: String          // absoluter Ordner der Projekt-Doku (Confluence-Exporte)
        /// Absoluter Ordner der Knowledgebase — **fehlt**, wenn keiner konfiguriert ist. Ein Skill
        /// soll den Unterschied sehen zwischen „hier ist die Knowledgebase" und „es gibt keine".
        public let kbPath: String?
        public let repoDir: String           // absolutes Haupt-Repo
        /// Ordner der Worktrees: `<repoDir>-worktree`. Steht in **beiden** Fällen in der Datei —
        /// Worktrees gibt es auch ohne Stack, dann eben als reine Git-Worktrees.
        public let worktreePrefix: String
        /// Hat das Projekt einen eigenen Docker-Stack? Der Wert, an dem die Skills verzweigen:
        /// `false` heisst `git worktree add` statt `iwf worktree create`, kein Netbird-Pre-Flight,
        /// keine Stack-Zeile im Task-File und Testläufe direkt im Worktree statt über `docker exec`.
        public let dockerStack: Bool
        /// TLD des lokalen Stacks; URL = `https://<worktree-name>.<stackDomain>`. **Fehlt** ohne
        /// Stack: ein Wert, hinter dem keine Domain steht, wäre eine Behauptung.
        public let stackDomain: String?
        public let gitlabProjectPath: String?
        /// Hinweis an menschliche Leser — Kanban überschreibt die Datei beim Projektwechsel.
        public let generatedBy: String
    }

    public static let fileName = ".claude/project.json"

    public static func values(for project: ProjectConfig) -> Values {
        Values(prefix: project.prefix,
               tasksPath: project.tasksPathAbsolute,
               docsPath: project.docsPathAbsolute,
               kbPath: project.kbPathAbsolute,
               repoDir: project.repoDir,
               worktreePrefix: project.repoDir + "-worktree",
               dockerStack: project.usesDockerStack,
               stackDomain: project.usesDockerStack ? "test" : nil,
               gitlabProjectPath: project.gitlabProjectPath,
               generatedBy: "Kanban — generiert aus der Kanban-Config, nicht von Hand editieren")
    }

    /// Schreibt die Datei nur bei inhaltlicher Änderung (kein mtime-Rauschen für File-Watcher).
    /// Liefert true, wenn geschrieben wurde.
    @discardableResult
    public static func write(for project: ProjectConfig) throws -> Bool {
        let url = URL(fileURLWithPath: project.repoDir).appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(values(for: project))
        data.append(UInt8(ascii: "\n"))

        if let existing = try? Data(contentsOf: url), existing == data { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return true
    }

    /// Liest die aktuell generierten Werte (nil, wenn keine Datei existiert oder sie fremd ist).
    public static func read(repoDir: String) -> Values? {
        let url = URL(fileURLWithPath: repoDir).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Values.self, from: data)
    }
}
