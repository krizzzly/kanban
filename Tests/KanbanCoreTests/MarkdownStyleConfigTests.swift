import XCTest
@testable import KanbanCore

/// Der `markdown`-Block der Config: Schriften, Farben, Grössen — und seit KANBAN-005 benannte
/// Fassungen wie beim Terminal.
final class MarkdownStyleConfigTests: XCTestCase {

    private func settings(_ json: String) -> KanbanSettings {
        KanbanSettingsStore.parse(Data(json.utf8))
    }

    private func theme(_ json: String) -> MarkdownTheme { settings(json).markdown }

    // MARK: - Schriftarten

    /// Ohne Eintrag bleibt genau die Kette übrig, die vorher fest im Stylesheet stand.
    func testOhneSchriftDieBisherigeKette() {
        XCTAssertEqual(MarkdownTheme.cssFontStack(nil),
                       "-apple-system, system-ui, \"Helvetica Neue\", sans-serif")
    }

    func testSchriftStehtVorDerRueckfallkette() {
        let stack = MarkdownTheme.cssFontStack("Iowan Old Style")
        XCTAssertTrue(stack.hasPrefix("\"Iowan Old Style\", "))
        XCTAssertTrue(stack.contains("sans-serif"), "die Rückfallkette muss dranbleiben")
    }

    /// Ein Tippfehler darf das Stylesheet nicht zerlegen: Anführungszeichen, Semikolon und
    /// geschweifte Klammern kämen sonst aus der Regel heraus.
    func testGefaehrlicheZeichenFallenWeg() {
        let stack = MarkdownTheme.cssFontStack("Arial\"; body { display: none } /*")
        XCTAssertFalse(stack.contains(";"))
        XCTAssertFalse(stack.contains("{"))
        XCTAssertFalse(stack.contains("}"))
        XCTAssertTrue(stack.hasPrefix("\"Arial"))
    }

    /// Ein geleertes Feld in den Einstellungen ist „Systemschrift", keine namenlose Schrift.
    func testLeererNameGiltAlsNichtGesetzt() {
        XCTAssertEqual(MarkdownTheme.cssFontStack("   "), MarkdownTheme.cssFontStack(nil))
    }

    // MARK: - Ohne eigenen Abschnitt

    func testOhneAbschnittGeltenDieMitgelieferten() {
        let s = settings("{}")
        XCTAssertEqual(s.markdown, MarkdownTheme.standard)
        XCTAssertEqual(s.markdownThemes.map(\.name), ["Blatt", "Blatt Dunkel"])
        XCTAssertNil(s.markdown.fontFamily)
        XCTAssertNil(s.markdown.headingFont)
    }

    func testLeereThemesMapGibtDieMitgelieferten() {
        XCTAssertEqual(settings("""
            { "markdown": { "themes": {} } }
            """).markdownThemes.map(\.name), ["Blatt", "Blatt Dunkel"])
    }

    // MARK: - Flacher Altblock (die Form vor den Fassungen)

    func testAltblockGiltAlsFassungEigene() {
        let s = settings("""
            { "markdown": { "fontFamily": "Iowan Old Style", "headingFont": "Futura" } }
            """)
        XCTAssertEqual(s.markdownThemes.map(\.name), [MarkdownTheme.eigeneName])
        XCTAssertEqual(s.markdown.fontFamily, "Iowan Old Style")
        XCTAssertEqual(s.markdown.headingFont, "Futura")
        // Farben unberührt: ein halb gefüllter Block darf den Rest nicht mitziehen.
        XCTAssertEqual(s.markdown.background, MarkdownTheme.standard.background)
    }

    func testLeereSchriftWirdZuNil() {
        let t = theme("""
            { "markdown": { "fontFamily": "  ", "headingFont": "" } }
            """)
        XCTAssertNil(t.fontFamily)
        XCTAssertNil(t.headingFont)
    }

    func testFarbenUndGroessenWerdenGelesen() {
        let t = theme("""
            { "markdown": { "background": "#101214", "text": "#EEEEEE",
                            "fontSize": "16", "headings": { "h1": "30" } } }
            """)
        XCTAssertEqual(MarkdownTheme.hex(t.background), "#101214")
        XCTAssertEqual(MarkdownTheme.hex(t.text), "#eeeeee")
        XCTAssertEqual(t.fontSizes.body, 16)
        XCTAssertEqual(t.fontSizes.h1, 30)
        // Nicht genannte Ebenen behalten die Vorgabe.
        XCTAssertEqual(t.fontSizes.h2, MarkdownFontSizes.standard.h2)
    }

