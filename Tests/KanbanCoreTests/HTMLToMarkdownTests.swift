import XCTest
@testable import KanbanCore

final class HTMLToMarkdownTests: XCTestCase {
    private func md(_ html: String) -> String { HTMLToMarkdown.convert(html) }

    // MARK: - Blöcke

    func testUeberschriftenUndAbsaetze() {
        XCTAssertEqual(md("<h2>Titel</h2><p>Text</p>"), "## Titel\n\nText")
    }

    /// Ein `contenteditable` legt Absätze als nackte `div`s ab — die dürfen nicht verschwinden.
    func testDivsSindAbsaetze() {
        XCTAssertEqual(md("<div>eins</div><div>zwei</div>"), "eins\n\nzwei")
    }

    /// Leerabsätze (`<p><br></p>`, `&nbsp;`) erzeugt der Editor beim Drücken von Enter — sie dürfen
    /// keine leeren Absätze in Jira werden.
    func testLeereAbsaetzeFallenWeg() {
        XCTAssertEqual(md("<p>eins</p><p><br></p><p>&nbsp;</p><p>zwei</p>"), "eins\n\nzwei")
    }

    func testZeilenumbruchBleibtWeicherUmbruch() {
        XCTAssertEqual(md("<p>eins<br>zwei</p>"), "eins\nzwei")
    }

    func testListeVerschachtelt() {
        let html = "<ul><li>eins</li><li>zwei<ul><li>tiefer</li></ul></li></ul>"
        XCTAssertEqual(md(html), "- eins\n- zwei\n  - tiefer")
    }

    /// **Echte WebKit-Ausgabe** aus dem kopflosen Probelauf: nach `execCommand('indent')` auf dem
    /// zweiten Punkt hängt die tiefere Liste als *Geschwister* des `<li>`, nicht in ihm.
    func testVerschachteltAlsGeschwisterListe() {
        XCTAssertEqual(md("<ul><li>eins</li><ul><li>zwei</li></ul></ul>"), "- eins\n  - zwei")
    }

    /// Der ganze Editor-Durchlauf des Probelaufs (fett, Einrücken, Inline-Code, Link, H3) in einem.
    func testEchteEditorAusgabe() {
        let html = "<h3><a href=\"https://x.test\">Titel</a></h3><p><b>Ein Absatz.</b></p>"
                 + "<ul><li><code>eins</code></li><ul><li>zwei</li></ul></ul>"
        XCTAssertEqual(md(html), """
        ### [Titel](https://x.test)

        **Ein Absatz.**

        - `eins`
          - zwei
        """)
    }

    func testGeordneteListeZaehltHoch() {
        XCTAssertEqual(md("<ol><li>a</li><li>b</li><li>c</li></ol>"), "1. a\n2. b\n3. c")
    }

    /// `<li><p>…</p></li>` — so schreibt cmark eine „lockere" Liste. Der Absatz ist der Punkt selbst.
    func testListenpunktMitAbsatz() {
        XCTAssertEqual(md("<ul><li><p>eins</p></li><li><p>zwei</p></li></ul>"), "- eins\n- zwei")
    }

    func testZitat() {
        XCTAssertEqual(md("<blockquote><p>Zitat</p></blockquote>"), "> Zitat")
    }

    /// Die Trennzeile zwischen zwei Blöcken im Zitat braucht ihr „>", sonst endet das Zitat dort —
    /// `MarkdownToADF` sammelt nur zusammenhängende `>`-Zeilen.
    func testZitatMitZweiAbsaetzen() {
        XCTAssertEqual(md("<blockquote><p>eins</p><p>zwei</p></blockquote>"), "> eins\n>\n> zwei")
    }

