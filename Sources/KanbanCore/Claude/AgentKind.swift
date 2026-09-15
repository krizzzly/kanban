import Foundation

/// Welcher Coding-Agent ein Projekt bedient. Die Wahl steht je Projekt in der Config
/// (`modules.jira.projects.<key>.agent`), Default ist Claude.
///
/// **Beide lesen dasselbe Asset-Format** — `SKILL.md` mit `description`/`argument-hint`/
/// `disable-model-invocation`, Argumente über `$ARGUMENTS`. Verifiziert am 2026-08-19: Claude Code
/// substituiert `$ARGUMENTS` in einem Skill (Probe-Skill mit Argumenten aufgerufen), Codex 0.147
/// listet ein Skill aus `~/.codex/skills` im `@`-Picker und fügt `$name` in den Composer ein; seine
/// eigene `skill-creator`-Anleitung nennt dieselben Frontmatter-Keys und dieselbe `$ARGUMENTS`-Syntax.
/// Deshalb gibt es **einen** kanonischen Bestand und nur diesen Typ, der die Unterschiede hält:
/// **Ort** (`~/.claude` vs. `~/.codex`) und **Präfix** (`/` vs. `$`).
public enum AgentKind: String, CaseIterable, Sendable, Codable {
    case claude
    case codex

    /// Was gilt, wenn die Config nichts sagt — Kanban ist auf Claude gewachsen.
    public static let fallback = AgentKind.claude

    /// Tolerant gegenüber der Config: unbekannt, leer oder fehlend → nil (der Aufrufer nimmt den
    /// Fallback). Ein Tippfehler soll ein Projekt nicht unbenutzbar machen.
    public init?(configValue: String?) {
        guard let raw = configValue?.trimmingCharacters(in: .whitespaces).lowercased(),
              !raw.isEmpty, let kind = AgentKind(rawValue: raw) else { return nil }
        self = kind
    }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex:  return "Codex"
        }
    }

    /// Was vor den Asset-Namen kommt, wenn Kanban ihn in die Console tippt.
    ///
    /// Codex hat **kein** `/name`: Custom Prompts (`~/.codex/prompts`) sind deprecated und seit
    /// 0.117 aus dem Slash-Menü verschwunden — verifiziert gegen 0.147, wo weder `/start` noch
    /// `/prompts:` einen Eintrag zeigt. Skills laufen dort über `$name`.
    public var commandPrefix: String {
        switch self {
        case .claude: return "/"
        case .codex:  return "$"
        }
    }

    /// Das Programm, das in der tmux-Session startet.
    public var executable: String { rawValue }

    /// `~/.claude` bzw. `~/.codex`.
    public var homeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".\(rawValue)", isDirectory: true)
    }

    /// Der Ort, an den `ClaudeAssetStore` die kanonischen Skills verlinkt — gilt in jedem Projekt.
    public var userSkillsDir: URL { homeDir.appendingPathComponent("skills", isDirectory: true) }

    /// Nur Claude kennt Commands als eigene Gattung. Codex hat ausschliesslich Skills, deshalb nil —
    /// dort wird nichts nach `prompts/` verlinkt, das wäre ein toter Ordner.
    public var userCommandsDir: URL? {
        switch self {
        case .claude: return homeDir.appendingPathComponent("commands", isDirectory: true)
        case .codex:  return nil
        }
    }

    /// Projekt-Ebene relativ zum Repo (`<repo>/.claude` bzw. `<repo>/.codex`).
    public var projectDirName: String { ".\(rawValue)" }

    /// Lässt sich die Session-Id beim Start vorgeben? `claude --session-id <uuid>` ja; Codex kennt
    /// nur `codex resume <id|name>` **nachträglich**, die Id erfindet es selbst.
    public var supportsPresetSessionId: Bool { self == .claude }
}
