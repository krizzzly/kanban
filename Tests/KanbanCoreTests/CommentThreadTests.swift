import XCTest
@testable import KanbanCore

/// Die Kommentar-Diskussion neben dem Task-File. Die Form stammt aus den echten Dateien dieser
/// Maschine: 78 `comments.json`, 216 Kommentare, **ausnahmslos** flach `{author, created, body}`.
final class CommentThreadTests: XCTestCase {
    private let json = """
    [{"author": "Miriam Pech", "created": "2026-03-25T14:06:12.269+0100",
      "body": "Zurückgestellt auf Story."},
     {"author": "Stephan Kämpfen", "created": "2026-04-08T18:01:41.947+0200",
      "body": "Für mich passt das so.\\n\\n- offen: wer ist „Vollzug\\"?\\n- **eher nicht** die PK"}]
    """

    func testParsesTheRealShape() throws {
        let comments = try XCTUnwrap(CommentThread.parse(json))
        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].author, "Miriam Pech")
        XCTAssertEqual(comments[1].body.contains("**eher nicht**"), true)
    }

    /// Fremdes JSON bleibt fremdes JSON — die Anzeige fällt dann auf den rohen Block zurück.
    func testForeignJsonIsNotAThread() {
        XCTAssertNil(CommentThread.parse(#"{"foo": 1}"#))
        XCTAssertNil(CommentThread.parse("[]"))
        XCTAssertNil(CommentThread.parse(#"[{"id": 7}]"#))
        XCTAssertNil(CommentThread.parse("kein json"))
    }

    /// Mit und ohne Sekundenbruchteile, verschiedene Offsets — und Unlesbares bleibt stehen, statt
    /// ein falsches Datum zu behaupten.
    func testTimestampFormats() {
        XCTAssertEqual(CommentThread.absolute("2026-03-25T14:06:12.269+0100"), "25.03.2026, 14:06")
        XCTAssertEqual(CommentThread.absolute("2026-04-08T18:01:41+0200"), "08.04.2026, 18:01")
        XCTAssertEqual(CommentThread.absolute("irgendwas"), "irgendwas")
        XCTAssertEqual(CommentThread.relative("irgendwas"), "irgendwas")
    }

    /// Der Body muss **als Markdown** ankommen: 13 der 216 echten Kommentare enthalten Links, 5
    /// Listen. Deshalb die Leerzeilen um den Inhalt — cmark liest einen HTML-Block sonst bis zur
    /// nächsten Leerzeile roh und liesse `**fett**` stehen.
    func testBodyStaysMarkdownInsideTheCard() throws {
        let comments = try XCTUnwrap(CommentThread.parse(json))
        let html = MarkdownHTML.render(CommentThread.markdown(comments))

        XCTAssertTrue(html.contains(#"<div class="comment">"#), html)
        XCTAssertTrue(html.contains("Miriam Pech"), html)
        XCTAssertTrue(html.contains("25.03.2026, 14:06"), html)
        XCTAssertTrue(html.contains("<strong>eher nicht</strong>"), html)   // Markdown gerendert
        XCTAssertTrue(html.contains("<li>"), html)                          // Liste gerendert
        XCTAssertFalse(html.contains("**eher nicht**"), html)               // nicht roh stehen geblieben
    }

    /// Jira liefert die Antwort-Struktur mit: `id` als **String**, `parentId` als **Zahl** —
    /// dieselbe API, zwei Typen (an CORETEST-4003 nachgesehen). Beides muss durchgehen.
    func testMixedIdTypesAreRead() throws {
        let comments = try XCTUnwrap(CommentThread.parse("""
        [{"id": "115217", "author": "A", "created": "2026-08-31T14:47:18.764+0200", "body": "root"},
         {"id": "115483", "parentId": 115217, "author": "B",
          "created": "2026-09-02T08:22:00.000+0200", "body": "antwort"}]
        """))
        XCTAssertEqual(comments[1].id, "115483")
        XCTAssertEqual(comments[1].parentId, "115217")
    }

    /// Antworten stehen direkt unter ihrem Bezug, eine Ebene tiefer.
    func testRepliesFollowTheirParentIndented() {
        let comments = [
            TaskComment(id: "1", author: "A", created: "", body: "root"),
            TaskComment(id: "2", author: "B", created: "", body: "zweite Wurzel"),
            TaskComment(id: "3", parentId: "1", author: "C", created: "", body: "antwort auf 1"),
            TaskComment(id: "4", parentId: "3", author: "D", created: "", body: "antwort auf 3"),
        ]
        let order = CommentThread.ordered(comments)
        XCTAssertEqual(order.map(\.comment.id), ["1", "3", "4", "2"])
        XCTAssertEqual(order.map(\.depth), [0, 1, 2, 0])
    }

    /// Eine Antwort auf einen Kommentar, den es nicht (mehr) gibt, wird zur Wurzel — sie
    /// verschwinden zu lassen wäre schlimmer, als sie flach zu zeigen.
    func testOrphanedReplyBecomesARoot() {
        let order = CommentThread.ordered([
            TaskComment(id: "9", parentId: "weg", author: "A", created: "", body: "x")])
        XCTAssertEqual(order.map(\.depth), [0])
    }

    /// Ältere Exporte haben keine Ids — dann bleibt es bei der flachen Liste.
    func testWithoutIdsEverythingStaysFlat() {
        let order = CommentThread.ordered([
            TaskComment(author: "A", created: "", body: "x"),
            TaskComment(author: "B", created: "", body: "y")])
        XCTAssertEqual(order.map(\.depth), [0, 0])
    }

    /// Mit gespeichertem Profilbild steht ein `<img>` im Kopf — **inline als data-URI**, weil
    /// WKWebViews `loadHTMLString` keinen Dateizugriff hat. Ohne Bild bleiben die Initialen.
    func testAvatarIsInlinedWhenPresent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("avatar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("T-1/avatars"),
                                                withIntermediateDirectories: true)
        // 1×1-PNG, echte Bytes — ein leerer File würde stillschweigend auf die Initialen fallen.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgYAAAAAM"
                                    + "AASsJTYQAAAAASUVORK5CYII=")!
        try png.write(to: dir.appendingPathComponent("T-1/avatars/Patric-Alder.png"))
        defer { try? FileManager.default.removeItem(at: dir) }

        let withAvatar = TaskComment(author: "Patric Alder", created: "", body: "x",
                                     avatar: "T-1/avatars/Patric-Alder.png")
        let markdown = CommentThread.markdown([withAvatar], directory: dir)
        XCTAssertTrue(markdown.contains(#"<img class="comment-avatar" src="data:image/png;base64,"#), markdown)
        XCTAssertTrue(markdown.contains(#"alt="PA""#), markdown)

        // Fehlende Datei → Initialen, keine kaputte Bildmarke.
        let missing = TaskComment(author: "Patric Alder", created: "", body: "x",
                                  avatar: "T-1/avatars/gibtsnicht.png")
        XCTAssertTrue(CommentThread.markdown([missing], directory: dir)
            .contains(#"<span class="comment-avatar">PA</span>"#))
    }

    /// Der Export schreibt `avatar` erst seit heute — ältere Dateien haben das Feld nicht.
    func testAvatarFieldIsOptional() throws {
        let comments = try XCTUnwrap(CommentThread.parse("""
        [{"author": "A", "created": "2026-01-01T00:00:00+0100", "body": "x"}]
        """))
        XCTAssertNil(comments[0].avatar)
    }

    func testInitialsMatchWhatJiraShows() {
        XCTAssertEqual(CommentThread.initials("Patric Alder"), "PA")
        XCTAssertEqual(CommentThread.initials("Suter Xeno"), "SX")
        XCTAssertEqual(CommentThread.initials("Entwicklung"), "E")
        XCTAssertEqual(CommentThread.initials(""), "?")
    }

    /// Erwähnungen nur für Namen aus **dieser** Diskussion: „@ + Grossbuchstabe" träfe sonst auch
    /// Handles, E-Mail-Adressen und Code.
    func testOnlyKnownAuthorsBecomeMentions() {
        let names: Set<String> = ["Patric Alder", "Suter Xeno"]
        let out = CommentThread.mentions(in: "@Patric Alder bitte prüfen, @Fremder nicht, "
                                         + "mail@example.test auch nicht", names: names)
        XCTAssertTrue(out.contains(#"<span class="mention">@Patric Alder</span>"#), out)
        XCTAssertFalse(out.contains("<span class=\"mention\">@Fremder"), out)
        XCTAssertFalse(out.contains("<span class=\"mention\">@example"), out)
    }

    func testRelativeDateReadsLikeJira() {
        let now = CommentThread.parse(date: "2026-09-03T12:00:00.000+0200")!
        XCTAssertEqual(CommentThread.relative("2026-09-02T12:00:00.000+0200", now: now), "gestern")
        XCTAssertEqual(CommentThread.absolute("2026-09-02T08:22:00.000+0200"), "02.09.2026, 08:22")
    }

    /// Ein `<` im Autornamen darf die Kopfzeile nicht zerlegen.
    func testAuthorIsEscaped() {
        let markdown = CommentThread.markdown([
            TaskComment(author: "A <b> & C", created: "2026-01-01T00:00:00+0100", body: "x")])
        XCTAssertTrue(markdown.contains("A &lt;b&gt; &amp; C"), markdown)
    }
}
