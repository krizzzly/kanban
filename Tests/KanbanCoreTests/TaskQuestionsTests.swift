import XCTest
@testable import KanbanCore

final class TaskQuestionsTests: XCTestCase {
    // MARK: - Questions (❓) — heading/title contains "fragen"

    func testBodyHeadingNachfragenIsFlagged() {
        XCTAssertTrue(TaskQuestions.hasQuestionHeading(
            title: "Impact-Analyse", markdown: "Text.\n\n### Offene Nachfragen\n- Welcher Default?"))
    }

    func testBodyHeadingFragenVariantsAreFlagged() {
        for heading in ["## Fragen", "### Rückfragen", "#### Offene Fragen", "### Nachfragen an Kunde"] {
            XCTAssertTrue(TaskQuestions.hasQuestionHeading(title: "Analyse", markdown: "\(heading)\n- x"),
                          "sollte flaggen: \(heading)")
        }
    }

    func testSectionTitledFragenIsFlaggedWithoutBodyHeading() {
        XCTAssertTrue(TaskQuestions.hasQuestionHeading(title: "Offene Fragen", markdown: "- Punkt ohne Heading"))
    }

    func testProseQuestionWithoutHeadingIsNotFlagged() {
        // A "?" in prose but no heading with "fragen" → not flagged.
        XCTAssertFalse(TaskQuestions.hasQuestionHeading(
            title: "Analyse", markdown: "Wie verhält sich X? Das klären wir im Code."))
    }

    func testBoldFragenMarkerIsNotAHeading() {
        // Only markdown headings count, not bold inline text.
        XCTAssertFalse(TaskQuestions.hasQuestionHeading(
            title: "Analyse", markdown: "**Fragen:** siehe unten."))
    }

    // MARK: - Decisions (green ✓) — title-based, not body-based

    func testDecisionTitleIsFlagged() {
        XCTAssertTrue(TaskQuestions.isDecisionTitle("Entscheidungen"))
        XCTAssertTrue(TaskQuestions.isDecisionTitle("Getroffene Entscheidung"))
    }

    func testNonDecisionTitleIsNotFlagged() {
        // A body mentioning "entschieden" must NOT flag its section (that was the inflation bug).
        XCTAssertFalse(TaskQuestions.isDecisionTitle("Analyse"))
        XCTAssertFalse(TaskQuestions.isDecisionTitle("Impact-Analyse"))
    }

    func testDecisionSectionIDsMatchesTitleOnly() {
        let sections = [
            TaskSection(id: 0, title: "Analyse", markdown: "Wir haben uns entschieden, B zu nehmen."),
            TaskSection(id: 1, title: "Entscheidungen", markdown: "- B gewählt."),
        ]
        XCTAssertEqual(TaskQuestions.decisionSectionIDs(sections), [1])   // NOT the Analyse body
    }

    func testSectionIDsPicksOnlyTheOneWithQuestionHeading() {
        let sections = [
            TaskSection(id: 0, title: "Analyse", markdown: "Reiner Text, ist das so? Kein Heading."),
            TaskSection(id: 1, title: "Impact-Analyse", markdown: "### Offene Nachfragen\n- Welcher Default gilt?"),
            TaskSection(id: 2, title: "Lösung", markdown: "Fertig."),
        ]
        XCTAssertEqual(TaskQuestions.openQuestionSectionIDs(sections), [1])
    }
}