    /// Unlesbares fällt auf die Vorgabe zurück, statt die ganze Config zu Fall zu bringen.
    func testKaputteWerteFallenZurueck() {
        let t = theme("""
            { "markdown": { "background": "dunkelblau", "fontSize": "riesig",
                            "headings": { "h1": "900" } } }
            """)
        XCTAssertEqual(t.background, MarkdownTheme.standard.background)
        XCTAssertEqual(t.fontSizes.body, MarkdownFontSizes.standard.body)
        XCTAssertEqual(t.fontSizes.h1, 72, "900 wird auf die Obergrenze gezogen")
    }

    // MARK: - Abdunklung der Flächen

    /// Der Punkt der Sache: wer den Hintergrund ändert, bekommt Flächen, die dazu passen — statt
    /// eines festen Graus auf farbigem Blatt.
    func testFlaecheFolgtDemBlatt() {
        let hell = theme("""
            { "markdown": { "background": "#ffffff" } }
            """)
        XCTAssertEqual(MarkdownTheme.hex(hell.flaeche), "#f0f0f0", "6 % dunkler als Weiss")

        let blau = theme("""
            { "markdown": { "background": "#dce6ff" } }
            """)
        XCTAssertEqual(MarkdownTheme.hex(blau.flaeche), "#cfd8f0", "bleibt blau, nur dunkler")
    }

    func testStaerkeIstEinstellbar() {
        XCTAssertEqual(MarkdownTheme.hex(theme("""
            { "markdown": { "background": "#ffffff", "shade": 20 } }
            """).flaeche), "#cccccc")
        XCTAssertEqual(MarkdownTheme.hex(theme("""
            { "markdown": { "background": "#ffffff", "shade": 0 } }
            """).flaeche), "#ffffff", "0 heisst: gar keine Fläche")
    }

    /// Auf einem fast schwarzen Blatt ergibt Abdunkeln keinen sichtbaren Unterschied — dort geht es
    /// um denselben Anteil in die andere Richtung.
    func testAufDunklemBlattWirdAufgehellt() {
        let dunkel = theme("""
            { "markdown": { "background": "#16181c", "shade": 20 } }
            """)
        XCTAssertEqual(MarkdownTheme.hex(dunkel.flaeche), "#454649")
        XCTAssertGreaterThan(dunkel.flaeche.r, dunkel.background.r)
    }

    func testFesteFarbeSchlaegtDieAbleitung() {
        let t = theme("""
            { "markdown": { "background": "#dce6ff", "codeBackground": "#112233" } }
            """)
        XCTAssertEqual(MarkdownTheme.hex(t.flaeche), "#112233")
    }

    func testStaerkeWirdAufDieGrenzenGezogen() {
        XCTAssertEqual(theme("""
            { "markdown": { "shade": 900 } }
            """).shade, 100)
        XCTAssertEqual(theme("""
            { "markdown": { "shade": "unlesbar" } }
            """).shade, MarkdownTheme.shadeVorgabe)
    }

    /// Die mitgelieferten Fassungen dürfen **keine** feste Code-Farbe mitschleppen: eine Kopie davon
    /// hätte sie sonst geerbt, und das Blatt zu ändern brächte wieder graue Blöcke auf Farbe.
    func testMitgelieferteFassungenLegenDieFlaecheNichtFest() {
        for fassung in MarkdownTheme.vorgaben {
            XCTAssertNil(fassung.codeBackground, "\(fassung.name) hält die Fläche fest")
            XCTAssertNil(fassung.werte.value(at: ["codeBackground"]),
                         "\(fassung.name) gäbe sie an jede Kopie weiter")
        }
    }

    // MARK: - Schrift je Überschriftenebene

    func testEbeneSchlaegtGemeinsameUeberschriftenschrift() {
        let t = theme("""
            { "markdown": { "fontFamily": "Iowan Old Style", "headingFont": "Futura",
                            "headingFonts": { "h1": "Didot" } } }
            """)
        XCTAssertEqual(t.schrift(fuerUeberschrift: 1), "Didot")
        XCTAssertEqual(t.schrift(fuerUeberschrift: 2), "Futura", "die anderen bleiben, wie sie waren")
        XCTAssertEqual(t.schrift(fuerUeberschrift: 6), "Futura")
    }

