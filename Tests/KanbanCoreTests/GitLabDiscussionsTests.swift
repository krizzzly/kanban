import XCTest
@testable import KanbanCore

final class GitLabDiscussionsTests: XCTestCase {
    private typealias Discussion = GitLabClient.RawDiscussion
    private typealias Note = GitLabClient.RawNote

    func testCountsOnlyUnresolvedResolvableDiscussions() {
        let discussions = [
            Discussion(notes: [Note(resolvable: true, resolved: false)]),   // offen → zählt
            Discussion(notes: [Note(resolvable: true, resolved: true)]),    // resolved → zählt nicht
            Discussion(notes: [Note(resolvable: false, resolved: nil)]),    // System-Note → zählt nicht
            Discussion(notes: nil),                                         // ohne Notes → zählt nicht
        ]
        XCTAssertEqual(GitLabClient.unresolvedCount(discussions), 1)
    }

    /// Ein Thread zählt einmal, sobald irgendeine seiner Notes offen ist — nicht pro Note.
    func testMixedThreadCountsOnce() {
        let thread = Discussion(notes: [
            Note(resolvable: true, resolved: true),
            Note(resolvable: true, resolved: false),
            Note(resolvable: true, resolved: false),
        ])
        XCTAssertEqual(GitLabClient.unresolvedCount([thread]), 1)
    }

    /// GitLabs Diskussions-JSON (auf die relevanten Felder reduziert) dekodiert in die Zählung.
    func testDecodesGitLabPayload() throws {
        let json = """
        [
          {"id": "a", "individual_note": false,
           "notes": [{"id": 1, "body": "bitte umbenennen", "resolvable": true, "resolved": false}]},
          {"id": "b", "individual_note": true,
           "notes": [{"id": 2, "body": "changed the milestone", "system": true, "resolvable": false}]},
          {"id": "c", "individual_note": false,
           "notes": [{"id": 3, "body": "done", "resolvable": true, "resolved": true}]}
        ]
        """
        let discussions = try JSONDecoder().decode([Discussion].self, from: Data(json.utf8))
        XCTAssertEqual(GitLabClient.unresolvedCount(discussions), 1)
    }
}
