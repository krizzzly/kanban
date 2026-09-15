import XCTest
@testable import KanbanCore

/// Die Suche im Task-File. Der rote Faden aller Tests: gesucht wird im **sichtbaren** Text, und die
/// Zählung je Sektion muss der entsprechen, die die WebView im DOM vornimmt.
final class TaskSearchTests: XCTestCase {

    private func sektion(_ id: Int, _ titel: String, _ markdown: String) -> TaskSection {
        TaskSection(id: id, title: titel, markdown: markdown)
    }

    // MARK: - Sichtbarer Text statt Markdown

    func testMarkdownSyntaxIstKeinTreffer() {
        let s = [sektion(0, "Lösung", "Die **Lösung** steht fest.")]
        XCTAssertEqual(TaskSearch.hits(query: "Lösung", in: s).count, 1)
        XCTAssertTrue(TaskSearch.hits(query: "**", in: s).isEmpty)
    }

    /// Die Adresse eines Links steht nicht auf dem Schirm — wer „example" sucht, meint den Text.
    func testLinkzielWirdNichtDurchsucht() {
        let s = [sektion(0, "X", "Siehe [die Doku](https://example.com/geheim).")]
        XCTAssertTrue(TaskSearch.hits(query: "example", in: s).isEmpty)
        XCTAssertEqual(TaskSearch.hits(query: "die Doku", in: s).count, 1)
    }

    func testBildpfadeWerdenNichtDurchsucht() {
        let s = [sektion(0, "X", "![Diagramm](bilder/aufbau.png)")]
        XCTAssertTrue(TaskSearch.hits(query: "aufbau", in: s).isEmpty)
    }

    /// Ohne Trenner am Tag klebten „Ende" und „Anfang" zu einem Wort zusammen — und „EndeAnfang"
    /// fände man dann als Treffer, den niemand sieht.
    func testBlockgrenzeTrenntWoerter() {
        let text = TaskSearch.visibleText("Ende\n\nAnfang")
        XCTAssertFalse(text.contains("EndeAnfang"))
        XCTAssertTrue(text.contains("Ende"))
        XCTAssertTrue(text.contains("Anfang"))
    }

    func testSkriptInhaltIstKeinText() {
        let ohne = TaskSearch.ohneTags("<p>sichtbar</p><script>var geheim = 1;</script><p>auch</p>")
        XCTAssertFalse(ohne.contains("geheim"))
        XCTAssertTrue(ohne.contains("sichtbar"))
        XCTAssertTrue(ohne.contains("auch"))
    }

    /// `&amp;` steht im DOM als „&" — danach sucht man auch.
    func testEntitiesWerdenZurueckuebersetzt() {
        XCTAssertTrue(TaskSearch.visibleText("Soll & Haben").contains("Soll & Haben"))
        XCTAssertEqual(TaskSearch.hits(query: "Soll & Haben",
                                       in: [sektion(0, "X", "Soll & Haben")]).count, 1)
    }

    /// `<C>` ist für cmark rohes HTML und für WebKit ein unbekanntes Element ohne Textinhalt — auf
    /// dem Schirm steht davon nichts, also ist es auch kein Treffer. Gleiches Ergebnis wie im DOM,
    /// und das ist die Bedingung dafür, dass beide Seiten gleich zählen.
    func testUnbekanntesTagIstKeinSichtbarerText() {
        XCTAssertFalse(TaskSearch.visibleText("A <C> B").contains("<C>"))
    }

    // MARK: - Treffer und Zählung

    func testGrossKleinschreibungEgal() {
        let s = [sektion(0, "X", "Datenbank und datenbank und DATENBANK")]
        XCTAssertEqual(TaskSearch.hits(query: "datenbank", in: s).count, 3)
    }

    /// Die Nummer läuft **je Sektion** von vorn — sie sagt der Ansicht, den wievielten Treffer im
    /// gerade gezeigten Dokument sie anspringen soll.
    func testNummerLaeuftJeSektionVonVorn() {
        let treffer = TaskSearch.hits(query: "test", in: [
            sektion(0, "A", "test test"),
            sektion(1, "B", "test"),
        ])
        XCTAssertEqual(treffer.map(\.indexInSection), [0, 1, 0])
        XCTAssertEqual(treffer.map(\.sectionID), [0, 0, 1])
    }

    func testTrefferMerkenSichIhrenTab() {
        let treffer = TaskSearch.hits(query: "Fehler", in: [
            sektion(-1, "Status", "kein Fehler"),
            sektion(-2, "Review", "ein Fehler im Review"),
        ])
        XCTAssertEqual(treffer.map(\.sectionTitle), ["Status", "Review"])
    }

    /// Ausdrücklich verlangt: der Review-Tab wird mitdurchsucht. Er ist eine Sektion wie jede
    /// andere (`displaySections` reiht ihn ein), und genau deshalb funktioniert es.
    func testReviewWirdMitdurchsucht() {
        let treffer = TaskSearch.hits(query: "Nachbesserung", in: [
            sektion(-1, "Status", "🔵 In Review"),
            sektion(-2, "Review #1", "Hier fehlt eine Nachbesserung."),
            sektion(-3, "Review #2", "Nachbesserung erledigt, Nachbesserung geprüft."),
            sektion(0, "Beschreibung", "nichts davon"),
        ])
        XCTAssertEqual(treffer.count, 3)
        XCTAssertEqual(treffer.map(\.sectionTitle), ["Review #1", "Review #2", "Review #2"])
        XCTAssertEqual(treffer.map(\.indexInSection), [0, 0, 1])
    }

    func testUeberlappendeTrefferZaehlenWieImDOM() {
        // „aaa" in „aaaaa": hinter jedem Treffer wird neu angesetzt, also genau einer.
        XCTAssertEqual(TaskSearch.hits(query: "aaa", in: [sektion(0, "X", "aaaaa")]).count, 1)
    }

    func testZuKurzeEingabeSuchtNicht() {
        let s = [sektion(0, "X", "eine Menge Text mit vielen e")]
        XCTAssertTrue(TaskSearch.hits(query: "e", in: s).isEmpty)
        XCTAssertTrue(TaskSearch.hits(query: " ", in: s).isEmpty)
        XCTAssertFalse(TaskSearch.hits(query: "Te", in: s).isEmpty)
    }

    // MARK: - Ausschnitt

    func testAusschnittEnthaeltDenTrefferUndBleibtEinzeilig() {
        let lang = String(repeating: "Vorlauf ", count: 20) + "GESUCHT"
            + String(repeating: " Nachlauf", count: 20)
        let treffer = TaskSearch.hits(query: "GESUCHT", in: [sektion(0, "X", lang)])
        let ausschnitt = try! XCTUnwrap(treffer.first).snippet
        XCTAssertTrue(ausschnitt.contains("GESUCHT"))
        XCTAssertFalse(ausschnitt.contains("\n"))
        XCTAssertTrue(ausschnitt.hasPrefix("…"), ausschnitt)
        XCTAssertTrue(ausschnitt.hasSuffix("…"), ausschnitt)
    }

    // MARK: - Index

    func testIndexLiefertDasGleicheWieDieEinmalsuche() {
        let sektionen = [sektion(0, "A", "Alpha beta"), sektion(-2, "Review", "beta gamma")]
        XCTAssertEqual(TaskSearchIndex(sections: sektionen).hits(query: "beta"),
                       TaskSearch.hits(query: "beta", in: sektionen))
    }

    func testLeererIndexFindetNichts() {
        XCTAssertTrue(TaskSearchIndex(sections: []).hits(query: "egal").isEmpty)
    }
}