    /// Ohne gemeinsame Überschriftenschrift fällt eine nicht gesetzte Ebene auf den Fliesstext —
    /// dieselbe Kette wie vorher, nur eine Stufe länger.
    func testOhneEintraegeAendertSichNichts() {
        let t = theme("""
            { "markdown": { "fontFamily": "Iowan Old Style", "headingFonts": { "h1": "Didot" } } }
            """)
        XCTAssertEqual(t.schrift(fuerUeberschrift: 1), "Didot")
        XCTAssertEqual(t.schrift(fuerUeberschrift: 3), "Iowan Old Style")

        let ohne = theme("{}")
        XCTAssertTrue(ohne.headingFonts.istLeer)
        XCTAssertNil(ohne.schrift(fuerUeberschrift: 1))
    }

    func testLeereEbeneGiltAlsNichtGesetzt() {
        let t = theme("""
            { "markdown": { "headingFont": "Futura", "headingFonts": { "h1": "   ", "h2": "" } } }
            """)
        XCTAssertEqual(t.schrift(fuerUeberschrift: 1), "Futura")
        XCTAssertEqual(t.schrift(fuerUeberschrift: 2), "Futura")
    }

    /// Die Schriften müssen den Weg durch die Datei überstehen, sonst verlöre „neue Fassung als
    /// Kopie" sie beim Anlegen.
    func testEbenenschriftenUeberlebenDenWegDurchDieDatei() throws {
        let fassung = MarkdownTheme(name: "X", background: MarkdownTheme.standard.background,
                                    text: MarkdownTheme.standard.text,
                                    secondaryText: MarkdownTheme.standard.secondaryText,
                                    codeBackground: MarkdownTheme.standard.codeBackground,
                                    link: MarkdownTheme.standard.link,
                                    border: MarkdownTheme.standard.border,
                                    headingFonts: MarkdownHeadingFonts(h1: "Didot", h3: "Futura"))
        let root = JSONValue.object([
            "markdown": .object(["theme": .string("X"), "themes": .object(["X": fassung.werte])]),
        ])
        let gelesen = KanbanSettingsStore.parse(try JSONEncoder().encode(root)).markdown
        XCTAssertEqual(gelesen.headingFonts.h1, "Didot")
        XCTAssertEqual(gelesen.headingFonts.h3, "Futura")
        XCTAssertNil(gelesen.headingFonts.h2)
    }

    // MARK: - Benannte Fassungen

    private let zweiFassungen = """
        { "markdown": {
            "theme": "Nacht",
            "themes": {
              "Tag":   { "background": "#ffffff", "text": "#111111" },
              "Nacht": { "background": "#101214", "text": "#eeeeee", "fontSize": 17 }
            } } }
        """

    func testAktiveFassungWirdUeberDenNamenGewaehlt() {
        let s = settings(zweiFassungen)
        XCTAssertEqual(s.markdown.name, "Nacht")
        XCTAssertEqual(MarkdownTheme.hex(s.markdown.background), "#101214")
        XCTAssertEqual(s.markdown.fontSizes.body, 17)
        XCTAssertEqual(s.markdownThemes.map(\.name), ["Nacht", "Tag"], "nach Namen sortiert")
    }

    /// Ein Name, den es nicht (mehr) gibt, ist kein Fehler — sonst stünde die Ansicht still, weil
    /// jemand eine Fassung umbenannt hat.
    func testUnbekannteAuswahlNimmtDieErsteFassung() {
        let s = settings("""
            { "markdown": { "theme": "Gibtsnicht",
                            "themes": { "Tag": { "background": "#ffffff" },
                                        "Nacht": { "background": "#101214" } } } }
            """)
        XCTAssertEqual(s.markdown.name, "Nacht", "erste nach Sortierung")
    }

    /// Stehen beide Formen in der Datei, gewinnt `themes` — und zwar vollständig: der flache Block
    /// wird nicht halb eingemischt. Genau deshalb zieht er beim Speichern um (`MarkdownAltblock`).
    func testFassungenSchlagenDenAltblock() {
        let s = settings("""
            { "markdown": { "background": "#ff0000", "fontSize": 40,
                            "themes": { "Tag": { "background": "#ffffff" } } } }
            """)
        XCTAssertEqual(s.markdownThemes.map(\.name), ["Tag"])
        XCTAssertEqual(MarkdownTheme.hex(s.markdown.background), "#ffffff")
        XCTAssertEqual(s.markdown.fontSizes.body, MarkdownFontSizes.standard.body,
                       "die 40 aus dem Altblock gilt nicht mehr")
    }

