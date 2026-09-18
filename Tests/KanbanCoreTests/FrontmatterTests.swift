import XCTest
@testable import KanbanCore

/// Der YAML-Kopf beim Rendern. Markdown kennt ihn nicht, und ohne Behandlung macht cmark daraus
/// eine Trennlinie plus **Setext-Überschrift** — der Kopf eines Skills stand als fette Zeile quer
/// über der Seite.
final class FrontmatterTests: XCTestCase {

    private let skill = """
    ---
    name: solve-task
    description: löst ein Ticket
    disable-model-invocation: true
    ---

    # solve-task

    Rumpf.
    """

    func testKopfWirdCodeblock() {
        let md = Frontmatter.alsCodeblock(skill)
        XCTAssertTrue(md.hasPrefix("```yaml\nname: solve-task"), md.prefix(40).description)
        XCTAssertTrue(md.contains("disable-model-invocation: true\n```"))
        XCTAssertTrue(md.contains("# solve-task"))
    }

    /// Das Ergebnis muss im HTML ein `<pre><code>` sein — und keine Überschrift mehr.
    func testGerendertStehtErAlsCodeblockDa() {
        let html = MarkdownHTML.render(skill)
        XCTAssertTrue(html.contains("<pre><code class=\"language-yaml\">"), html.prefix(120).description)
        XCTAssertTrue(html.contains("name: solve-task"))
        XCTAssertFalse(html.contains("<h2>name: solve-task"), "war vorher eine Setext-Überschrift")
        XCTAssertFalse(html.hasPrefix("<hr />"), "und davor eine Trennlinie")
        XCTAssertTrue(html.contains("<h1>solve-task</h1>"), "der echte Titel bleibt einer")
    }

    func testOhneKopfBleibtAllesWieEsWar() {
        let md = "# Titel\n\nText\n"
        XCTAssertEqual(Frontmatter.alsCodeblock(md), md)
        XCTAssertNil(Frontmatter.block(md))
    }

    /// `---` als Trennlinie mitten im Text ist kein Kopf; ein nie geschlossener Block auch nicht.
    func testTrennlinieUndOffenerBlockSindKeinKopf() {
        XCTAssertNil(Frontmatter.block("# Titel\n\n---\n\nText"))
        XCTAssertNil(Frontmatter.block("---\nname: x\nkein Ende"))
        let strich = "# Titel\n\n---\n\nText"
        XCTAssertEqual(Frontmatter.alsCodeblock(strich), strich)
    }

    /// Backticks im Kopf dürfen den Zaun nicht sprengen — `description: nutzt `foo`` ist in einem
    /// Skill-Kopf nichts Besonderes.
    func testZaunIstLaengerAlsDerInhalt() {
        let mit = "---\ndescription: nutzt ```json``` dafür\n---\n\nRumpf"
        let md = Frontmatter.alsCodeblock(mit)
        XCTAssertTrue(md.hasPrefix("````yaml"), md.prefix(20).description)
        // Und cmark liest das auch so: der Rumpf steht ausserhalb des Blocks.
        XCTAssertTrue(MarkdownHTML.render(mit).contains("<p>Rumpf</p>"))
    }

    func testZaunlaenge() {
        XCTAssertEqual(Frontmatter.zaunlaenge(fuer: "ohne"), 3)
        XCTAssertEqual(Frontmatter.zaunlaenge(fuer: "ein `code`"), 3)
        XCTAssertEqual(Frontmatter.zaunlaenge(fuer: "```drei```"), 4)
        XCTAssertEqual(Frontmatter.zaunlaenge(fuer: "`````fünf`````"), 6)
    }

    /// Der Kopf ist Text und wird als solcher gesucht — gerendert steht er ja auf dem Schirm.
    func testKopfIstDurchsuchbar() {
        let treffer = TaskSearch.hits(query: "disable-model-invocation",
                                      in: [TaskSection(id: 0, title: "x", markdown: skill)])
        XCTAssertEqual(treffer.count, 1)
    }
}

/// Die Farben der gerenderten Ansichten kommen aus der Config (`markdown.*`).
final class MarkdownThemeTests: XCTestCase {

    private func settings(_ json: String) -> KanbanSettings {
        KanbanSettingsStore.parse(Data(json.utf8))
    }

