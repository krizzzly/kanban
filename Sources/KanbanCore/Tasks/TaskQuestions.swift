import Foundation

/// Per-section tab-pill signals, driven by simple, predictable rules (headings / titles):
/// - **Questions (❓):** the section title, or any markdown heading in its body, contains "fragen"
///   (Fragen / Nachfragen / Rückfragen / Offene Fragen …). Questions live scattered under
///   `## Analyse`, `## Impact-Analyse`, … so a body-heading match is what pinpoints them.
/// - **Decisions (✓):** the section title contains "Entscheidung" (a dedicated Entscheidungen tab).
public enum TaskQuestions {
    /// The ids of sections whose title or a body heading mentions "fragen".
    public static func openQuestionSectionIDs(_ sections: [TaskSection]) -> Set<Int> {
        Set(sections.filter { hasQuestionHeading(title: $0.title, markdown: $0.markdown) }.map(\.id))
    }

    /// The ids of the dedicated "Entscheidungen" section(s).
    public static func decisionSectionIDs(_ sections: [TaskSection]) -> Set<Int> {
        Set(sections.filter { isDecisionTitle($0.title) }.map(\.id))
    }

    /// Pure test seam: is this an "Entscheidungen"-type section title?
    static func isDecisionTitle(_ title: String) -> Bool {
        title.lowercased().contains("entscheidung")
    }

    /// Pure test seam: does the section title, or a markdown heading in its body, contain "fragen"?
    static func hasQuestionHeading(title: String, markdown: String) -> Bool {
        if title.lowercased().contains("fragen") { return true }
        return markdown.components(separatedBy: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("#") && trimmed.lowercased().contains("fragen")
        }
    }
}
