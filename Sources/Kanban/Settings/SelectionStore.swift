import Foundation
import KanbanCore

/// Remembers what the user last had open so a restart lands where they left off: the open projects
/// (one window each), the project last worked in and — per project, because every project has its
/// own board — the selected sprint.
///
/// UserDefaults, like `AppScale`: this is local UI state. It deliberately does **not** go into
/// `~/.hermes/config.json`, which is shared with Hermes and describes projects, not window state.
enum SelectionStore {
    private static let projectDefaultsKey = "selectedProjectKey"
    private static let openProjectsDefaultsKey = "openProjectKeys"
    private static let sprintDefaultsKey = "selectedSprintByProject"
    private static let boardModeDefaultsKey = "boardModeByProject"

    /// The project key selected when the app last quit (nil on first run).
    ///
    /// Seit „ein Fenster je Projekt" ist das **nicht** mehr, was beim Start aufgeht — dafür gibt es
    /// `openProjectKeys`. Es bleibt das zuletzt benutzte Projekt: die Rückfallebene, wenn die Liste
    /// leer ist, und die Quelle, aus der die Liste beim ersten Start migriert wird.
    static var projectKey: String? {
        get { UserDefaults.standard.string(forKey: projectDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: projectDefaultsKey) }
    }

    /// Die Projekte mit offenem Fenster, in der Reihenfolge, in der die Fenster aufgingen.
    ///
    /// nil heisst „noch nie geschrieben" (nicht „keines offen") — nur dann greift die Migration vom
    /// alten Einzelwert, siehe `OpenProjects.wiederherstellen`.
    static var openProjectKeys: [String]? {
        get { UserDefaults.standard.stringArray(forKey: openProjectsDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: openProjectsDefaultsKey) }
    }

    /// Die zuletzt gewählte Jira-Quelle als `SprintChoice.id` — eine Sprint-Id oder `"board"`.
    ///
    /// Gespeichert wird als String, gelesen wird **auch** eine Zahl: bis zur Board-Wahl stand hier
    /// eine nackte Sprint-Id, und ein Nutzer soll seine Auswahl nicht verlieren, nur weil das
    /// Format gewachsen ist.
    static func sprintChoice(forProject key: String) -> String? {
        switch UserDefaults.standard.dictionary(forKey: sprintDefaultsKey)?[key] {
        case let text as String: return text
        case let number as NSNumber: return String(number.intValue)
        default: return nil
        }
    }

    static func setSprintChoice(_ id: String, forProject key: String) {
        var map = UserDefaults.standard.dictionary(forKey: sprintDefaultsKey) ?? [:]
        map[key] = id
        UserDefaults.standard.set(map, forKey: sprintDefaultsKey)
    }

    /// Sprint- oder freier Modus, ebenfalls je Projekt: ein Projekt ohne Jira-Board darf dauerhaft
    /// frei laufen, während ein anderes im Sprint bleibt.
    static func boardMode(forProject key: String) -> BoardMode? {
        (UserDefaults.standard.dictionary(forKey: boardModeDefaultsKey)?[key] as? String)
            .flatMap(BoardMode.init(rawValue:))
    }

    static func setBoardMode(_ mode: BoardMode, forProject key: String) {
        var map = UserDefaults.standard.dictionary(forKey: boardModeDefaultsKey) ?? [:]
        map[key] = mode.rawValue
        UserDefaults.standard.set(map, forKey: boardModeDefaultsKey)
    }
}
