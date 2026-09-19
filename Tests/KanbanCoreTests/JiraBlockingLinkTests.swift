import XCTest
@testable import KanbanCore

/// Die Richtung einer `Blocks`-Verknüpfung — aus einer **echten** Jira-Antwort.
///
/// Warum als Test und nicht als Kommentar: die Feldnamen legen die falsche Lesart nahe. Wer
/// `outwardIssue` als „blockiert mich" liest, bekommt ein Brett, auf dem jede Sperre spiegelverkehrt
/// steht — und das fällt nicht auf, weil beide Seiten plausibel aussehen. Die Nutzlast unten ist
/// wörtlich die Antwort von `centris-hub.atlassian.net` für CENTRISBAU-9 (der Compose-Stack, der
/// auf das Monorepo wartet und seinerseits drei Vorgänge aufhält).
final class JiraBlockingLinkTests: XCTestCase {

    private let echteAntwort = """
    {"issues":[{"key":"CENTRISBAU-9","fields":{
      "summary":"Docker-Compose-Stack fuer api, web, postgres und keycloak",
      "status":{"name":"Zu erledigen","statusCategory":{"key":"new"}},
      "issuetype":{"name":"Story","subtask":false},
      "issuelinks":[
        {"type":{"name":"Blocks"},
         "inwardIssue":{"key":"CENTRISBAU-8","fields":{
           "summary":"Monorepo-Geruest mit pnpm Workspaces und Turborepo",
           "status":{"name":"Zu erledigen","statusCategory":{"key":"new"}}}}},
        {"type":{"name":"Blocks"},
         "outwardIssue":{"key":"CENTRISBAU-10","fields":{
           "summary":"Lokale Domains, mkcert-Zertifikat und DNS-Eintrag je Stack",
           "status":{"name":"Zu erledigen","statusCategory":{"key":"new"}}}}},
        {"type":{"name":"Blocks"},
         "outwardIssue":{"key":"CENTRISBAU-12","fields":{
           "summary":"Development-Services Mailpit und Adminer hinter Profilen",
           "status":{"name":"Zu erledigen","statusCategory":{"key":"new"}}}}},
        {"type":{"name":"Relates"},
         "inwardIssue":{"key":"CENTRISBAU-99","fields":{
           "summary":"Irgendwas Verwandtes",
           "status":{"name":"Zu erledigen","statusCategory":{"key":"new"}}}}}
      ]}}]}
    """

    private func ticket() throws -> Ticket {
        let list = try JSONDecoder().decode(JiraClient.IssueList.self,
                                            from: Data(echteAntwort.utf8))
        return try XCTUnwrap(JiraClient.tickets(from: list).first)
    }

    /// `inwardIssue` ist der Blocker — CENTRISBAU-9 wartet auf das Monorepo-Gerüst.
    func testInwardIssueIstDerBlocker() throws {
        XCTAssertEqual(try ticket().blockedBy.map(\.key), ["CENTRISBAU-8"])
    }

    /// Und `outwardIssue` ist es **nicht**: -10 und -12 warten auf -9, nicht umgekehrt. Genau hier
    /// stand der Fehler, den erst die echte Antwort gezeigt hat.
    func testOutwardIssueIstKeinBlocker() throws {
        let keys = try ticket().blockedBy.map(\.key)
        XCTAssertFalse(keys.contains("CENTRISBAU-10"))
        XCTAssertFalse(keys.contains("CENTRISBAU-12"))
    }

    /// Andere Verknüpfungstypen sind keine Sperre — „Relates" sagt nichts über Reihenfolge.
    func testNurBlocksZaehlt() throws {
        XCTAssertFalse(try ticket().blockedBy.map(\.key).contains("CENTRISBAU-99"))
    }

    /// Der Status des Blockers kommt aus dem Link selbst — deshalb braucht die Ableitung keine
    /// Zusatzanfrage, auch wenn der Blocker gar nicht im Sprint liegt.
    func testStatusStehtImLink() throws {
        let blocker = try XCTUnwrap(ticket().blockedBy.first)
        XCTAssertEqual(blocker.statusCategory, "new")
        XCTAssertFalse(blocker.isDone)
        XCTAssertEqual(blocker.summary, "Monorepo-Geruest mit pnpm Workspaces und Turborepo")
    }

    /// Der Rang ist die Position in der Antwort — die Agile-API liefert nach Rank sortiert.
    func testRankKommtAusDerReihenfolge() throws {
        XCTAssertEqual(try ticket().rankIndex, 0)
    }
}
