import Foundation

/// A plain 8-bit-per-channel RGB colour. UI-agnostic on purpose — the Kanban target maps it to
/// `NSColor` / SwiftTerm's `Color`, so `KanbanCore` stays free of AppKit.
public struct TerminalRGB: Sendable, Hashable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    /// Parses `#rrggbb` or `rrggbb` (case-insensitive). Returns nil for anything else.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }
}

/// A terminal colour scheme, mirroring the fields of an iTerm2 `.itermcolors` file. `ansi` holds the
/// 16 standard ANSI colours (0–7 normal, 8–15 bright), in order.
public struct TerminalTheme: Sendable, Hashable {
    public let name: String
    public let background: TerminalRGB
    public let foreground: TerminalRGB
    public let cursor: TerminalRGB
    public let cursorText: TerminalRGB?
    public let selectionBackground: TerminalRGB?
    public let selectionText: TerminalRGB?
    public let ansi: [TerminalRGB]   // exactly 16

    public init(name: String, background: TerminalRGB, foreground: TerminalRGB, cursor: TerminalRGB,
                cursorText: TerminalRGB? = nil, selectionBackground: TerminalRGB? = nil,
                selectionText: TerminalRGB? = nil, ansi: [TerminalRGB]) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionText = selectionText
        self.ansi = ansi
    }
}

extension TerminalTheme {
    /// Die Fassung als JSON-Objekt — für „neue Fassung als Kopie" und für den Seed. Optionales
    /// bleibt weg, wenn es nicht gesetzt ist: ein `"cursorText": null` in der Datei wäre Rauschen.
    public var werte: JSONValue {
        var obj: [String: JSONValue] = [
            "background": .string(MarkdownTheme.hex(background)),
            "foreground": .string(MarkdownTheme.hex(foreground)),
            "cursor": .string(MarkdownTheme.hex(cursor)),
            "ansi": .array(ansi.map { .string(MarkdownTheme.hex($0)) }),
        ]
        if let cursorText { obj["cursorText"] = .string(MarkdownTheme.hex(cursorText)) }
        if let selectionBackground { obj["selectionBackground"] = .string(MarkdownTheme.hex(selectionBackground)) }
        if let selectionText { obj["selectionText"] = .string(MarkdownTheme.hex(selectionText)) }
        return .object(obj)
    }
}

// MARK: - Built-in themes

extension TerminalTheme {
    private static func rgb(_ hex: String) -> TerminalRGB { TerminalRGB(hex: hex)! }

    /// iTerm2 "Solarized Dark" (Ethan Schoonover), imported from the iTerm2-Color-Schemes repo.
    public static let solarizedDark = TerminalTheme(
        name: "Solarized Dark",
        background: rgb("#002b36"),
        foreground: rgb("#839496"),
        cursor: rgb("#839496"),
        cursorText: rgb("#073642"),
        selectionBackground: rgb("#073642"),
        selectionText: rgb("#93a1a1"),
        ansi: [
            rgb("#073642"), rgb("#dc322f"), rgb("#859900"), rgb("#b58900"),
            rgb("#268bd2"), rgb("#d33682"), rgb("#2aa198"), rgb("#eee8d5"),
            rgb("#002b36"), rgb("#cb4b16"), rgb("#586e75"), rgb("#657b83"),
            rgb("#839496"), rgb("#6c71c4"), rgb("#93a1a1"), rgb("#fdf6e3"),
        ]
    )

    /// The original hand-tuned Kanban dark palette (bg `#000f13`, green caret).
    public static let kanbanDark = TerminalTheme(
        name: "Kanban Dark",
        background: rgb("#000f13"),
        foreground: rgb("#ededed"),
        cursor: rgb("#5af78e"),
        cursorText: rgb("#000f13"),
        selectionBackground: rgb("#333333"),
        selectionText: rgb("#ffffff"),
        ansi: [
            rgb("#333333"), rgb("#ff5f56"), rgb("#5af78e"), rgb("#ffd75f"),
            rgb("#57acff"), rgb("#ff6ac1"), rgb("#5af7d4"), rgb("#e0e0e0"),
            rgb("#666666"), rgb("#ff6e67"), rgb("#5af78e"), rgb("#fffc67"),
            rgb("#6bc1ff"), rgb("#ff77d0"), rgb("#5af7d4"), rgb("#ffffff"),
        ]
    )
}

