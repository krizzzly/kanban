import XCTest
@testable import KanbanCore

final class CommitMessageTests: XCTestCase {
    /// The documented shape solve-task writes (Schritt 7b).
    private let real = """
    <!-- kanban-claude-session: abc -->
    # BFEZVM-4464 - Kennzahlen

    ## Lösungsplan
    **Commit-Message:** `FALSCH | aus dem Plan, nicht der Lösung`

    ## Lösung

    **Commit-Message:** `BFEZVM-4464 | Add weighted/HGT hint to overall energy efficiency chart`

    **Test-URL (Ergebnis ansehen):** `https://bfezvm-4464.test/zv/123`
    — zeigt den Hinweis im Diagramm-Modal

    ## Nächste Schritte
    - [ ] Code Review
    """

    func testReadsMessageFromLoesungSection() {
        XCTAssertEqual(CommitMessage.suggestion(in: real),
                       "BFEZVM-4464 | Add weighted/HGT hint to overall energy efficiency chart")
    }

    func testLoesungsplanIsNotMistakenForLoesung() {
        // Both headings start with "## Lösung" — only the exact section may be read.
        let planOnly = """
        ## Lösungsplan
        **Commit-Message:** `FALSCH | nur ein Plan`
        """
        XCTAssertNil(CommitMessage.suggestion(in: planOnly))
    }

    func testStopsAtTheNextSection() {
        let content = """
        ## Lösung
        Kein Message-Eintrag hier.

        ## Anhang
        **Commit-Message:** `FALSCH | anderer Abschnitt`
        """
        XCTAssertNil(CommitMessage.suggestion(in: content))
    }

    func testToleratesMessageWithoutBackticks() {
        let content = """
        ## Lösung

        **Commit-Message:** EVEN-3513 | remove invitations tile
        """
        XCTAssertEqual(CommitMessage.suggestion(in: content), "EVEN-3513 | remove invitations tile")
    }

    func testTaskFileWithoutASolutionYieldsNothing() {
        XCTAssertNil(CommitMessage.suggestion(in: "# EVEN-1\n\n## Beschreibung\nHallo"))
    }

    func testFallbackFollowsTheCommitConvention() {
        XCTAssertEqual(CommitMessage.fallback(ticketKey: "EVEN-3513"), "EVEN-3513 | ")
    }
}
