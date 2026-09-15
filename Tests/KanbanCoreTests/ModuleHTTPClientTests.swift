import XCTest
@testable import KanbanCore

final class ModuleHTTPClientTests: XCTestCase {
    /// Der Host-Guard greift **vor** der Anfrage: ein fremder Host bekommt den Token gar nicht erst
    /// zu sehen. Der Test braucht deshalb kein Netz.
    func testRefusesAnUnknownHostBeforeSending() {
        let client = ModuleHTTPClient.jira(email: "a@b.c", apiToken: "t",
                                           baseUrls: ["https://firma.atlassian.net"])
        XCTAssertThrowsError(try client.guarded("https://fremder-host.example/rest/api/3/myself")) {
            guard case APIError.forbiddenHost(let module, let host) = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
            XCTAssertEqual(module, "jira")
            XCTAssertEqual(host, "fremder-host.example")
        }
    }

    /// Ein Jira-Projekt darf auf einer anderen Instanz liegen (`zvmsupport`) — beide Hosts stehen in
    /// der Liste, sonst verweigerte der Guard genau dieses Projekt.
    func testAllowsEveryConfiguredHost() throws {
        let client = ModuleHTTPClient.jira(
            email: "a@b.c", apiToken: "t",
            baseUrls: ["https://firma.atlassian.net", "https://support-energie.atlassian.net"])
        XCTAssertNoThrow(try client.guarded("https://firma.atlassian.net/rest/api/3/myself"))
        XCTAssertNoThrow(try client.guarded("https://support-energie.atlassian.net/rest/api/3/myself"))
    }

    /// Gross-/Kleinschreibung im Host darf nicht durchrutschen — sonst wäre der Guard umgehbar.
    func testHostComparisonIsCaseInsensitive() {
        let client = ModuleHTTPClient.gitlab(baseUrl: "https://Git.Firma.IO", apiToken: "t")
        XCTAssertNoThrow(try client.guarded("https://git.firma.io/api/v4/projects"))
    }

    func testRejectsAMalformedURL() {
        let client = ModuleHTTPClient.gitlab(baseUrl: "https://git.firma.io", apiToken: "t")
        XCTAssertThrowsError(try client.guarded("kein://:url")) {
            if case APIError.badURL = $0 {} else { XCTFail("falscher Fehler: \($0)") }
        }
    }

    /// Fehlermeldungen kommen aus dem Body — Jiras `errorMessages` und GitLabs `message`.
    func testErrorBodyMessages() {
        XCTAssertEqual(APIErrorBody.message(in: Data(#"{"errorMessages":["Kein Zugriff"]}"#.utf8)),
                       "Kein Zugriff")
        XCTAssertEqual(APIErrorBody.message(in: Data(#"{"errors":{"worklog":"zu lang"}}"#.utf8)),
                       "zu lang")
        XCTAssertEqual(APIErrorBody.message(in: Data(#"{"message":"403 Forbidden"}"#.utf8)),
                       "403 Forbidden")
        XCTAssertNil(APIErrorBody.message(in: Data("kein json".utf8)))
    }
}