    func testVorgabeIstDeckendesWeiss() {
        let theme = MarkdownTheme.standard
        XCTAssertEqual(MarkdownTheme.hex(theme.background), "#ffffff")
        XCTAssertEqual(theme.colorScheme, "light")
        XCTAssertNotEqual(MarkdownTheme.hex(theme.flaeche),
                          MarkdownTheme.hex(theme.background), "der Codeblock muss sich abheben")
    }

    func testFarbenKommenAusDerConfig() {
        let s = settings(##"{"markdown":{"background":"#fafafa","codeBackground":"#dddddd"}}"##)
        XCTAssertEqual(MarkdownTheme.hex(s.markdown.background), "#fafafa")
        XCTAssertEqual(MarkdownTheme.hex(s.markdown.flaeche), "#dddddd",
                       "eine fest gesetzte Farbe gewinnt gegen die Ableitung")
        // Nicht gesetzte Werte bleiben die Vorgabe.
        XCTAssertEqual(MarkdownTheme.hex(s.markdown.text),
                       MarkdownTheme.hex(MarkdownTheme.standard.text))
    }

    /// Eine unlesbare Farbe darf weder die Palette noch die Config zu Fall bringen.
    func testKaputteFarbeFaelltAufDieVorgabeZurueck() {
        let s = settings(##"{"markdown":{"background":"kein hex","text":"#112233"}}"##)
        XCTAssertEqual(MarkdownTheme.hex(s.markdown.background), "#ffffff")
        XCTAssertEqual(MarkdownTheme.hex(s.markdown.text), "#112233")
    }

    /// Dunkel konfiguriert zieht `color-scheme` nach — sonst blieben die Scrollbalken weiss.
    func testDunkleFlaecheMeldetDunkel() {
        let s = settings(##"{"markdown":{"background":"#1e1e1e"}}"##)
        XCTAssertEqual(s.markdown.colorScheme, "dark")
    }

    func testOhneAbschnittGiltDieVorgabe() {
        XCTAssertEqual(settings("{}").markdown, MarkdownTheme.standard)
    }

    // MARK: - Schriftgrössen

    /// Der Punkt der ganzen Übung: die Ebenen müssen sich unterscheiden. Vorher standen alle sechs
    /// auf Textgrösse und nur die Strichstärke trennte sie.
    func testUeberschriftenSindAbsteigendUndUnterscheidbar() {
        let s = MarkdownFontSizes.standard
        let ebenen = [s.h1, s.h2, s.h3, s.h4, s.h5, s.h6]
        XCTAssertEqual(ebenen, ebenen.sorted(by: >), "H1 > H2 > … > H6")
        XCTAssertEqual(Set(ebenen).count, ebenen.count, "keine zwei Ebenen gleich gross")
        XCTAssertGreaterThan(s.h1, s.body * 1.5, "H1 muss deutlich über dem Fliesstext liegen")
        XCTAssertEqual(s.h4, s.body, "ab H4 gliedert die Fettung, nicht die Grösse")
    }

    func testGroessenKommenAusDerConfig() {
        let s = settings(##"{"markdown":{"fontSize":"16","headings":{"h1":"34","h3":"19"}}}"##)
        XCTAssertEqual(s.markdown.fontSizes.body, 16)
        XCTAssertEqual(s.markdown.fontSizes.h1, 34)
        XCTAssertEqual(s.markdown.fontSizes.h3, 19)
        // Nicht gesetzte Ebenen bleiben die Vorgabe.
        XCTAssertEqual(s.markdown.fontSizes.h2, MarkdownFontSizes.standard.h2)
    }

    /// Eine 0 oder eine 900 in der Config macht die Ansicht unbenutzbar, ohne dass man sähe, warum.
    func testGroessenWerdenBegrenzt() {
        let s = settings(##"{"markdown":{"headings":{"h1":"900","h2":"0","h3":"keine zahl"}}}"##)
        XCTAssertEqual(s.markdown.fontSizes.h1, 72)
        XCTAssertEqual(s.markdown.fontSizes.h2, 8)
        XCTAssertEqual(s.markdown.fontSizes.h3, MarkdownFontSizes.standard.h3)
    }

    func testGroesseJeEbene() {
        let s = MarkdownFontSizes.standard
        XCTAssertEqual(s.groesse(fuer: 1), s.h1)
        XCTAssertEqual(s.groesse(fuer: 6), s.h6)
        XCTAssertEqual(s.groesse(fuer: 99), s.h6, "unbekannte Ebene fällt auf die kleinste")
    }
}
