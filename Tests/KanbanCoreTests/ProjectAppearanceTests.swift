import XCTest
@testable import KanbanCore

final class ProjectAppearanceTests: XCTestCase {

    // MARK: - Normalisierung

    func testFarbeWirdAufKleinesRRGGBBGebracht() {
        XCTAssertEqual(ProjectAppearance.normalizeColor("#1A2B3C"), "#1a2b3c")
        XCTAssertEqual(ProjectAppearance.normalizeColor("1a2b3c"), "#1a2b3c")
        XCTAssertEqual(ProjectAppearance.normalizeColor("  #1a2b3c  "), "#1a2b3c")
    }

    /// Eine halb getippte Farbe darf die Kopfzeile nicht einfärben — und die Config nicht
    /// zu Fall bringen.
    func testUnlesbareFarbeGiltAlsNichtGesetzt() {
        XCTAssertNil(ProjectAppearance.normalizeColor("#12"))
        XCTAssertNil(ProjectAppearance.normalizeColor("blau"))
        XCTAssertNil(ProjectAppearance.normalizeColor(""))
        XCTAssertNil(ProjectAppearance.normalizeColor("   "))
        XCTAssertNil(ProjectAppearance.normalizeColor(nil))
    }

    func testRanddickeWirdBeschnitten() {
        XCTAssertEqual(ProjectAppearance.normalizeWidth("2"), 2)
        XCTAssertEqual(ProjectAppearance.normalizeWidth("0"), 0)
        XCTAssertEqual(ProjectAppearance.normalizeWidth("2000"), 20)   // Vertipper
        XCTAssertEqual(ProjectAppearance.normalizeWidth("-5"), 0)
        XCTAssertNil(ProjectAppearance.normalizeWidth("dick"))
        XCTAssertNil(ProjectAppearance.normalizeWidth(nil))
    }

    // MARK: - Eingabefeld

    func testHexEingabeLaesstNurZiffernDurch() {
        XCTAssertEqual(ProjectAppearance.sanitizeHexInput("1A2B3C"), "1a2b3c")
        XCTAssertEqual(ProjectAppearance.sanitizeHexInput("#1a2b3c"), "1a2b3c")   // eingefügt
        XCTAssertEqual(ProjectAppearance.sanitizeHexInput("  #1a2b3c "), "1a2b3c")
    }

    func testHexEingabeWirftUnbrauchbaresWeg() {
        XCTAssertEqual(ProjectAppearance.sanitizeHexInput("blau"), "ba")   // b und a sind Hexziffern
        XCTAssertEqual(ProjectAppearance.sanitizeHexInput("zzz"), "")
        XCTAssertEqual(ProjectAppearance.sanitizeHexInput("1a2b3c4d5e"), "1a2b3c")   // nach 6 Schluss
    }

    /// Beim Tippen von links entstehen zwangsläufig unvollständige Stände — die dürfen im Feld
    /// stehen bleiben, gelten aber noch nicht als Farbe.
    func testUnvollstaendigeEingabeBleibtStehenGiltAberNicht() {
        XCTAssertEqual(ProjectAppearance.sanitizeHexInput("1a2"), "1a2")
        XCTAssertNil(ProjectAppearance.normalizeColor("#1a2"))
    }

    // MARK: - „gar nichts definiert"

    /// Der Normalfall und die eigentliche Anforderung: ohne Eintrag bleibt die Kopfzeile, wie sie ist.
    func testOhneWerteIstNichtsGesetzt() {
        let leer = ProjectAppearance.make(imagePath: nil, background: nil, foreground: nil,
                                          borderColor: nil, borderWidth: nil)
        XCTAssertTrue(leer.isEmpty)
        XCTAssertEqual(leer, .none)
    }

    /// Ein einziges gesetztes Feld reicht — die anderen bleiben leer, statt auf eine erfundene
    /// Vorgabe zu fallen.
    func testEinzelnesFeldReicht() {
        let nurBild = ProjectAppearance.make(imagePath: "/tmp/logo.png", background: nil,
                                             foreground: nil, borderColor: nil, borderWidth: nil)
        XCTAssertFalse(nurBild.isEmpty)
        XCTAssertEqual(nurBild.imagePath, "/tmp/logo.png")
        XCTAssertNil(nurBild.headerBackground)
        XCTAssertNil(nurBild.headerBorderWidth)
    }

    // MARK: - Aus der Config

    private func projekte(_ json: String) throws -> [ProjectConfig] {
        try KanbanConfig.resolve(Data(json.utf8), docsRoot: "/tmp/docs").projects
    }

    private let basis = """
        "modules": { "jira": { "projects": {
            "core": { "prefix": "CORETEST", "tasksPath": "/tmp/tasks/core" } } } }
        """

    func testProjektOhneAppearanceAbschnitt() throws {
        let projects = try projekte("{ \(basis) }")
        XCTAssertEqual(projects.count, 1)
        XCTAssertTrue(projects[0].appearance.isEmpty)
    }

    func testVollstaendigerAbschnittWirdGelesen() throws {
        let projects = try projekte("""
            { \(basis),
              "appearance": { "projects": { "core": {
                  "image": "/tmp/images/core.png",
                  "headerBackground": "#102030",
                  "headerForeground": "#FFFFFF",
                  "headerBorderColor": "#FF0000",
                  "headerBorderWidth": "3" } } } }
            """)
        let a = projects[0].appearance
        XCTAssertEqual(a.imagePath, "/tmp/images/core.png")
        XCTAssertEqual(a.headerBackground, "#102030")
        XCTAssertEqual(a.headerForeground, "#ffffff")
        XCTAssertEqual(a.headerBorderColor, "#ff0000")
        XCTAssertEqual(a.headerBorderWidth, 3)
    }

