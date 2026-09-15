import Foundation

/// Woher die Jira-Karten kommen: aus einem Sprint oder aus dem **Board** als Ganzem.
///
/// Der zweite Fall ist kein Notnagel, sondern der Normalfall mancher Projekte: `CORE` hat ein
/// Scrum-Board mit 50 Sprints, alle geschlossen — der letzte endete 2021. Dort wird ohne Sprint
/// gearbeitet, und ohne diese Wahl bliebe das Board leer („Keine Sprints für dieses Board").
public enum SprintChoice: Sendable, Equatable, Identifiable {
    /// Die offenen Tickets des Boards (plus kürzlich erledigte, siehe `JiraClient.openBoardJQL`).
    case board
    case sprint(JiraSprint)

    public var id: String {
        switch self {
        case .board: return "board"
        case .sprint(let sprint): return String(sprint.id)
        }
    }

    public var sprint: JiraSprint? {
        if case .sprint(let sprint) = self { return sprint }
        return nil
    }

    public var label: String {
        switch self {
        case .board: return "📋 Ganzes Board (offen)"
        case .sprint(let sprint):
            switch sprint.state {
            case "active": return "🟢 \(sprint.name)"
            case "future": return "🔜 \(sprint.name)"
            case "closed": return "✓ \(sprint.name)"
            default: return sprint.name
            }
        }
    }
}

/// Was der Picker anbietet und was davon vorgewählt ist — reine Logik, damit die Regel ohne Netz
/// und ohne UI prüfbar ist. Die Wahl selbst persistiert die App (`SelectionStore`).
public enum SprintSelection {
    /// Picker-Reihenfolge: der aktive Sprint zuerst, dann neu nach alt (Id absteigend), das Board
    /// zuletzt. Das Board steht **immer** zur Wahl, nicht nur bei sprintlosen Projekten: auch mit
    /// laufendem Sprint will man gelegentlich das ganze Brett sehen, und ein Eintrag am Ende der
    /// Liste stört niemanden.
    public static func ordered(_ sprints: [JiraSprint]) -> [JiraSprint] {
        sprints.sorted { a, b in
            if (a.state == "active") != (b.state == "active") { return a.state == "active" }
            return a.id > b.id
        }
    }

    public static func choices(_ sprints: [JiraSprint]) -> [SprintChoice] {
        ordered(sprints).map(SprintChoice.sprint) + [.board]
    }

    /// Die Vorauswahl: die zuletzt für dieses Board getroffene Wahl, solange es sie noch gibt — ein
    /// geschlossener Sprint eingeschlossen, denn die Wahl war Absicht und der Picker markiert ihn
    /// „✓". Sonst der aktive Sprint. Gibt es **keinen** aktiven, gewinnt das Board: ein Projekt, das
    /// seine Sprints vor Jahren geschlossen hat, soll nicht im jüngsten Altsprint landen.
    public static func resolve(sprints: [JiraSprint], storedId: String?) -> SprintChoice {
        let all = choices(sprints)
        if let storedId, let stored = all.first(where: { $0.id == storedId }) { return stored }
        if let active = sprints.first(where: { $0.state == "active" }) { return .sprint(active) }
        return .board
    }
}
