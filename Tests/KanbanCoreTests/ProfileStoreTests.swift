import XCTest
@testable import KanbanCore

/// Die Profil-Ebene: `profiles.json`, die Migration des gewachsenen Bestands und die Pfade, die
/// daran hängen.
///
/// Jeder Test arbeitet in einem eigenen Temp-Ordner als „globaler Datenordner" — sonst schriebe er
/// in den echten unter `~/Library/Application Support/Kanban`.
final class ProfileStoreTests: XCTestCase {
    private var temp: URL!

    override func setUp() {
        super.setUp()
        temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kanban-profile-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        KanbanPaths.setGlobalRoot(temp)
        KanbanPaths.reset()
    }

    override func tearDown() {
        KanbanPaths.setGlobalRoot(nil)
        KanbanPaths.reset()
        try? FileManager.default.removeItem(at: temp)
        super.tearDown()
    }

    // MARK: - Migration

    /// Der Kern des Schnitts: die Migration schreibt **eine Datei** und verschiebt nichts.
    ///
    /// Ein Umzug wäre nicht bloss teurer, sondern falsch — die Config zeigt mit absoluten Pfaden in
    /// den Datenordner (Task-Files, Doku, Bilder), und die Skill-Sets sind Ziel absoluter Symlinks
    /// aus den Agent-Homes und aus jedem Repo.
    func testMigrationMachtDenFlachenBestandZumProfilOhneEtwasZuVerschieben() throws {
        try "{}".write(to: temp.appendingPathComponent("config.json"),
                       atomically: true, encoding: .utf8)
        let tasks = temp.appendingPathComponent("tasks/even", isDirectory: true)
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try "# EVEN-1".write(to: tasks.appendingPathComponent("EVEN-1_x.md"),
                             atomically: true, encoding: .utf8)

        XCTAssertTrue(ProfileStore.migrateIfNeeded())

        let liste = ProfileStore.load()
        XCTAssertEqual(liste.profiles.count, 1)
        XCTAssertEqual(liste.active, ProfileStore.defaultSlug)
        // Der Ordner des Profils *ist* der Datenordner.
        XCTAssertTrue(ProfileStore.sameFolder(liste.profiles[0].path, temp.path))
        XCTAssertTrue(liste.profiles[0].isDefault)
        // Und alles liegt noch, wo es lag.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tasks.appendingPathComponent("EVEN-1_x.md").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temp.appendingPathComponent("config.json").path))
    }

    /// Ein zweiter Start darf die Liste nicht überschreiben.
    func testMigrationLaeuftNurEinmal() {
        XCTAssertTrue(ProfileStore.migrateIfNeeded())
        XCTAssertFalse(ProfileStore.migrateIfNeeded())
    }

    /// Ohne Datei gilt dasselbe wie vor der Profil-Ebene — ein Profil, Ordner = Datenordner.
    func testOhneDateiGiltDasVorgabeProfil() {
        let liste = ProfileStore.load()
        XCTAssertEqual(liste.profiles.count, 1)
        XCTAssertTrue(liste.profiles[0].isDefault)
        XCTAssertEqual(ProfileStore.activeFolder().path, temp.path)
    }

    /// Eine kaputte Liste darf niemanden von seinen Daten aussperren.
    func testKaputteDateiFaelltAufDieVorgabeZurueckUndSagtEs() throws {
        try "{ das ist kein JSON".write(to: KanbanPaths.profilesFile,
                                        atomically: true, encoding: .utf8)
        let liste = ProfileStore.load()
        XCTAssertEqual(liste.profiles.count, 1)
        XCTAssertTrue(liste.profiles[0].isDefault)
        XCTAssertNotNil(ProfileStore.lastError)
    }

    /// Ein von Hand entferntes aktives Profil fällt auf das erste vorhandene zurück.
    func testUnbekanntesAktivesProfilFaelltAufDasErsteZurueck() throws {
        ProfileStore.migrateIfNeeded()
        let angelegt = try ProfileStore.create(name: "Privat")
        var liste = ProfileStore.load()
        liste.active = "gibtesnicht"
        try ProfileStore.save(liste)
        XCTAssertEqual(ProfileStore.load().activeProfile?.slug, ProfileStore.defaultSlug)
        XCTAssertNotEqual(angelegt.slug, ProfileStore.defaultSlug)
    }

    // MARK: - Anlegen, Umbenennen, Entfernen

