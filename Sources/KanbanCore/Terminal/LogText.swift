import Foundation

/// Der Puffer, in dem die Ausgabe eines laufenden Befehls steht (Stack-Panel, Stack-Sweep).
///
/// Zwei Dinge sind hier gemessen, nicht geschätzt:
///
/// 1. **Die Grösse wird in Bytes geprüft, nicht in Zeichen.** `String.count` zählt
///    Graphemcluster und läuft dafür über den ganzen Puffer; bei einem Anhängen je pty-Lesevorgang
///    (1407 davon für 66 KB Ausgabe, Ø 47 Byte) wurde daraus quadratische Arbeit — 46,8 ms allein
///    fürs Anhängen. `utf8.count` ist bei Swifts UTF-8-Strings O(1).
/// 2. **Gekappt wird in Blöcken und auf Zeilengrenze.** Bei jedem Anhängen zu kappen hiesse, den
///    ganzen Puffer jedes Mal zu kopieren; und ein Schnitt mitten in einer Zeile könnte eine
///    Escape-Sequenz oder ein Mehrbyte-Zeichen zerteilen, was die Ansicht als Müll zeigte. Deshalb
///    erst bei `limitBytes` auf `keepBytes` zurück, und dort bis zum nächsten Zeilenumbruch.
public enum LogText {
    /// Ab hier wird gekappt (~200 KB: ein `iwf stack build` bleibt darunter).
    public static let limitBytes = 200_000
    /// So viel bleibt stehen. Der Abstand zum Limit ist Absicht: er macht das Kappen selten.
    public static let keepBytes = 150_000

    /// Hängt `chunk` an `text` an und kappt vorne, wenn der Puffer zu gross wird.
    public static func appending(_ text: String, _ chunk: String) -> String {
        let combined = text + chunk
        guard combined.utf8.count > limitBytes else { return combined }
        return trimmed(combined)
    }

    /// Der Zuwachs, wenn `text` mit `old` anfängt — sonst nil (dann wurde vorne gekappt oder ein
    /// neuer Befehl gestartet, und die Ansicht muss neu aufbauen).
    ///
    /// Verglichen wird über die **UTF-8-Sicht**: ein Byte-Vergleich über 200 KB kostet nichts,
    /// während `String.hasPrefix` auf Unicode-Äquivalenz prüft und `String.count` die
    /// Graphemcluster des ganzen Puffers zählt.
    public static func appendedPart(of text: String, after old: String) -> String? {
        let new = text.utf8, previous = old.utf8
        guard new.count >= previous.count else { return nil }
        var i = previous.startIndex
        var j = new.startIndex
        while i < previous.endIndex {
            guard previous[i] == new[j] else { return nil }
            previous.formIndex(after: &i)
            new.formIndex(after: &j)
        }
        return String(decoding: new[j...], as: UTF8.self)
    }

    /// Die letzten `keepBytes`, ab dem ersten vollständigen Zeilenanfang darin.
    public static func trimmed(_ text: String) -> String {
        // `utf8.suffix` kann mitten in einem Zeichen schneiden; der Schnitt auf den nächsten
        // Zeilenumbruch räumt das mit weg, deshalb erst dekodieren, dann die Zeile verwerfen.
        var kept = String(decoding: text.utf8.suffix(keepBytes), as: UTF8.self)
        if let newline = kept.firstIndex(of: "\n") {
            kept = String(kept[kept.index(after: newline)...])
        }
        return kept
    }
}
