import XCTest
@testable import KanbanCore

/// Die Fassungs-Verwaltung, wie die Einstellungen sie benutzt: anlegen, entfernen, umbenennen, die
/// 16 ANSI-Farben — und der Umzug des flachen `markdown`-Altblocks.
final class ThemeMapEditTests: XCTestCase {

    private var terminal: ThemeMapSpec { KanbanConfigSchema.terminalGruppe.themeMap! }
    private var markdown: ThemeMapSpec { KanbanConfigSchema.markdownGruppe.themeMap! }

    private func konfigMitZweiFassungen() -> JSONValue {
        .object(["terminal": .object([
            "theme": .string("Kanban Dark"),
            "themes": .object(["Kanban Dark": TerminalTheme.kanbanDark.werte,
                               "Solarized Dark": TerminalTheme.solarizedDark.werte]),
        ])])
    }

    // MARK: - Anlegen

    /// Eine leere Fassung gäbe es in der Auswahl nie: ohne Pflichtfarben und ohne 16 ANSI-Farben
    /// wirft `RawTheme.resolved` sie stumm weg. Deshalb startet sie als Kopie der aktiven.
    func testNeueFassungIstKopieDerAktiven() {
        var root = konfigMitZweiFassungen()
        XCTAssertTrue(ThemeMapEdit.add(&root, spec: terminal, name: "Meine"))
        XCTAssertEqual(root.value(at: ["terminal", "themes", "Meine"]),
                       TerminalTheme.kanbanDark.werte)
        XCTAssertNil(terminal.fehler(in: root.value(at: ["terminal", "themes", "Meine"])),
                     "die Kopie ist von Anfang an vollständig")
    }

    func testNeueFassungOhneBestandNimmtDieVorlage() {
        var root = JSONValue.object([:])
        XCTAssertTrue(ThemeMapEdit.add(&root, spec: markdown, name: "Meine"))
        XCTAssertEqual(root.value(at: ["markdown", "themes", "Meine"]),
                       MarkdownTheme.standard.werte)
    }

    func testNameDoppeltOderLeerLegtNichtsAn() {
        var root = konfigMitZweiFassungen()
        XCTAssertFalse(ThemeMapEdit.add(&root, spec: terminal, name: "Kanban Dark"))
        XCTAssertFalse(ThemeMapEdit.add(&root, spec: terminal, name: "   "))
        XCTAssertEqual(ThemeMapEdit.namen(root, terminal), ["Kanban Dark", "Solarized Dark"])
    }

    // MARK: - Entfernen

    func testEntfernenDerAktivenZiehtDieAuswahlNach() {
        var root = konfigMitZweiFassungen()
        ThemeMapEdit.remove(&root, spec: terminal, name: "Kanban Dark")
        XCTAssertEqual(ThemeMapEdit.namen(root, terminal), ["Solarized Dark"])
        XCTAssertEqual(root.value(at: ["terminal", "theme"])?.stringValue, "Solarized Dark",
                       "sonst zeigt die Auswahl ins Leere und es griffe stumm die erste")
    }

    func testEntfernenEinerAnderenLaesstDieAuswahlStehen() {
        var root = konfigMitZweiFassungen()
        ThemeMapEdit.remove(&root, spec: terminal, name: "Solarized Dark")
        XCTAssertEqual(root.value(at: ["terminal", "theme"])?.stringValue, "Kanban Dark")
    }

    // MARK: - Umbenennen

    func testUmbenennenZiehtDieAuswahlNach() {
        var root = konfigMitZweiFassungen()
        XCTAssertTrue(ThemeMapEdit.rename(&root, spec: terminal, from: "Kanban Dark", to: "Nacht"))
        XCTAssertEqual(ThemeMapEdit.namen(root, terminal), ["Nacht", "Solarized Dark"])
        XCTAssertEqual(root.value(at: ["terminal", "theme"])?.stringValue, "Nacht")
        XCTAssertEqual(root.value(at: ["terminal", "themes", "Nacht"]), TerminalTheme.kanbanDark.werte)
    }

