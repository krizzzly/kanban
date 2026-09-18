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

/// Eine Schriftart je Überschriftenebene — typischerweise, um H1 abzusetzen.
///
/// nil heisst „wie die anderen Überschriften": darunter liegt `headingFont` (gemeinsam für alle
/// sechs), darunter `fontFamily`, darunter die Systemschrift. Eine leere Ebene ändert also nichts.
public struct MarkdownHeadingFonts: Sendable, Hashable {
    public let h1: String?
    public let h2: String?
    public let h3: String?
    public let h4: String?
    public let h5: String?
    public let h6: String?

    public init(h1: String? = nil, h2: String? = nil, h3: String? = nil,
                h4: String? = nil, h5: String? = nil, h6: String? = nil) {
        self.h1 = h1
        self.h2 = h2
        self.h3 = h3
        self.h4 = h4
        self.h5 = h5
        self.h6 = h6
    }

    public static let keine = MarkdownHeadingFonts()

    public var istLeer: Bool {
        h1 == nil && h2 == nil && h3 == nil && h4 == nil && h5 == nil && h6 == nil
    }

    public func schrift(fuer ebene: Int) -> String? {
        switch ebene {
        case 1: return h1
        case 2: return h2
        case 3: return h3
        case 4: return h4
        case 5: return h5
        default: return h6
        }
    }

