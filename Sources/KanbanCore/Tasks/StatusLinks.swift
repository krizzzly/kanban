import Foundation

/// Turns the Status-tab preamble into clickable links, using base URLs from the Hermes config and
/// the values shown in the block itself:
///   • the H1 title            → Jira ticket URL              (browser)
///   • 🌳 WORKTREE `<path>`     → `kanban-ide://` scheme       (opens in PhpStorm, app-side)
///   • 🌿 BRANCH   `<branch>`   → Branch-URL der Forge          (browser)
///   • 🐳 STACK    `<url>`      → the URL itself               (browser)
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
                               forge: ForgeLocation?) -> String {
        let jira = jiraURL(ticketKey: ticketKey, base: jiraBaseUrl)
        var titleLinked = false

        return preamble.components(separatedBy: "\n").map { line -> String in
            // H1 title → Jira (first H1 only; `##`/`###` are left alone).
            if !titleLinked, line.hasPrefix("# "), let jira {
                titleLinked = true
                let text = String(line.dropFirst(2))
                return text.contains("](") ? line : "# [\(text)](\(jira))"
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

    // MARK: - URL builders

    /// Eine `!<iid>`- bzw. `#<nummer>`-Karte ist Arbeit **ohne** Ticketnummer — zu ihr gibt es per
    /// Definition kein Jira-Issue. Ohne diese Ausnahme verlinkte ihre H1 auf `/browse/!49` bzw.
    /// `/browse/#49` und liefe ins Leere.
    private static func jiraURL(ticketKey: String?, base: String?) -> String? {
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
