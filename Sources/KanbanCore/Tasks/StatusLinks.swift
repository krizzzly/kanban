import Foundation

/// Turns the Status-tab preamble into clickable links, using base URLs from the Hermes config and
/// the values shown in the block itself:
///   • 🎫 JIRA     `<url>`      → the URL itself               (browser)
///   • 🌳 WORKTREE `<path>`     → `kanban-ide://` scheme       (opens in PhpStorm, app-side)
///   • 🌿 BRANCH   `<branch>`   → Branch-URL der Forge          (browser)
///   • 🐳 STACK    `<url>`      → the URL itself               (browser)
/// Die H1 bleibt unangetastet: eine Überschrift ist kein Navigationselement, und im Rohtext der
/// Datei stand von der Verlinkung ohnehin nie etwas. Der Weg zum Ticket steht stattdessen als Zeile
/// im Block — dort, wo auch Worktree, Branch und Stack stehen.
/// Pure string logic — the app resolves the `kanban-ide` scheme and opens http(s) links externally.
public enum StatusLinks {
    /// Custom scheme the app intercepts to open a directory in the IDE.
    public static let ideScheme = "kanban-ide"

    /// Builds the `kanban-ide://open?path=…` URL for a worktree directory.
    public static func ideURL(forPath path: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?#+")
        let enc = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return "\(ideScheme)://open?path=\(enc)"
    }

    /// `forge` trägt Plattform, Web-Basis und Projekt-Pfad — nil, wenn dem Projekt keine Forge
    /// zugeordnet ist. Dann bleibt der Branch ein blosser Code-Span, wie bisher ohne GitLab.
    public static func linkify(preamble: String,
                               ticketKey: String?,
                               jiraBaseUrl: String?,
                               forge: ForgeLocation?,
                               usesJira: Bool = true) -> String {
        // Bestandsdateien haben die Zeile nicht — sie wird für die Anzeige abgeleitet. Steht sie in
        // der Datei, gewinnt die Datei; ohne Jira-Anbindung entsteht gar keine.
        let source = usesJira
            ? withJiraLine(preamble, url: jiraURL(ticketKey: ticketKey, base: jiraBaseUrl))
            : preamble

        return source.components(separatedBy: "\n").map { line -> String in
            if line.contains("**JIRA**") {
                return linkFirstCode(in: line) { $0.hasPrefix("http") ? $0 : nil }
            }
            if line.contains("**WORKTREE**") {
                return linkFirstCode(in: line) { ideURL(forPath: $0) }
            }
            if line.contains("**BRANCH**") {
                return linkFirstCode(in: line) { forge?.branchURL($0) }
            }
            if line.contains("**STACK**") {
                return linkFirstCode(in: line) { $0.hasPrefix("http") ? $0 : nil }
            }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - Die JIRA-Zeile

    /// Die JIRA-Zeile, wie sie in den Block gehört — eine Stelle, an der sie gebaut wird, für das
    /// Rendern und für die Migration der Bestandsdateien.
    public static func jiraLine(url: String) -> String { "> 🎫 **JIRA**: `\(url)`" }

    /// Führt der Block unter der H1 bereits eine JIRA-Zeile? Bewusst **nur** der Block: das Wort
    /// `**JIRA**` kommt auch im Fliesstext eines Task-Files vor (eine Datei beschreibt genau diese
    /// Zeile), und eine Suche über die ganze Datei hielte die Migration dort fälschlich für erledigt.
    public static func hasJiraLine(_ markdown: String) -> Bool {
        let lines = markdown.components(separatedBy: "\n")
        guard let h1 = lines.firstIndex(where: { $0.hasPrefix("# ") }) else { return false }
        return lines[blockRange(lines, belowHeadingAt: h1)].contains { $0.contains("**JIRA**") }
    }

    /// Setzt die JIRA-Zeile als **erste** Zeile in den Block unter der H1 — die Wurzel von allem
    /// anderen im Block steht zuoberst. Unverändert zurück, wenn der Block schon eine `**JIRA**`-Zeile
    /// führt (die Datei gewinnt), `url` fehlt oder es gar keine H1 gibt.
    ///
    /// Ohne bestehenden Block (`--no-worktree`) entsteht ein Blockquote mit nur dieser Zeile.
    /// Arbeitet auf Präambel **und** ganzer Datei: beide fangen mit derselben H1 an.
    public static func withJiraLine(_ markdown: String, url: String?) -> String {
        guard let url, !url.isEmpty else { return markdown }
        var lines = markdown.components(separatedBy: "\n")
        guard let h1 = lines.firstIndex(where: { $0.hasPrefix("# ") }) else { return markdown }

        let block = blockRange(lines, belowHeadingAt: h1)
        guard !lines[block].contains(where: { $0.contains("**JIRA**") }) else { return markdown }

        if !block.isEmpty {
            // In den bestehenden Block: mit `\` am Ende, sonst kollabiert er beim Rendern zu einer Zeile.
            lines.insert(jiraLine(url: url) + "\\", at: block.lowerBound)
        } else {
            let next = h1 + 1
            let needsBlankAfter = next < lines.count && !isBlank(lines[next])
            lines.insert(contentsOf: needsBlankAfter ? ["", jiraLine(url: url), ""] : ["", jiraLine(url: url)],
                         at: next)
        }
        return lines.joined(separator: "\n")
    }

    /// Die Zeilen des Blockquotes unter der H1 — leer, wenn keiner folgt. Der Block steht direkt
    /// unter der Überschrift, durch höchstens eine Leerzeile abgesetzt.
    private static func blockRange(_ lines: [String], belowHeadingAt h1: Int) -> Range<Int> {
        var start = h1 + 1
        if start < lines.count, isBlank(lines[start]) { start += 1 }
        var end = start
        while end < lines.count, lines[end].hasPrefix(">") { end += 1 }
        return start..<end
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - URL builders

    /// Eine `!<iid>`- bzw. `#<nummer>`-Karte ist Arbeit **ohne** Ticketnummer — zu ihr gibt es per
    /// Definition kein Jira-Issue. Ohne diese Ausnahme zeigte ihre Zeile auf `/browse/!49` bzw.
    /// `/browse/#49` und liefe ins Leere.
    public static func jiraURL(ticketKey: String?, base: String?) -> String? {
        guard let key = ticketKey, !key.isEmpty,
              !key.hasPrefix("!"), !key.hasPrefix("#"),
              let base, !base.isEmpty else { return nil }
        return "\(trimTrailingSlash(base))/browse/\(key)"
    }

    private static func trimTrailingSlash(_ s: String) -> String {
        s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    // MARK: - Code-span linking

    /// Wraps the **first** `` `code` `` span for which `makeURL` returns a URL in a markdown link,
    /// preserving the code span (`[`code`](url)`). Lines already containing a link are left untouched.
    private static func linkFirstCode(in line: String, makeURL: (String) -> String?) -> String {
        guard !line.contains("](") else { return line }
        var result = ""
        var rest = Substring(line)
        var linked = false

        while let open = rest.firstIndex(of: "`") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "`") else {
                result += rest
                return result
            }
            let code = String(rest[afterOpen..<close])
            result += rest[..<open]
            if !linked, !code.isEmpty, let url = makeURL(code) {
                result += "[`\(code)`](\(url))"
                linked = true
            } else {
                result += "`\(code)`"
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}