    func testUmbenennenAufEinenVergebenenNamenTutNichts() {
        var root = konfigMitZweiFassungen()
        XCTAssertFalse(ThemeMapEdit.rename(&root, spec: terminal,
                                           from: "Kanban Dark", to: "Solarized Dark"))
        XCTAssertEqual(root.value(at: ["terminal", "themes", "Solarized Dark"]),
                       TerminalTheme.solarizedDark.werte, "die bestehende Fassung bleibt unangetastet")
    }

    // MARK: - ANSI

    func testAnsiListeWirdAufSechzehnGebracht() {
        var root = JSONValue.object([:])
        let pfad = ["terminal", "themes", "Meine", "ansi"]
        ThemeMapEdit.setAnsi(&root, path: pfad, index: 3, hex: "#ffd75f")
        let liste = root.value(at: pfad)?.arrayValue ?? []
        XCTAssertEqual(liste.count, 16, "mit 15 Einträgen fiele die ganze Fassung beim Laden weg")
        XCTAssertEqual(liste[3].stringValue, "#ffd75f")
        XCTAssertEqual(liste[0].stringValue, "")
    }

    // MARK: - Vollständigkeit: dieselbe Auskunft wie beim Laden

    func testUnvollstaendigeFassungWirdErkanntUndFaelltAuchWirklichWeg() throws {
        let halb = JSONValue.object(["background": .string("#000000")])   // foreground fehlt, kein ansi
        XCTAssertNotNil(terminal.fehler(in: halb))

        let root = JSONValue.object(["terminal": .object([
            "theme": .string("Halb"), "themes": .object(["Halb": halb]),
        ])])
        let gelesen = KanbanSettingsStore.parse(try JSONEncoder().encode(root))
        XCTAssertEqual(gelesen.activeTerminalTheme.name, "Solarized Dark",
                       "der Decoder wirft sie weg — die Warnung sagt also die Wahrheit")
    }

    func testFehlendeAnsiFarbeWirdBenannt() {
        var werte = TerminalTheme.kanbanDark.werte
        var liste = werte.value(at: ["ansi"])?.arrayValue ?? []
        liste.removeLast()
        werte.set(.array(liste), at: ["ansi"])
        XCTAssertEqual(terminal.fehler(in: werte), "15 von 16 ANSI-Farben lesbar — erst mit allen 16 zählt die Fassung.")
    }

    /// Markdown kennt keine Pflichtfarben: dort fällt jeder Wert einzeln auf die Vorgabe zurück,
    /// eine halbe Fassung ist also eine gültige Fassung.
    func testMarkdownFassungIstNieUnvollstaendig() {
        XCTAssertNil(markdown.fehler(in: .object(["link": .string("#2c65cf")])))
    }

    // MARK: - Altblock-Umzug

    func testAltblockZiehtVerlustfreiUm() throws {
        var root = JSONValue.object(["markdown": .object([
            "background": .string("#101214"), "text": .string("#eeeeee"),
            "fontSize": .int(16), "headings": .object(["h1": .int(30)]),
            "fontFamily": .string("Iowan Old Style"),
        ])])
        let vorher = KanbanSettingsStore.parse(try JSONEncoder().encode(root)).markdown

        XCTAssertTrue(MarkdownAltblock.migriere(&root))

        XCTAssertNil(root.value(at: ["markdown", "background"]), "der flache Block ist leer geräumt")
        XCTAssertEqual(root.value(at: ["markdown", "theme"])?.stringValue, MarkdownTheme.eigeneName)
        let nachher = KanbanSettingsStore.parse(try JSONEncoder().encode(root)).markdown
        XCTAssertEqual(nachher.background, vorher.background)
        XCTAssertEqual(nachher.text, vorher.text)
        XCTAssertEqual(nachher.fontSizes, vorher.fontSizes)
        XCTAssertEqual(nachher.fontFamily, vorher.fontFamily)
    }

    func testMitFassungenPassiertNichts() {
        var root = JSONValue.object(["markdown": .object([
            "background": .string("#ff0000"),
            "themes": .object(["Tag": .object(["background": .string("#ffffff")])]),
        ])])
        XCTAssertFalse(MarkdownAltblock.migriere(&root))
        XCTAssertEqual(root.value(at: ["markdown", "background"])?.stringValue, "#ff0000",
                       "nichts angefasst — `themes` gewinnt beim Laden ohnehin")
    }

