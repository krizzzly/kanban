import Foundation

/// Die Suche über dem Board: **eine** Eingabe, zwei Felder — Ticketnummer und Titel.
///
/// Gesucht wird als Teilstring und ohne Rücksicht auf Gross-/Kleinschreibung. Wer „4237" tippt,
/// meint CORETEST-4237 und hat den Präfix gar nicht erst getippt — ein Vergleich auf den ganzen Key
/// fände hier nichts.
///
/// Mehrere Begriffe sind ein **Und**, und jeder darf in einem anderen Feld sitzen: „4237 refund"
/// findet das Ticket über die Nummer *und* ein Wort aus dem Titel. Ein einzelner Teilstring über
/// „Key + Titel" scheiterte daran, weil zwischen beidem der Rest des Titels steht.
public enum TicketFilter {
    /// Passt das Ticket zur Eingabe?
    ///
    /// Eine leere Eingabe passt immer: kein Filter ist kein Filter, nicht „nichts gefunden".
    public static func matches(key: String, summary: String, query: String) -> Bool {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return true }
        let haystack = "\(key) \(summary)".lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}
