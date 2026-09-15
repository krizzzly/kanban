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

/// Everything the app needs from its own (writable) config, resolved and validated.
public struct KanbanSettings: Sendable {
    public let activeTerminalTheme: TerminalTheme
    public let terminalThemes: [TerminalTheme]
    public let font: TerminalFontSettings
    /// When false (default), the ⌥ Option key produces composed characters (needed on Swiss/German
    /// layouts for `# @ { } [ ] |` …). Set true to treat Option as the Meta key instead.
    public let optionAsMeta: Bool
}

/// Reads (and, on first launch, seeds) the terminal part of Kanban's config. Same file as
/// `KanbanConfig` — the modules live next to `terminal` in it, hence the shared `fileURL`.
public enum KanbanSettingsStore {
    public static var fileURL: URL { KanbanConfig.fileURL }

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
                       optionAsMeta: false)
    }

    private static func resolve(_ raw: RawSettings) -> KanbanSettings {
        let parsed: [TerminalTheme] = (raw.terminal?.themes ?? [:]).compactMap { name, t in
            t.resolved(name: name)
        }
        let themes = parsed.isEmpty ? [.solarizedDark, .kanbanDark] : parsed.sorted { $0.name < $1.name }
        let active = raw.terminal?.theme.flatMap { name in themes.first { $0.name == name } }
            ?? themes.first!
        return KanbanSettings(activeTerminalTheme: active, terminalThemes: themes,
                              font: resolveFont(raw.terminal?.font),
                              optionAsMeta: raw.terminal?.optionAsMeta ?? false)
    }

    private static func resolveFont(_ raw: RawFont?) -> TerminalFontSettings {
        let size = raw?.size.map { min(max($0, 6), 72) } ?? TerminalFontSettings.default.size
        let family = raw?.family.flatMap { $0.isEmpty ? nil : $0 }
        return TerminalFontSettings(size: size,
                                    smoothing: raw?.smoothing ?? TerminalFontSettings.default.smoothing,
                                    family: family)
    }
}

// MARK: - Raw decoding shapes

private struct RawSettings: Decodable {
    let terminal: RawTerminal?
}

private struct RawTerminal: Decodable {
    let theme: String?                    // active theme name
    let font: RawFont?
    let optionAsMeta: Bool?
    let themes: [String: RawTheme]?
}

private struct RawFont: Decodable {
    let size: Double?
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
private let defaultConfigJSON = """
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
  }
}

"""
