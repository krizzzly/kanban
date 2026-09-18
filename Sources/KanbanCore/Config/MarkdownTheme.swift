import Foundation

/// Die Schriftgrössen der gerenderten Ansichten, in Punkt.
///
/// Überschriften waren bis hierher **alle so gross wie der Fliesstext** (15 px) und nur an der
/// Strichstärke zu unterscheiden — auf einem Task-File mit `#`, `##` und `###` war die Gliederung
/// damit praktisch nicht zu sehen. Jetzt hat jede Ebene ihre eigene Grösse, und die steht im Theme,
/// weil sie Geschmack ist wie die Farben daneben.
public struct MarkdownFontSizes: Sendable, Hashable {
    public let body: Double
    public let h1: Double
    public let h2: Double
    public let h3: Double
    public let h4: Double
    public let h5: Double
    public let h6: Double

    public init(body: Double, h1: Double, h2: Double, h3: Double,
                h4: Double, h5: Double, h6: Double) {
        self.body = body
        self.h1 = h1
        self.h2 = h2
        self.h3 = h3
        self.h4 = h4
        self.h5 = h5
        self.h6 = h6
    }

    /// Eine ruhige Staffel um den 15-px-Fliesstext: H1 deutlich grösser, H4 auf Textgrösse (dort
    /// gliedert die Fettung, nicht die Grösse), H5/H6 kleiner — wie GitHub es macht.
    public static let standard = MarkdownFontSizes(body: 15, h1: 26, h2: 21, h3: 17,
                                                   h4: 15, h5: 14, h6: 13)

    /// Jede Grösse einzeln lesbar, damit die Config sie einzeln setzen kann.
    public func groesse(fuer ebene: Int) -> Double {
        switch ebene {
        case 1: return h1
        case 2: return h2
        case 3: return h3
        case 4: return h4
        case 5: return h5
        default: return h6
        }
    }
}

/// Die Farben der **gerenderten** Markdown-Ansichten: Task-File-Tabs, Knowledgebase, das
/// Dokumentfenster aus dem Finder und die Lese-Ansicht des Asset-Editors.
///
/// Konfiguriert wie das Terminal-Theme — im `markdown`-Abschnitt derselben Datei, ohne eigene
/// Oberfläche, aus demselben Grund: das ist Geschmack, den man einmal einstellt.
///
/// **Eine** Palette, kein Hell/Dunkel-Paar. Vorher wechselten die Farben mit dem
/// System-Erscheinungsbild (`prefers-color-scheme`), und die Fläche war *durchsichtig* — die
/// gerenderte Datei nahm den Hintergrund des SwiftUI-Bereichs an. Eine gerenderte Markdown-Datei ist
/// aber ein Blatt Papier, kein Fenster­teil: sie soll aussehen wie das, was sie zeigt, und nicht
/// mitwandern. Wer es dunkel will, stellt die sechs Werte dunkel — dann zieht auch
/// `color-scheme` nach (abgeleitet aus der Helligkeit des Hintergrunds).
public struct MarkdownTheme: Sendable, Hashable {
    /// Die Fläche selbst. Vorgabe **weiss** und **deckend**.
    public let background: TerminalRGB
    public let text: TerminalRGB
    /// Zitate, Fussnoten, Hilfszeilen.
    public let secondaryText: TerminalRGB
    /// Hintergrund von `code`, ```-Blöcken und Tabellenköpfen — hierhin gehört auch das
    /// Frontmatter, das als Codeblock gerendert wird (siehe `Frontmatter`).
    public let codeBackground: TerminalRGB
    public let link: TerminalRGB
    public let border: TerminalRGB
    /// Fliesstext und die sechs Überschriftenebenen (siehe `MarkdownFontSizes`).
    public let fontSizes: MarkdownFontSizes

    public init(background: TerminalRGB, text: TerminalRGB, secondaryText: TerminalRGB,
                codeBackground: TerminalRGB, link: TerminalRGB, border: TerminalRGB,
                fontSizes: MarkdownFontSizes = .standard) {
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.codeBackground = codeBackground
        self.link = link
        self.border = border
        self.fontSizes = fontSizes
    }

    private static func rgb(_ hex: String) -> TerminalRGB { TerminalRGB(hex: hex)! }

    /// Die Vorgabe: das bisherige helle Farbschema (aus MarkdownUIs `.gitHub`, das kanban-code
    /// benutzt), nur mit **deckendem** Weiss statt Durchsicht und einem etwas kräftigeren Grau für
    /// Codeblöcke — auf Weiss war `#f7f7f9` kaum von der Fläche zu unterscheiden.
    public static let standard = MarkdownTheme(
        background: rgb("#ffffff"),
        text: rgb("#060606"),
        secondaryText: rgb("#6b6e7b"),
        codeBackground: rgb("#f1f1f4"),
        link: rgb("#2c65cf"),
        border: rgb("#e4e4e8"))

    /// `#rrggbb` für CSS.
    public static func hex(_ c: TerminalRGB) -> String {
        String(format: "#%02x%02x%02x", c.r, c.g, c.b)
    }

    /// Wie WebKit die Fläche einschätzen soll — davon hängen Scrollbalken und Bedienelemente ab.
    /// Abgeleitet aus der Helligkeit des Hintergrunds, damit eine dunkel konfigurierte Palette keine
    /// weissen Scrollbalken bekommt.
    public var colorScheme: String {
        let helligkeit = (0.299 * Double(background.r) + 0.587 * Double(background.g)
                          + 0.114 * Double(background.b)) / 255
        return helligkeit < 0.5 ? "dark" : "light"
    }

    /// Eine etwas abgesetzte Linie für Trenner — aus `border` abgeleitet statt als siebtes Feld:
    /// zwei Grautöne, die sich um 10 % unterscheiden, will niemand einzeln einstellen.
    public var divider: TerminalRGB {
        func dunkler(_ v: UInt8) -> UInt8 { UInt8(max(0, Int(v) - 20)) }
        return TerminalRGB(r: dunkler(border.r), g: dunkler(border.g), b: dunkler(border.b))
    }
}
