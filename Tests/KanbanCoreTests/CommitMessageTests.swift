import XCTest
@testable import KanbanCore

final class CommitMessageTests: XCTestCase {
    /// The shape solve-task wrote until 2026-09-17 — still on 220 task files.
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

    /// The documented shape solve-task writes today (Kapitel 15): `## Commit`, next to the
    /// `## Lösung` that now carries Jira's developer solution field.
    private let heutige = """
    # CORETEST-4275 - OMGE-Abzug

    ## Lösung

    Wurde behoben.

    ## Commit

    **Commit-Message:** `CORETEST-4275 | Apply dossier OMGE deduction to certificate reporting`

    **Verifikationsziel:** https://core-4275.test — Dossier → GF → Report
    """

    func testReadsMessageFromCommitSection() {
        XCTAssertEqual(CommitMessage.suggestion(in: heutige),
                       "CORETEST-4275 | Apply dossier OMGE deduction to certificate reporting")
    }

    func testJiraSolutionTextIsNotMistakenForAMessage() {
        // `## Lösung` holds Jira prose now; without a message there it must not win over `## Commit`.
        let content = """
        ## Lösung

        Wurde behoben.

        ## Commit

        **Commit-Message:** `CORETEST-4251 | Fix NOGA code lookup on location import`
        """
        XCTAssertEqual(CommitMessage.suggestion(in: content),
                       "CORETEST-4251 | Fix NOGA code lookup on location import")
    }

    func testCommitMessageHeadingIsNotTheCommitSection() {
        // The skill's console block `## Commit-Message` is a different heading and carries no line.
        let content = """
        ## Commit-Message
        CORETEST-4275 | nur die Konsolenausgabe
        """
        XCTAssertNil(CommitMessage.suggestion(in: content))
    }

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
