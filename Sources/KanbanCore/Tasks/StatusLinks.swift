import Foundation

/// Turns the Status-tab preamble into clickable links, using base URLs from the Hermes config and
/// the values shown in the block itself:
///   • the H1 title            → Jira ticket URL              (browser)
///   • 🌳 WORKTREE `<path>`     → `kanban-ide://` scheme       (opens in PhpStorm, app-side)
///   • 🌿 BRANCH   `<branch>`   → GitLab branch tree URL       (browser)
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

    public static func linkify(preamble: String,
                               ticketKey: String?,
                               jiraBaseUrl: String?,
                               gitlabBaseUrl: String?,
                               gitlabProjectPath: String?) -> String {
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
                return linkFirstCode(in: line) { gitlabBranchURL(branch: $0, base: gitlabBaseUrl, projectPath: gitlabProjectPath) }
            }
            if line.contains("**STACK**") {
                return linkFirstCode(in: line) { $0.hasPrefix("http") ? $0 : nil }
            }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - URL builders

    private static func jiraURL(ticketKey: String?, base: String?) -> String? {
        guard let key = ticketKey, !key.isEmpty, let base, !base.isEmpty else { return nil }
        return "\(trimTrailingSlash(base))/browse/\(key)"
    }

    private static func gitlabBranchURL(branch: String, base: String?, projectPath: String?) -> String? {
        guard let base, !base.isEmpty, let path = projectPath, !path.isEmpty else { return nil }
        let enc = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        return "\(trimTrailingSlash(base))/\(path)/-/tree/\(enc)"
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