// MARK: - Font settings

/// Terminal font configuration. `size` is the point size **before** the app-wide UI scale is applied.
/// `smoothing` toggles macOS font smoothing (anti-aliasing / "thin strokes"). `family` is an optional
/// preferred font name; when nil or unavailable the app falls back to its built-in candidates.
public struct TerminalFontSettings: Sendable, Hashable {
    public let size: Double
    public let smoothing: Bool
    public let family: String?

    public init(size: Double, smoothing: Bool, family: String?) {
        self.size = size
        self.smoothing = smoothing
        self.family = family
    }

    public static let `default` = TerminalFontSettings(size: 16, smoothing: true, family: nil)
}

// MARK: - Settings loading

public extension Notification.Name {
    /// Die Darstellung wurde neu geladen (`KanbanSettingsStore.reload()`). Wer sein Aussehen selbst
    /// zusammenbaut, zeichnet daraufhin neu — SwiftUI merkt von einer Datei auf der Platte nichts.
    static let kanbanAppearanceChanged = Notification.Name("KanbanAppearanceChanged")
}

/// Everything the app needs from its own (writable) config, resolved and validated.
public struct KanbanSettings: Sendable {
    public let activeTerminalTheme: TerminalTheme
    public let terminalThemes: [TerminalTheme]
    public let font: TerminalFontSettings
    /// When false (default), the ⌥ Option key produces composed characters (needed on Swiss/German
    /// layouts for `# @ { } [ ] |` …). Set true to treat Option as the Meta key instead.
    public let optionAsMeta: Bool
    /// Die **aktive** Fassung der gerenderten Markdown-Ansichten (`markdown.theme`).
    public let markdown: MarkdownTheme
    /// Alle benannten Markdown-Fassungen, nach Namen sortiert — dieselbe Form wie `terminalThemes`.
    public let markdownThemes: [MarkdownTheme]
}

/// Reads (and, on first launch, seeds) the terminal part of Kanban's config. Same file as
/// `KanbanConfig` — the modules live next to `terminal` in it, hence the shared `fileURL`.
public enum KanbanSettingsStore {
    public static var fileURL: URL { KanbanConfig.fileURL }

    /// Der gelebte Stand. **Neu ladbar**, und das ist der Punkt: vorher war das ein `static let`,
    /// also ein Wert pro Prozess — eine geänderte Farbe wirkte erst nach einem Neustart der App.
    /// Eine Einstellung, die man speichert und nicht sieht, hält man für kaputt.
    public private(set) static var current: KanbanSettings = load()

    /// Nach dem Speichern der Einstellungen: Datei neu lesen und alle anstossen, die davon leben.
    /// Die Benachrichtigung ist der Weg zu den Ansichten, die ihr Aussehen selbst bauen — von einer
    /// geänderten Datei auf der Platte erfährt SwiftUI nichts.
    @discardableResult
    public static func reload() -> KanbanSettings {
        current = load()
        NotificationCenter.default.post(name: .kanbanAppearanceChanged, object: nil)
        return current
    }

