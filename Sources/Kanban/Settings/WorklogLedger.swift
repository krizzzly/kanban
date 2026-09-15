import Foundation

/// Records how much of each ticket's ⏱ time has already been booked to Jira, so a later booking logs
/// only the new delta and the same time can never be booked twice. Local UI state, like
/// `SessionIdStore` — persisted to `~/Library/Application Support/Kanban/worklog.json`. It is the
/// app's own record of its bookings; worklogs added by hand in Jira are not tracked here.
///
/// Gemerkt wird **je Tag** (`byDay`), weil auf den Arbeitstag gebucht wird und nicht auf heute. Die
/// Gesamtsumme bleibt daneben stehen: sie trägt die Anzeige („Gebucht") und die Alt-Buchungen aus der
/// Zeit vor dieser Änderung, die keinen Tag kennen (siehe `unattributedSeconds`).
enum WorklogLedger {
    struct Entry: Codable {
        var bookedSeconds: TimeInterval
        var lastBookedAt: Date?
        /// `yyyy-MM-dd` → gebuchte Sekunden. Fehlt in Dateien, die vor dieser Änderung entstanden
        /// sind — dann steckt alles in `bookedSeconds`.
        var byDay: [String: TimeInterval]?

        /// Gebuchtes ohne Tageszuordnung. `WorklogBooking.dailyBookings` rechnet es auf die
        /// ältesten Tage an, statt sie ein zweites Mal zu buchen.
        var unattributedSeconds: TimeInterval {
            max(0, bookedSeconds - (byDay ?? [:]).values.reduce(0, +))
        }
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

    /// Adds `seconds` to a ticket's booked total **and** to the day they were worked, after a
    /// successful Jira write. Additive on purpose: each call logs a delta, and the running sums are
    /// what block re-booking the same time.
    static func record(_ seconds: TimeInterval, dayKey: String, at date: Date, forTicket key: String) {
        var map = load()
        var entry = map[key] ?? Entry(bookedSeconds: 0, lastBookedAt: nil, byDay: [:])
        entry.bookedSeconds += seconds
        entry.lastBookedAt = date
        var byDay = entry.byDay ?? [:]
        byDay[dayKey, default: 0] += seconds
        entry.byDay = byDay
        map[key] = entry
        save(map)
    }

    private static func save(_ map: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