    /// Was `werte` schreibt, muss die Auflösung wieder genauso lesen — sonst verlöre „neue Fassung
    /// als Kopie" bei jedem Anlegen etwas.
    func testFassungUeberlebtDenWegDurchDieDatei() throws {
        let root = JSONValue.object([
            "markdown": .object(["theme": .string("X"),
                                 "themes": .object(["X": MarkdownTheme.blattDunkel.werte])]),
        ])
        let daten = try JSONEncoder().encode(root)
        let gelesen = KanbanSettingsStore.parse(daten).markdown
        let vorbild = MarkdownTheme.blattDunkel
        XCTAssertEqual(gelesen.background, vorbild.background)
        XCTAssertEqual(gelesen.text, vorbild.text)
        XCTAssertEqual(gelesen.secondaryText, vorbild.secondaryText)
        XCTAssertEqual(gelesen.codeBackground, vorbild.codeBackground)
        XCTAssertEqual(gelesen.link, vorbild.link)
        XCTAssertEqual(gelesen.border, vorbild.border)
        XCTAssertEqual(gelesen.fontSizes, vorbild.fontSizes)
    }

    // MARK: - Zahl oder Zeichenkette (der teure Fall)

    func testZahlenDuerfenZahlenSein() {
        let t = theme("""
            { "markdown": { "fontSize": 16, "headings": { "h1": 30 } } }
            """)
        XCTAssertEqual(t.fontSizes.body, 16)
        XCTAssertEqual(t.fontSizes.h1, 30)
    }

    /// Die Regression zum teuersten Fund dieses Tasks: `RawSettings` wird mit **einem** `try?`
    /// gelesen. Warf der Decoder an einem einzigen Wert, galt die Vorgabe für **alles** — das
    /// konfigurierte Terminal-Theme war weg, die Markdown-Palette auch, ohne eine Meldung.
    func testEinFalscherTypNimmtNichtMehrDieGanzeConfigMit() {
        let s = settings("""
            { "terminal": { "theme": "Kanban Dark",
                            "font": { "size": "18" },
                            "themes": { "Kanban Dark": {
                              "background": "#000f13", "foreground": "#ededed",
                              "ansi": ["#333333","#ff5f56","#5af78e","#ffd75f",
                                       "#57acff","#ff6ac1","#5af7d4","#e0e0e0",
                                       "#666666","#ff6e67","#5af78e","#fffc67",
                                       "#6bc1ff","#ff77d0","#5af7d4","#ffffff"] } } },
              "markdown": { "background": "#101214", "fontSize": 16 } }
            """)
        XCTAssertEqual(s.activeTerminalTheme.name, "Kanban Dark", "Theme bleibt, trotz Zahl als Text")
        XCTAssertEqual(s.font.size, 18, "„18\" wird als 18 gelesen")
        XCTAssertEqual(MarkdownTheme.hex(s.markdown.background), "#101214")
        XCTAssertEqual(s.markdown.fontSizes.body, 16)
    }

    /// Der Seed ist die Datei, die bei einer frischen Installation entsteht — und ein grosses
    /// String-Literal. Ein Tippfehler darin fiele sonst erst dem nächsten neuen Rechner auf.
    func testDerSeedBringtBeideFassungenMit() {
        let s = KanbanSettingsStore.parse(Data(defaultConfigJSON.utf8))
        XCTAssertEqual(s.activeTerminalTheme.name, "Solarized Dark")
        XCTAssertEqual(s.terminalThemes.map(\.name), ["Kanban Dark", "Solarized Dark"])
        XCTAssertEqual(s.markdown.name, "Blatt")
        XCTAssertEqual(s.markdownThemes.map(\.name), ["Blatt", "Blatt Dunkel"])
        XCTAssertEqual(s.markdown.fontSizes.h1, 26)
        XCTAssertEqual(s.font.size, 16)
    }

    func testUnlesbareZahlBleibtBeiDerVorgabe() {
        let s = settings("""
            { "terminal": { "font": { "size": "sehr gross" } }, "markdown": { "fontSize": true } }
            """)
        XCTAssertEqual(s.font.size, TerminalFontSettings.default.size)
        XCTAssertEqual(s.markdown.fontSizes.body, MarkdownFontSizes.standard.body)
    }
}
