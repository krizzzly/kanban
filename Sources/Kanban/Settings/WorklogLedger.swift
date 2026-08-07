import Foundation

/// Records how much of each ticket's ⏱ time has already been booked to Jira, so a later booking logs
/// only the new delta and the same time can never be booked twice. Local UI state, like
/// `SessionIdStore` — persisted to `~/Library/Application Support/Kanban/worklog.json`. It is the
/// app's own record of its bookings; worklogs added by hand in Jira are not tracked here.
enum WorklogLedger {
    struct Entry: Codable {
        var bookedSeconds: TimeInterval
        var lastBookedAt: Date?
    }

    private static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("worklog.json")
    }

    static func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return map
    }

    /// Just the booked seconds per ticket — what the model needs to compute the open amount.
    static func bookedSeconds() -> [String: TimeInterval] {
        load().mapValues(\.bookedSeconds)
    }

    static func entry(forTicket key: String) -> Entry? { load()[key] }

    /// Adds `seconds` to a ticket's booked total after a successful Jira write. Additive on purpose:
    /// each call logs a delta, and the running sum is what blocks re-booking the same time.
    static func record(_ seconds: TimeInterval, at date: Date, forTicket key: String) {
        var map = load()
        var entry = map[key] ?? Entry(bookedSeconds: 0, lastBookedAt: nil)
        entry.bookedSeconds += seconds
        entry.lastBookedAt = date
        map[key] = entry
        save(map)
    }

    private static func save(_ map: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
