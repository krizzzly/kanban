import Foundation

/// Ein Command, der in die Skill-Form gezogen wurde.
public struct CommandToSkillMigration: Sendable, Hashable {
    public let name: String
    public let skillURL: URL        // neuer Ort: skills/<name>/SKILL.md
    public let removedSymlink: URL? // aufgeräumter Symlink in ~/.claude/commands, falls unser eigener
}

/// Einmal-Umzug des kanonischen Bestands: `commands/<name>.md` → `skills/<name>/SKILL.md`.
///
/// Nötig, weil Kanban die Workflow-Assets ab jetzt als **Skills** ausliefert — das ist die einzige
/// Gattung, die Claude Code *und* Codex kennen (siehe `AgentKind`). Der Umzug **verschiebt** die
/// Datei statt sie neu zu seeden: 7 von 10 Commands waren beim Bau dieses Wegs gegenüber dem
/// Auslieferungsstand editiert, ein Reseed hätte diese Arbeit weggeworfen.
///
/// Am Inhalt wird nur das Frontmatter ergänzt, und nur was fehlt: `name` (Codex braucht es) und
/// `disable-model-invocation: true`. Letzteres ist keine Kosmetik — als Command konnte
/// `destroy-worktree` nie von allein loslaufen, als Skill könnte es das.
///
/// Idempotent: existiert `skills/<name>/` schon, bleibt der Command liegen (nichts wird
/// überschrieben, nichts gelöscht) und taucht weiter im Editor auf.
public enum ClaudeAssetMigration {
    @discardableResult
    public static func migrateCommandsToSkills(store: ClaudeAssetStore) -> [CommandToSkillMigration] {
        var done: [CommandToSkillMigration] = []
        let fm = FileManager.default
        let skillsRoot = store.canonicalRoot.appendingPathComponent(ClaudeAssetKind.skill.rawValue,
                                                                    isDirectory: true)

        for command in store.assets(.command) {
            let skillDir = skillsRoot.appendingPathComponent(command.name, isDirectory: true)
            guard !fm.fileExists(atPath: skillDir.path) else { continue }

            // Zustand des alten Symlinks **vor** dem Verschieben festhalten — danach zeigt er ins Nichts.
            let staleLink = store.symlinkState(for: command, agent: .claude) == .linked
                ? store.symlinkTarget(for: command, agent: .claude) : nil

            let target = skillDir.appendingPathComponent("SKILL.md")
            do {
                try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
                try fm.moveItem(at: command.url, to: target)
                if let content = try? String(contentsOf: target, encoding: .utf8) {
                    let patched = ensuringFrontmatter(content, name: command.name)
                    if patched != content {
                        try? patched.write(to: target, atomically: true, encoding: .utf8)
                    }
                }
                if let staleLink { try? fm.removeItem(at: staleLink) }
                done.append(CommandToSkillMigration(name: command.name, skillURL: target,
                                                    removedSymlink: staleLink))
            } catch {
                continue   // still: ein hängengebliebener Command ist sichtbar, kein Datenverlust
            }
        }
        return done
    }

    /// Ergänzt `name` und `disable-model-invocation` im Frontmatter, ohne den Rumpf zu berühren.
    /// Ohne Frontmatter wird eins angelegt — sonst hätte der Skill in Codex keinen Namen.
    static func ensuringFrontmatter(_ content: String, name: String) -> String {
        var lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closing = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              }) else {
            return "---\nname: \(name)\ndisable-model-invocation: true\n---\n\n" + content
        }

        var front = Array(lines[1..<closing])
        let keys = Set(front.compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return line[..<colon].trimmingCharacters(in: .whitespaces)
        })
        if !keys.contains("name") { front.insert("name: \(name)", at: 0) }
        if !keys.contains("disable-model-invocation") { front.append("disable-model-invocation: true") }

        lines.replaceSubrange(1..<closing, with: front)
        return lines.joined(separator: "\n")
    }
}
