import Foundation

/// Reads the text a task file offers for the Jira field „Lösung".
///
/// The contract (solve-task, Schritt 7): the task file carries
///
///     ## JIRA Lösungsfeld
///     ### Für Test-Ingenieur
///     …
///     ### Für Kunde
///     …
///
/// and **`### Für Kunde` is the part that belongs in Jira** — the prose that says what was solved,
/// which decisions were taken, where the implementation deviates from the acceptance criteria and
/// what was assumed. The test-engineer part (changed-file lists, click paths) stays local; it is
/// noise in the field the reviewer reads.
///
/// Why the field matters: the task file is **not** committed. Everything that only exists there is
/// gone once the worktree is destroyed, so the Jira field is the last place it survives.
///
/// Older task files (and hand-written ones) have no `### Für Kunde` — those fall back to the whole
/// section, which is what the dialog proposed before. The caller is told which of the two it got,
/// so the editor can name its source instead of leaving the user guessing.
public enum SolutionDraft {
    /// Which part of the task file the suggestion came from.
    public enum Source: Sendable, Hashable {
        /// The `### Für Kunde` subsection — the intended source.
        case customerPart
        /// The whole `## JIRA Lösungsfeld` section, because it has no `### Für Kunde`.
        case wholeSection
    }

    /// The suggested field content, or nil when the task file has no `## JIRA Lösungsfeld` at all.
    public static func suggestion(in content: String) -> (text: String, source: Source)? {
        guard let section = nonEmpty(solutionFieldSection(in: content)) else { return nil }
        if let customer = nonEmpty(customerPart(in: section)) { return (customer, .customerPart) }
        return (section, .wholeSection)
    }

    /// The body of the `## JIRA Lösungsfeld` section (heading excluded, up to the next H2).
    static func solutionFieldSection(in content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { isSolutionFieldHeading($0) }) else { return nil }
        var body: [String] = []
        for line in lines[(start + 1)...] {
            if headingLevel(line) == 2 { break }
            body.append(line)
        }
        return body.joined(separator: "\n")
    }

    /// The `### Für Kunde` subsection of a section body — up to the next H3 (or H2). Deeper headings
    /// (`#### …`) belong to the subsection and do not end it.
    static func customerPart(in section: String) -> String? {
        var body: [String] = []
        var inside = false
        for line in section.components(separatedBy: .newlines) {
            if let level = headingLevel(line), level <= 3 {
                if inside { break }
                inside = level == 3 && Self.customerHeadings.contains(headingTitle(line))
                continue
            }
            if inside { body.append(line) }
        }
        return inside ? body.joined(separator: "\n") : nil
    }

    /// Spellings accepted for the customer subsection — with and without the umlaut, singular/plural.
    static let customerHeadings: Set<String> = ["für kunde", "fuer kunde", "für kunden", "fuer kunden"]

    private static let sectionHeadings: Set<String> = ["jira lösungsfeld", "jira loesungsfeld"]

    private static func isSolutionFieldHeading(_ line: String) -> Bool {
        headingLevel(line) == 2 && sectionHeadings.contains(headingTitle(line))
    }

    /// `###` → 3, for a heading line only (`#` immediately followed by more `#` and then a space).
    /// Everything else — text, `#hashtag`, a fenced line — is nil.
    private static func headingLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes > 0, trimmed.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return hashes
    }

    /// The heading's text, lowercased and stripped of a trailing colon, ready to compare.
    private static func headingTitle(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return title.hasSuffix(":") ? String(title.dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
                                    : title.lowercased()
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
