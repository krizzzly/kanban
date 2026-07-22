import AppKit
import SwiftTerm
import KanbanCore

/// A `LocalProcessTerminalView` pre-styled from the active `TerminalTheme` (read from Kanban's own
/// `config.json`; defaults to iTerm2 Solarized Dark). Process lifecycle (tmux attach) is managed by
/// `TerminalCache`.
final class KanbanTerminalView: LocalProcessTerminalView {
    /// Kanban's own settings, loaded once from `~/Library/Application Support/Kanban/config.json`.
    static let settings: KanbanSettings = KanbanSettingsStore.load()

    /// The active colour scheme.
    static var theme: TerminalTheme { settings.activeTerminalTheme }

    /// The caret colour for the active theme — also used by `TerminalCache` when restoring the caret
    /// after copy-mode scrolling.
    static var themedCaretColor: NSColor { nsColor(theme.cursor) }

    private static func nsColor(_ c: TerminalRGB) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255.0, green: CGFloat(c.g) / 255.0,
                blue: CGFloat(c.b) / 255.0, alpha: 1.0)
    }

    /// Base terminal point size (before the app UI scale). Configured via `terminal.font.size`.
    static var baseFontSize: CGFloat { CGFloat(settings.font.size) }

    /// Built-in fallback font families, tried in order after any configured `terminal.font.family`.
    private static let fallbackFontFamilies = [
        "Meslo LG S DZ Regular for Powerline",
        "Meslo LG S DZ for Powerline",
        "MesloLGSDZ Nerd Font",
    ]

    /// Preferred font families, tried in order; the configured family (if any) wins. Falls back to
    /// the system monospaced font when none resolve.
    private static var fontCandidates: [String] {
        if let family = settings.font.family { return [family] + fallbackFontFamilies }
        return fallbackFontFamilies
    }

    /// The effective terminal font, honouring the app UI scale.
    static var terminalFont: NSFont {
        let size = baseFontSize * AppScale.factor
        for name in fontCandidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyTheme()
        getTerminal().setCursorStyle(.steadyBlock)   // no blinking caret (default is .blinkBlock)
        // Let ⌥ Option produce composed characters (#, @, {, }, … on Swiss/German layouts) instead
        // of acting as the Meta key. Configurable via `terminal.optionAsMeta`.
        optionAsMetaKey = Self.settings.optionAsMeta
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Keep the caret steady: any blinking style the inner app (or the SwiftTerm default) requests is
    /// coerced to its non-blinking equivalent, so the cursor never blinks while typing.
    override func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        let steady: CursorStyle
        switch newStyle {
        case .blinkBlock, .steadyBlock:         steady = .steadyBlock
        case .blinkBar, .steadyBar:             steady = .steadyBar
        case .blinkUnderline, .steadyUnderline: steady = .steadyUnderline
        }
        super.cursorStyleChanged(source: source, newStyle: steady)
    }

    /// Applies the terminal font. Must be called **after** construction — SwiftTerm's `font` setter
    /// does not take effect when invoked during `init` (the cell metrics are not recomputed), so
    /// setting it here (from `TerminalCache`) is what actually resizes the glyphs.
    func applyFont() {
        font = Self.terminalFont
    }

    private func applyTheme() {
        let theme = Self.theme
        nativeBackgroundColor = Self.nsColor(theme.background)
        nativeForegroundColor = Self.nsColor(theme.foreground)
        caretColor = Self.themedCaretColor
        fontSmoothing = Self.settings.font.smoothing   // anti-aliasing / "thin strokes"
        if let selBg = theme.selectionBackground { selectedTextBackgroundColor = Self.nsColor(selBg) }

        // SwiftTerm.Color uses UInt16 0–65535, so 8-bit values are scaled by 257.
        installColors(theme.ansi.map { Color(red: UInt16($0.r) * 257, green: UInt16($0.g) * 257, blue: UInt16($0.b) * 257) })
    }
}