    /// Die sechs Ebenen als JSON — nur, was gesetzt ist.
    public var werte: JSONValue? {
        var obj: [String: JSONValue] = [:]
        for ebene in 1...6 {
            if let name = schrift(fuer: ebene) { obj["h\(ebene)"] = .string(name) }
        }
        return obj.isEmpty ? nil : .object(obj)
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
    /// Der Name der Fassung — so steht sie unter `markdown.themes` und so heisst sie in der Auswahl.
    /// Ein von Hand angelegter flacher `markdown`-Block hat keinen; er wird als `Eigene` gelesen.
    public let name: String
    /// Die Fläche selbst. Vorgabe **weiss** und **deckend**.
    public let background: TerminalRGB
    public let text: TerminalRGB
    /// Zitate, Fussnoten, Hilfszeilen.
    public let secondaryText: TerminalRGB
    /// Hintergrund von `code`, ```-Blöcken, Tabellenköpfen und Zebrastreifen — hierhin gehört auch
    /// das Frontmatter, das als Codeblock gerendert wird (siehe `Frontmatter`).
    ///
    /// **nil heisst „aus dem Blatt abgeleitet"** (siehe `shade` und `flaeche`). Eine feste Farbe
    /// hier hiess bisher: wer den Hintergrund ändert, behält graue Codeblöcke auf blauem Blatt.
    /// Gesetzt gewinnt sie weiterhin — wer eine exakte Farbe will, bekommt sie.
    public let codeBackground: TerminalRGB?
    /// Wie stark sich diese Flächen vom Blatt absetzen, in Prozent (0–100). Vorgabe 6.
    public let link: TerminalRGB
    public let border: TerminalRGB
    /// Fliesstext und die sechs Überschriftenebenen (siehe `MarkdownFontSizes`).
    public let fontSizes: MarkdownFontSizes
    /// Schriftart des Fliesstextes — **nil heisst Systemschrift**, nicht „keine". Der Name ist der,
    /// den die Schriftsammlung zeigt (`Iowan Old Style`), ohne Anführungszeichen.
    public let fontFamily: String?
    /// Schriftart der Überschriften als **gemeinsamer** Wert für alle sechs Ebenen. nil = wie der
    /// Fliesstext.
    public let headingFont: String?
    /// Schrift je Ebene, wo eine Ebene aus der Reihe tanzen soll (typischerweise H1).
    public let headingFonts: MarkdownHeadingFonts

    public let shade: Double

    public static let shadeVorgabe: Double = 6

    public init(name: String = MarkdownTheme.eigeneName,
                background: TerminalRGB, text: TerminalRGB, secondaryText: TerminalRGB,
                codeBackground: TerminalRGB? = nil, shade: Double = MarkdownTheme.shadeVorgabe,
                link: TerminalRGB, border: TerminalRGB,
                fontSizes: MarkdownFontSizes = .standard,
                fontFamily: String? = nil, headingFont: String? = nil,
                headingFonts: MarkdownHeadingFonts = .keine) {
        self.name = name
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.codeBackground = codeBackground
        self.shade = shade
        self.link = link
        self.border = border
        self.fontSizes = fontSizes
        self.fontFamily = fontFamily
        self.headingFont = headingFont
        self.headingFonts = headingFonts
    }

    /// Die Schrift **dieser** Überschriftenebene, mit den Rückfällen in der Reihenfolge, in der sie
    /// gemeint sind: eigene Ebene → gemeinsame Überschriftenschrift → Fliesstext → Systemschrift.
    public func schrift(fuerUeberschrift ebene: Int) -> String? {
        headingFonts.schrift(fuer: ebene) ?? headingFont ?? fontFamily
    }

    /// Der CSS-Wert für `font-family`: der konfigurierte Name, gefolgt von der bisherigen Kette als
    /// Rückfall. Ohne Eintrag bleibt genau die Kette übrig, die vorher fest im Stylesheet stand.
    ///
    /// Der Name wird **entschärft**, bevor er dort landet: Anführungszeichen, Semikolon oder
    /// geschweifte Klammern könnten die Regel verlassen und den Rest des Stylesheets kippen. Das ist
    /// die eigene Config, also kein Angriff — aber ein Tippfehler soll die Ansicht nicht zerlegen.
    public static func cssFontStack(_ name: String?) -> String {
        let fallback = "-apple-system, system-ui, \"Helvetica Neue\", sans-serif"
        guard let name else { return fallback }
        let sauber = name.filter { !"\";{}\n\r\\".contains($0) }
            .trimmingCharacters(in: .whitespaces)
        guard !sauber.isEmpty else { return fallback }
        return "\"\(sauber)\", \(fallback)"
    }

    /// Die tatsächlich gezeichnete Fläche: die gesetzte Farbe, sonst das um `shade` Prozent
    /// abgesetzte Blatt.
    public var flaeche: TerminalRGB {
        codeBackground ?? Self.abgesetzt(background, prozent: shade)
    }

    /// Den Hintergrund um `prozent` **relativ** abdunkeln — die Fläche folgt damit dem Blatt,
    /// statt als fester Grauton darauf zu liegen.
    ///
    /// Auf einem dunklen Blatt wird um denselben Anteil **aufgehellt**, und zwar nicht aus
    /// Geschmack: `#16181c` um 6 % abzudunkeln ergibt `#15161a` — ein Unterschied von einem
    /// Zahlenschritt, den kein Bildschirm zeigt. Die Richtung leitet sich wie `color-scheme` aus der
    /// Helligkeit des Hintergrunds ab. Wer es anders will, setzt die Farbe direkt.
    public static func abgesetzt(_ grund: TerminalRGB, prozent: Double) -> TerminalRGB {
        let anteil = min(max(prozent, 0), 100) / 100
        let helligkeit = (0.299 * Double(grund.r) + 0.587 * Double(grund.g)
                          + 0.114 * Double(grund.b)) / 255
        func kanal(_ wert: UInt8) -> UInt8 {
            let v = Double(wert)
            // Hell: Richtung Schwarz, anteilig am Wert. Dunkel: Richtung Weiss, anteilig am Rest.
            let neu = helligkeit < 0.5 ? v + (255 - v) * anteil : v * (1 - anteil)
            return UInt8(min(max(neu.rounded(), 0), 255))
        }
        return TerminalRGB(r: kanal(grund.r), g: kanal(grund.g), b: kanal(grund.b))
    }

    private static func rgb(_ hex: String) -> TerminalRGB { TerminalRGB(hex: hex)! }

    /// Der Name, unter dem ein flacher `markdown`-Block ohne `themes` gelesen wird — und unter dem
    /// er beim ersten Speichern in die Themes-Map übernommen wird.
    public static let eigeneName = "Eigene"

    /// Die Vorgabe: das bisherige helle Farbschema (aus MarkdownUIs `.gitHub`, das kanban-code
    /// benutzt), nur mit **deckendem** Weiss statt Durchsicht und einem etwas kräftigeren Grau für
    /// Codeblöcke — auf Weiss war `#f7f7f9` kaum von der Fläche zu unterscheiden.
    public static let standard = MarkdownTheme(
        name: "Blatt",
        background: rgb("#ffffff"),
        text: rgb("#060606"),
        secondaryText: rgb("#6b6e7b"),
        link: rgb("#2c65cf"),
        border: rgb("#e4e4e8"))

    /// Das Gegenstück in Dunkel. **Kein** Hell/Dunkel-Paar zu `Blatt`, sondern eine zweite Fassung,
    /// zwischen denen man von Hand wechselt: eine gerenderte Datei ist ein Blatt Papier und soll
    /// nicht mit dem System-Erscheinungsbild mitwandern. `color-scheme` leitet sich aus der
    /// Helligkeit des Hintergrunds ab, die Scrollbalken ziehen also mit.
    public static let blattDunkel = MarkdownTheme(
        name: "Blatt Dunkel",
        background: rgb("#16181c"),
        text: rgb("#e6e7ea"),
        secondaryText: rgb("#9aa0ab"),
        link: rgb("#7aa7ff"),
        border: rgb("#2d323b"))

    /// Was mitgeliefert wird, wenn die Datei keine eigene Fassung hat.
    public static let vorgaben: [MarkdownTheme] = [.standard, .blattDunkel]

    /// Die Fassung als JSON-Objekt — für den Seed, für „neue Fassung als Kopie" und für die
    /// einmalige Übernahme eines flachen Altblocks.
    public var werte: JSONValue {
        var obj: [String: JSONValue] = [
            "background": .string(MarkdownTheme.hex(background)),
            "text": .string(MarkdownTheme.hex(text)),
            "secondaryText": .string(MarkdownTheme.hex(secondaryText)),
            "link": .string(MarkdownTheme.hex(link)),
            "border": .string(MarkdownTheme.hex(border)),
            "fontSize": .double(fontSizes.body),
            "headings": .object([
                "h1": .double(fontSizes.h1), "h2": .double(fontSizes.h2),
                "h3": .double(fontSizes.h3), "h4": .double(fontSizes.h4),
                "h5": .double(fontSizes.h5), "h6": .double(fontSizes.h6),
            ]),
        ]
        // Nur, was gesetzt ist: eine mitkopierte Code-Farbe hielte die Fläche fest, obwohl sie
        // dem Blatt folgen soll — genau das war der Fehler an der alten Form.
        if let codeBackground { obj["codeBackground"] = .string(MarkdownTheme.hex(codeBackground)) }
        if shade != MarkdownTheme.shadeVorgabe { obj["shade"] = .double(shade) }
        if let fontFamily { obj["fontFamily"] = .string(fontFamily) }
        if let headingFont { obj["headingFont"] = .string(headingFont) }
        if let schriften = headingFonts.werte { obj["headingFonts"] = schriften }
        return .object(obj)
    }

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
