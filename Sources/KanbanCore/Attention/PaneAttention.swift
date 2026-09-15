import Foundation

/// Pure classifier of a captured tmux pane running an agent's TUI — Claude Code oder Codex. Used as
/// a fallback/augment to the hook markers: it catches sessions started before the hook was installed
/// and self-heals stale markers (once the agent is visibly working again, the app clears the marker).
///
/// Für Codex ist das derzeit der **einzige** Weg: Kanbans Attention-Hook (`ClaudeHookInstaller`)
/// schreibt in `~/.claude/settings.json`. Codex hat zwar eigene Hooks (`~/.codex/hooks.json`, mit
/// `PermissionRequest`/`SessionStart`/`UserPromptSubmit`), verlangt dafür aber einen eigenen
/// Trust-Schritt — das bleibt ein eigener Schritt. Die Pane-Auswertung braucht dafür nichts.
public enum PaneAttention {
    /// True while the agent is actively generating. Beide TUIs sagen dasselbe, nur mit anderem
    /// Vorspann: Claude „· Working… (esc to interrupt)", Codex „… to interrupt" in der Fusszeile
    /// (Strings aus dem Binary, 0.148). Der Hinweis erscheint nur, solange ein Turn läuft.
    ///
    /// **Ein Token-Zähler ist kein Arbeitsnachweis.** Bis 2026-09-07 galt auch ein blosses
    /// „tokens" als arbeitend — gedacht als Reserve für „… · N tokens · esc to interrupt", also für
    /// eine Zeile, die den eigentlichen Hinweis ohnehin schon trägt. Eine **eigene Statuszeile**
    /// (`cc-statusline`: „ΣTokens: 917k", „916703 tokens") schreibt das Wort dagegen dauerhaft hin,
    /// und damit galt **jede** Konsole für immer als arbeitend. Drei Folgen, alle beobachtet an
    /// CORETEST-4237: der ⏱-Zähler eines abgebrochenen Turns lief unbegrenzt weiter (87 h auf einen
    /// Prompt vom 2026-09-03), `showsQuestion` stieg wegen des `isWorking`-Vorbehalts immer sofort
    /// aus (Rückfragen wurden nie erkannt), und `AttentionMarkers` wurden bei jedem Scan als
    /// „Claude ist wieder beschäftigt" gelöscht. Erkannt wird deshalb nur, was ausschliesslich
    /// während eines laufenden Turns in der Pane steht.
    public static func isWorking(_ pane: String) -> Bool {
        let hay = pane.lowercased()
        return hay.contains("to interrupt")
            || hay.contains("· working")
    }

    /// True when the pane shows a blocking prompt the user must answer: a selection/permission
    /// picker (numbered options with the `❯` cursor, or a "Do you want to proceed?" block).
    public static func showsQuestion(_ pane: String) -> Bool {
        if isWorking(pane) { return false }   // a running turn isn't waiting on the user
        let lines = pane.components(separatedBy: "\n")

        // Numbered picker options, e.g. "❯ 1. Yes" / "  2. No, and tell Claude…" / "› 1. List skills".
        let optionLines = lines.filter { matches(#"^\s*(❯|›)?\s*[1-9][0-9]?\.\s+\S"#, $0) }
        if optionLines.count >= 2 { return true }                 // a real menu (≥2 options)

        // Ein einzelner Eintrag zählt nur **mit** Cursor auf derselben Zeile. Früher genügte ein `❯`
        // irgendwo in der Pane — bei Codex steht sein `›` immer in der Eingabezeile, und jede
        // nummerierte Zeile einer Antwort („1. Zuerst …") wäre als Rückfrage durchgegangen.
        if optionLines.contains(where: { matches(#"^\s*(❯|›)\s*[1-9][0-9]?\.\s+\S"#, $0) }) {
            return true
        }

        let hay = pane.lowercased()
        if hay.contains("do you want to proceed?") { return true }
        if hay.contains("do you want to make this edit") { return true }
        // Codex' Freigabe-Dialoge, wörtlich aus dem Binary (0.148).
        if hay.contains("allow codex to run") { return true }
        if hay.contains("codex wants to edit") { return true }
        if hay.contains("approve app tool call?") { return true }
        return false
    }

    private static func matches(_ pattern: String, _ line: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = line as NSString
        return re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }
}
