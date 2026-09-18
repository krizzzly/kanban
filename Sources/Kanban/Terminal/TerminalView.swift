import AppKit
import SwiftTerm
import KanbanCore

/// A `LocalProcessTerminalView` pre-styled from the active `TerminalTheme` (read from Kanban's own
/// `config.json`; defaults to iTerm2 Solarized Dark). Process lifecycle (tmux attach) is managed by
/// `TerminalCache`.
final class KanbanTerminalView: LocalProcessTerminalView {
    /// Kanbans eigene Einstellungen aus `~/Library/Application Support/Kanban/config.json` —
    /// **der jeweils aktuelle Stand**, nicht der beim Start gelesene: `KanbanSettingsStore.reload()`
    /// tauscht ihn nach dem Speichern aus, und `TerminalCache.reapplyAppearance()` zieht die
    /// bestehenden Ansichten nach.
    static var settings: KanbanSettings { KanbanSettingsStore.current }

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
        // With mouse reporting on, SwiftTerm clears the local selection on every data feed
        // (`feedPrepare`) — Claude's continuously repainting TUI made any selection vanish
        // instantly. Neither Claude nor our tmux setup (mouse off) requests mouse events, and
        // scrolling is intercepted app-side (`TerminalCache`), so reporting is safe to disable.
        allowMouseReporting = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Wortweises Bearbeiten (⌥← / ⌥→ / ⌥⌫)

    /// Tastencodes der drei Kombinationen — layoutunabhängig, im Gegensatz zu
    /// `charactersIgnoringModifiers`.
    private enum KeyCode {
        static let delete: UInt16 = 51
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
    }

    /// ⌥← / ⌥→ / ⌥⌫ als Meta-Sequenzen, weil `optionAsMetaKey` **aus** ist: ⌥ soll auf dem
    /// Schweizer Layout weiter `@ # { }` schreiben, und mit ausgeschaltetem Meta gibt SwiftTerm die
    /// drei Kombinationen an AppKit weiter, wo sie ins Leere laufen (ein `moveWordLeft:` o. ä.
    /// behandelt der Terminal-View nicht) — ⌥← bewegte den Cursor also um **ein Zeichen**, ⌥⌫ tat
    /// gar nichts.
    ///
    /// Gesendet wird die emacs-Schreibweise (`ESC b` / `ESC f` / `ESC DEL`, wie iTerm2s „natural
    /// text editing“), nicht die CSI-Form: gegen die echten Konsolen gemessen versteht **jede** der
    /// drei Empfänger die Meta-Sequenzen — Claude Code (`\x1Bb` → meta+left → `prevWord`, `ESC DEL`
    /// → `deleteWordBefore`), Codex und die zsh. `ESC[1;3D` verstehen dagegen nur Claude und Codex;
    /// in der zsh landet daraus ein wörtliches „D“ auf der Zeile.
    ///
    /// Bei eingeschaltetem `optionAsMeta` macht SwiftTerm dasselbe schon selbst, deshalb greift die
    /// Behandlung nur, solange der Schalter aus ist.
    private static func metaSequence(for event: NSEvent) -> [UInt8]? {
        let flags = event.modifierFlags
        guard flags.contains(.option), flags.intersection([.command, .control]).isEmpty else { return nil }
        switch event.keyCode {
        case KeyCode.leftArrow:  return EscapeSequences.emacsBack      // ESC b — ein Wort zurück
        case KeyCode.rightArrow: return EscapeSequences.emacsForward   // ESC f — ein Wort vorwärts
        case KeyCode.delete:     return [0x1b, 0x7f]                   // ESC DEL — Wort davor löschen
        default:                 return nil
        }
    }

    /// Schickt die Meta-Sequenz, wenn `event` eine der drei Kombinationen ist, und meldet, dass die
    /// Taste damit verbraucht ist. Aufgerufen wird das aus `TerminalCache`s Tastatur-Monitor:
    /// SwiftTerms `keyDown` ist `public` und nicht `open`, lässt sich also nicht überschreiben —
    /// derselbe Grund, aus dem schon das Scrollen app-seitig abgefangen wird.
    func handleWordEditingKey(_ event: NSEvent) -> Bool {
        guard !optionAsMetaKey, let bytes = Self.metaSequence(for: event) else { return false }
        send(bytes)
        return true
    }

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

    /// Farben, Schriftglättung und die ⌥-Taste aus dem aktuellen Stand übernehmen — auch an einer
    /// Ansicht, die längst läuft. Der Prozess dahinter merkt davon nichts; es wechselt nur, wie er
    /// gezeichnet wird.
    func applyAppearance() {
        applyTheme()
        optionAsMetaKey = Self.settings.optionAsMeta
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