    /// Loads the settings, seeding a default config file on first launch. Never throws: on any error
    /// it falls back to the built-in Solarized Dark theme.
    public static func load() -> KanbanSettings {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? defaultConfigJSON.data(using: .utf8)?.write(to: url, options: .atomic)
        }
        guard let data = try? Data(contentsOf: url) else { return fallback }
        return parse(data)
    }

    /// Decodes and resolves settings from raw JSON. Filesystem-free, so it is unit-testable.
    public static func parse(_ data: Data) -> KanbanSettings {
        guard let raw = try? JSONDecoder().decode(RawSettings.self, from: data) else { return fallback }
        return resolve(raw)
    }

    private static var fallback: KanbanSettings {
        KanbanSettings(activeTerminalTheme: .solarizedDark,
                       terminalThemes: [.solarizedDark, .kanbanDark],
                       font: .default,
                       optionAsMeta: false,
                       markdown: .standard,
                       markdownThemes: MarkdownTheme.vorgaben)
    }

    private static func resolve(_ raw: RawSettings) -> KanbanSettings {
        let parsed: [TerminalTheme] = (raw.terminal?.themes ?? [:]).compactMap { name, t in
            t.resolved(name: name)
        }
        let themes = parsed.isEmpty ? [.solarizedDark, .kanbanDark] : parsed.sorted { $0.name < $1.name }
        let active = raw.terminal?.theme.flatMap { name in themes.first { $0.name == name } }
            ?? themes.first!
        let md = resolveMarkdownThemes(raw.markdown)
        return KanbanSettings(activeTerminalTheme: active, terminalThemes: themes,
                              font: resolveFont(raw.terminal?.font),
                              optionAsMeta: raw.terminal?.optionAsMeta ?? false,
                              markdown: md.aktiv, markdownThemes: md.alle)
    }

    /// Die Markdown-Fassungen wie beim Terminal: benannte Einträge unter `markdown.themes`, die
    /// aktive über `markdown.theme`.
    ///
    /// Reihenfolge der Auflösung — **`themes` gewinnt**: gibt es benannte Fassungen, gelten nur
    /// sie. Sonst zählt ein flacher Altblock als Fassung `Eigene` (wer den Block je von Hand
    /// angelegt hat, verliert ihn nicht). Ist auch der leer, kommen die mitgelieferten.
    static func resolveMarkdownThemes(_ raw: RawMarkdown?) -> (aktiv: MarkdownTheme,
                                                              alle: [MarkdownTheme]) {
        let benannt = (raw?.themes ?? [:])
            .map { name, roh in resolveMarkdown(roh, name: name) }
            .sorted { $0.name < $1.name }
        let alle: [MarkdownTheme]
        if !benannt.isEmpty {
            alle = benannt
        } else if let raw, !raw.istLeer {
            alle = [resolveMarkdown(raw, name: MarkdownTheme.eigeneName)]
        } else {
            alle = MarkdownTheme.vorgaben
        }
        // Ein Name, den es nicht (mehr) gibt, ist kein Fehler: dann gilt die erste Fassung.
        let aktiv = raw?.theme.flatMap { name in alle.first { $0.name == name } } ?? alle[0]
        return (aktiv, alle)
    }

    /// Jede Farbe einzeln: ein unlesbarer Wert fällt auf die Vorgabe zurück, statt die ganze
    /// Palette (oder die Config) zu Fall zu bringen — eine falsche Farbe soll man sehen und
    /// korrigieren, nicht daran scheitern.
    static func resolveMarkdown(_ raw: RawMarkdown?, name: String = MarkdownTheme.eigeneName)
        -> MarkdownTheme {
        let vorgabe = MarkdownTheme.standard
        guard let raw else { return vorgabe }
        func farbe(_ hex: String?, _ fallback: TerminalRGB) -> TerminalRGB {
            hex.flatMap(TerminalRGB.init(hex:)) ?? fallback
        }
        // Leer heisst Systemschrift, nicht „Schrift ohne Namen" — sonst ergaebe ein geleertes Feld
        // in den Einstellungen eine kaputte CSS-Regel statt der Vorgabe.
        func schrift(_ name: String?) -> String? {
            let getrimmt = name?.trimmingCharacters(in: .whitespaces)
            return (getrimmt?.isEmpty ?? true) ? nil : getrimmt
        }
        return MarkdownTheme(
            name: name,
            background: farbe(raw.background, vorgabe.background),
            text: farbe(raw.text, vorgabe.text),
            secondaryText: farbe(raw.secondaryText, vorgabe.secondaryText),
            codeBackground: farbe(raw.codeBackground, vorgabe.codeBackground),
            link: farbe(raw.link, vorgabe.link),
            border: farbe(raw.border, vorgabe.border),
            fontSizes: resolveFontSizes(body: raw.fontSize, headings: raw.headings),
            fontFamily: schrift(raw.fontFamily),
            headingFont: schrift(raw.headingFont),
            headingFonts: MarkdownHeadingFonts(h1: schrift(raw.headingFonts?.h1),
                                               h2: schrift(raw.headingFonts?.h2),
                                               h3: schrift(raw.headingFonts?.h3),
                                               h4: schrift(raw.headingFonts?.h4),
                                               h5: schrift(raw.headingFonts?.h5),
                                               h6: schrift(raw.headingFonts?.h6)))
    }

    /// Grössen wie die Farben: einzeln, mit Rückfallwert, und **begrenzt** (8–72 pt). Eine 0 oder
    /// eine 900 in der Config macht die Ansicht sonst unbenutzbar, ohne dass man sähe, warum.
    static func resolveFontSizes(body: LenientNumber?, headings: RawHeadings?) -> MarkdownFontSizes {
        let vorgabe = MarkdownFontSizes.standard
        func punkt(_ zahl: LenientNumber?, _ fallback: Double) -> Double {
            guard let wert = zahl?.wert else { return fallback }
            return Swift.min(Swift.max(wert, 8), 72)
        }
        return MarkdownFontSizes(
            body: punkt(body, vorgabe.body),
            h1: punkt(headings?.h1, vorgabe.h1),
            h2: punkt(headings?.h2, vorgabe.h2),
            h3: punkt(headings?.h3, vorgabe.h3),
            h4: punkt(headings?.h4, vorgabe.h4),
            h5: punkt(headings?.h5, vorgabe.h5),
            h6: punkt(headings?.h6, vorgabe.h6))
    }

    private static func resolveFont(_ raw: RawFont?) -> TerminalFontSettings {
        let size = raw?.size?.wert.map { min(max($0, 6), 72) } ?? TerminalFontSettings.default.size
        let family = raw?.family.flatMap { $0.isEmpty ? nil : $0 }
        return TerminalFontSettings(size: size,
                                    smoothing: raw?.smoothing ?? TerminalFontSettings.default.smoothing,
                                    family: family)
    }
}

