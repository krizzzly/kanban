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

    /// The ticket's stored session id, or nil — unlike `ensure` this never creates one, so it is safe
    /// to ask for every card on the board.
    static func peek(forTicket key: String) -> String? {
        load()[key]
    }

    /// Records the ticket's session id. Written together with the task-file marker so the two stores
    /// cannot drift apart again (see `ClaudeSessionResolution`).
    static func set(_ sessionId: String, forTicket key: String) {
        var map = load()
        guard map[key] != sessionId else { return }
        map[key] = sessionId
        save(map)
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