    func testOhneMarkdownAbschnittPassiertNichts() {
        var root = JSONValue.object(["terminal": .object(["theme": .string("Kanban Dark")])])
        XCTAssertFalse(MarkdownAltblock.migriere(&root))
    }

    func testEineVorhandeneAuswahlBleibtStehen() {
        var root = JSONValue.object(["markdown": .object([
            "theme": .string("Blatt"), "background": .string("#101214"),
        ])])
        XCTAssertTrue(MarkdownAltblock.migriere(&root))
        XCTAssertEqual(root.value(at: ["markdown", "theme"])?.stringValue, "Blatt",
                       "eine getroffene Wahl wird nicht überschrieben")
    }
}

/// Die Verdrahtung der Sektion „Darstellung": ohne sie gäbe es die Werte weiterhin nur im Roh-JSON.
final class DarstellungSchemaTests: XCTestCase {

    private var darstellung: ConfigSectionSpec {
        KanbanConfigSchema.sections.first { $0.id == "appearance" }!
    }

    func testDarstellungFuehrtMarkdownUndTerminal() {
        XCTAssertEqual(darstellung.groups.map(\.id), ["markdown", "terminal"])
        XCTAssertNotNil(darstellung.projectMap, "die Kopfzeile je Projekt bleibt")
        XCTAssertNil(KanbanConfigSchema.sections.first { $0.id == "markdown" },
                     "Markdown ist eine Gruppe der Darstellung, keine eigene Sektion mehr")
    }

    func testJedesFeldSchreibtInSeinenEigenenBlock() {
        for gruppe in darstellung.groups {
            for feld in gruppe.fields {
                XCTAssertEqual(feld.path.first, gruppe.id, "\(feld.id) schreibt daneben")
            }
            guard let map = gruppe.themeMap else { return XCTFail("\(gruppe.id) ohne Fassungen") }
            XCTAssertEqual(map.path, [gruppe.id, "themes"])
            XCTAssertEqual(map.activePath, [gruppe.id, "theme"])
        }
    }

    /// Die Auswahl muss auf **die** Map zeigen, die darunter editiert wird — sonst listet sie
    /// Namen, die es woanders gibt.
    func testDieAuswahlZeigtAufDieEigeneMap() {
        for gruppe in darstellung.groups {
            let auswahl = gruppe.fields.first { $0.path == [gruppe.id, "theme"] }
            guard case .choiceFromKeys(let pfad)? = auswahl?.kind else {
                return XCTFail("\(gruppe.id): keine Auswahl über die vorhandenen Fassungen")
            }
            XCTAssertEqual(pfad, gruppe.themeMap?.path)
        }
    }

    func testGroessenSindZahlenfelderKeineTextfelder() {
        let felder = KanbanConfigSchema.markdownThemeFelder
            .filter { $0.subpath == ["fontSize"] || $0.subpath.first == "headings" }
        XCTAssertEqual(felder.count, 7)
        for feld in felder {
            guard case .number(let min, let max) = feld.kind else {
                return XCTFail("\(feld.id) müsste eine Zahl sein — als Text kippt es die Config")
            }
            XCTAssertEqual([min, max], [8, 72], "dieselben Grenzen wie im Decoder")
        }
    }

    func testTerminalSchriftgroesseIstEinZahlenfeld() {
        let feld = KanbanConfigSchema.terminalGruppe.fields
            .first { $0.path == ["terminal", "font", "size"] }
        guard case .number(let min, let max)? = feld?.kind else {
            return XCTFail("`terminal.font.size` ist eine Zahl in der Datei")
        }
        XCTAssertEqual([min, max], [6, 72])
    }

    func testTerminalFassungenKennenIhrePflichtfarbenUndDieAnsiListe() {
        let map = KanbanConfigSchema.terminalGruppe.themeMap
        XCTAssertEqual(map?.requiredKeys, ["background", "foreground"])
        XCTAssertEqual(map?.ansiKey, "ansi")
        XCTAssertEqual(map?.vorlagen.map(\.name), ["Solarized Dark", "Kanban Dark"])
        XCTAssertNil(KanbanConfigSchema.markdownGruppe.themeMap?.ansiKey,
                     "Markdown hat keine ANSI-Farben")
    }
}