// MARK: - Raw decoding shapes

private struct RawSettings: Decodable {
    let terminal: RawTerminal?
    let markdown: RawMarkdown?
}

struct RawMarkdown: Decodable {
    /// Name der aktiven Fassung (`markdown.theme`) — steht nur im obersten Block, nicht in den
    /// Fassungen selbst.
    let theme: String?
    /// Die benannten Fassungen. Dieselbe Form wie der flache Block, damit ein Altblock unverändert
    /// als Fassung durchgeht.
    let themes: [String: RawMarkdown]?
    let fontFamily: String?
    let headingFont: String?
    let background: String?
    let text: String?
    let secondaryText: String?
    let codeBackground: String?
    let link: String?
    let border: String?
    let fontSize: LenientNumber?
    let headings: RawHeadings?
    /// Schrift je Überschriftenebene — die Grössen stehen nebenan in `headings`, damit die alte
    /// Form dieses Blocks unverändert gültig bleibt.
    let headingFonts: RawHeadingFonts?

    /// Trägt der Block selbst etwas, oder steht dort nur die Auswahl? Entscheidet, ob ein Altblock
    /// als Fassung `Eigene` gilt oder die mitgelieferten greifen.
    var istLeer: Bool {
        fontFamily == nil && headingFont == nil && background == nil && text == nil
            && secondaryText == nil && codeBackground == nil && link == nil && border == nil
            && fontSize == nil && headings == nil && headingFonts == nil
    }
}

struct RawHeadingFonts: Decodable {
    let h1: String?
    let h2: String?
    let h3: String?
    let h4: String?
    let h5: String?
    let h6: String?
}

/// Eine Zahl, die in der Datei als Zahl **oder** als Zeichenkette stehen darf.
///
/// Der Grund ist unangenehm konkret: `RawSettings` wird mit **einem** `try?` gelesen. Wirft der
/// Decoder an einem einzigen Wert, greift `fallback` — und zwar für **alles**, Terminal-Theme
/// eingeschlossen. Gemessen: ein `"fontSize": 16` (Zahl statt Zeichenkette) setzte die komplette
/// Darstellung auf die Vorgaben zurück, ohne Fehlermeldung. Beide Schreibweisen anzunehmen ist
/// billiger als jede Erklärung dafür — und die Einstellungen schreiben ab jetzt Zahlen.
struct LenientNumber: Decodable, Sendable, Hashable {
    let wert: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let zahl = try? container.decode(Double.self) {
            wert = zahl
        } else if let text = try? container.decode(String.self) {
            wert = Double(text.trimmingCharacters(in: .whitespaces))
        } else {
            wert = nil   // null, Objekt, Liste: nicht lesbar, aber kein Grund zu werfen
        }
    }
}

/// Die Überschriftengrössen stehen verschachtelt (`markdown.headings.h1`), damit die Datei nicht
/// sechs `h…`-Schlüssel neben den Farben trägt.
struct RawHeadings: Decodable {
    let h1: LenientNumber?
    let h2: LenientNumber?
    let h3: LenientNumber?
    let h4: LenientNumber?
    let h5: LenientNumber?
    let h6: LenientNumber?
}

