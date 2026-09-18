import Foundation

/// The shared location for Kanban's attention markers: one empty file per Claude `session_id`,
/// written by the `Notification` hook and removed on `UserPromptSubmit`/`SessionEnd`. The app
/// watches this directory and maps each session id back to its ticket.
public enum AttentionMarkers {
    /// `~/Library/Application Support/Kanban/attention/`
    /// Bewusst **global** und nicht je Profil: das Hook-Skript in `~/.claude/settings.json` nennt
    /// diesen Ordner mit absolutem Pfad. Ein Marker-Ordner je Profil hiesse, diese fremde Datei bei
    /// jedem Wechsel umzuschreiben — viel Risiko für nichts. Die Marker tragen ohnehin
    /// Claude-`session_id`s, also UUIDs: kollidieren können sie zwischen Profilen nicht.
    public static var directory: URL {
        let base = KanbanPaths.attentionDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The `session_id`s that currently have a marker. Markers older than `maxAge` are ignored and
    /// pruned (defends against a missed clear-event leaving a session flagged forever).
    public static func activeSessionIds(maxAge: TimeInterval = 6 * 3600) -> Set<String> {
        let dir = directory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var result: Set<String> = []
        let now = Date()
        for url in entries {
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? now
            if now.timeIntervalSince(mtime) > maxAge {
                try? FileManager.default.removeItem(at: url)
            } else {
                result.insert(name)
            }
        }
        return result
    }

    /// Removes a session's marker (used by the app to self-heal when the pane shows work resumed).
    public static func clear(sessionId: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(sessionId))
    }
}
