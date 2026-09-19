import Foundation

/// Ein Vorgang, der einen anderen blockiert — mit dem, was Jira über seine Erledigung sagt.
///
/// Der Zustand steht **im Link selbst**: Jira bettet Summary und Status des verknüpften Vorgangs in
/// `issuelinks` ein. Das ist der Grund, warum die Sperre ohne eine einzige Zusatzanfrage ableitbar
/// ist — und warum sie auch dann stimmt, wenn der Blocker gar nicht im Sprint liegt (der Normalfall:
/// das Fundament ist längst im Backlog nach unten gerutscht, während die Karte, die es blockiert,
/// im Sprint steht).
public struct BlockingRef: Sendable, Hashable, Codable {
    public let key: String
    public let summary: String
    /// `statusCategory.key` des Blockers — `done` heisst erledigt.
    public let statusCategory: String?

    public init(key: String, summary: String = "", statusCategory: String? = nil) {
        self.key = key
        self.summary = summary
        self.statusCategory = statusCategory
    }

    /// Erledigt = die Sperre ist gefallen. Ohne Auskunft gilt sie als **offen**: eine Sperre, über
    /// die nichts bekannt ist, stillschweigend fallen zu lassen wäre die gefährlichere Annahme.
    public var isDone: Bool { statusCategory == "done" }
}

/// Wie die Reihenfolge eines Backlogs auf dem Brett sichtbar wird.
///
/// **Warum abgeleitet und nicht gepflegt:** dieselbe Haltung wie bei der Spalte (`WorkflowStatus`).
/// Die Reihenfolge steht in Jira als **Rank** (die Backlog-Sortierung, eine Totalordnung), die
/// Sperren stehen als `Blocks`-Verknüpfungen. Beides holt das Board ohnehin mit; „was ist als
/// nächstes dran" ist daraus eine Ableitung, kein zusätzlicher Zustand, den jemand pflegen müsste.
///
/// **Nicht die Priorität.** Jiras `priority` ist eine Klasse mit fünf Stufen, keine Folge — in einem
/// echten Backlog liegen regelmässig mehr als die Hälfte der Vorgänge in derselben Stufe (gemessen:
/// 61 von 113 auf „Highest"). Daraus lässt sich kein „was zuerst" ableiten. Der Rank kann das, weil
/// er je Vorgang verschieden ist.
public enum TicketOrder {

    /// Die Sperren eines Tickets, die **noch offen** sind.
    public static func openBlockers(of ticket: Ticket) -> [BlockingRef] {
        ticket.blockedBy.filter { !$0.isDone }
    }

    /// Ist das Ticket durch einen unerledigten Vorgang gesperrt?
    public static func isBlocked(_ ticket: Ticket) -> Bool {
        !openBlockers(of: ticket).isEmpty
    }

    /// Das Ticket, das als **nächstes** drankommt: das oberste nach Rank, das weder erledigt noch
    /// gesperrt ist.
    ///
    /// - Die Liste kommt in Rank-Reihenfolge herein (die Agile-API liefert sie so, siehe
    ///   `JiraClient`), deshalb entscheidet hier schlicht die Position — kein eigenes Sortieren.
    /// - **Erledigte fallen raus**, nicht nur die gesperrten: sonst zeigte der Vorschlag auf etwas,
    ///   das längst gemergt ist.
    /// - **Epics fallen raus**: sie sind Behälter, keine Arbeit.
    /// - Ohne Rank-Information (freier Modus, lokale Tickets) gibt es kein „als nächstes" — dann
    ///   nil statt eines geratenen Vorschlags.
    public static func nextUp(_ tickets: [Ticket]) -> Ticket? {
        tickets.first { candidate in
            guard candidate.rankIndex != nil else { return false }
            guard !candidate.isDoneInJira else { return false }
            guard !isEpic(candidate) else { return false }
            return !isBlocked(candidate)
        }
    }

    /// Verstösse gegen die eigene Reihenfolge: Tickets, an denen **gearbeitet wird**, obwohl sie
    /// noch gesperrt sind.
    ///
    /// Das ist die Frage, die ein Plan beantworten können muss, sobald er geschrieben ist — ein
    /// Backlog in Reihenfolge nützt nichts, wenn nebenher an Nummer 40 gebaut wird. Gemeldet wird
    /// nur, was **angefangen** ist (Spalte jenseits von Sprint/Offen); ein gesperrtes Ticket, das
    /// ruhig liegt, ist kein Verstoss, sondern der Normalfall.
    public static func violations(_ cards: [(ticket: Ticket, column: KanbanColumn)]) -> [Ticket] {
        cards.filter { entry in
            guard entry.column == .inBearbeitung || entry.column == .review else { return false }
            return isBlocked(entry.ticket)
        }.map(\.ticket)
    }

    /// Wohin ein verschobener Vorgang in Jira gehängt wird.
    ///
    /// Die Agile-API kennt keine absolute Position, nur „vor" oder „hinter" einem Anker (LexoRank
    /// vergibt Schlüssel *zwischen* zwei bestehenden). Diese Funktion beantwortet, welcher Nachbar
    /// der Anker ist.
    ///
    /// **Vorzugsweise der Vorgänger** (`after`): hängt die Karte hinter ihrem linken Nachbarn,
    /// bleibt sie auch dann richtig, wenn hinter ihr gleichzeitig etwas Neues einsortiert wird.
    /// Nur ganz oben gibt es keinen Vorgänger — dann `before` auf den, der bisher Erster war.
    ///
    /// - Parameters:
    ///   - keys: die Reihenfolge **vor** dem Verschieben
    ///   - from: Quellindex, `to`: Zielindex in SwiftUIs `onMove`-Zählweise
    /// - Returns: der bewegte Key, sein Anker und ob davor eingehängt wird — oder nil, wenn sich
    ///   nichts ändert (Liste zu kurz, Ziel gleich Quelle).
    public static func moveAnchor(keys: [String], from: Int, to: Int)
        -> (moved: String, anchor: String, before: Bool)? {
        guard keys.count > 1, from >= 0, from < keys.count else { return nil }
        var neu = keys
        let bewegt = neu.remove(at: from)
        // `onMove` zählt das Ziel in der Liste **vor** dem Entfernen — danach rutscht alles
        // dahinter um eins vor. Ohne diese Korrektur landet jede Abwärtsbewegung eine Position
        // zu weit oben.
        // Beidseitig eingefangen: `onMove` liefert zwar immer gültige Werte, aber ein Zielindex
        // ausserhalb der Liste ist ein Absturz („Negative Array index is out of range"), und diese
        // Funktion wird auch von den ⌘↑/⌘↓-Knöpfen gefüttert. Ein Zug, der danach nichts ändert,
        // fällt unten ohnehin als nil heraus.
        let zielIndex = min(max(0, to > from ? to - 1 : to), neu.count)
        neu.insert(bewegt, at: zielIndex)
        guard neu != keys else { return nil }
        if zielIndex == 0 {
            return (bewegt, neu[1], true)
        }
        return (bewegt, neu[zielIndex - 1], false)
    }

    private static func isEpic(_ ticket: Ticket) -> Bool {
        guard let type = ticket.type?.lowercased() else { return false }
        return type == "epic"
    }
}
