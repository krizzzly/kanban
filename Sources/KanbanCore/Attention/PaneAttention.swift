import Foundation

/// Pure classifier of a captured tmux pane running Claude Code. Used as a fallback/augment to the
/// hook markers: it catches sessions started before the hook was installed and self-heals stale
/// markers (once Claude is visibly working again, the app clears the marker).
public enum PaneAttention {
    /// True while Claude is actively generating (its status line shows the running spinner). SwiftTerm
    /// panes render Claude's "· Working… (esc to interrupt)" / ellipsis line while a turn runs.
    public static func isWorking(_ pane: String) -> Bool {
        let hay = pane.lowercased()
        return hay.contains("esc to interrupt")
            || hay.contains("· working")
            || hay.contains("tokens")           // "… · N tokens · esc to interrupt"
    }

    /// True when the pane shows a blocking prompt the user must answer: a selection/permission
    /// picker (numbered options with the `❯` cursor, or a "Do you want to proceed?" block).
    public static func showsQuestion(_ pane: String) -> Bool {
        if isWorking(pane) { return false }   // a running turn isn't waiting on the user
        let lines = pane.components(separatedBy: "\n")

        // Numbered picker options, e.g. "❯ 1. Yes" / "  2. No, and tell Claude…".
        let optionPattern = try? NSRegularExpression(pattern: #"^\s*(❯\s*)?[1-9][0-9]?\.\s+\S"#)
        let optionLines = lines.filter { line in
            guard let re = optionPattern else { return false }
            let ns = line as NSString
            return re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
        }
        if optionLines.count >= 2 { return true }                 // a real menu (≥2 options)
        if lines.contains(where: { $0.contains("❯") }) && optionLines.count >= 1 { return true }

        let hay = pane.lowercased()
        if hay.contains("do you want to proceed?") { return true }
        if hay.contains("do you want to make this edit") { return true }
        return false
    }
}
