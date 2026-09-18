import Foundation
import KanbanCore

/// Der Auslieferungsstand der Skill-Sets (SPM-Resources im App-Bundle) und was beim App-Start damit
/// passiert: **überschreibend** in den Bestand spiegeln, dann das Standard-Set in die Agent-Homes
/// verlinken.
///
/// Die Umkehr gegenüber dem früheren Seeding ist der Kern dieses Umbaus: gepflegt werden die Sets
/// im Kanban-Repo, nicht in Application Support. Der Bestand ist nur noch die Stelle, auf die
/// Symlinks zeigen dürfen — das App-Bundle wird bei einem Update ersetzt, Links dorthin brächen.
enum ClaudeAssetFactory {
    /// `ClaudeAssets/` aus den Bundle-Resources; nil bei kaputtem Bundle (dann bleibt der Bestand,
    /// wie er ist — die App läuft auch ohne Auslieferungsstand, sie liefert dann eben nichts nach).
    static var bundledRoot: URL? {
        Bundle.module.url(forResource: "ClaudeAssets", withExtension: nil)
    }

    /// Still und nicht-fatal — ein fehlgeschlagener Sync darf den App-Start nicht verhindern.
    @discardableResult
    static func syncAtLaunch(defaultSkillSet: String? = nil) -> [ClaudeAssetSet] {
        let store = ClaudeAssetStore()
        if let factory = bundledRoot {
            _ = try? store.syncSets(from: factory)
        }
        linkDefaultSetIntoHomes(defaultSkillSet, store: store)
        return store.sets()
    }

    /// Das Standard-Set zusätzlich in `~/.claude` und `~/.codex` — für eine Console, die in keinem
    /// Projekt steht. Hängt dabei die Symlinks des alten, flachen Modells auf das Set um
    /// (`ClaudeSymlinkState.otherSet`); Fremdes bleibt liegen.
    static func linkDefaultSetIntoHomes(_ name: String?, store: ClaudeAssetStore = ClaudeAssetStore()) {
        guard let set = store.defaultSet(configured: name) else { return }
        store.link(set, toHomes: AgentKind.allCases)
    }

    /// Das Set eines Projekts in sein Repo verlinken. Ohne Repo-Ordner passiert nichts — die
    /// Übersicht sagt das dann auch, statt still wirkungslos zu bleiben.
    @discardableResult
    static func link(_ project: ProjectConfig, defaultSkillSet: String?,
                     store: ClaudeAssetStore = ClaudeAssetStore()) -> ClaudeLinkReport? {
        guard FileManager.default.fileExists(atPath: project.repoDir),
              let set = store.resolve(skillSet: project.skillSet, default: defaultSkillSet).set
        else { return nil }
        return store.link(set, toProject: project.repoDir, agent: project.agent)
    }

    /// Der Name des Sets, mit dem dieses Projekt wirklich läuft — das, was in `.claude/project.json`
    /// stehen soll.
    static func resolvedSetName(for project: ProjectConfig, defaultSkillSet: String?,
                                store: ClaudeAssetStore = ClaudeAssetStore()) -> String? {
        store.resolve(skillSet: project.skillSet, default: defaultSkillSet).set?.name
    }
}
