import Foundation

/// Fallback store for Claude session ids of tickets that have **no** task file (Jira-only). Tickets
/// with a task file keep their id in the file itself (see `ClaudeSession`). Persists to
/// `~/Library/Application Support/Kanban/sessions.json`.
enum SessionIdStore {
    private static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sessions.json")
    }

    /// Returns the ticket's stored session id, generating and persisting one if absent.
    static func ensure(forTicket key: String) -> String {
        var map = load()
        if let existing = map[key] { return existing }
        let id = UUID().uuidString.lowercased()
        map[key] = id
        save(map)
        return id
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private static func save(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
