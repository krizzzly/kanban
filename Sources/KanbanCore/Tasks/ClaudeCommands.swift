import Foundation

/// Ein Workflow-Asset, das Kanban in die Console tippt (`/<name> <args>` bei Claude,
/// `$<name> <args>` bei Codex — siehe `AgentKind.commandPrefix`).
///
/// Quelle ist normalerweise ein **Skill** (`skills/<name>/SKILL.md`) auf User- oder Projekt-Ebene;
/// gleichnamige Alt-Commands (`commands/<name>.md`, nur Claude) werden weiter gefunden, damit von
/// Hand angelegte Projekt-Commands nicht verschwinden.
public struct ClaudeCommand: Sendable, Hashable, Identifiable {
    public enum Level: String, Sendable {
        case user, project
    }

    public let name: String          // Skill-Ordner bzw. Dateiname ohne .md → "/name" / "$name"
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

/// Liest die Workflow-Assets, die in einem Projekt gelten: User-Ebene plus Projekt-Ebene, für den
/// Agent dieses Projekts (`~/.claude/…` bzw. `~/.codex/…`).
///
/// Bei Namensgleichheit gewinnt die **User-Ebene** — empirisch verifiziert am 2026-08-07 mit
/// Claude Code 2.1.222 (gleichnamiger Command auf beiden Ebenen via `claude -p`, zweimal
/// reproduziert plus Gegenprobe ohne User-Kopie). Die verbreitete Annahme „Projekt sticht User"
/// stimmt nicht; überdeckte Projektkopien werden als `shadowedProjectURL` ausgewiesen.
///
/// Innerhalb einer Ebene sticht der **Skill** den gleichnamigen Alt-Command: das ist die Gattung, die
/// Kanban ausliefert, und die einzige, die beide Agents lesen.
public enum ClaudeCommandScanner {
    /// `~/.claude/commands` — Altbestand; der kanonische Bestand liegt heute unter `skills/`.
    public static var defaultUserCommandsDir: URL {
        AgentKind.claude.userCommandsDir!
    }

    /// Alle Assets, die im Projekt gelten, alphabetisch. Fehlende Ordner → leer.
    ///
    /// `userSkillsDir`/`userCommandsDir` sind nur für Tests da; im Betrieb ergeben sie sich aus dem
    /// Agent (Codex hat keinen Commands-Ordner, dort bleibt der zweite Weg leer).
    public static func scan(repoDir: String,
                            agent: AgentKind = .claude,
                            userSkillsDir: URL? = nil,
                            userCommandsDir: URL? = nil) -> [ClaudeCommand] {
        let projectRoot = URL(fileURLWithPath: repoDir)
            .appendingPathComponent(agent.projectDirName, isDirectory: true)
        let project = merged(skills: skillFiles(in: projectRoot.appendingPathComponent("skills")),
                             commands: commandFiles(in: projectRoot.appendingPathComponent("commands")))
        let user = merged(
            skills: skillFiles(in: userSkillsDir ?? agent.userSkillsDir),
            commands: commandFiles(in: userCommandsDir ?? agent.userCommandsDir))

        var commands = user.map { name, url in
            command(name: name, url: url, level: .user, shadowedProjectURL: project[name])
        }
        commands += project
            .filter { user[$0.key] == nil }
            .map { command(name: $0.key, url: $0.value, level: .project, shadowedProjectURL: nil) }
        return commands.sorted { $0.name < $1.name }
    }

    /// The subset of `scan` matching `names`, returned in the order of `names`
    /// (workflow order, not alphabetical). Assets neither level defines are skipped.
    public static func scan(repoDir: String, only names: [String],
                            agent: AgentKind = .claude,
                            userSkillsDir: URL? = nil,
                            userCommandsDir: URL? = nil) -> [ClaudeCommand] {
        let all = Dictionary(uniqueKeysWithValues:
            scan(repoDir: repoDir, agent: agent, userSkillsDir: userSkillsDir,
                 userCommandsDir: userCommandsDir).map { ($0.name, $0) })
        return names.compactMap { all[$0] }
    }

    /// Skill sticht Alt-Command bei gleichem Namen.
    private static func merged(skills: [String: URL], commands: [String: URL]) -> [String: URL] {
        commands.merging(skills) { _, skill in skill }
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
    private static func commandFiles(in dir: URL?) -> [String: URL] {
        guard let dir, let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries
            .filter { $0.pathExtension == "md" }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) })
    }

    /// `name → SKILL.md` eines Skills-Ordners. Der Name ist der **Ordner** (so ruft man den Skill
    /// auf), nicht das Frontmatter — ein abweichendes `name:` wäre in beiden Agents wirkungslos.
    /// Symlinks auf Ordner zählen wie Ordner, genau so liegt der kanonische Bestand da.
    private static func skillFiles(in dir: URL) -> [String: URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [:] }
        var result: [String: URL] = [:]
        for entry in entries {
            let skill = entry.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skill.path) else { continue }
            result[entry.lastPathComponent] = skill
        }
        return result
    }

    // MARK: - Aus dem Skill-Set statt von der Platte

    /// Die Skills eines Sets — **alle**, die das Set anbietet.
    ///
    /// Das ist die Quelle für das Command-Menü am Ticket, und zwar bewusst das **Set** und nicht
    /// der Scan der Zielorte: was ein Projekt sieht, ist sein Set, nicht die Vereinigung aus
    /// Projekt-Ebene und Agent-Home. Ein Skill, der einem Set dazukommt, steht damit ohne
    /// Codeänderung im Menü — vorher entschied das eine fest verdrahtete Liste aus vier Namen.
    ///
    /// - Parameter first: Namen, die vorn stehen sollen (Workflow-Reihenfolge). Alles andere folgt
    ///   alphabetisch; ein Name, den das Set nicht führt, wird übersprungen.
    public static func commands(in set: ClaudeAssetSet, first: [String] = []) -> [ClaudeCommand] {
        let skills = ClaudeAssetStore.assets(.skill, in: set)
        let nachName = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0) })
        let vorn = first.compactMap { nachName[$0] }
        let rest = skills.filter { !first.contains($0.name) }   // `assets` liefert bereits sortiert
        return (vorn + rest).map { skill in
            command(name: skill.name, url: skill.url.appendingPathComponent("SKILL.md"),
                    level: .project, shadowedProjectURL: nil)
        }
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
