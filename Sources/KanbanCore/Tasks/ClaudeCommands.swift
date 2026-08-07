import Foundation

/// A slash command visible in the Claude console (`/<name> <args>`), from either the project level
/// (`<repo>/.claude/commands/`) or the user level (`~/.claude/commands/`, gilt in jedem Projekt).
public struct ClaudeCommand: Sendable, Hashable, Identifiable {
    public enum Level: String, Sendable {
        case user, project
    }

    public let name: String          // filename without .md → "/name"
    public let description: String?  // frontmatter `description:`
    public let argumentHint: String? // frontmatter `argument-hint:`
    public let level: Level
    /// Gleichnamige Projektkopie, die von der User-Ebene überdeckt wird (Präzedenz siehe Scanner).
    public let shadowedProjectURL: URL?

    public var id: String { name }

    public init(name: String, description: String?, argumentHint: String?,
                level: Level = .project, shadowedProjectURL: URL? = nil) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.level = level
        self.shadowedProjectURL = shadowedProjectURL
    }
}

/// Reads the slash commands effective in a project: user level plus project level.
///
/// Bei Namensgleichheit gewinnt die **User-Ebene** — empirisch verifiziert am 2026-08-07 mit
/// Claude Code 2.1.222 (gleichnamiger Command auf beiden Ebenen via `claude -p`, zweimal
/// reproduziert plus Gegenprobe ohne User-Kopie). Die verbreitete Annahme „Projekt sticht User"
/// stimmt nicht; überdeckte Projektkopien werden als `shadowedProjectURL` ausgewiesen.
public enum ClaudeCommandScanner {
    /// `~/.claude/commands` — der Ort, an den `ClaudeAssetStore` die kanonischen Commands verlinkt.
    public static var defaultUserCommandsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/commands", isDirectory: true)
    }

    /// All commands effective in the project, alphabetically. Missing directories → empty.
    public static func scan(repoDir: String,
                            userCommandsDir: URL = defaultUserCommandsDir) -> [ClaudeCommand] {
        let projectDir = URL(fileURLWithPath: repoDir).appendingPathComponent(".claude/commands")
        let project = commandFiles(in: projectDir)
        let user = commandFiles(in: userCommandsDir)

        var commands = user.map { name, url in
            command(name: name, url: url, level: .user, shadowedProjectURL: project[name])
        }
        commands += project
            .filter { user[$0.key] == nil }
            .map { command(name: $0.key, url: $0.value, level: .project, shadowedProjectURL: nil) }
        return commands.sorted { $0.name < $1.name }
    }

    /// The subset of `scan` matching `names`, returned in the order of `names`
    /// (workflow order, not alphabetical). Commands neither level defines are skipped.
    public static func scan(repoDir: String, only names: [String],
                            userCommandsDir: URL = defaultUserCommandsDir) -> [ClaudeCommand] {
        let all = Dictionary(uniqueKeysWithValues:
            scan(repoDir: repoDir, userCommandsDir: userCommandsDir).map { ($0.name, $0) })
        return names.compactMap { all[$0] }
    }

    private static func command(name: String, url: URL, level: ClaudeCommand.Level,
                                shadowedProjectURL: URL?) -> ClaudeCommand {
        let front = (try? String(contentsOf: url, encoding: .utf8)).map(frontmatter) ?? [:]
        return ClaudeCommand(name: name,
                             description: front["description"],
                             argumentHint: front["argument-hint"],
                             level: level,
                             shadowedProjectURL: shadowedProjectURL)
    }

    /// `name → url` der .md-Dateien eines Command-Ordners; Symlinks zählen wie Dateien.
    private static func commandFiles(in dir: URL) -> [String: URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries
            .filter { $0.pathExtension == "md" }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) })
    }

    /// Minimal YAML frontmatter reader: `key: value` lines between the leading `---` fences.
    static func frontmatter(of content: String) -> [String: String] {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        lines = lines.dropFirst()
        var result: [String: String] = [:]
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty { result[key] = value }
        }
        return result
    }
}
