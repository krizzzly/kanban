import XCTest
@testable import KanbanCore

final class SolutionDraftTests: XCTestCase {
    /// The shape solve-task writes (Schritt 7), shortened but structurally real.
    private let real = """
    <!-- kanban-claude-session: abc -->
    # EVEN-3547 - Einladung ohne Verwalter-Recht

    ## Lösung

    **Commit-Message:** `EVEN-3547 | Grant admin right on invite`

    ## JIRA Lösungsfeld

    ### Für Test-Ingenieur

    **Manuelle Testanleitung:**

    - Rolle: Projektkoordination
    - URL/Seite: /projekt/1/berechtigungen

    **Geänderte Dateien:**

    - Backend: `src/Service/User/Role/UserRoleManager.php`

    ### Für Kunde

    Mit gesetztem Häkchen bekommt die Nachweisverfassung das Verwalter-Recht direkt zugewiesen.

    **Entscheidungen, Abweichungen, Annahmen:**

    - **Entscheidung:** Recht beim Annehmen der Einladung vergeben, nicht beim Versenden — vorher
      existiert der Benutzer noch nicht.
    - **Annahme:** Das Häkchen gilt auch für Bestandspersonen (AK sagt dazu nichts).

    ## Abschluss-Checkliste

    - [x] JIRA Lösungsfeld ausgefüllt
    """

    func testTakesTheCustomerSubsection() {
        let result = SolutionDraft.suggestion(in: real)
        XCTAssertEqual(result?.source, .customerPart)
        let text = result?.text ?? ""
        XCTAssertTrue(text.hasPrefix("Mit gesetztem Häkchen"))
        XCTAssertTrue(text.contains("**Entscheidungen, Abweichungen, Annahmen:**"))
        XCTAssertTrue(text.hasSuffix("(AK sagt dazu nichts)."))
        // The test-engineer part is local noise — it must not travel into the Jira field.
        XCTAssertFalse(text.contains("Geänderte Dateien"))
        XCTAssertFalse(text.contains("Für Test-Ingenieur"))
        // Neither may the following H2 leak in.
        XCTAssertFalse(text.contains("Abschluss-Checkliste"))
    }

    func testFallsBackToTheWholeSectionWithoutACustomerPart() {
        let content = """
        # EVEN-1 - Titel

        ## JIRA Lösungsfeld

        Freihändig geschrieben, ohne Unterabschnitte.

        ## Nächste Schritte
        - [ ] Review
        """
        let result = SolutionDraft.suggestion(in: content)
        XCTAssertEqual(result?.source, .wholeSection)
        XCTAssertEqual(result?.text, "Freihändig geschrieben, ohne Unterabschnitte.")
    }

    /// An empty `### Für Kunde` (template placeholder deleted) must not silently propose "".
    func testEmptyCustomerPartFallsBackToTheSection() {
        let content = """
        ## JIRA Lösungsfeld

        ### Für Test-Ingenieur

        Schritt 1

        ### Für Kunde

        """
        let result = SolutionDraft.suggestion(in: content)
        XCTAssertEqual(result?.source, .wholeSection)
        XCTAssertTrue(result?.text.contains("Für Test-Ingenieur") ?? false)
    }

    func testNoSolutionFieldSectionAtAll() {
        XCTAssertNil(SolutionDraft.suggestion(in: "# EVEN-1 - Titel\n\n## Lösung\n\nnur das"))
    }

    func testEmptySolutionFieldSection() {
        XCTAssertNil(SolutionDraft.suggestion(in: "## JIRA Lösungsfeld\n\n## Nächste Schritte\n- [ ] x"))
    }

    /// Deeper headings belong to the customer part — they must not cut it short.
    func testDeeperHeadingsStayInsideTheCustomerPart() {
        let content = """
        ## JIRA Lösungsfeld

        ### Für Kunde

        Einleitung

        #### Detail

        Auch das gehört dazu.
        """
        XCTAssertEqual(SolutionDraft.suggestion(in: content)?.text,
                       "Einleitung\n\n#### Detail\n\nAuch das gehört dazu.")
    }

    /// Hand-written spellings: no umlaut, plural, trailing colon.
    func testAcceptsTheUsualSpellings() {
        for heading in ["### Fuer Kunde", "### Für Kunden", "### Für Kunde:"] {
            let content = "## JIRA Loesungsfeld\n\n### Für Test-Ingenieur\n\nx\n\n\(heading)\n\ndrin"
            XCTAssertEqual(SolutionDraft.suggestion(in: content)?.text, "drin", heading)
        }
    }

    /// `## Lösung` sits right before the field section in real files — it must not be mistaken for it.
    func testLoesungSectionIsNotTheSolutionField() {
        let content = "## Lösung\n\n**Commit-Message:** `X | y`\n\n## JIRA Lösungsfeld\n\n### Für Kunde\n\nText"
        XCTAssertEqual(SolutionDraft.suggestion(in: content)?.text, "Text")
    }
}
