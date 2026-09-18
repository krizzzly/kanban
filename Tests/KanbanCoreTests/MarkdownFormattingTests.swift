import XCTest
@testable import KanbanCore

final class MarkdownFormattingTests: XCTestCase {

    private func auswahl(_ ort: Int, _ laenge: Int) -> NSRange {
        NSRange(location: ort, length: laenge)
    }

    // MARK: - Umschliessende Auszeichnung

    func testFettUmschliesstDieAuswahl() {
        let r = MarkdownFormatting.inline("Das ist wichtig", selection: auswahl(8, 7), marker: "**")
        XCTAssertEqual(r.text, "Das ist **wichtig**")
        // Der markierte Text bleibt markiert, nur um zwei Zeichen verschoben.
        XCTAssertEqual(r.selection, auswahl(10, 7))
    }

    /// Ohne Auswahl entsteht ein leeres Paar, und der Cursor steht **dazwischen** — sonst müsste man
    /// nach jedem Klick erst zurücknavigieren.
    func testFettOhneAuswahlSetztDenCursorDazwischen() {
        let r = MarkdownFormatting.inline("ab", selection: auswahl(2, 0), marker: "**")
        XCTAssertEqual(r.text, "ab****")
        XCTAssertEqual(r.selection, auswahl(4, 0))
    }

    /// Derselbe Knopf nimmt zurück, was er gesetzt hat — sonst entstünde `****so****`.
    func testZweiterKlickNimmtDieAuszeichnungWeg() {
        let r = MarkdownFormatting.inline("Das ist **wichtig**", selection: auswahl(10, 7), marker: "**")
        XCTAssertEqual(r.text, "Das ist wichtig")
        XCTAssertEqual(r.selection, auswahl(8, 7))
    }

    func testKursivUndCodeNutzenDieselbeRegel() {
        XCTAssertEqual(MarkdownFormatting.inline("hallo", selection: auswahl(0, 5), marker: "*").text,
                       "*hallo*")
        XCTAssertEqual(MarkdownFormatting.inline("hallo", selection: auswahl(0, 5), marker: "`").text,
                       "`hallo`")
    }

    /// Kursiv darf fett nicht als „schon ausgezeichnet" missdeuten: `*` steht zwar in `**`, aber
    /// direkt vor der Auswahl steht dort nur eines der beiden Sternchen.
    func testKursivInnerhalbVonFettZeichnetAus() {
        let r = MarkdownFormatting.inline("**wichtig**", selection: auswahl(2, 7), marker: "*")
        XCTAssertEqual(r.text, "***wichtig***")
    }

    // MARK: - Zeilenweise Auszeichnung

    func testListeErfasstAlleBeruehrtenZeilen() {
        let text = "eins\nzwei\ndrei"
        // Auswahl reicht von der Mitte der ersten bis in die zweite Zeile.
        let r = MarkdownFormatting.linePrefix(text, selection: auswahl(2, 5), prefix: "- ")
        XCTAssertEqual(r.text, "- eins\n- zwei\ndrei")
    }

    func testUeberschriftAufEinerZeile() {
        let r = MarkdownFormatting.linePrefix("Titel", selection: auswahl(0, 0), prefix: "## ")
        XCTAssertEqual(r.text, "## Titel")
    }

    func testZweiterKlickNimmtDasZeilenpraefixWeg() {
        let r = MarkdownFormatting.linePrefix("- eins\n- zwei", selection: auswahl(0, 13), prefix: "- ")
        XCTAssertEqual(r.text, "eins\nzwei")
    }

    /// Leerzeilen bekommen kein Präfix — eine Liste mit einem nackten „- " dazwischen wäre ein
    /// leerer Punkt.
    func testLeerzeilenBleibenLeer() {
        let r = MarkdownFormatting.linePrefix("eins\n\nzwei", selection: auswahl(0, 10), prefix: "- ")
        XCTAssertEqual(r.text, "- eins\n\n- zwei")
    }

    /// Halb ausgezeichnet heisst: der Knopf zeichnet den Rest **aus**, statt alles wegzunehmen.
    func testTeilweiseAusgezeichneterBlockWirdVervollstaendigt() {
        let r = MarkdownFormatting.linePrefix("- eins\nzwei", selection: auswahl(0, 11), prefix: "- ")
        XCTAssertEqual(r.text, "- - eins\n- zwei")
    }

    // MARK: - Link

    func testLinkMitAuswahlNimmtSieAlsBeschriftung() {
        let r = MarkdownFormatting.link("siehe Doku hier", selection: auswahl(6, 4))
        XCTAssertEqual(r.text, "siehe [Doku](url) hier")
        // Markiert ist „url" — das ist die Stelle, die man als Nächstes füllt.
        let markiert = (r.text as NSString).substring(with: r.selection)
        XCTAssertEqual(markiert, "url")
    }

    func testLinkOhneAuswahlSetztEinGeruest() {
        let r = MarkdownFormatting.link("", selection: auswahl(0, 0))
        XCTAssertEqual(r.text, "[Text](url)")
        XCTAssertEqual((r.text as NSString).substring(with: r.selection), "url")
    }

    // MARK: - Robustheit

    /// Auswahl und Text können sich überholen (Tippen, dann Klick auf die Leiste). Eine Auswahl
    /// hinter dem Textende darf nicht abstürzen, sondern muss gekappt werden.
    func testAuswahlHinterDemTextendeStuerztNicht() {
        let r = MarkdownFormatting.inline("kurz", selection: auswahl(99, 20), marker: "**")
        XCTAssertEqual(r.text, "kurz****")
        let z = MarkdownFormatting.linePrefix("kurz", selection: auswahl(99, 20), prefix: "- ")
        XCTAssertEqual(z.text, "- kurz")
    }

    func testLeererTextBleibtBedienbar() {
        XCTAssertEqual(MarkdownFormatting.inline("", selection: auswahl(0, 0), marker: "**").text, "****")
        XCTAssertEqual(MarkdownFormatting.linePrefix("", selection: auswahl(0, 0), prefix: "- ").text, "")
    }
}
