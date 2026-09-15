import XCTest
@testable import KanbanCore

/// `JiraClient.parseIssue` — die Übersetzung einer Jira-Antwort in `JiraIssue`. Die Feldformen
/// stammen aus einer echten Antwort dieser Instanz (`/rest/api/3/issue/<KEY>?expand=names`).
final class JiraIssueParsingTests: XCTestCase {
    private func parse(_ json: String) throws -> JiraIssue {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return JiraClient.parseIssue(key: "EVEN-1", raw: raw)
    }

    private func adfDoc(_ text: String) -> String {
        #"{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"\#(text)"}]}]}"#
    }

    func testCoreFieldsAndUsers() throws {
        let issue = try parse("""
        {"names": {"customfield_10076": "Akzeptanzkriterien"},
         "fields": {
           "summary": "Trigger Nachtrag eingereicht",
           "issuetype": {"name": "Story"},
           "reporter": {"accountId": "a1", "displayName": "Miriam Pech",
                        "avatarUrls": {"48x48": "https://x/av48"}},
           "assignee": {"accountId": "a2", "displayName": "Christian Hiller"},
           "description": \(adfDoc("Beschreibung")),
           "customfield_10076": \(adfDoc("Kriterium"))
         }}
        """)

        XCTAssertEqual(issue.summary, "Trigger Nachtrag eingereicht")
        XCTAssertEqual(issue.issueType, "Story")
        XCTAssertEqual(issue.reporter?.displayName, "Miriam Pech")
        XCTAssertEqual(issue.reporter?.avatarUrl, "https://x/av48")
        XCTAssertEqual(issue.assignee?.accountId, "a2")
        XCTAssertEqual(issue.description, "Beschreibung")
        XCTAssertEqual(issue.akzeptanzkriterien, "Kriterium")
    }

    /// Der Meta-Block: Jiras eigene Dauerschreibweise, und die Aggregat-Werte nur, wenn sie von der
    /// Einzelschätzung abweichen — sonst stünde zweimal dieselbe Zahl im UI.
    func testMetaBlock() throws {
        let issue = try parse("""
        {"fields": {
          "status": {"name": "In Arbeit"},
          "priority": {"name": "Mittel"},
          "customfield_10016": 3,
          "labels": ["backend", "ui"],
          "components": [{"name": "API"}],
          "created": "2026-08-14T12:03:56.332+0200",
          "timetracking": {"timeSpentSeconds": 5400},
          "aggregatetimespent": 12600,
          "watches": {"watchCount": 2},
          "votes": {"votes": 1},
          "parent": {"key": "EVEN-3345", "fields": {"summary": "Story oben"}}
        }}
        """)

        XCTAssertEqual(issue.meta.status, "In Arbeit")
        XCTAssertEqual(issue.meta.storyPoints, 3)
        XCTAssertEqual(issue.meta.labels, ["backend", "ui"])
        XCTAssertEqual(issue.meta.components, ["API"])
        XCTAssertEqual(issue.meta.timeSpent, "1h 30m")
        XCTAssertEqual(issue.meta.aggregateTimeSpent, "3h 30m")
        XCTAssertEqual(issue.meta.watchers, 2)
        XCTAssertEqual(issue.meta.votes, 1)
        XCTAssertEqual(issue.meta.parent?.key, "EVEN-3345")
        XCTAssertEqual(issue.meta.parent?.summary, "Story oben")
    }

    func testAggregateEqualToSingleEstimateIsDropped() throws {
        let issue = try parse("""
        {"fields": {"timetracking": {"timeSpentSeconds": 3600}, "aggregatetimespent": 3600}}
        """)
        XCTAssertEqual(issue.meta.timeSpent, "1h")
        XCTAssertNil(issue.meta.aggregateTimeSpent)
    }