    /// Ein neues Profil startet leer — und trägt genau einen Wert: die Hermes-Rückschreibung ist
    /// aus. Sonst schriebe ein privates Profil seine Projekte in die Config der anderen Welt.
    func testNeuesProfilBekommtEigenenOrdnerUndHermesSyncAus() throws {
        ProfileStore.migrateIfNeeded()
        let profil = try ProfileStore.create(name: "Privat")

        XCTAssertEqual(profil.slug, "privat")
        XCTAssertFalse(profil.isDefault)
        XCTAssertEqual(profil.folder.path, temp.appendingPathComponent("profiles/privat").path)

        let config = try String(contentsOf: profil.folder.appendingPathComponent("config.json"),
                                encoding: .utf8)
        XCTAssertTrue(config.contains("\"syncProjects\""))
        XCTAssertTrue(config.contains("false"))
        // Keine Zugangsdaten, keine Projekte — nichts aus dem anderen Profil.
        XCTAssertFalse(config.contains("apiToken"))
        XCTAssertFalse(config.contains("modules"))
    }

    func testNeuesProfilIstNichtSofortAktiv() throws {
        ProfileStore.migrateIfNeeded()
        _ = try ProfileStore.create(name: "Privat")
        XCTAssertEqual(ProfileStore.active().slug, ProfileStore.defaultSlug)
    }

    func testUmschaltenHaeltFest() throws {
        ProfileStore.migrateIfNeeded()
        let privat = try ProfileStore.create(name: "Privat")
        try ProfileStore.activate(slug: privat.slug)
        XCTAssertEqual(ProfileStore.active().slug, "privat")
        XCTAssertEqual(ProfileStore.activeFolder().path, privat.folder.path)
    }

    /// Der Slug bleibt beim Umbenennen stehen: er steckt in UserDefaults-Schlüsseln und in den
    /// Namen laufender tmux-Sitzungen.
    func testUmbenennenLaesstDenSlugUndDenOrdnerInRuhe() throws {
        ProfileStore.migrateIfNeeded()
        let profil = try ProfileStore.create(name: "Privat")
        try ProfileStore.rename(slug: profil.slug, to: "Zuhause")

        let neu = try XCTUnwrap(ProfileStore.load().profiles.first { $0.slug == "privat" })
        XCTAssertEqual(neu.name, "Zuhause")
        XCTAssertEqual(neu.path, profil.path)
    }

    /// Entfernen nimmt den Eintrag, **nicht** den Ordner — dieselbe Haltung wie bei den Skill-Sets.
    /// In einem Profilordner liegen Task-Files, gebuchte Zeiten und Zugangsdaten.
    func testEntfernenLaesstDenOrdnerStehen() throws {
        ProfileStore.migrateIfNeeded()
        let profil = try ProfileStore.create(name: "Privat")
        try ProfileStore.remove(slug: profil.slug)

        XCTAssertFalse(ProfileStore.load().profiles.contains { $0.slug == "privat" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: profil.folder.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: profil.folder.appendingPathComponent("config.json").path))
    }

    /// Das aktive Profil zu entfernen darf nicht ins Leere führen.
    func testEntferntesAktivesProfilGibtDasAktiveWeiter() throws {
        ProfileStore.migrateIfNeeded()
        let privat = try ProfileStore.create(name: "Privat")
        try ProfileStore.activate(slug: privat.slug)
        try ProfileStore.remove(slug: privat.slug)
        XCTAssertEqual(ProfileStore.active().slug, ProfileStore.defaultSlug)
    }

    func testDasLetzteProfilBleibt() throws {
        ProfileStore.migrateIfNeeded()
        XCTAssertThrowsError(try ProfileStore.remove(slug: ProfileStore.defaultSlug))
    }

    // MARK: - Slugs

    func testSlugKommtOhneUmlauteAusOhneZeichenZuVerlieren() {
        XCTAssertEqual(ProfileStore.slug(for: "Büro", taken: []), "buero")
        XCTAssertEqual(ProfileStore.slug(for: "Größe", taken: []), "groesse")
        XCTAssertEqual(ProfileStore.slug(for: "Mein Profil!", taken: []), "mein-profil")
        XCTAssertEqual(ProfileStore.slug(for: "  ", taken: []), "profil")
    }

    func testSlugZaehltBeiKollisionHoch() {
        XCTAssertEqual(ProfileStore.slug(for: "Privat", taken: ["privat"]), "privat-2")
        XCTAssertEqual(ProfileStore.slug(for: "Privat", taken: ["privat", "privat-2"]), "privat-3")
    }
}
