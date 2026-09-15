import XCTest
@testable import KanbanCore

/// Die Übersetzung der GitLab-Antworten in Domain-Typen. Feldformen aus echten Antworten dieser
/// Instanz (`/merge_requests/:iid`, `/notes`, `/discussions`, `/diffs`).
final class GitLabParsingTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testMergeRequestIncludingDiffRefs() throws {
        let mr = GitLabClient.parseMergeRequest(try json("""
        {"id": 12345, "iid": 651, "project_id": 616,
         "title": "EVEN-3679 | add improvement request withdrawn trigger",
         "description": "Beschreibung", "state": "opened", "draft": false,
         "author": {"name": "Christian Hiller", "username": "chiller"},
         "reviewers": [{"name": "Ebi Nicholas"}],
         "assignees": [{"username": "chiller"}],
         "source_branch": "feature/EVEN-3679", "target_branch": "develop",
         "labels": ["backend"],
         "created_at": "2026-08-14T10:00:00Z", "merged_at": null,
         "detailed_merge_status": "mergeable",
         "web_url": "https://git.iwf.io/applications/even/-/merge_requests/651",
         "changes_count": "5", "user_notes_count": 7,
         "diff_refs": {"base_sha": "52978229", "start_sha": "52978229", "head_sha": "2efb678e"}}
        """))

        XCTAssertEqual(mr.iid, 651)
        XCTAssertEqual(mr.author, "Christian Hiller")
        XCTAssertEqual(mr.reviewers, ["Ebi Nicholas"])
        XCTAssertEqual(mr.assignees, ["chiller"])       // ohne name greift username
        XCTAssertEqual(mr.mergeStatus, "mergeable")
        XCTAssertEqual(mr.changesCount, "5")
        XCTAssertEqual(mr.diffRefs?.headSha, "2efb678e")
        XCTAssertFalse(mr.draft)
    }

    /// Ohne `diff_refs` ist kein Inline-Kommentar möglich — das muss sichtbar bleiben statt in
    /// leeren Strings zu verschwinden.
    func testMissingDiffRefsStayNil() throws {
        let mr = GitLabClient.parseMergeRequest(try json(#"{"iid": 1, "title": "x", "state": "opened"}"#))
        XCTAssertNil(mr.diffRefs)
    }

    /// Draft erkennen wir wie beim Karten-Badge über drei Signale — ältere Instanzen setzen nur den
    /// Titel.
    func testDraftDetection() throws {
        func draft(_ body: String) throws -> Bool {
            GitLabClient.parseMergeRequest(try json(body)).draft
        }
        XCTAssertTrue(try draft(#"{"iid":1,"title":"x","state":"opened","draft":true}"#))
        XCTAssertTrue(try draft(#"{"iid":1,"title":"x","state":"opened","work_in_progress":true}"#))
        XCTAssertTrue(try draft(#"{"iid":1,"title":"Draft: x","state":"opened"}"#))
        XCTAssertTrue(try draft(#"{"iid":1,"title":"WIP: x","state":"opened"}"#))
        XCTAssertFalse(try draft(#"{"iid":1,"title":"x","state":"opened"}"#))
    }

    func testNoteWithInlinePosition() throws {
        let note = GitLabClient.parseNote(try json("""
        {"id": 69432, "author": {"name": "Ebi Nicholas"}, "body": "wie wärs mit …",
         "created_at": "2026-07-01T09:00:00Z", "resolvable": true, "resolved": true,
         "position": {"new_path": "src/Entity/User/User.php", "old_path": "src/Entity/User/User.php",
                      "new_line": 128, "old_line": null}}
        """))

        XCTAssertEqual(note.id, 69432)
        XCTAssertEqual(note.author, "Ebi Nicholas")
        XCTAssertEqual(note.position?.filePath, "src/Entity/User/User.php")
        XCTAssertEqual(note.position?.newLine, 128)
        XCTAssertNil(note.position?.oldLine)
        XCTAssertEqual(note.resolved, true)
    }

    /// Ein Thread gilt als offen, sobald eine *auflösbare* Note offen ist — dieselbe Regel wie beim
    /// Karten-Badge. System-Notes zählen nie.
    func testDiscussionResolutionState() {
        func discussion(_ notes: [(resolvable: Bool?, resolved: Bool?)]) -> GitLabDiscussion {
            GitLabDiscussion(id: "d", individual: false, notes: notes.map {
                GitLabNote(id: 0, author: nil, body: "", createdAt: nil,
                           resolved: $0.resolved, resolvable: $0.resolvable, position: nil)
            })
        }
        XCTAssertTrue(discussion([(true, false)]).isUnresolved)
        XCTAssertTrue(discussion([(true, true), (true, false)]).isUnresolved)
        XCTAssertFalse(discussion([(true, true)]).isUnresolved)
        XCTAssertFalse(discussion([(false, nil)]).isUnresolved)   // reine System-Notes
        XCTAssertFalse(discussion([]).isUnresolved)
    }

    func testDiffEntry() throws {
        let diff = GitLabClient.parseDiff(try json("""
        {"old_path": "a.php", "new_path": "b.php", "diff": "@@ -1 +1 @@\\n-alt\\n+neu\\n",
         "new_file": false, "renamed_file": true, "deleted_file": false}
        """))
        XCTAssertEqual(diff.oldPath, "a.php")
        XCTAssertEqual(diff.newPath, "b.php")
        XCTAssertTrue(diff.renamedFile)
        XCTAssertEqual(MRDiffPosition.parseHunks(diff.diff).count, 1)
    }

    func testProjectPathEncoding() {
        XCTAssertEqual(GitLabClient.encode("applications/even"), "applications%2Feven")
        XCTAssertEqual(GitLabClient.encode("a/b/c"), "a%2Fb%2Fc")
    }
}
