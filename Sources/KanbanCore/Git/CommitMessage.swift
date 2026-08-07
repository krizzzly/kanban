import Foundation

/// Reads the commit message `solve-task` leaves in a task file.
///
/// The contract (solve-task, Schritt 7b): under `## Lösung` there is a line
///
///     **Commit-Message:** `BFEZVM-4464 | Add weighted/HGT hint to overall energy efficiency chart`
///
/// That section is the single source of truth for the message, so the commit dialog proposes exactly
/// what Claude wrote — the user can still edit it before committing.
public enum CommitMessage {
    /// The suggested message, or nil when the task file has none yet (task not finished by solve-task).
    public static func suggestion(in content: String) -> String? {
        guard let section = loesungSection(in: content) else { return nil }
        return backtickedMessage(in: section) ?? plainMessage(in: section)
    }

    /// The body of the `## Lösung` section (up to the next H2). `## Lösungsplan` must not match — it is
    /// a different section that also starts with "## Lösung".
    private static func loesungSection(in content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { isLoesungHeading($0) }) else { return nil }
        var body: [String] = []
        for line in lines[(start + 1)...] {
            if line.hasPrefix("## ") { break }
            body.append(line)
        }
        return body.joined(separator: "\n")
    }

    private static func isLoesungHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("## ") else { return false }
        let title = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
        return title == "lösung" || title == "loesung"
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
