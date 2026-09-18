import Foundation

/// Reads the commit message `solve-task` leaves in a task file.
///
/// The contract (solve-task, Kapitel 15): under `## Commit` there is a line
///
///     **Commit-Message:** `BFEZVM-4464 | Add weighted/HGT hint to overall energy efficiency chart`
///
/// That section is the single source of truth for the message, so the commit dialog proposes exactly
/// what Claude wrote — the user can still edit it before committing.
///
/// Until 2026-09-17 the section was called `## Lösung`, and 220 task files still carry it there. That
/// heading now belongs to the developer solution field `get-task` imports from Jira, so `## Commit` is
/// read first and `## Lösung` stays as the fallback for the existing files. A `## Commit` without a
/// message falls through rather than ending the search — an empty new section must not hide an old one.
public enum CommitMessage {
    /// Section headings that may carry the message, most specific first. Each entry holds the spellings
    /// of one heading (the umlaut-free variant is accepted the way the rest of the app does it).
    private static let headings: [Set<String>] = [["commit"], ["lösung", "loesung"]]

    /// The suggested message, or nil when the task file has none yet (task not finished by solve-task).
    public static func suggestion(in content: String) -> String? {
        for titles in headings {
            guard let section = section(in: content, titles: titles) else { continue }
            if let message = backtickedMessage(in: section) ?? plainMessage(in: section) { return message }
        }
        return nil
    }

    /// The body of the first H2 whose title is one of `titles` (up to the next H2). The comparison is on
    /// the whole title, never a prefix: `## Lösungsplan` must not match `lösung`, and `## Commit-Message`
    /// (the console block of the skill) must not match `commit`.
    private static func section(in content: String, titles: Set<String>) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { isHeading($0, titles: titles) }) else { return nil }
        var body: [String] = []
        for line in lines[(start + 1)...] {
            if line.hasPrefix("## ") { break }
            body.append(line)
        }
        return body.joined(separator: "\n")
    }

    private static func isHeading(_ line: String, titles: Set<String>) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("## ") else { return false }
        let title = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
        return titles.contains(title)
    }

    /// `**Commit-Message:** \`…\`` — the documented form.
    private static func backtickedMessage(in section: String) -> String? {
        for line in section.components(separatedBy: .newlines) where line.lowercased().contains("commit-message") {
            guard let open = line.firstIndex(of: "`") else { continue }
            let rest = line[line.index(after: open)...]
            guard let close = rest.firstIndex(of: "`") else { continue }
            let message = String(rest[..<close]).trimmingCharacters(in: .whitespaces)
            if !message.isEmpty { return message }
        }
        return nil
    }

    /// Tolerates a message written without backticks (`**Commit-Message:** TICKET | text`).
    private static func plainMessage(in section: String) -> String? {
        for line in section.components(separatedBy: .newlines) {
            let cleaned = line.replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            let lower = cleaned.lowercased()
            guard lower.hasPrefix("commit-message"), let colon = cleaned.firstIndex(of: ":") else { continue }
            let message = cleaned[cleaned.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " `"))
            if !message.isEmpty { return message }
        }
        return nil
    }

    /// Fallback proposal when the task file carries none: `TICKET | ` for the user to complete, matching
    /// the project's commit convention.
    public static func fallback(ticketKey: String) -> String { "\(ticketKey) | " }
}
