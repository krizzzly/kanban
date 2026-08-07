import Foundation

/// Remembers what the user last had open so a restart lands where they left off: the selected project
/// and — per project, because every project has its own board — the selected sprint.
///
/// UserDefaults, like `AppScale`: this is local UI state. It deliberately does **not** go into
/// `~/.hermes/config.json`, which is shared with Hermes and describes projects, not window state.
enum SelectionStore {
    private static let projectDefaultsKey = "selectedProjectKey"
    private static let sprintDefaultsKey = "selectedSprintByProject"

    /// The project key selected when the app last quit (nil on first run).
    static var projectKey: String? {
        get { UserDefaults.standard.string(forKey: projectDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: projectDefaultsKey) }
    }

    static func sprintId(forProject key: String) -> Int? {
        (UserDefaults.standard.dictionary(forKey: sprintDefaultsKey)?[key] as? NSNumber)?.intValue
    }

    static func setSprintId(_ id: Int, forProject key: String) {
        var map = UserDefaults.standard.dictionary(forKey: sprintDefaultsKey) ?? [:]
        map[key] = id
        UserDefaults.standard.set(map, forKey: sprintDefaultsKey)
    }
}