    /// Jedes Feld genau einmal: Rich-Text bekommt einen eigenen Abschnitt, alles flach Darstellbare
    /// bleibt in „Weitere Felder". Ohne diese Trennung stand dasselbe Feld doppelt da.
    func testCustomFieldsAndExtraFieldsDoNotOverlap() throws {
        let issue = try parse("""
        {"names": {"customfield_10100": "Lösung", "customfield_10101": "Verrechnungstyp",
                   "customfield_10102": "Freigegeben von"},
         "fields": {
           "customfield_10100": \(adfDoc("Reicher Text")),
           "customfield_10101": {"value": "Direkte Verrechnung"},
           "customfield_10102": {"accountId": "a3", "displayName": "Chef"},
           "summary": "wird nie gelistet"
         }}
        """)

        // Rich-Text und Identität → eigener Abschnitt …
        XCTAssertEqual(issue.customFields.map(\.name), ["Lösung", "Freigegeben von"])
        XCTAssertEqual(issue.customFields.first?.value, "Reicher Text")
        XCTAssertEqual(issue.customFields.last?.value, "Chef")

        // … alles flach Darstellbare in die Liste, und keins von beidem doppelt.
        XCTAssertEqual(issue.extraFields.map(\.name), ["Verrechnungstyp"])
        XCTAssertFalse(issue.extraFields.contains { $0.name == "Lösung" })
        XCTAssertFalse(issue.extraFields.contains { $0.id == "summary" })
    }

    func testSubtasksAndLinkedIssues() throws {
        let issue = try parse("""
        {"fields": {
          "subtasks": [{"key": "EVEN-2", "fields": {"summary": "Teilaufgabe"}}],
          "issuelinks": [
            {"type": {"outward": "blockiert", "inward": "wird blockiert von"},
             "outwardIssue": {"key": "EVEN-3", "fields": {"summary": "Ziel", "status": {"name": "Offen"}}}},
            {"type": {"outward": "verursacht", "inward": "verursacht durch"},
             "inwardIssue": {"key": "EVEN-4", "fields": {"summary": "Quelle"}}}
          ]}}
        """)

        XCTAssertEqual(issue.subtasks.map(\.key), ["EVEN-2"])
        XCTAssertEqual(issue.linkedIssues.map(\.key), ["EVEN-3", "EVEN-4"])
        XCTAssertEqual(issue.linkedIssues.first?.relation, "blockiert")
        XCTAssertEqual(issue.linkedIssues.first?.status, "Offen")
        XCTAssertEqual(issue.linkedIssues.last?.relation, "verursacht durch")
    }

    /// Ein Bild im Text bekommt die URL seines Attachments; ein Attachment, auf das nichts zeigt,
    /// wird hinten angehängt — Jira zeigt es unter der Beschreibung, es gehört also zum Ticket.
    func testImagesAreMatchedToAttachments() throws {
        let issue = try parse("""
        {"fields": {
          "description": {"type":"doc","version":1,"content":[
            {"type":"mediaSingle","content":[
              {"type":"media","attrs":{"id":"m1","alt":"bild.png"}}]}]},
          "attachment": [
            {"id":"1","filename":"bild.png","content":"https://x/att/1","mimeType":"image/png","size":10},
            {"id":"2","filename":"anhang.pdf","content":"https://x/att/2"}
          ]}}
        """)

        XCTAssertEqual(issue.attachments.count, 2)
        XCTAssertEqual(issue.images.count, 2)

        let referenced = try XCTUnwrap(issue.images.first)
        XCTAssertEqual(referenced.originalName, "bild.png")
        XCTAssertEqual(referenced.url, "https://x/att/1")
        XCTAssertFalse(referenced.unreferenced)

        let orphan = try XCTUnwrap(issue.images.last)
        XCTAssertEqual(orphan.originalName, "anhang.pdf")
        XCTAssertEqual(orphan.filename, "2-anhang.pdf")
        XCTAssertTrue(orphan.unreferenced)
    }

    /// Ein leeres Ticket darf keinen Absturz und keine erfundenen Werte ergeben.
    func testEmptyIssue() throws {
        let issue = try parse(#"{"fields": {}}"#)
        XCTAssertEqual(issue.summary, "")
        XCTAssertNil(issue.description)
        XCTAssertTrue(issue.customFields.isEmpty)
        XCTAssertTrue(issue.extraFields.isEmpty)
        XCTAssertTrue(issue.images.isEmpty)
        XCTAssertEqual(issue.meta.watchers, 0)
    }
}