    /// WebKits `execCommand('indent')` erzeugt ausserhalb von Listen ein randloses `<blockquote>`
    /// als reine Einrückung — daraus darf in Jira kein Zitat werden.
    func testRandlosesBlockquoteIstKeinZitat() {
        let html = "<blockquote style=\"margin: 0 0 0 40px; border: none; padding: 0px;\">"
                 + "<p>nur eingerückt</p></blockquote>"
        XCTAssertEqual(md(html), "nur eingerückt")
    }

    /// Eingefügter Browser-Inhalt bringt `<style>`-Blöcke mit; ein `<script>` wäre noch schlimmer.
    func testSkriptUndStilBlockeWerdenUebersprungen() {
        XCTAssertEqual(md("<style>p { color: red }</style><p>Text</p><script>alert(1)</script>"), "Text")
    }

    func testCodeblockMitSprache() {
        let html = "<pre><code class=\"language-swift\">let x = 1\nlet y = 2\n</code></pre>"
        XCTAssertEqual(md(html), "```swift\nlet x = 1\nlet y = 2\n```")
    }

    /// Im Codeblock wird **nicht** normalisiert: Einrückung ist dort Inhalt.
    func testCodeblockBehaeltEinrueckung() {
        XCTAssertEqual(md("<pre><code>if (x) {\n    y();\n}</code></pre>"),
                       "```\nif (x) {\n    y();\n}\n```")
    }

    func testLinie() {
        XCTAssertEqual(md("<p>a</p><hr><p>b</p>"), "a\n\n---\n\nb")
    }

    // MARK: - Marks

    func testMarks() {
        XCTAssertEqual(md("<p><b>fett</b> <i>kursiv</i> <code>code</code> <del>weg</del></p>"),
                       "**fett** *kursiv* `code` ~~weg~~")
    }

    func testLink() {
        XCTAssertEqual(md("<p><a href=\"https://x.test\">Text</a></p>"), "[Text](https://x.test)")
    }

    /// Ein Link ohne Beschriftung (kommt beim Einfügen einer nackten URL) trägt die URL selbst.
    func testLinkOhneBeschriftung() {
        XCTAssertEqual(md("<p><a href=\"https://x.test\"></a></p>"), "[https://x.test](https://x.test)")
    }

    /// `** fett **` wäre in Markdown keine Hervorhebung — die Leerzeichen müssen nach draussen.
    func testLeerzeichenWandernAusDerMarkHeraus() {
        XCTAssertEqual(md("<p>a<b> fett </b>b</p>"), "a **fett** b")
    }

    func testLeereMarkErzeugtKeineMarker() {
        XCTAssertEqual(md("<p>a<b></b><i> </i>b</p>"), "a b")
    }

    /// `<b><strong>x</strong></b>` erzeugt Safari beim Einfügen — `****x****` versteht
    /// `MarkdownToADF` nicht mehr (`\*\*([^*]+)\*\*`).
    func testDoppelteMarkWirdNichtVerdoppelt() {
        XCTAssertEqual(md("<p><b><strong>x</strong></b></p>"), "**x**")
    }

    /// Gepasteter Text bringt Formatierung als `style` statt als Tag mit.
    func testStyleAttributeWerdenGelesen() {
        XCTAssertEqual(md("<p><span style=\"font-weight: bold\">fett</span></p>"), "**fett**")
        XCTAssertEqual(md("<p><span style=\"font-weight:700\">fett</span></p>"), "**fett**")
        XCTAssertEqual(md("<p><span style=\"font-style: italic\">kursiv</span></p>"), "*kursiv*")
        XCTAssertEqual(md("<p><span style=\"text-decoration: line-through\">weg</span></p>"), "~~weg~~")
    }

    /// Unbekanntes wird entpackt, nicht weggeworfen — Text ist wichtiger als Struktur.
    func testUnbekanntesWirdEntpackt() {
        XCTAssertEqual(md("<p><u>unter</u> <sup>hoch</sup> <mark>markiert</mark></p>"),
                       "unter hoch markiert")
        XCTAssertEqual(md("<table><tr><td>Zelle</td></tr></table>"), "Zelle")
    }