    /// Der Abschnitt darf halb gefüllt sein: nur ein Bild, sonst nichts.
    func testTeilweiseGefuellterAbschnitt() throws {
        let projects = try projekte("""
            { \(basis),
              "appearance": { "projects": { "core": { "image": "/tmp/images/core.png" } } } }
            """)
        let a = projects[0].appearance
        XCTAssertEqual(a.imagePath, "/tmp/images/core.png")
        XCTAssertNil(a.headerBackground)
        XCTAssertFalse(a.isEmpty)
    }

    /// Ein Eintrag für ein *anderes* Projekt färbt dieses hier nicht ein.
    func testAbschnittEinesAnderenProjektsWirktNicht() throws {
        let projects = try projekte("""
            { \(basis),
              "appearance": { "projects": { "zba": { "headerBackground": "#102030" } } } }
            """)
        XCTAssertTrue(projects[0].appearance.isEmpty)
    }

    /// Kaputte Werte in der Config schalten das Feature für dieses Projekt ab, statt die ganze
    /// Config zu verweigern — dieselbe Regel wie beim Watchdog.
    func testKaputteWerteFallenAufNichtGesetzt() throws {
        let projects = try projekte("""
            { \(basis),
              "appearance": { "projects": { "core": {
                  "headerBackground": "dunkelblau",
                  "headerBorderWidth": "dick" } } } }
            """)
        XCTAssertTrue(projects[0].appearance.isEmpty)
    }

    // MARK: - Verdrahtung

    /// Einen Abschnitt zu definieren und ihn in `sections` zu vergessen, sähe im Code vollständig
    /// aus und wäre in den Einstellungen unsichtbar.
    func testAbschnittStehtInDenEinstellungen() {
        let abschnitt = KanbanConfigSchema.sections.first { $0.id == "appearance" }
        XCTAssertNotNil(abschnitt)
        XCTAssertEqual(abschnitt?.projectMap?.path, ["appearance", "projects"])
        XCTAssertEqual(abschnitt?.projectMap?.fields.map(\.key),
                       ["image", "headerBackground", "headerForeground",
                        "headerBorderColor", "headerBorderWidth"])
        // Kein Feld ist Pflicht — „gar nichts definiert" muss möglich bleiben.
        XCTAssertTrue(abschnitt?.projectMap?.fields.allSatisfy { !$0.required } ?? false)
    }

    // MARK: - Bildablage

    /// SVG und PDF stehen vorn: sie skalieren auf Zeilenhöhe verlustfrei. AppKit lädt SVG seit
    /// macOS 13 selbst — die Liste hatte es davor zu Unrecht ausgeschlossen.
    func testVektorFormateSindErlaubt() {
        XCTAssertTrue(ProjectImageStore.allowedExtensions.contains("svg"))
        XCTAssertTrue(ProjectImageStore.allowedExtensions.contains("pdf"))
    }

    func testFremdeEndungWirdAbgelehnt() throws {
        let quelle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("logo-\(UUID().uuidString).txt")
        try Data("kein Bild".utf8).write(to: quelle)
        defer { try? FileManager.default.removeItem(at: quelle) }

        XCTAssertThrowsError(try ProjectImageStore.store(source: quelle, projectKey: "test")) { fehler in
            guard case ProjectImageError.unsupportedType(let ext) = fehler else {
                return XCTFail("anderer Fehler: \(fehler)")
            }
            XCTAssertEqual(ext, "txt")
        }
    }

    /// Ein zweites Bild ersetzt das erste — auch mit anderer Endung, sonst bliebe die alte Datei
    /// als Leiche liegen, auf die keine Einstellung mehr zeigt.
    func testNeuesBildErsetztDasAlteAuchBeiAndererEndung() throws {
        let key = "appearancetest-\(UUID().uuidString.prefix(8))"
        defer { ProjectImageStore.remove(projectKey: key) }

        let png = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(key).png")
        let svg = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(key).svg")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: png)
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'/>".utf8).write(to: svg)
        defer { try? FileManager.default.removeItem(at: png); try? FileManager.default.removeItem(at: svg) }

        let ersterPfad = try ProjectImageStore.store(source: png, projectKey: key)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ersterPfad))

        let zweiterPfad = try ProjectImageStore.store(source: svg, projectKey: key)
        XCTAssertTrue(zweiterPfad.hasSuffix(".svg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: zweiterPfad))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ersterPfad), "das PNG blieb liegen")
    }

    // MARK: - Projekt entfernen

    /// Beim Entfernen eines Projekts muss auch sein Darstellungs-Eintrag weg — er steht als
    /// einziger **ausserhalb** von `modules` und wurde deshalb von der Modulschleife nicht erfasst.
    func testEntfernenRaeumtDenDarstellungsEintragMitWeg() throws {
        let json = """
            { "appearance": { "projects": { "core": { "headerBackground": "#102030" },
                                            "zba": { "headerBackground": "#304050" } } },
              "modules": { "jira": { "projects": { "core": { "prefix": "CORETEST" } } } } }
            """
        let config = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let danach = ProjectProjection.remove("core", from: config)

        XCTAssertNil(danach.value(at: ["appearance", "projects", "core"]))
        XCTAssertNil(danach.value(at: ["modules", "jira", "projects", "core"]))
        XCTAssertNotNil(danach.value(at: ["appearance", "projects", "zba"]))
    }
}
