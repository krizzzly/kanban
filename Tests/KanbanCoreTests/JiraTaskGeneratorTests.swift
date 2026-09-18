import XCTest
@testable import KanbanCore

final class JiraTaskGeneratorTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    // MARK: - Pre-Flight (INV-6)

    /// Die Ziffer ist die Schranke: `EVEN-2` darf sich `EVEN-2591` nicht einverleiben. Ein naives
    /// `contains` tat genau das und meldete für ein frisches Ticket, die Datei existiere schon.
    func testPreflightMatchesTheTicketButNotALongerNumber() throws {
        let directory = try temporaryDirectory()
        for name in ["EVEN-2591_anderes_ticket.md", "EVEN-20.md", "NOTES.md"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        XCTAssertNil(JiraTaskGenerator.existingTaskFile(ticketKey: "EVEN-2", in: directory))

        try Data("x".utf8).write(to: directory.appendingPathComponent("EVEN-2_endlich.md"))
        XCTAssertEqual(JiraTaskGenerator.existingTaskFile(ticketKey: "EVEN-2", in: directory),
                       "EVEN-2_endlich.md")
    }

    func testPreflightMatchesTheBareName() throws {
        let directory = try temporaryDirectory()
        try Data("x".utf8).write(to: directory.appendingPathComponent("EVEN-7.md"))
        XCTAssertEqual(JiraTaskGenerator.existingTaskFile(ticketKey: "EVEN-7", in: directory), "EVEN-7.md")
    }

    /// Ein leeres Verzeichnis ist kein Fehler, sondern der Normalfall.
    func testPreflightOnMissingDirectory() {
        XCTAssertNil(JiraTaskGenerator.existingTaskFile(
            ticketKey: "EVEN-1", in: URL(fileURLWithPath: "/gibt/es/nicht")))
    }

    // MARK: - Sperre (R8/R13)

    /// Die Sperre liegt ausserhalb des Tasks-Verzeichnisses und des Ticket-Ordners — im Ordner
    /// erschiene sie im Anhang-Baum, im Tasks-Verzeichnis hielte `TaskFile.belongsToTicket` sie für
    /// eine Datei des Tickets.
    func testSecondExportOfTheSameTicketIsRefused() throws {
        let first = try XCTUnwrap(ExportLock(ticketKey: "EVEN-LOCKTEST"))
        XCTAssertNil(ExportLock(ticketKey: "EVEN-LOCKTEST"))
        first.release()
        let again = try XCTUnwrap(ExportLock(ticketKey: "EVEN-LOCKTEST"))
        again.release()
    }

    // MARK: - Bildzähler über Haupt-Ticket und Unteraufgaben (INV-5 / B-7)

    /// Der Zähler läuft **durch**. Ohne das zeigten zwei `{{IMG_n}}` aus verschiedenen
    /// Unteraufgaben auf dieselbe Datei — und eine davon wäre die falsche.
    func testImageIndexRunsThroughIssueAndSubtasks() throws {
        func document(_ alt: String) -> String {
            """
            {"type":"doc","content":[{"type":"mediaSingle","content":[
              {"type":"media","attrs":{"id":"m","alt":"\(alt)","collection":"c"}}]}]}
            """
        }
        func issueJSON(_ alts: [String]) -> String {
            let media = alts.map { "{\"type\":\"mediaSingle\",\"content\":[{\"type\":\"media\",\"attrs\":{\"id\":\"m\",\"alt\":\"\($0)\"}}]}" }
                .joined(separator: ",")
            let attachments = alts.map { "{\"id\":\"a\",\"filename\":\"\($0)\",\"content\":\"https://x.test/\($0)\"}" }
                .joined(separator: ",")
            return """
            {"fields":{"summary":"S","description":{"type":"doc","content":[\(media)]},
             "attachment":[\(attachments)]}}
            """
        }

        let issue = JiraClient.parseIssue(key: "EVEN-1", raw: try json(issueJSON(["a.png", "b.png"])))
        XCTAssertEqual(issue.images.map(\.index), [0, 1])

        var next = issue.images.count
        var indices = issue.images.map(\.index)
        for (key, alt) in [("EVEN-2", "c.png"), ("EVEN-3", "d.png")] {
            let raw = try json("""
            {"fields":{"summary":"\(key)","description":\(document(alt)),
             "attachment":[{"id":"a","filename":"\(alt)","content":"https://x.test/\(alt)"}]}}
            """)
            let content = JiraClient.parseSubtask(key: key, raw: raw, imageStartIndex: next)
            indices += content.images.map(\.index)
            next = content.nextImageIndex
        }
        XCTAssertEqual(indices, [0, 1, 2, 3])
        XCTAssertEqual(next, 4)
    }

    // MARK: - Kommentare (C5/C6)

    /// `id` kommt als String, `parentId` als **Zahl** — dieselbe API, zwei Typen. Und die
    /// Avatar-URL nimmt das grösste angebotene Format.
    func testCommentsCarryThreadingAndAvatar() throws {
        let raw = try json("""
        [{"id":"115483","author":{"displayName":"A","accountId":"1",
           "avatarUrls":{"24x24":"https://a.test/24.png","48x48":"https://a.test/48.png"}},
          "created":"2026-01-01T10:00:00.000+0100","body":{"type":"doc","content":[
            {"type":"paragraph","content":[{"type":"text","text":"Frage"}]}]}},
         {"id":"115484","parentId":115483,"author":{"displayName":"B","accountId":"2",
           "avatarUrls":{"32x32":"https://b.test/32.png"}},
          "created":"2026-01-01T11:00:00.000+0100","body":{"type":"doc","content":[
            {"type":"paragraph","content":[{"type":"text","text":"Antwort"}]}]}}]
        """).arrayValue ?? []

        let comments = JiraClient.parseComments(raw)
        XCTAssertEqual(comments.map(\.id), ["115483", "115484"])
        XCTAssertNil(comments[0].parentId)
        XCTAssertEqual(comments[1].parentId, "115483")
        XCTAssertEqual(comments[0].avatarUrl, "https://a.test/48.png")
        XCTAssertEqual(comments[1].avatarUrl, "https://b.test/32.png")
        XCTAssertEqual(comments[1].body, "Antwort")
    }

    /// **INV-3** — was der Export schreibt, muss die Kommentar-Ansicht lesen können. Geprüft wird
    /// nicht „sieht ähnlich aus", sondern der Weg, den die App tatsächlich geht: `CommentThread.parse`.
    func testWrittenCommentsJSONIsReadableByTheViewer() throws {
        let records = [
            TaskComment(id: "1", author: "A", created: "2026-01-01T10:00:00.000+0100", body: "Frage"),
            TaskComment(id: "2", parentId: "1", author: "B",
                        created: "2026-01-01T11:00:00.000+0100", body: "Antwort",
                        avatar: "EVEN-1/avatars/B.png"),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(records), as: UTF8.self)

        let parsed = try XCTUnwrap(CommentThread.parse(text))
        XCTAssertEqual(parsed, records)
        // Die Antwort hängt unter ihrem Bezug, nicht daneben.
        XCTAssertEqual(CommentThread.ordered(parsed).map(\.depth), [0, 1])
        // Ein Feld ohne Wert steht gar nicht da, statt als `null` — so sehen ältere Exporte aus.
        XCTAssertFalse(text.contains("null"))
        XCTAssertFalse(text.contains("\\/"))
    }

    // MARK: - Dateinamen der Profilbilder (R4 / INV-7)

    /// Der Anzeigename kommt aus einem fremden Feld und wird hier zu einem Pfad. Ohne Reduktion
    /// verliesse `../../` das Verzeichnis; Jiras accountId bringt ausserdem `:` mit.
    func testAvatarFilenamesCannotLeaveTheDirectory() {
        XCTAssertEqual(TaskAssetDownloader.safeName("../../etc/passwd"), "-etc-passwd")
        XCTAssertEqual(TaskAssetDownloader.safeName("5b10a2:844c-2b8f"), "5b10a2-844c-2b8f")
        XCTAssertEqual(TaskAssetDownloader.safeName("Müller Meier"), "M-ller-Meier")
        XCTAssertEqual(TaskAssetDownloader.safeName(""), "autor")
        XCTAssertEqual(TaskAssetDownloader.safeName("///"), "autor")
        XCTAssertEqual(TaskAssetDownloader.safeName(String(repeating: "a", count: 80)).count, 40)

        for name in ["../../etc/passwd", "a/b", "..", ":", "Müller Meier"] {
            let safe = TaskAssetDownloader.safeName(name)
            XCTAssertFalse(safe.contains("/"), "\(name) → \(safe)")
            XCTAssertFalse(safe.contains(".."), "\(name) → \(safe)")
        }
    }

    /// Zwei Autoren mit demselben Anzeigenamen: der zweite bekommt ein Kürzel seiner Bild-URL,
    /// sonst bekäme einer das Gesicht des anderen.
    func testSameDisplayNameYieldsDifferentFilenames() {
        let first = TaskAssetDownloader.shortHash("https://a.test/1.png")
        let second = TaskAssetDownloader.shortHash("https://a.test/2.png")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 8)
    }

    func testAvatarHostAllowlist() {
        XCTAssertTrue(AvatarHosts.isAllowed("https://secure.gravatar.com/avatar/x"))
        XCTAssertTrue(AvatarHosts.isAllowed("https://avatar-management--avatars.eu-west-1.prod.public.atl-paas.net/x"))
        XCTAssertFalse(AvatarHosts.isAllowed("http://secure.gravatar.com/avatar/x"), "kein https")
        XCTAssertFalse(AvatarHosts.isAllowed("https://boeser-gravatar.com/x"), "Suffix ist kein Host")
        XCTAssertFalse(AvatarHosts.isAllowed("https://intern.firma.test/x"))
    }

    /// Atlassians Initialen-PNG ist kein Profilbild — verworfen wird es sowohl direkt als auch als
    /// Ziel der Gravatar-Umleitung.
    func testInitialsFallbackIsRecognisedAtBothEnds() {
        XCTAssertTrue(AvatarHosts.isInitialsFallback("https://x.atl-paas.net/initials/PA-0.png"))
        XCTAssertTrue(AvatarHosts.isInitialsFallback("https://i1.wp.com/.../initials/PA-0.png"))
        XCTAssertFalse(AvatarHosts.isInitialsFallback("https://x.atl-paas.net/avatar/echt.png"))
        XCTAssertFalse(AvatarHosts.isInitialsFallback(nil))
    }

    /// Der Dateiname bleibt auf der Platte im Original, im Markdown steht er kodiert — sonst
    /// zerbricht ein Leerzeichen den Link.
    func testRelativePathIsPercentEncoded() {
        XCTAssertEqual(TaskAssetDownloader.pathEncoded("1-mein bild.png"), "1-mein%20bild.png")
        XCTAssertEqual(TaskAssetDownloader.pathEncoded("2-Größe.xlsx"), "2-Gr%C3%B6%C3%9Fe.xlsx")
        XCTAssertEqual(TaskAssetDownloader.pathEncoded("3-plain.png"), "3-plain.png")
    }
}
