import Foundation

/// Zu welchem Projekt gehört ein Ticket?
///
/// Die Frage stellt sich an zwei Stellen, seit jedes Projekt sein eigenes Fenster hat: beim
/// Deep-Link (`Kanban --select BFEZVM-4259` muss wissen, welches Board er aufmacht) und beim Klick
/// auf eine Benachrichtigung (sie soll das Ticket im Fenster **seines** Projekts zeigen, nicht im
/// gerade vordersten). Beide Male entscheidet der Präfix — und deshalb steht die Regel hier, wo sie
/// ohne UI prüfbar ist.
public enum TicketRouting {

    /// Das Projekt, dessen Präfix den Ticket-Key trägt — oder nil.
    ///
    /// Der Trennstrich gehört zur Prüfung: ein Ticket heisst `<PREFIX>-<zahl>`, und ohne ihn zöge
    /// ein kürzerer Präfix die Tickets eines längeren an sich (`EVEN` alle von `EVENT`). Karten ohne
    /// Ticketnummer (`!130`, siehe `LocalTickets`) gehören zu keinem Präfix und damit zu keinem
    /// Projekt — sie kommen über das Repo, nicht über die Nummer.
    public static func projekt(fuerTicket key: String, in projekte: [ProjectConfig]) -> ProjectConfig? {
        let gross = key.uppercased()
        return projekte.first { gross.hasPrefix($0.prefix.uppercased() + "-") }
    }
}
