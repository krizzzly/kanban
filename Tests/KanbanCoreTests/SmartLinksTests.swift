import XCTest
@testable import KanbanCore

final class SmartLinksTests: XCTestCase {
    private func adf(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    // MARK: - Klassifikation

    func testClassifiesJiraIssues() {
        XCTAssertEqual(SmartLinks.classify("https://x.atlassian.net/browse/EVEN-123"),
                       .jiraIssue(key: "EVEN-123"))
        XCTAssertEqual(SmartLinks.classify("https://x.atlassian.net/jira/software/c/projects/A/boards/1?selectedIssue=CORETEST-4207"),
                       .jiraIssue(key: "CORETEST-4207"))
        XCTAssertNil(SmartLinks.classify("https://irgendwo.test/seite"))
        XCTAssertNil(SmartLinks.classify(""))
    }

    /// Der Kommentar gewinnt gegen die Seite: die Kommentar-URL erfüllt beide Muster, und der
    /// Kommentar ist die genauere Aussage.
    func testCommentWinsOverPage() {
        XCTAssertEqual(SmartLinks.classify("https://x.atlassian.net/wiki/spaces/S/pages/12345/Titel?focusedCommentId=999"),
                       .confluenceComment(pageId: "12345", commentId: "999"))
        XCTAssertEqual(SmartLinks.classify("https://x.atlassian.net/wiki/spaces/S/pages/12345/Titel"),
                       .confluencePage(pageId: "12345"))
    }

    /// Die beiden Werte stehen so in Hermes' `smart-links.js` — dort an Kurzlinks aus dem Live-Space
    /// gegengeprüft. Damit prüft dieser Test die Dekodierung gegen echte Daten und nicht gegen die
    /// eigene Implementierung.
    func testTinyLinkDecodesToPageId() {
        XCTAssertEqual(SmartLinks.pageIdFromTinyLink("AgDRM"), "819003394")
        XCTAssertEqual(SmartLinks.pageIdFromTinyLink("AYArOw"), "992706561")
        XCTAssertEqual(SmartLinks.classify("https://x.atlassian.net/wiki/x/AgDRM"),
                       .confluencePage(pageId: "819003394"))
    }

    func testTinyLinkRejectsNonsense() {
        XCTAssertNil(SmartLinks.pageIdFromTinyLink(""))
        XCTAssertNil(SmartLinks.pageIdFromTinyLink("viel-zu-langer-code"))
        XCTAssertNil(SmartLinks.pageIdFromTinyLink("mit/schraegstrich"))
        XCTAssertNil(SmartLinks.pageIdFromTinyLink("A"))          // dekodiert zu 0
    }

    // MARK: - Einsammeln

    /// Karten **und** Links, deren sichtbarer Text die URL selbst ist — aber kein Link, den jemand
    /// beschriftet hat, und nichts Unauflösbares.
    func testCollectsCardsAndBareURLLinks() throws {
        let doc = try adf("""
        {"type":"doc","content":[
          {"type":"paragraph","content":[
            {"type":"inlineCard","attrs":{"url":"https://x.atlassian.net/browse/EVEN-1"}},
            {"type":"text","text":"https://x.atlassian.net/browse/EVEN-2",
             "marks":[{"type":"link","attrs":{"href":"https://x.atlassian.net/browse/EVEN-2"}}]},
            {"type":"text","text":"eigener Text",
             "marks":[{"type":"link","attrs":{"href":"https://x.atlassian.net/browse/EVEN-3"}}]},
            {"type":"text","text":"https://fremd.test/x",
             "marks":[{"type":"link","attrs":{"href":"https://fremd.test/x"}}]}
          ]},
          {"type":"blockCard","attrs":{"url":"https://x.atlassian.net/browse/EVEN-1"}}
        ]}
        """)
        XCTAssertEqual(SmartLinks.collectURLs(in: doc),
                       ["https://x.atlassian.net/browse/EVEN-1",
                        "https://x.atlassian.net/browse/EVEN-2"])
    }

    func testFallbackLabelMatchesTheConverter() {
        XCTAssertEqual(SmartLinks.fallbackLabel("https://x.atlassian.net/browse/EVEN-123"), "EVEN-123")
        XCTAssertEqual(SmartLinks.fallbackLabel("https://c.test/pages/456/Meine+Seite"), "Meine Seite")
    }

    // MARK: - Budget

    /// Das Budget ist ein Runaway-Guard, keine funktionale Grenze: es greift erst weit jenseits
    /// dessen, was ein reales Ticket verlinkt. Ohne konfigurierte Basis-URL löst nichts auf — der
    /// Test prüft deshalb, dass ein fremder Host **fail-open** durchfällt statt zu werfen.
    func testForeignHostsResolveToNothingInsteadOfFailing() async {
        let links = SmartLinks(http: ModuleHTTPClient(module: "jira", baseUrls: ["https://konfiguriert.test"],
                                                      authHeaders: [:]),
                               baseUrls: ["https://konfiguriert.test"])
        let resolved = await links.resolve(urls: ["https://fremd.test/browse/EVEN-1",
                                                  "https://irgendwo.test/seite"])
        XCTAssertTrue(resolved.isEmpty)
    }
}
