import Foundation

/// A project slash command from `<repo>/.claude/commands/<name>.md`, invocable in the Claude
/// console as `/<name> <args>`.
public struct ClaudeCommand: Sendable, Hashable, Identifiable {
    public let name: String          // filename without .md → "/name"
    public let description: String?  // frontmatter `description:`
    public let argumentHint: String? // frontmatter `argument-hint:`

    public var id: String { name }

    public init(name: String, description: String?, argumentHint: String?) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
    }
}

/// Reads the slash commands a project defines in `<repoDir>/.claude/commands/*.md`.
public enum ClaudeCommandScanner {
    /// All commands in the project, alphabetically. Missing directory → empty.
    public static func scan(repoDir: String) -> [ClaudeCommand] {
        let dir = URL(fileURLWithPath: repoDir).appendingPathComponent(".claude/commands")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> ClaudeCommand? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let front = frontmatter(of: content)
                return ClaudeCommand(name: url.deletingPathExtension().lastPathComponent,
                                     description: front["description"],
                                     argumentHint: front["argument-hint"])
            }
            .sorted { $0.name < $1.name }
    }

    /// The subset of `scan` matching `names`, returned in the order of `names`
    /// (workflow order, not alphabetical). Commands the project doesn't define are skipped.
    public static func scan(repoDir: String, only names: [String]) -> [ClaudeCommand] {
        let all = Dictionary(uniqueKeysWithValues: scan(repoDir: repoDir).map { ($0.name, $0) })
        return names.compactMap { all[$0] }
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
