import Foundation

/// Maps the prompts of a Claude session onto the lines of its tmux pane, so a click in the prompt
/// timeline can scroll the terminal to the place where that prompt was sent.
///
/// Why an alignment and not a text search: prompts repeat ("ok mach das bitte" three times in one
/// session), and a `search-backward` would land on the newest match every time. The pane's prompt
/// lines are however a **contiguous suffix** of the session's prompts — everything older has been
/// pushed out of tmux's history — so walking both lists backwards in lockstep pins each prompt to
/// its own line, duplicates included.
///
/// Prompts that fall off the top of the history stay unmapped; the UI greys those out and reads the
/// turn back from the transcript instead.
public enum PromptLocator {
    /// Wie ein abgeschickter Prompt in der Pane steht: Marker in Spalte 0, dann der Text. `❯` ist
    /// Claude Code (`>` die ältere Fassung), `›` ist Codex — am 2026-08-20 an einer fortgesetzten
    /// Codex-Session abgelesen, dort steht die Frage des Menschen als `› auf welche Ordner …` und
    /// Codex' Antwort als `• …`.
    ///
    /// Das ist ein UI-Detail und kann sich mit einer Version ändern — dann wird nichts gefunden und
    /// jede Bubble fällt auf „nicht in der Scrollback" zurück. Das ist die sichere Art, falsch zu
    /// liegen: ein falscher Sprung wäre schlimmer als keiner.
    public static let markers = ["❯ ", "› ", "> "]

    /// How many characters must line up. The pane truncates the prompt at the pane width and folds
    /// the rest into the following lines, so only a prefix can ever be compared.
    static let matchPrefix = 30

    /// How far back one pane line may look for its prompt before it is given up on.
    ///
    /// Not every `❯` line has a turn behind it: a prompt typed while Claude was still answering is
    /// echoed by the TUI but folded into the running turn, so it never opens one. Without a bound,
    /// such a line would walk the whole remaining list and leave every older prompt unmapped —
    /// measured on a real session that cost 7 of 9 mappings.
    static let lookback = 10

    /// turn index → 0-based line index in `paneLines`.
    public static func locate(prompts: [String], paneLines: [String]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var cursor = prompts.count - 1   // prompts above this one are still unclaimed

        for pane in promptLines(in: paneLines).reversed() {
            guard cursor >= 0 else { break }
            let lowest = max(0, cursor - lookback + 1)
            var index = cursor
            var found: Int?
            while index >= lowest {
                if matches(prompt: prompts[index], paneText: pane.text) { found = index; break }
                index -= 1
            }
            // Nothing within the window → the line has no turn of its own; drop it and leave the
            // cursor where it was, so the next line up can still claim these prompts.
            guard let found else { continue }
            result[found] = pane.line
            cursor = found - 1
        }
        return result
    }

    // MARK: - Pieces

    static func promptLines(in paneLines: [String]) -> [(line: Int, text: String)] {
        paneLines.enumerated().compactMap { index, line in
            for marker in markers where line.hasPrefix(marker) {
                let text = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : (index, text)
            }
            return nil
        }
    }

    static func matches(prompt: String, paneText: String) -> Bool {
        let expected = normalize(prompt)
        let actual = normalize(paneText)
        guard !expected.isEmpty, !actual.isEmpty else { return false }
        let length = min(matchPrefix, min(expected.count, actual.count))
        return expected.prefix(length) == actual.prefix(length)
    }

    /// Collapse whitespace: the pane pads every line to the pane width and may have re-wrapped the
    /// text, so only the visible characters can be compared.
    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
