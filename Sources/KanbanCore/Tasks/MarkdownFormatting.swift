import Foundation

/// Was die Knöpfe einer Markdown-Werkzeugleiste mit Text und Auswahl machen — **reine Rechnung**,
/// ohne AppKit. Die Ansicht reicht Text und Auswahl herein und setzt beides aus dem Ergebnis zurück.
///
/// Dass die Auswahl mit zurückkommt, ist kein Beiwerk: nach „Fett" muss der Cursor zwischen den
/// Sternchen stehen (leere Auswahl) bzw. der markierte Text markiert bleiben (sonst tippt man beim
/// nächsten Knopf über die eigene Auswahl).
public enum MarkdownFormatting {
    public struct Result: Equatable, Sendable {
        public let text: String
        public let selection: NSRange

        public init(text: String, selection: NSRange) {
            self.text = text
            self.selection = selection
        }
    }

    /// Umschliessende Auszeichnung: `**fett**`, `*kursiv*`, `` `code` ``.
    ///
    /// Steht die Auszeichnung schon da, wird sie **entfernt** statt verdoppelt — ein zweiter Klick
    /// auf „Fett" soll fett wieder wegnehmen und nicht `****so****` erzeugen.
    public static func inline(_ text: String, selection: NSRange, marker: String) -> Result {
        let zeichen = Array(text)
        let bereich = clamp(selection, zu: zeichen.count)
        let marke = Array(marker)
        let start = bereich.location
        let ende = bereich.location + bereich.length

        // Schon ausgezeichnet? Die Marken stehen dann direkt **vor** und **hinter** der Auswahl —
        // und zwar **genau** so viele, wie die Marke lang ist.
        //
        // Die Länge mitzuzählen ist der Punkt: in `**wichtig**` sieht ein Kursiv-Klick sonst links
        // und rechts je ein `*`, hält das für „schon kursiv" und nimmt es weg — aus fett würde
        // stillschweigend kursiv. Gemeint war `***wichtig***`.
        if let zeichenDerMarke = marke.first,
           start >= marke.count, ende + marke.count <= zeichen.count,
           Array(zeichen[(start - marke.count)..<start]) == marke,
           Array(zeichen[ende..<(ende + marke.count)]) == marke,
           folge(zeichen, ab: start - 1, schritt: -1, zeichen: zeichenDerMarke) == marke.count,
           folge(zeichen, ab: ende, schritt: 1, zeichen: zeichenDerMarke) == marke.count {
            var neu = zeichen
            neu.removeSubrange(ende..<(ende + marke.count))
            neu.removeSubrange((start - marke.count)..<start)
            return Result(text: String(neu),
                          selection: NSRange(location: start - marke.count, length: bereich.length))
        }

        var neu = zeichen
        neu.insert(contentsOf: marke, at: ende)
        neu.insert(contentsOf: marke, at: start)
        return Result(text: String(neu),
                      selection: NSRange(location: start + marke.count, length: bereich.length))
    }

    /// Zeilenweise Auszeichnung: `# `, `- `, `> `. Betroffen ist **jede** Zeile, die die Auswahl
    /// berührt — eine markierte Liste soll mit einem Klick eine Liste werden, nicht nur ihre erste
    /// Zeile.
    ///
    /// Tragen bereits alle betroffenen Zeilen das Präfix, wird es entfernt (gleicher Gedanke wie
    /// oben: derselbe Knopf nimmt zurück, was er gesetzt hat).
    public static func linePrefix(_ text: String, selection: NSRange, prefix: String) -> Result {
        let zeichen = Array(text)
        let bereich = clamp(selection, zu: zeichen.count)
        let start = zeilenanfang(zeichen, vor: bereich.location)
        let ende = zeilenende(zeichen, ab: bereich.location + bereich.length)

        let block = String(zeichen[start..<ende])
        let zeilen = block.components(separatedBy: "\n")
        let entfernen = zeilen.allSatisfy { $0.hasPrefix(prefix) || $0.isEmpty }
            && zeilen.contains { $0.hasPrefix(prefix) }

        let neueZeilen = zeilen.map { zeile -> String in
            if entfernen { return zeile.hasPrefix(prefix) ? String(zeile.dropFirst(prefix.count)) : zeile }
            return zeile.isEmpty ? zeile : prefix + zeile
        }
        let neuerBlock = neueZeilen.joined(separator: "\n")

        var neu = zeichen
        neu.replaceSubrange(start..<ende, with: Array(neuerBlock))
        // Der ganze veränderte Block bleibt markiert: so wirkt ein zweiter Klick wieder auf dasselbe.
        return Result(text: String(neu),
                      selection: NSRange(location: start, length: neuerBlock.count))
    }

    /// `[Text](url)` — mit Auswahl wird sie der Linktext, ohne Auswahl entsteht ein Gerüst, in dem
    /// die URL markiert ist (das ist das Feld, das man als Nächstes füllt).
    public static func link(_ text: String, selection: NSRange) -> Result {
        let zeichen = Array(text)
        let bereich = clamp(selection, zu: zeichen.count)
        let beschriftung = String(zeichen[bereich.location..<(bereich.location + bereich.length)])
        let ersatz = "[\(beschriftung.isEmpty ? "Text" : beschriftung)](url)"

        var neu = zeichen
        neu.replaceSubrange(bereich.location..<(bereich.location + bereich.length), with: Array(ersatz))
        // Auf „url" zeigen: der Rest steht schon, das ist die offene Stelle.
        let urlStart = bereich.location + ersatz.count - 4
        return Result(text: String(neu), selection: NSRange(location: urlStart, length: 3))
    }

    // MARK: - Hilfen

    /// Eine Auswahl, die aus einem anderen Textstand stammt (Tippen und Klick können sich
    /// überholen), darf nicht über das Ende hinausreichen — sonst stürzt das Teilen der Zeichen ab.
    private static func clamp(_ range: NSRange, zu laenge: Int) -> NSRange {
        let start = Swift.min(Swift.max(range.location, 0), laenge)
        let length = Swift.min(Swift.max(range.length, 0), laenge - start)
        return NSRange(location: start, length: length)
    }

    /// Wie viele gleiche Zeichen ab `ab` in Richtung `schritt` ununterbrochen stehen.
    private static func folge(_ zeichen: [Character], ab: Int, schritt: Int,
                              zeichen gesucht: Character) -> Int {
        var i = ab
        var anzahl = 0
        while i >= 0, i < zeichen.count, zeichen[i] == gesucht {
            anzahl += 1
            i += schritt
        }
        return anzahl
    }

    private static func zeilenanfang(_ zeichen: [Character], vor position: Int) -> Int {
        var i = position
        while i > 0, zeichen[i - 1] != "\n" { i -= 1 }
        return i
    }

    private static func zeilenende(_ zeichen: [Character], ab position: Int) -> Int {
        var i = position
        while i < zeichen.count, zeichen[i] != "\n" { i += 1 }
        return i
    }
}
