import Foundation

/// Woher die Reihenfolge eines Projekts kommt.
public enum ReihenfolgeQuelle: Sendable {
    /// Jiras Rank — die Backlog-Sortierung. Ein Zug schreibt dorthin zurück.
    case jira
    /// Von Hand gelegt und lokal gemerkt (`LocalOrder`) — für Projekte ohne Jira.
    case lokal

    public var beschreibung: String {
        switch self {
        case .jira: return "Ziehen oder ⌘↑/⌘↓ — schreibt den Rang sofort nach Jira"
        case .lokal: return "Ziehen oder ⌘↑/⌘↓ — lokal gemerkt, ohne Jira"
        }
    }
}

/// Die von Hand gelegte Reihenfolge eines Projekts **ohne** Jira.
///
/// Der Rang eines Backlogs ist normalerweise ein Jira-Feld (`TicketOrder`). Ein Projekt im freien
/// Modus hat keins — seine Karten kommen aus Task-Files, Worktrees und MRs (`LocalTickets`) und
/// tragen nichts, woran sich eine Ordnung festmachen liesse. Genau dafür ist dieser Speicher da:
/// eine Liste von Ticket-Schlüsseln je Projekt, gemerkt in Kanbans eigenem Datenordner.
///
/// **Warum eine Datei und nicht `UserDefaults`:** die Reihenfolge ist keine Anzeige-Einstellung wie
/// der zuletzt gewählte Sprint, sondern eine **Entscheidung des Menschen**. Sie gehört zu
/// `worklog.json` und `watchdog.json` — Dinge, deren Verlust weh tut.
public enum LocalOrder {

    /// Bringt die vorhandenen Tickets in die gemerkte Reihenfolge.
    ///
    /// - Bekannte Schlüssel stehen in der Reihenfolge des Speichers.
    /// - **Unbekannte hängen hinten an**, in der Reihenfolge, in der sie hereinkamen. Ein neues
    ///   Ticket rutscht damit nie ungefragt nach vorn — wer es vorn haben will, zieht es dorthin.
    /// - Gemerkte Schlüssel, die es nicht mehr gibt, fallen weg (aber erst hier, nicht im
    ///   Speicher: ein Task-File kann kurz verschwinden, weil ein Worktree gerade umzieht).
    public static func arrange(_ keys: [String], stored: [String]) -> [String] {
        let vorhanden = Set(keys)
        let bekannt = stored.filter { vorhanden.contains($0) }
        let gesehen = Set(bekannt)
        return bekannt + keys.filter { !gesehen.contains($0) }
    }

    /// Wendet einen Zug an — dieselbe Zählweise wie SwiftUIs `onMove` (Ziel **vor** dem Entfernen).
    /// Gibt `nil` zurück, wenn sich nichts ändert; dann muss auch nichts geschrieben werden.
    public static func moved(_ order: [String], from: Int, to: Int) -> [String]? {
        guard order.count > 1, from >= 0, from < order.count else { return nil }
        var neu = order
        let bewegt = neu.remove(at: from)
        let ziel = min(max(0, to > from ? to - 1 : to), neu.count)
        neu.insert(bewegt, at: ziel)
        return neu == order ? nil : neu
    }
}

/// Liest und schreibt die lokalen Reihenfolgen — eine Datei für alle Projekte des Profils.
public struct LocalOrderStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? KanbanPaths.orderFile
    }

    public func order(forProject key: String) -> [String] {
        alle()[key] ?? []
    }

    public func setOrder(_ order: [String], forProject key: String) {
        var map = alle()
        map[key] = order
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Eine unlesbare Datei ist kein Grund abzustürzen — dann ist die Reihenfolge eben leer und
    /// ergibt sich aus der Liste selbst. Sie geht beim nächsten Zug ohnehin neu raus.
    private func alle() -> [String: [String]] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return map
    }
}
