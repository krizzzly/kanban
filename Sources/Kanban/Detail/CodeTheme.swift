import AppKit
import SwiftUI
import KanbanCore

/// Dark colours for the code panes (diff + editor), derived from the app's existing "Kanban Dark"
/// terminal palette — so the commit dialog and the embedded console look like the same tool.
enum CodeTheme {
    /// The *active* terminal theme from Kanban's own config — not a hard-coded one, so switching the
    /// terminal theme moves the code panes with it.
    private static var palette: TerminalTheme { KanbanTerminalView.theme }

    /// Same font as the terminal: the configured family/size (incl. the app UI scale), with the same
    /// fallback chain. One place decides what code looks like in this app.
    static var nsFont: NSFont { KanbanTerminalView.terminalFont }
    static var font: Font { Font(nsFont) }
    /// Line numbers a touch smaller than the code itself, in the same family.
    static var gutterFont: Font { Font(NSFont(descriptor: nsFont.fontDescriptor,
                                              size: max(9, nsFont.pointSize - 2)) ?? nsFont) }

    private static func color(_ rgb: TerminalRGB) -> Color {
        Color(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    private static func nsColor(_ rgb: TerminalRGB) -> NSColor {
        NSColor(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255,
                blue: CGFloat(rgb.b) / 255, alpha: 1)
    }

    // MARK: - Surfaces

    static var background: Color { color(palette.background) }
    static var backgroundNS: NSColor { nsColor(palette.background) }
    static var foreground: Color { color(palette.foreground) }
    static var foregroundNS: NSColor { nsColor(palette.foreground) }
    /// Line numbers and other chrome: the theme's foreground, dimmed.
    ///
    /// **Nicht** `ansi[8]` ("bright black") — in Solarized Dark ist dieser Slot `#002b36`, also genau
    /// die Hintergrundfarbe; die Zeilennummern waren damit unsichtbar. Vom Vordergrund abgeleitet
    /// funktioniert es in jedem Theme.
    static var gutter: Color { foreground.opacity(0.65) }
    static var gutterNS: NSColor { foregroundNS.withAlphaComponent(0.65) }
    static var gutterNSFont: NSFont {
        NSFont(descriptor: nsFont.fontDescriptor, size: max(9, nsFont.pointSize - 2)) ?? nsFont
    }

    /// Marker-Farben für `+` / `−`, damit die Richtung auch ohne Flächenfarbe lesbar ist.
    static var additionMarker: Color { color(palette.ansi[2]) }
    static var deletionMarker: Color { color(palette.ansi[1]) }

    // MARK: - Diff tints (stronger than on white — a dark background swallows pale washes)

    static var additionBackground: Color { Color(.sRGB, red: 0.13, green: 0.36, blue: 0.20, opacity: 0.55) }
    static var deletionBackground: Color { Color(.sRGB, red: 0.45, green: 0.15, blue: 0.17, opacity: 0.50) }
    static var hunkBackground: Color { Color(.sRGB, red: 0.16, green: 0.28, blue: 0.45, opacity: 0.45) }
    static var additionBackgroundNS: NSColor { NSColor(srgbRed: 0.13, green: 0.36, blue: 0.20, alpha: 0.55) }
    static var deletionBackgroundNS: NSColor { NSColor(srgbRed: 0.45, green: 0.15, blue: 0.17, alpha: 0.50) }

    // MARK: - Syntax

    /// ANSI slots follow the usual editor convention: green strings, grey comments, magenta keywords,
    /// yellow numbers, cyan variables, red tags, blue attributes.
    static func color(for kind: SyntaxToken.Kind) -> Color {
        switch kind {
        case .comment:   return foreground.opacity(0.72)   // s. `gutter`: ansi[8] ist unbrauchbar
        case .string:    return color(palette.ansi[2])
        case .keyword:   return color(palette.ansi[13])
        case .number:    return color(palette.ansi[3])
        case .variable:  return color(palette.ansi[6])
        case .tag:       return color(palette.ansi[9])
        case .attribute: return color(palette.ansi[12])
        case .type:      return color(palette.ansi[14])
        }
    }

    static func nsColor(for kind: SyntaxToken.Kind) -> NSColor {
        switch kind {
        case .comment:   return foregroundNS.withAlphaComponent(0.72)
        case .string:    return nsColor(palette.ansi[2])
        case .keyword:   return nsColor(palette.ansi[13])
        case .number:    return nsColor(palette.ansi[3])
        case .variable:  return nsColor(palette.ansi[6])
        case .tag:       return nsColor(palette.ansi[9])
        case .attribute: return nsColor(palette.ansi[12])
        case .type:      return nsColor(palette.ansi[14])
        }
    }

    /// ANSI-Index 0–15 aus der aktiven Terminal-Palette — dieselbe, die die xterm-Console benutzt.
    static func ansi(_ index: Int) -> Color {
        let palette = KanbanTerminalView.theme.ansi
        guard index >= 0, index < palette.count else { return foreground }
        return color(palette[index])
    }

    /// Dasselbe für AppKit — die Log-Ansicht (`LogTextView`) färbt `NSAttributedString`s.
    static func ansiNS(_ index: Int) -> NSColor {
        let palette = KanbanTerminalView.theme.ansi
        guard index >= 0, index < palette.count else { return foregroundNS }
        return nsColor(palette[index])
    }

    // Ein `ansiText(_:) -> AttributedString` stand hier und ist bewusst weg: es baute die farbige
    // Fassung stückweise mit `AttributedString.append` und kostete bei vollem Puffer 40 ms — pro
    // Body-Durchlauf, weil es mitten im SwiftUI-Body stand. Die Log-Ansicht hängt statt dessen an
    // (`LogTextView`); den langsamen Weg stehen zu lassen hiesse, ihn wieder zu benutzen.

    /// Builds a coloured `AttributedString` for one source line — used by the SwiftUI diff rows.
    /// Assembled from segments rather than by mutating ranges: `AttributedString` indices are
    /// character-based while the tokenizer works on UTF-16 ranges, and mixing the two silently
    /// mis-colours any line containing an umlaut or emoji.
    static func highlighted(_ line: String, language: CodeLanguage) -> AttributedString {
        func plain(_ text: String) -> AttributedString {
            var piece = AttributedString(text)
            piece.foregroundColor = foreground
            return piece
        }
        let tokens = SyntaxHighlighter.tokens(in: line, language: language)
        guard !tokens.isEmpty else { return plain(line) }

        let ns = line as NSString
        var result = AttributedString()
        var cursor = 0
        for token in tokens {
            guard token.range.location >= cursor, NSMaxRange(token.range) <= ns.length else { continue }
            if token.range.location > cursor {
                result.append(plain(ns.substring(with: NSRange(location: cursor,
                                                               length: token.range.location - cursor))))
            }
            var piece = AttributedString(ns.substring(with: token.range))
            piece.foregroundColor = color(for: token.kind)
            result.append(piece)
            cursor = NSMaxRange(token.range)
        }
        if cursor < ns.length { result.append(plain(ns.substring(from: cursor))) }
        return result
    }
}
