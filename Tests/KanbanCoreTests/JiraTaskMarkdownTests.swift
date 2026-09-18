import XCTest
@testable import KanbanCore

/// Der Aufbau des Task-Files gegen **Hermes' eigene Ausgabe**. Der Erwartungswert unten ist nicht
/// ausgedacht, sondern das Ergebnis von `modules/jira/format.js` für dieselben Daten. Ohne diesen
/// Test driften die beiden Fassungen unsichtbar auseinander: jede Seite prüft sonst nur gegen sich
/// selbst, und beide bleiben dabei grün.
final class JiraTaskMarkdownTests: XCTestCase {
    private func meta() -> JiraIssueMeta {
        JiraIssueMeta(status: "In Arbeit", priority: "Hoch", resolution: nil, resolutionDate: nil,
                      storyPoints: 3, labels: ["frontend", "regression"], components: ["Dateiablage"],
                      fixVersions: [], affectedVersions: [], created: "2026-01-02",
                      updated: "2026-01-09", dueDate: nil, originalEstimate: nil,
                      remainingEstimate: nil, timeSpent: nil, aggregateOriginalEstimate: nil,
                      aggregateRemainingEstimate: nil, aggregateTimeSpent: nil, watchers: 2, votes: 1,
                      parent: JiraSubtaskRef(key: "EVEN-1", summary: "Epic Dateiablage"))
    }

    private func issue() -> JiraIssue {
        JiraIssue(key: "EVEN-42", summary: "Anhänge werden nicht angezeigt", issueType: "Bug",
                  reporter: JiraUser(accountId: "1", displayName: "kunde@example.test",
                                     emailAddress: nil, avatarUrl: nil),
                  assignee: nil,
                  creator: JiraUser(accountId: "2", displayName: "Interner Ersteller",
                                    emailAddress: nil, avatarUrl: nil),
                  meta: meta(),
                  description: "Die Liste bleibt leer.\n\n![1-bild.png]({{IMG_0}})",
                  environment: "macOS 15",
                  ausgangslage: "Vorher ging es.",
                  erwartetesErgebnis: "Anhänge erscheinen.",
                  erweiterteBeschreibung: nil,
                  akzeptanzkriterien: "- [x] Liste zeigt Anhänge\n- [ ] Leerer Zustand",
                  customFields: [JiraCustomField(id: "customfield_10052", name: "Lösung", value: "Noch offen")],
                  extraFields: [JiraExtraField(id: "customfield_99", name: "Rang", value: "0|i0001")],
                  subtasks: [JiraSubtaskRef(key: "EVEN-43", summary: "Backend")],
                  linkedIssues: [JiraLinkedIssue(key: "EVEN-7", summary: "Vorgänger",
                                                 status: "Fertig", relation: "blockiert")],
                  attachments: [], images: [])
    }

    func testMatchesTheJavaScriptFormatter() {
        let savedImages = [
            SavedImage(filename: "1-bild.png", relativePath: "EVEN-42/1-bild.png",
                       index: 0, unreferenced: false),
            SavedImage(filename: "2-tabelle.xlsx", relativePath: "EVEN-42/2-tabelle.xlsx",
                       index: 1, unreferenced: true),
        ]
        let subtasks = [JiraSubtaskContent(key: "EVEN-43", summary: "Backend",
                                           description: "Endpunkt liefert nichts.",
                                           akzeptanzkriterien: "- Endpunkt liefert die Liste",
                                           customFields: [JiraCustomField(id: "cf1", name: "Aufwand", value: "2h")],
                                           images: [], nextImageIndex: 2)]

        let expected = """
        # EVEN-42 - Anhänge werden nicht angezeigt
        Typ: Bug
        Status: In Arbeit
        Priorität: Hoch
        Story Points: 3
        Erstellt: 2026-01-02
        Aktualisiert: 2026-01-09
        Labels: frontend, regression
        Komponenten: Dateiablage
        Parent: EVEN-1 — Epic Dateiablage
        Watchers: 2
        Votes: 1

        kunde@example.test hat diese Anfrage erstellt

        ## Beschreibung
        Die Liste bleibt leer.

        ![1-bild.png](EVEN-42/1-bild.png)

        ## Ausgangslage
        Vorher ging es.

        ## Erwartetes Ergebnis / Verhalten
        Anhänge erscheinen.

        ## Akzeptanzkriterien
        - [x] Liste zeigt Anhänge
        - [ ] Leerer Zustand

        ## Environment
        macOS 15

        ## Lösung
        Noch offen

        ## Verwandte Tasks
        - **EVEN-7**: Vorgänger _(blockiert)_ [Fertig]

        ## Sub-Tasks

        ### EVEN-43 - Backend

        Endpunkt liefert nichts.

        #### Akzeptanzkriterien
        - Endpunkt liefert die Liste

        #### Aufwand
        2h

        ## Kommentare

        [Kommentar-Diskussion (JSON)](EVEN-42/comments.json) — 4 Kommentare

        ## Anhänge
        ![2-tabelle.xlsx](EVEN-42/2-tabelle.xlsx)



        ## Weitere Felder
        - **Rang**: 0|i0001
        """

        let actual = JiraTaskMarkdown.format(issue: issue(), savedImages: savedImages,
                                             subtaskContents: subtasks,
                                             commentsLink: CommentsLink(path: "EVEN-42/comments.json", count: 4))
        XCTAssertEqual(actual, expected)
    }

    /// Ohne geholten Inhalt stehen die Unteraufgaben kurz da — nie beide Formen zugleich.
    func testSubtasksAreShortWithoutContent() {
        let md = JiraTaskMarkdown.format(issue: issue())
        XCTAssertTrue(md.contains("## Sub-Tasks\n- EVEN-43: Backend"))
        XCTAssertFalse(md.contains("### EVEN-43"))
    }

    /// Ein Anhang ohne `content`-URL wird übersprungen — die Bildzeile, deren Platzhalter nichts
    /// gefunden hat, muss dann ganz verschwinden statt als gebrochenes Bild stehenzubleiben.
    func testUnresolvedPlaceholderRemovesTheImageLine() {
        let text = "Davor\n\n![1-weg.png]({{IMG_7}})\nDanach"
        XCTAssertEqual(JiraTaskMarkdown.replacePlaceholders(text, savedImages: []),
                       "Davor\n\nDanach")
    }

    /// `1` und `1.0` sind in Jira dasselbe Feld; „1.0" im Task-File wäre ein Unterschied ohne Grund.
    func testIntegralStoryPointsLoseTheDecimal() {
        let md = JiraTaskMarkdown.renderMeta(
            JiraIssueMeta(status: nil, priority: nil, resolution: nil, resolutionDate: nil,
                          storyPoints: 1, labels: [], components: [], fixVersions: [],
                          affectedVersions: [], created: nil, updated: nil, dueDate: nil,
                          originalEstimate: nil, remainingEstimate: nil, timeSpent: nil,
                          aggregateOriginalEstimate: nil, aggregateRemainingEstimate: nil,
                          aggregateTimeSpent: nil, watchers: 0, votes: 0, parent: nil))
        XCTAssertEqual(md, "Story Points: 1")
    }
}
