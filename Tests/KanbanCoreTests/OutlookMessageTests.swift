import XCTest
@testable import KanbanCore

final class OutlookMessageTests: XCTestCase {
    // MARK: - Text-Properties

    /// Der Fehler, der die halbe Vorschau gekostet hat: die Streams sind **uneinheitlich** — `0E04`
    /// (An) zählt die abschliessende Null mit, `0037` (Betreff) nicht. Bleibt sie stehen, endet das
    /// gerenderte Markdown an dieser Stelle (cmark las bis zur ersten Null): gemessen 208 statt
    /// 762 Zeichen, der ganze Mail-Körper fehlte.
    func testTrailingNulTerminatorIsStripped() {
        let withTerminator: [UInt8] = [0x48, 0x00, 0x69, 0x00, 0x00, 0x00]   // "Hi\0"
        XCTAssertEqual(OutlookMessageReader.utf16String(withTerminator), "Hi")
        let without: [UInt8] = [0x48, 0x00, 0x69, 0x00]
        XCTAssertEqual(OutlookMessageReader.utf16String(without), "Hi")
    }

    func testUtf16PropertiesKeepUmlauts() {
        let bytes = Array("Rückerstattung".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        XCTAssertEqual(OutlookMessageReader.utf16String(bytes), "Rückerstattung")
    }

    /// Eine ungerade Bytezahl ist ein halbes Zeichen — sie darf nicht in einen Absturz laufen.
    func testOddByteCountIsSurvived() {
        XCTAssertNoThrow(OutlookMessageReader.utf16String([0x48, 0x00, 0x69]))
    }

    // MARK: - Absender

    /// Intern verschickte Mails tragen in `0C1F` keinen Postfachnamen, sondern den Exchange-Pfad.
    /// Der sähe im Kopf aus wie eine Adresse und wäre keine.
    func testExchangeDistinguishedNameIsNotAnAddress() {
        XCTAssertNil(OutlookMessageReader.mailAddress(
            "/o=intraOrg/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=_BFE-ZV319"))
        XCTAssertNil(OutlookMessageReader.mailAddress(""))
        XCTAssertNil(OutlookMessageReader.mailAddress(nil))
        XCTAssertEqual(OutlookMessageReader.mailAddress("joelle.mosig@bafu.admin.ch"),
                       "joelle.mosig@bafu.admin.ch")
    }

    // MARK: - HTML-Körper

    /// Outlooks HTML bringt seitenlanges Word-CSS mit. Der Markdown-Renderer *entschärft* `<style>`
    /// nur (er escapt es), also stünde das CSS als sichtbarer Text über der Mail — es muss weg,
    /// nicht neutralisiert werden.
    func testStyleAndScriptBlocksAreRemovedNotEscaped() {
        let html = """
        <html><head><meta charset="utf-8"><title>x</title>
        <style>p.MsoNormal {mso-para-margin:0cm;}</style></head>
        <body><p>Hallo</p><script>alert(1)</script></body></html>
        """
        let body = OutlookMessageReader.bodyFragment(of: html)
        XCTAssertEqual(body, "<p>Hallo</p>")
        XCTAssertFalse(body.contains("mso-para-margin"))
        XCTAssertFalse(body.contains("charset"))
    }

    func testFragmentWithoutBodyTagIsKept() {
        XCTAssertEqual(OutlookMessageReader.bodyFragment(of: "<p>nur ein Absatz</p>"),
                       "<p>nur ein Absatz</p>")
    }

    /// Ein `<head>` ohne Abschluss kommt in echten Mails vor — es darf nicht den Rest verschlucken.
    func testUnclosedHeadDoesNotEatTheBody() {
        let body = OutlookMessageReader.bodyFragment(of: "<html><body><p>da</p></body></html>")
        XCTAssertEqual(body, "<p>da</p>")
    }

    // MARK: - Eingebettete Bilder

    private func part(_ name: String, cid: String?, bytes: [UInt8] = [1, 2, 3]) -> OutlookMessageReader.Part {
        OutlookMessageReader.Part(name: name, bytes: bytes, contentID: cid, mime: nil)
    }

    func testCidReferencesBecomeDataURIs() {
        let html = #"<img src="cid:image001.png@01DC.67AC" width="10">"#
        let result = OutlookMessageReader.inlineImages(
            in: html, parts: [part("image001.png", cid: "image001.png@01DC.67AC")])
        XCTAssertFalse(result.html.contains("cid:"))
        XCTAssertTrue(result.html.contains("data:image/png;base64,AQID"))
        XCTAssertEqual(result.usedContentIDs, ["image001.png@01DC.67AC"])
    }

    /// „Inline" heisst **im Körper zu sehen**, nicht bloss „hat eine Content-Id". Vier der sechs
    /// echten Dateien tragen Bilder mit Id, haben aber gar keinen HTML-Körper — nach der Id allein
    /// zu gehen meldete „keine Anhänge" über sechs Bildern.
    func testAnUnreferencedImageIsNotCountedAsInline() {
        let result = OutlookMessageReader.inlineImages(
            in: "<p>reiner Text, kein Bild</p>", parts: [part("logo.png", cid: "logo@x")])
        XCTAssertTrue(result.usedContentIDs.isEmpty)
        XCTAssertEqual(result.html, "<p>reiner Text, kein Bild</p>")
    }

    func testOversizedImagesStayAsPlaceholders() {
        let huge = [UInt8](repeating: 0, count: OutlookMessageReader.maxInlineImageBytes + 1)
        let result = OutlookMessageReader.inlineImages(
            in: #"<img src="cid:big@x">"#, parts: [part("big.png", cid: "big@x", bytes: huge)])
        XCTAssertTrue(result.html.contains("cid:big@x"))
        XCTAssertTrue(result.usedContentIDs.isEmpty)
    }

    // MARK: - Kodierung

    /// Der HTML-Körper liegt in der Codepage der Nachricht, nicht in UTF-8.
    func testHtmlIsDecodedWithTheDeclaredCodepage() {
        let latin1: [UInt8] = [0x52, 0xFC, 0x63, 0x6B]   // "Rück" in ISO-8859-1
        XCTAssertEqual(OutlookMessageReader.decodeHTML(latin1, codepage: 28591), "Rück")
        XCTAssertEqual(OutlookMessageReader.decodeHTML(latin1, codepage: 1252), "Rück")
        // Ohne Angabe darf es trotzdem nicht scheitern — Latin-1 ist der Rückfall.
        XCTAssertEqual(OutlookMessageReader.decodeHTML(latin1, codepage: nil), "Rück")
    }

    func testUtf8CodepageIsHonoured() {
        XCTAssertEqual(OutlookMessageReader.decodeHTML(Array("Grüsse".utf8), codepage: 65001), "Grüsse")
    }

    // MARK: - Feste Eigenschaften

    /// Kopf 32 Bytes, dann 16-Byte-Einträge: Typ, Id, Flags, Wert. An vier echten Dateien
    /// gegengerechnet — der Rest geht dort jedes Mal genau auf.
    func testFixedPropertyLookup() {
        var bytes = [UInt8](repeating: 0, count: 32 + 16)
        bytes[32] = 0x40; bytes[33] = 0x00          // Typ 0x0040 (Zeitstempel)
        bytes[34] = 0x39; bytes[35] = 0x00          // Id 0x0039
        bytes[40] = 0xFF                            // Wert
        XCTAssertEqual(OutlookMessageReader.fixedProperty(bytes, id: 0x0039, type: 0x0040), 0xFF)
        XCTAssertNil(OutlookMessageReader.fixedProperty(bytes, id: 0x0E06, type: 0x0040))
        XCTAssertNil(OutlookMessageReader.fixedProperty(bytes, id: 0x0039, type: 0x0003))
        XCTAssertNil(OutlookMessageReader.fixedProperty([], id: 0x0039, type: 0x0040))
    }

    func testFileTimeConversion() {
        // 2026-03-26 19:44:00 UTC als FILETIME.
        let date = OutlookMessageReader.fileTime(134_190_278_400_000_000)
        XCTAssertEqual(date?.timeIntervalSince1970 ?? 0, 1_774_554_240, accuracy: 1)
        XCTAssertNil(OutlookMessageReader.fileTime(0))
        XCTAssertNil(OutlookMessageReader.fileTime(1))                  // vor 1970
        XCTAssertNil(OutlookMessageReader.fileTime(UInt64.max))         // jenseits des Jahres 3000
    }

    // MARK: - Darstellung

    private func message(html: String?, text: String?,
                         attachments: [OutlookMessage.Attachment] = []) -> OutlookMessage {
        OutlookMessage(subject: "Betreff", fromName: "Mosig Joëlle",
                       fromAddress: "joelle@example.ch", to: "Alder Patric", cc: nil,
                       date: Date(timeIntervalSince1970: 1_774_554_240),
                       html: html, text: text, attachments: attachments)
    }

    /// Ein Text-Körper kommt mit harten Zeilenumbrüchen. Als Markdown-Absatz gelesen liefe er zu
    /// einer einzigen Zeile zusammen — jede Aufzählung und jedes Zitat wäre dahin.
    func testPlainTextBodyKeepsItsLineBreaks() {
        let markdown = message(html: nil, text: "Zeile eins\nZeile zwei").markdown
        XCTAssertTrue(markdown.contains("white-space: pre-wrap"))
        XCTAssertTrue(MarkdownHTML.render(markdown).contains("Zeile eins\nZeile zwei"))
    }

    func testHtmlBodyIsPreferredOverText() {
        let markdown = message(html: "<p>reich</p>", text: "arm").markdown
        XCTAssertTrue(markdown.contains("<p>reich</p>"))
        XCTAssertFalse(markdown.contains("arm"))
    }

    /// Spitze Klammern im Kopf sind Text, keine Auszeichnung — ungeschützt schluckte der Renderer
    /// die Adresse als unbekanntes Tag.
    func testHeaderValuesAreEscaped() {
        let rendered = MarkdownHTML.render(message(html: nil, text: "x").markdown)
        XCTAssertTrue(rendered.contains("&lt;"))
        XCTAssertTrue(rendered.contains("joelle@example.ch"))
    }

    /// Eingebettete Signaturbilder stehen nicht in der Anhangliste — echte Anhänge schon.
    func testOnlyRealAttachmentsAreListed() {
        let msg = message(html: "<p>x</p>", text: nil, attachments: [
            .init(name: "image001.png", byteCount: 100, isInline: true),
            .init(name: "Bericht.pdf", byteCount: 2048, isInline: false),
        ])
        XCTAssertEqual(msg.realAttachments.map(\.name), ["Bericht.pdf"])
        XCTAssertTrue(msg.markdown.contains("Bericht.pdf"))
        XCTAssertFalse(msg.markdown.contains("image001.png"))
    }

    func testAMessageWithoutAnyBodySaysSo() {
        XCTAssertTrue(message(html: nil, text: nil).markdown.contains("kein Inhalt"))
    }

    func testMessageFileDetection() {
        XCTAssertTrue(OutlookMessageReader.isMessageFile("/x/Mail.MSG"))
        XCTAssertTrue(OutlookMessageReader.isMessageFile("a.msg"))
        XCTAssertFalse(OutlookMessageReader.isMessageFile("a.md"))
        XCTAssertFalse(OutlookMessageReader.isMessageFile("msg"))
    }

    func testUnreadableFileIsNilNotACrash() {
        XCTAssertNil(OutlookMessageReader.read(data: Data("kein compound file".utf8)))
        XCTAssertNil(OutlookMessageReader.read(URL(fileURLWithPath: "/nope/nirgends.msg")))
    }
}
