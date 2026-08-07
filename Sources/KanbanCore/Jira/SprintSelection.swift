import Foundation

/// Which sprint the board shows, as pure logic: the picker order plus the restore rule that lets a
/// chosen sprint survive an app restart (the id itself is persisted by the app, see `SelectionStore`).
public enum SprintSelection {
    /// Picker order: the active sprint first, then newest to oldest by id.
    public static func ordered(_ sprints: [JiraSprint]) -> [JiraSprint] {
        sprints.sorted { a, b in
            if (a.state == "active") != (b.state == "active") { return a.state == "active" }
            return a.id > b.id
        }
    }

    /// The sprint to select: the one last chosen for this board while it is still on the board — a
    /// closed one included, since choosing it was deliberate and the picker marks it "✓" — otherwise
    /// the active sprint, otherwise the first. A stored id the board no longer knows (sprint deleted,
    /// board switched) falls back instead of leaving the board empty.
    public static func resolve(sprints: [JiraSprint], storedId: Int?) -> JiraSprint? {
        if let storedId, let stored = sprints.first(where: { $0.id == storedId }) { return stored }
        return sprints.first { $0.state == "active" } ?? sprints.first
    }
}
