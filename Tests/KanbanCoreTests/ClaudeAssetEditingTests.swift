import XCTest
@testable import KanbanCore

/// Neue Assets anlegen und Fassungen aufbewahren — beides gegen ein echtes Verzeichnis, weil beides
/// aus Dateien und Symlinks besteht.
final class ClaudeAssetCreationTests: XCTestCase {
    private var wurzel: URL!
    private var store: ClaudeAssetStore!

    override func setUpWithError() throws {
        wurzel = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: wurzel, withIntermediateDirectories: true)
        store = ClaudeAssetStore(canonicalRoot: wurzel.appendingPathComponent("claude"),
                                 userClaudeDir: wurzel.appendingPathComponent("home-claude"),
                                 userCodexDir: wurzel.appendingPathComponent("home-codex"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
    }

    // MARK: - Namen

    func testNamenWerdenNormalisiert() {
        XCTAssertEqual(ClaudeAssetName.normalisiert("  Mein Neuer Skill  "), "mein-neuer-skill")
        XCTAssertEqual(ClaudeAssetName.normalisiert("db_access"), "db-access")
        XCTAssertEqual(ClaudeAssetName.normalisiert("a--b"), "a-b")
        XCTAssertEqual(ClaudeAssetName.normalisiert("-rand-"), "rand")
    }

    /// Der Name ist Dateiname, Symlink-Ziel **und** Aufruf (`/name`). Was dort nicht funktioniert,
    /// darf gar nicht erst entstehen.
    func testUnbrauchbareNamenWerdenAbgelehnt() {
        XCTAssertThrowsError(try ClaudeAssetName.pruefen(""))
        XCTAssertThrowsError(try ClaudeAssetName.pruefen("1-start-mit-ziffer"))
        XCTAssertThrowsError(try ClaudeAssetName.pruefen("mit/slash"))
        XCTAssertThrowsError(try ClaudeAssetName.pruefen("Gross"))
        XCTAssertThrowsError(try ClaudeAssetName.pruefen("umlaut-ä"))
        XCTAssertNoThrow(try ClaudeAssetName.pruefen("create-task"))
        XCTAssertNoThrow(try ClaudeAssetName.pruefen("a1"))
    }

    // MARK: - Anlegen

    func testSkillWirdOrdnerMitSkillMd() throws {
        let asset = try store.create(kind: .skill, name: "Mein Skill", beschreibung: "tut etwas")
        XCTAssertEqual(asset.name, "mein-skill")
        let datei = asset.url.appendingPathComponent("SKILL.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: datei.path))
        let text = try String(contentsOf: datei, encoding: .utf8)
        XCTAssertTrue(text.contains("name: mein-skill"))
        XCTAssertTrue(text.contains("description: tut etwas"))
        // Ein Skill darf nicht von allein loslaufen — das konnte ein Command nie.
        XCTAssertTrue(text.contains("disable-model-invocation: true"))
        XCTAssertTrue(text.contains("$ARGUMENTS"))
    }

    func testRuleWirdEinzelneDatei() throws {
        let asset = try store.create(kind: .rule, name: "meine-regel")
        XCTAssertEqual(asset.url.lastPathComponent, "meine-regel.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.url.path))
        XCTAssertFalse(try String(contentsOf: asset.url, encoding: .utf8).contains("disable-model-invocation"))
    }

    func testNeuesAssetTauchtImBestandAuf() throws {
        try store.create(kind: .skill, name: "alpha")
        try store.create(kind: .rule, name: "beta")
        XCTAssertEqual(store.assets(.skill).map(\.name), ["alpha"])
        XCTAssertEqual(store.assets(.rule).map(\.name), ["beta"])
    }

    func testDoppelterNameWirdAbgelehnt() throws {
        try store.create(kind: .skill, name: "alpha")
        XCTAssertThrowsError(try store.create(kind: .skill, name: "Alpha")) { fehler in
            XCTAssertEqual(fehler as? ClaudeAssetName.Fehler, .belegt("alpha"))
        }
    }

    /// „Aus Datei anlegen": der Inhalt kommt von der Platte, das Frontmatter ergänzt Kanban — ohne
    /// Kopf wäre der Skill für beide Agents unsichtbar.
    func testSkillAusDateiinhaltBekommtFrontmatter() throws {
        let asset = try store.create(kind: .skill, name: "aus-datei",
                                     beschreibung: "von der Platte",
                                     inhalt: "# Eine Anleitung\n\nSchritt eins.\n")
        let text = try String(contentsOf: asset.url.appendingPathComponent("SKILL.md"),
                              encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("---\nname: aus-datei"))
        XCTAssertTrue(text.contains("description: von der Platte"))
        XCTAssertTrue(text.contains("disable-model-invocation: true"))
        XCTAssertTrue(text.contains("Schritt eins."))
        XCTAssertFalse(text.contains("TODO:"), "die Vorlage ist ersetzt, nicht angehängt")
    }

    /// Bringt die Datei ein eigenes Frontmatter mit, gilt es unverändert.
    func testEigenesFrontmatterAusDerDateiBleibt() throws {
        let asset = try store.create(kind: .skill, name: "eigen",
                                     inhalt: "---\nname: anders\ndescription: eigen\n---\n\n# x\n")
        let text = try String(contentsOf: asset.url.appendingPathComponent("SKILL.md"),
                              encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("---\nname: anders"))
        XCTAssertFalse(text.contains("disable-model-invocation"))
    }

    func testRuleAusDateiinhaltBleibtWieSieIst() throws {
        let asset = try store.create(kind: .rule, name: "regel", inhalt: "# Meine Regel\n")
        XCTAssertEqual(try String(contentsOf: asset.url, encoding: .utf8), "# Meine Regel\n")
    }

    /// Ein neuer Skill ist sofort verlinkbar — sonst wäre er nur eine Datei im Bestand und in
    /// keinem Projekt zu gebrauchen.
    func testNeuerSkillLaesstSichVerlinken() throws {
        let asset = try store.create(kind: .skill, name: "alpha")
        for agent in store.linkableAgents(for: asset) {
            try store.installSymlink(for: asset, agent: agent)
            XCTAssertEqual(store.symlinkState(for: asset, agent: agent), .linked)
        }
        XCTAssertEqual(store.linkableAgents(for: asset).count, 2, "Claude und Codex")
    }

    /// Löschen nimmt die Symlinks mit — sonst zeigten sie ins Leere.
    func testLoeschenNimmtDieSymlinksMit() throws {
        let asset = try store.create(kind: .skill, name: "alpha")
        try store.installSymlink(for: asset, agent: .claude)
        try store.delete(asset)
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.url.path))
        XCTAssertEqual(store.symlinkState(for: asset, agent: .claude), .notInstalled)
    }
}

final class ClaudeAssetVersionTests: XCTestCase {
    private var wurzel: URL!
    private var store: ClaudeAssetStore!
    private var versionen: ClaudeAssetVersionStore!
    private var datei: URL!