private struct RawTerminal: Decodable {
    let theme: String?                    // active theme name
    let font: RawFont?
    let optionAsMeta: Bool?
    let themes: [String: RawTheme]?
}

private struct RawFont: Decodable {
    let size: LenientNumber?
    let smoothing: Bool?
    let family: String?
}

private struct RawTheme: Decodable {
    let background: String
    let foreground: String
    let cursor: String?
    let cursorText: String?
    let selectionBackground: String?
    let selectionText: String?
    let ansi: [String]

    /// Resolves to a validated `TerminalTheme`, or nil if a required colour is malformed or `ansi`
    /// doesn't hold exactly 16 valid colours.
    func resolved(name: String) -> TerminalTheme? {
        guard let bg = TerminalRGB(hex: background),
              let fg = TerminalRGB(hex: foreground) else { return nil }
        let ansiRGB = ansi.compactMap(TerminalRGB.init(hex:))
        guard ansiRGB.count == 16 else { return nil }
        let cur = cursor.flatMap(TerminalRGB.init(hex:)) ?? fg
        return TerminalTheme(
            name: name,
            background: bg,
            foreground: fg,
            cursor: cur,
            cursorText: cursorText.flatMap(TerminalRGB.init(hex:)),
            selectionBackground: selectionBackground.flatMap(TerminalRGB.init(hex:)),
            selectionText: selectionText.flatMap(TerminalRGB.init(hex:)),
            ansi: ansiRGB
        )
    }
}

// MARK: - Seed config

/// Written verbatim on first launch. `theme` selects the active scheme by name; add more entries
/// under `themes` (same shape) to define your own. `ansi` must list exactly 16 `#rrggbb` colours.
///
/// Der `markdown`-Abschnitt steht seit KANBAN-005 mit drin: vorher gab es die Werte zwar, aber in
/// keiner Datei — man musste wissen, dass es sie gibt, um sie zu suchen.
let defaultConfigJSON = """
{
  "terminal": {
    "theme": "Solarized Dark",
    "optionAsMeta": false,
    "font": {
      "size": 16,
      "smoothing": true,
      "family": "Meslo LG S DZ Regular for Powerline"
    },
    "themes": {
      "Solarized Dark": {
        "background": "#002b36",
        "foreground": "#839496",
        "cursor": "#839496",
        "cursorText": "#073642",
        "selectionBackground": "#073642",
        "selectionText": "#93a1a1",
        "ansi": [
          "#073642", "#dc322f", "#859900", "#b58900",
          "#268bd2", "#d33682", "#2aa198", "#eee8d5",
          "#002b36", "#cb4b16", "#586e75", "#657b83",
          "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"
        ]
      },
      "Kanban Dark": {
        "background": "#000f13",
        "foreground": "#ededed",
        "cursor": "#5af78e",
        "cursorText": "#000f13",
        "selectionBackground": "#333333",
        "selectionText": "#ffffff",
        "ansi": [
          "#333333", "#ff5f56", "#5af78e", "#ffd75f",
          "#57acff", "#ff6ac1", "#5af7d4", "#e0e0e0",
          "#666666", "#ff6e67", "#5af78e", "#fffc67",
          "#6bc1ff", "#ff77d0", "#5af7d4", "#ffffff"
        ]
      }
    }
  },
  "markdown": {
    "theme": "Blatt",
    "themes": {
      "Blatt": {
        "background": "#ffffff",
        "text": "#060606",
        "secondaryText": "#6b6e7b",
        "codeBackground": "#f1f1f4",
        "link": "#2c65cf",
        "border": "#e4e4e8",
        "fontSize": 15,
        "headings": { "h1": 26, "h2": 21, "h3": 17, "h4": 15, "h5": 14, "h6": 13 }
      },
      "Blatt Dunkel": {
        "background": "#16181c",
        "text": "#e6e7ea",
        "secondaryText": "#9aa0ab",
        "codeBackground": "#22262d",
        "link": "#7aa7ff",
        "border": "#2d323b",
        "fontSize": 15,
        "headings": { "h1": 26, "h2": 21, "h3": 17, "h4": 15, "h5": 14, "h6": 13 }
      }
    }
  }
}

"""