    func testBildBehaeltAltText() {
        XCTAssertEqual(md("<p><img src=\"x.png\" alt=\"Diagramm\"></p>"), "Diagramm")
    }

    /// Zeilenumbrüche in cmarks Ausgabe sind HTML-Whitespace, kein Absatzende.
    func testUmbruecheImQuelltextWerdenZuLeerzeichen() {
        XCTAssertEqual(md("<p>ein\n  zwei\n\tdrei</p>"), "ein zwei drei")
    }

    func testKaputtesHTMLVerliertKeinenText() {
        XCTAssertEqual(md("<p>offen <b>fett</p>"), "offen **fett**")
    }

    /// Regression: ohne ausdrückliche UTF-8-Angabe wirft Foundations HTML-Tidy alles Nicht-ASCII
    /// still weg — „Gebäude — Rücksprache" wurde zu „Gebude  Rcksprache", mitten im Text, der nach
    /// Jira geht.
    func testNichtASCIIUeberlebt() {
        XCTAssertEqual(md("<p>Gebäude — „Rücksprache“ 😀 · Größe</p>"),
                       "Gebäude — „Rücksprache“ 😀 · Größe")
    }

    /// Ein vollständiges Dokument (mit eigener Kodierungs-Angabe) wird nicht noch einmal eingepackt.
    func testVollstaendigesDokument() {
        let html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head>"
                 + "<body><h3>Größe</h3><p>Text</p></body></html>"
        XCTAssertEqual(md(html), "### Größe\n\nText")
    }

    func testLeeresHTML() {
        XCTAssertEqual(md(""), "")
        XCTAssertEqual(md("<p></p>"), "")
    }
}

// MARK: - Rundreise

/// Der eigentliche Schutz des Editors: was durch cmark nach HTML und zurück läuft, muss **gleich**
/// bleiben. Nur dann kann ein Umschalten zwischen der formatierten und der Markdown-Ansicht nichts
/// zerstören.
final class HTMLMarkdownRoundTripTests: XCTestCase {
    private func roundTrip(_ markdown: String) -> String {
        HTMLToMarkdown.convert(MarkdownHTML.render(markdown))
    }

    private func assertStable(_ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(roundTrip(markdown), markdown, file: file, line: line)
    }

    func testUeberschriftenUndAbsaetze() {
        assertStable("## Titel\n\nEin Absatz mit **fett**, *kursiv* und `code`.")
    }

    func testListen() {
        assertStable("- eins\n- zwei\n  - tiefer\n  - noch tiefer\n- drei")
        assertStable("1. eins\n2. zwei\n3. drei")
    }

    func testZitatUndCode() {
        assertStable("> Ein Zitat")
        assertStable("```swift\nlet x = 1\n```")
    }

    func testLinkUndDurchstreichen() {
        assertStable("Siehe [Doku](https://x.test) — ~~alt~~ ist weg.")
    }

    func testLinie() {
        assertStable("oben\n\n---\n\nunten")
    }

    /// Der realistische Fall: ein „### Für Kunde"-Block, wie `solve-task` ihn schreibt.
    func testEinGanzerLoesungstext() {
        assertStable("""
        ## Was wurde gemacht

        Der Umbenennen-Vorgang schreibt jetzt einen Log-Eintrag.

        ### Entscheidungen, Abweichungen, Annahmen

        - **Entscheidung:** Der Eintrag hängt am Projekt, nicht am Gebäude — begründet durch AK 3.
        - **Annahme:** Bestandsdaten brauchen keine Nachmigration.
          - Rücksprache mit dem Fachbereich steht aus.
        - Keine Abweichungen von den Akzeptanzkriterien.

        ## Test

        1. Projekt öffnen
        2. Gebäude umbenennen
        3. Log prüfen — der Eintrag steht mit `alter Name → neuer Name` da

        > Achtung: der Log ist nur für Rollen mit `LOG_VIEW` sichtbar.
        """)
    }
}
