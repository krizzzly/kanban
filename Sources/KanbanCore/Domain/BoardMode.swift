import Foundation

/// Woher die Ticketliste des Boards kommt.
///
/// - `sprint`: aus Jira — der gewählte Sprint gibt die Karten vor (der ursprüngliche Modus).
/// - `free`: aus dem, was lokal existiert (`LocalTickets`) — Task-Files, Worktrees, MRs. Kein
///   Sprint-Selektor, keine Sprint-Spalte, dafür der Knopf „Task erstellen".
///
/// Die Spalten-Herleitung ist in beiden Modi dieselbe; nur die **Sprint**-Spalte ergibt ohne Sprint
/// keinen Sinn — sie bedeutet „in Jira eingeplant, lokal noch nichts da" und fällt deshalb weg.
public enum BoardMode: String, Sendable, CaseIterable, Identifiable {
    case sprint
    case free

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sprint: return "Sprint"
        case .free: return "Frei"
        }
    }

    public var icon: String {
        switch self {
        case .sprint: return "calendar"
        case .free: return "tray.full"
        }
    }

    /// Die Spalten dieses Modus, in Board-Reihenfolge.
    public var columns: [KanbanColumn] {
        switch self {
        case .sprint: return KanbanColumn.ordered
        case .free: return KanbanColumn.ordered.filter { $0 != .sprint }
        }
    }
}
