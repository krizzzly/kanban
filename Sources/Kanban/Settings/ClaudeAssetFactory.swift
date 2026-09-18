import Foundation
import KanbanCore

/// Was die App mit den Skill-Sets tut: sie **verlinkt** sie, mehr nicht.
///
/// Die Sets sind physisch gepflegte Ordner (`claude.setsPath`, per Vorgabe das Kanban-Repo), und
/// genau diese Ordner sind das Ziel der Symlinks. Es gibt keine Kopie, keinen Auslieferungsstand
/// und keinen Sync: eine Änderung an einem `SKILL.md` wirkt sofort in jedem verlinkten Projekt,
/// ohne Rebuild und ohne Neustart.
enum ClaudeAssetFactory {
    /// Beim App-Start: das Standard-Set in die Agent-Homes, damit eine Console ausserhalb eines
    /// Projekts nicht leer dasteht. Still und nicht-fatal — ein fehlender Sets-Ordner darf den
    /// Start nicht verhindern; die Übersicht sagt dann, dass dort nichts liegt.
    static func linkAtLaunch() {
        let config = try? KanbanConfig.load()
        linkDefaultSetIntoHomes(config?.defaultSkillSet)
    }

    /// Das Standard-Set in `~/.claude` und `~/.codex`. Hängt dabei die Symlinks des alten, flachen
    /// Modells auf das Set um (`ClaudeSymlinkState.otherSet`); Fremdes bleibt liegen.
    static func linkDefaultSetIntoHomes(_ name: String?,
                                        store: ClaudeAssetStore = .configured()) {
        guard let set = store.defaultSet(configured: name) else {
            // Kein Set heisst **nicht** „nichts tun": die Homes gehören allen Profilen gemeinsam,
            // und die Links des zuvor aktiven Profils blieben sonst stehen — bei Namensgleichheit
            // sticht die User-Ebene die Projektebene, das neue Profil sähe also weiter die Skills
            // des alten.
            store.unlinkHomes(AgentKind.allCases)
            return
        }
        store.link(set, toHomes: AgentKind.allCases)
    }

    /// Das Set eines Projekts in sein Repo verlinken. Ohne Repo-Ordner passiert nichts — die
    /// Übersicht sagt das dann auch, statt still wirkungslos zu bleiben.
    @discardableResult
    static func link(_ project: ProjectConfig, defaultSkillSet: String?,
                     store: ClaudeAssetStore = .configured()) -> ClaudeLinkReport? {
        guard FileManager.default.fileExists(atPath: project.repoDir),
              let set = store.resolve(skillSet: project.skillSet, default: defaultSkillSet).set
        else { return nil }
        return store.link(set, toProject: project.repoDir, agent: project.agent)
    }

    /// Der Name des Sets, mit dem dieses Projekt wirklich läuft — das, was in `.claude/project.json`
    /// stehen soll.
    static func resolvedSetName(for project: ProjectConfig, defaultSkillSet: String?,
                                store: ClaudeAssetStore = .configured()) -> String? {
        store.resolve(skillSet: project.skillSet, default: defaultSkillSet).set?.name
    }
}
