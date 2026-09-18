import XCTest
@testable import KanbanCore

/// Wie die gemerkte Auswahl je Profil getrennt wird — die Schlüssel-Abbildung hinter
/// `SelectionStore`.
///
/// Ohne sie machte der Start im privaten Profil die Fenster der Arbeit auf: `openProjectKeys`,
/// `selectedProjectKey`, `selectedSprintByProject` und `boardModeByProject` lagen bis dahin
/// unpräfixiert in `UserDefaults` und gehörten damit allen Profilen gemeinsam.
final class ProfileDefaultsTests: XCTestCase {
    private func profil(_ slug: String, pfad: String) -> KanbanProfile {
        KanbanProfile(slug: slug, name: slug, path: pfad)
    }

    /// Ohne Profil verhält sich alles wie vor der Profil-Ebene — kein Präfix, kein Rückgriff.
    func testOhneProfilBleibenDieSchluesselWieSieWaren() {
        let keys = ProfileDefaults(profile: nil)
        XCTAssertEqual(keys.key("openProjectKeys"), "openProjectKeys")
        XCTAssertNil(keys.legacyKey("openProjectKeys"))
    }

    func testJedesProfilSchreibtUnterSeinemEigenenSchluessel() {
        let keys = ProfileDefaults(slug: "privat", readsLegacyKeys: false)
        XCTAssertEqual(keys.key("openProjectKeys"), "privat.openProjectKeys")
        XCTAssertEqual(keys.key("selectedProjectKey"), "privat.selectedProjectKey")
    }

    /// Das migrierte Profil erbt die alten Schlüssel **beim Lesen** — niemand soll seine offenen
    /// Fenster verlieren, bloss weil das Format eine Ebene bekommen hat.
    func testDasMigrierteProfilLiestDieAltenSchluesselMit() {
        let keys = ProfileDefaults(slug: "arbeit", readsLegacyKeys: true)
        XCTAssertEqual(keys.key("openProjectKeys"), "arbeit.openProjectKeys")
        XCTAssertEqual(keys.legacyKey("openProjectKeys"), "openProjectKeys")
    }

    /// Und ein zweites Profil erbt sie **nicht** — es soll die Fenster der anderen Welt ja gerade
    /// nicht sehen. Das ist der ganze Zweck der Übung.
    func testEinZweitesProfilErbtNichts() {
        let keys = ProfileDefaults(slug: "privat", readsLegacyKeys: false)
        XCTAssertNil(keys.legacyKey("openProjectKeys"))
    }

    /// Die Zuordnung „wer erbt" kommt aus dem Profil selbst, nicht aus einer zweiten Liste.
    func testNurDasProfilImDatenordnerGiltAlsMigriert() {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kanban-defaults-\(UUID().uuidString)", isDirectory: true)
        KanbanPaths.setGlobalRoot(temp)
        defer { KanbanPaths.setGlobalRoot(nil); KanbanPaths.reset() }

        let arbeit = ProfileDefaults(profile: profil("arbeit", pfad: temp.path))
        let privat = ProfileDefaults(
            profile: profil("privat", pfad: temp.appendingPathComponent("profiles/privat").path))

        XCTAssertTrue(arbeit.readsLegacyKeys)
        XCTAssertFalse(privat.readsLegacyKeys)
    }
}