    override func setUpWithError() throws {
        wurzel = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("versionen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: wurzel, withIntermediateDirectories: true)
        let bestand = wurzel.appendingPathComponent("claude")
        store = ClaudeAssetStore(canonicalRoot: bestand,
                                 userClaudeDir: wurzel.appendingPathComponent("home-claude"),
                                 userCodexDir: wurzel.appendingPathComponent("home-codex"))
        versionen = ClaudeAssetVersionStore(canonicalRoot: bestand)
        let asset = try store.create(kind: .skill, name: "solve-task")
        datei = asset.url.appendingPathComponent("SKILL.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
    }

    private func schreibe(_ text: String) throws {
        try text.write(to: datei, atomically: true, encoding: .utf8)
    }

    private func sekunden(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + Double(n)) }

    func testGesicherteFassungLaesstSichWiederAktivieren() throws {
        try schreibe("erste Fassung")
        try versionen.sichern(datei, jetzt: sekunden(0))
        try schreibe("umgebaut, gefällt mir nicht")

        let alle = versionen.versionen(von: datei)
        XCTAssertEqual(alle.count, 1)
        try versionen.aktivieren(alle[0], in: datei, jetzt: sekunden(10))
        XCTAssertEqual(try String(contentsOf: datei, encoding: .utf8), "erste Fassung")
    }

    /// Aktivieren muss selbst rückgängig zu machen sein — sonst ist es ein Verlust statt eines
    /// Wechsels.
    func testAktivierenSichertDenBisherigenStand() throws {
        try schreibe("alt")
        try versionen.sichern(datei, jetzt: sekunden(0))
        try schreibe("neu")
        try versionen.aktivieren(versionen.versionen(von: datei)[0], in: datei, jetzt: sekunden(10))

        let inhalte = versionen.versionen(von: datei).compactMap(versionen.inhalt)
        XCTAssertEqual(inhalte.count, 2)
        XCTAssertTrue(inhalte.contains("neu"), "der überschriebene Stand ist noch da")
    }

    func testNeuesteZuerst() throws {
        try schreibe("a"); try versionen.sichern(datei, jetzt: sekunden(0))
        try schreibe("b"); try versionen.sichern(datei, jetzt: sekunden(60))
        XCTAssertEqual(versionen.versionen(von: datei).compactMap(versionen.inhalt), ["b", "a"])
    }

    /// Zweimal Speichern ohne Änderung soll keine zweite Fassung erzeugen.
    func testGleicherInhaltGibtKeineZweiteFassung() throws {
        try schreibe("unverändert")
        XCTAssertNotNil(try versionen.sichern(datei, jetzt: sekunden(0)))
        XCTAssertNil(try versionen.sichern(datei, jetzt: sekunden(60)))
        XCTAssertEqual(versionen.versionen(von: datei).count, 1)
    }

    /// Eine **benannte** Fassung entsteht trotzdem — der Name ist ja der Punkt.
    func testBenannteFassungEntstehtAuchBeiGleichemInhalt() throws {
        try schreibe("unverändert")
        try versionen.sichern(datei, jetzt: sekunden(0))
        XCTAssertNotNil(try versionen.sichern(datei, bezeichnung: "vor dem Umbau", jetzt: sekunden(60)))
        XCTAssertEqual(versionen.versionen(von: datei).first?.bezeichnung, "vor dem Umbau")
    }

    func testBezeichnungUeberlebtDenDateinamen() throws {
        try schreibe("x")
        try versionen.sichern(datei, bezeichnung: "Stand vor dem Review", jetzt: sekunden(0))
        let version = try XCTUnwrap(versionen.versionen(von: datei).first)
        XCTAssertEqual(version.bezeichnung, "Stand vor dem Review")
        XCTAssertEqual(version.datum, sekunden(0))
    }

    /// Ein `/` in der Bezeichnung würde einen Unterordner aufmachen.
    func testSchraegstrichInDerBezeichnungLandetNichtImPfad() throws {
        try schreibe("x")
        try versionen.sichern(datei, bezeichnung: "vor/nach", jetzt: sekunden(0))
        let version = try XCTUnwrap(versionen.versionen(von: datei).first)
        XCTAssertEqual(version.bezeichnung, "vor-nach")
        XCTAssertEqual(version.url.deletingLastPathComponent().lastPathComponent, "SKILL.md")
    }

    func testZweiFassungenInDerselbenSekundeUeberschreibenSichNicht() throws {
        try schreibe("a"); try versionen.sichern(datei, bezeichnung: "eins", jetzt: sekunden(0))
        try schreibe("b"); try versionen.sichern(datei, bezeichnung: "zwei", jetzt: sekunden(0))
        XCTAssertEqual(versionen.versionen(von: datei).count, 2)
    }

    /// Automatische Fassungen werden gedeckelt, benannte nie — sie sind die, die jemand behalten
    /// wollte.
    func testAutomatischeWerdenGedeckeltBenannteBleiben() throws {
        try schreibe("wichtig")
        try versionen.sichern(datei, bezeichnung: "behalten", jetzt: sekunden(0))
        for i in 1...(ClaudeAssetVersionStore.maxAutomatisch + 5) {
            try schreibe("stand \(i)")
            try versionen.sichern(datei, jetzt: sekunden(i))
        }
        let alle = versionen.versionen(von: datei)
        XCTAssertEqual(alle.filter { $0.bezeichnung == nil }.count,
                       ClaudeAssetVersionStore.maxAutomatisch)
        XCTAssertEqual(alle.filter { $0.bezeichnung != nil }.map(\.bezeichnung), ["behalten"])
    }

    func testAktiveFassungWirdErkannt() throws {
        try schreibe("aktuell")
        try versionen.sichern(datei, jetzt: sekunden(0))
        let version = try XCTUnwrap(versionen.versionen(von: datei).first)
        XCTAssertTrue(versionen.istAktiv(version, in: datei))
        try schreibe("etwas anderes")
        XCTAssertFalse(versionen.istAktiv(version, in: datei))
    }

    /// Die Historie liegt unter `.versions` und darf nie als Asset auftauchen.
    func testHistorieIstKeinAsset() throws {
        try schreibe("x")
        try versionen.sichern(datei, jetzt: sekunden(0))
        XCTAssertEqual(store.assets(.skill).map(\.name), ["solve-task"])
        XCTAssertTrue(store.allAssets().allSatisfy { !$0.url.path.contains(".versions") })
    }

    /// Der Dialog verspricht es, also muss es stimmen: die Historie liegt **neben** dem Asset, ein
    /// Zurücksetzen auf den Auslieferungsstand wirft sie nicht weg — sonst wäre „zurücksetzen" ein
    /// Einbahnweg, und genau das war der Zustand vorher.
    func testZuruecksetzenAufWerkLaesstDieFassungenStehen() throws {
        try schreibe("mein Umbau")
        try versionen.sichern(datei, bezeichnung: "mein Stand", jetzt: sekunden(0))

        // Auslieferungsstand nachstellen und zurücksetzen.
        let werk = wurzel.appendingPathComponent("bundle")
        let werkSkill = werk.appendingPathComponent("skills/solve-task")
        try FileManager.default.createDirectory(at: werkSkill, withIntermediateDirectories: true)
        try "Auslieferung".write(to: werkSkill.appendingPathComponent("SKILL.md"),
                                 atomically: true, encoding: .utf8)
        let asset = try XCTUnwrap(store.assets(.skill).first)
        try store.resetToFactory(asset, from: werk)

        XCTAssertEqual(try String(contentsOf: datei, encoding: .utf8), "Auslieferung")
        let alle = versionen.versionen(von: datei)
        XCTAssertEqual(alle.count, 1)
        // …und von dort kommt der eigene Stand zurück.
        try versionen.aktivieren(alle[0], in: datei, jetzt: sekunden(99))
        XCTAssertEqual(try String(contentsOf: datei, encoding: .utf8), "mein Umbau")
    }

    func testLoeschenEntferntNurDieseFassung() throws {
        try schreibe("a"); try versionen.sichern(datei, jetzt: sekunden(0))
        try schreibe("b"); try versionen.sichern(datei, jetzt: sekunden(60))
        try versionen.loeschen(versionen.versionen(von: datei)[0])
        XCTAssertEqual(versionen.versionen(von: datei).compactMap(versionen.inhalt), ["a"])
    }
}
