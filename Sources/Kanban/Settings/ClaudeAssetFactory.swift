import Foundation
import KanbanCore

/// Der Auslieferungsstand der Claude-Assets (SPM-Resources im App-Bundle) und das Seeding beim
/// App-Start: fehlende Assets werden in den kanonischen Bestand kopiert, editierte nie angefasst.
enum ClaudeAssetFactory {
    /// `ClaudeAssets/` aus den Bundle-Resources; nil bei kaputtem Bundle (dann bleibt der Bestand,
    /// wie er ist — die App funktioniert ohne Auslieferungsstand, nur Zurücksetzen geht nicht).
    static var bundledRoot: URL? {
        Bundle.module.url(forResource: "ClaudeAssets", withExtension: nil)
    }

    /// Still und nicht-fatal — ein fehlgeschlagenes Seeding darf den App-Start nicht verhindern.
    ///
    /// **Vor** dem Seeding läuft der Command→Skill-Umzug: sonst käme der alte, womöglich editierte
    /// `commands/get-task.md` neben einem frisch geseedeten `skills/get-task/` zu liegen, und Claude
    /// hätte `/get-task` zweimal. Der Umzug ist idempotent und verschiebt, statt zu kopieren.
    @discardableResult
    static func seedAtLaunch() -> [ClaudeAsset] {
        let store = ClaudeAssetStore()
        relink(migrated: ClaudeAssetMigration.migrateCommandsToSkills(store: store), store: store)
        guard let factory = bundledRoot else { return [] }
        return (try? store.seedMissing(from: factory)) ?? []
    }

    /// Hält die Erreichbarkeit gerade: **was in einem Agent-Home hängt, hängt in allen.**
    ///
    /// Zwei Fälle, eine Regel. Nach dem Command→Skill-Umzug wäre `/get-task` sonst weg, bis jemand
    /// im Editor „Alle verlinken" drückt (der alte Command-Symlink ist ja mit umgezogen). Und ein
    /// Skill, den es schon vor Codex gab, wäre in einem Codex-Projekt unsichtbar geblieben.
    ///
    /// Bewusst **nicht** „alles verlinken": ein Asset, das der Mensch nie verlinkt hat, bleibt
    /// unverlinkt. Fremde Zielorte werden nie überschrieben, das regelt `installSymlink`.
    private static func relink(migrated: [CommandToSkillMigration], store: ClaudeAssetStore) {
        let justMigrated = Set(migrated.filter { $0.removedSymlink != nil }.map(\.name))
        for skill in store.assets(.skill) {
            let states = store.symlinkStates(for: skill)
            guard justMigrated.contains(skill.name) || states.values.contains(.linked) else { continue }
            for (agent, state) in states where state == .notInstalled {
                try? store.installSymlink(for: skill, agent: agent)
            }
        }
    }
}
