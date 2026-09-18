import Foundation
import KanbanCore

/// Remembers what the user last had open so a restart lands where they left off: the open projects
/// (one window each), the project last worked in and — per project, because every project has its
/// own board — the selected sprint.
///
/// UserDefaults, like `AppScale`: this is local UI state. It deliberately does **not** go into
/// `~/.hermes/config.json`, which is shared with Hermes and describes projects, not window state.
///
/// Jeder Schlüssel gehört einem **Profil** (`ProfileDefaults`): ohne Präfix machte der Start im
/// privaten Profil die Fenster der Arbeit auf. Welches Profil gilt, setzt die App; ungesetzt
/// verhält sich der Speicher wie vor der Profil-Ebene.
enum SelectionStore {
    private static let projectDefaultsKey = "selectedProjectKey"
    private static let openProjectsDefaultsKey = "openProjectKeys"
    private static let sprintDefaultsKey = "selectedSprintByProject"
    private static let boardModeDefaultsKey = "boardModeByProject"
    private static let setsRootDefaultsKey = "claudeSetsRootSeen"

    /// Die Schlüssel-Abbildung des aktiven Profils.
    static var keys = ProfileDefaults(profile: nil)
    /// Injizierbar, damit ein Test nicht die echten Voreinstellungen anfasst.
    static var defaults: UserDefaults = .standard

    /// Lesen mit Rückgriff auf den alten Schlüssel — siehe `ProfileDefaults`.
    private static func read<T>(_ name: String, _ hole: (String) -> T?) -> T? {
        if let wert = hole(keys.key(name)) { return wert }
        guard let alt = keys.legacyKey(name) else { return nil }
        return hole(alt)
    }

    /// The project key selected when the app last quit (nil on first run).
    ///
    /// Seit „ein Fenster je Projekt" ist das **nicht** mehr, was beim Start aufgeht — dafür gibt es
    /// `openProjectKeys`. Es bleibt das zuletzt benutzte Projekt: die Rückfallebene, wenn die Liste
    /// leer ist, und die Quelle, aus der die Liste beim ersten Start migriert wird.
    static var projectKey: String? {
        get { read(projectDefaultsKey) { defaults.string(forKey: $0) } }
        set { defaults.set(newValue, forKey: keys.key(projectDefaultsKey)) }
    }

    /// Die Projekte mit offenem Fenster, in der Reihenfolge, in der die Fenster aufgingen.
    ///
    /// nil heisst „noch nie geschrieben" (nicht „keines offen") — nur dann greift die Migration vom
    /// alten Einzelwert, siehe `OpenProjects.wiederherstellen`.
    static var openProjectKeys: [String]? {
        get { read(openProjectsDefaultsKey) { defaults.stringArray(forKey: $0) } }
        set { defaults.set(newValue, forKey: keys.key(openProjectsDefaultsKey)) }
    }

    /// Der Sammelordner der Skill-Sets, wie ihn die Übersicht zuletzt gesehen hat.
    ///
    /// Nur dafür da, einen **Wechsel** zu bemerken: zeigt ein Symlink noch in den alten Ordner, ist
    /// er einer von uns und wird umgehängt statt als fremd liegengelassen (`formerRoots`). Das kann
    /// die Config selbst nicht sagen — sie kennt nur den Wert von jetzt. Hier richtig aufgehoben und
    /// nicht in der Config: ein Beobachtungsposten, keine Einstellung.
    static var claudeSetsRootSeen: String? {
        get { UserDefaults.standard.string(forKey: setsRootDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: setsRootDefaultsKey) }
    }

    /// Die zuletzt gewählte Jira-Quelle als `SprintChoice.id` — eine Sprint-Id oder `"board"`.
    ///
    /// Gespeichert wird als String, gelesen wird **auch** eine Zahl: bis zur Board-Wahl stand hier
    /// eine nackte Sprint-Id, und ein Nutzer soll seine Auswahl nicht verlieren, nur weil das
    /// Format gewachsen ist.
    static func sprintChoice(forProject key: String) -> String? {
        switch read(sprintDefaultsKey, { defaults.dictionary(forKey: $0) })?[key] {
        case let text as String: return text
        case let number as NSNumber: return String(number.intValue)
        default: return nil
        }
    }

    static func setSprintChoice(_ id: String, forProject key: String) {
        var map = read(sprintDefaultsKey, { defaults.dictionary(forKey: $0) }) ?? [:]
        map[key] = id
        defaults.set(map, forKey: keys.key(sprintDefaultsKey))
    }

    /// Sprint- oder freier Modus, ebenfalls je Projekt: ein Projekt ohne Jira-Board darf dauerhaft
    /// frei laufen, während ein anderes im Sprint bleibt.
    static func boardMode(forProject key: String) -> BoardMode? {
        (read(boardModeDefaultsKey, { defaults.dictionary(forKey: $0) })?[key] as? String)
            .flatMap(BoardMode.init(rawValue:))
    }

    static func setBoardMode(_ mode: BoardMode, forProject key: String) {
        var map = read(boardModeDefaultsKey, { defaults.dictionary(forKey: $0) }) ?? [:]
        map[key] = mode.rawValue
        defaults.set(map, forKey: keys.key(boardModeDefaultsKey))
    }
}
