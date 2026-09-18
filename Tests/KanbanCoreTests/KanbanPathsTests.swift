import XCTest
@testable import KanbanCore

/// Die Pfad-Ebene: was zum Profil gehört und was global bleibt.
///
/// Die Trennung ist keine Geschmacksfrage. `attention/` und das Hook-Skript stehen mit **absolutem
/// Pfad** in `~/.claude/settings.json`; wanderten sie mit dem Profil, müsste diese fremde Datei bei
/// jedem Wechsel umgeschrieben werden.
final class KanbanPathsTests: XCTestCase {
    private var temp: URL!

    override func setUp() {
        super.setUp()
        temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kanban-paths-\(UUID().uuidString)", isDirectory: true)
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

    /// Alle profilgebundenen Ablagen als Pfade — in fester Reihenfolge, damit sich zwei Profile
    /// paarweise vergleichen lassen.
    private func profilPfade() -> [String] {
        [KanbanPaths.configFile, KanbanPaths.tasksRoot, KanbanPaths.docsRoot,
         KanbanPaths.claudeSetsRoot, KanbanPaths.imagesRoot, KanbanPaths.sessionsFile,
         KanbanPaths.worklogFile, KanbanPaths.watchdogFile, KanbanPaths.locksDirectory].map(\.path)
    }

    func testOhneProfileZeigtAllesInDenFlachenOrdner() {
        XCTAssertEqual(KanbanPaths.root.path, temp.path)
        XCTAssertEqual(KanbanPaths.configFile.path, temp.appendingPathComponent("config.json").path)
        XCTAssertEqual(KanbanPaths.tasksRoot.path, temp.appendingPathComponent("tasks").path)
        XCTAssertEqual(KanbanPaths.watchdogFile.path,
                       temp.appendingPathComponent("watchdog.json").path)
    }

    /// Jede profilgebundene Ablage liegt unter der Wurzel — und zwei Profile teilen keine davon.
    func testZweiProfileTeilenKeineEinzigeAblage() {
        let a = temp.appendingPathComponent("profiles/a", isDirectory: true)
        let b = temp.appendingPathComponent("profiles/b", isDirectory: true)

        KanbanPaths.setRoot(a)
        let ersterStand = profilPfade()
        KanbanPaths.setRoot(b)
        let zweiterStand = profilPfade()

        XCTAssertEqual(ersterStand.count, zweiterStand.count)
        for (links, rechts) in zip(ersterStand, zweiterStand) {
            XCTAssertNotEqual(links, rechts)
            XCTAssertTrue(links.hasPrefix(a.path + "/"), links)
            XCTAssertTrue(rechts.hasPrefix(b.path + "/"), rechts)
        }
    }

    /// Die drei globalen Werte bleiben, wo sie sind — auch wenn das Profil woandershin zeigt.
    func testDasGlobaleBleibtGlobal() {
        KanbanPaths.setRoot(temp.appendingPathComponent("profiles/privat", isDirectory: true))

        XCTAssertEqual(KanbanPaths.globalRoot.path, temp.path)
        XCTAssertEqual(KanbanPaths.profilesFile.path,
                       temp.appendingPathComponent("profiles.json").path)
        XCTAssertEqual(KanbanPaths.attentionDirectory.path,
                       temp.appendingPathComponent("attention").path)
        XCTAssertEqual(KanbanPaths.hookScript.path,
                       temp.appendingPathComponent("kanban-attention-hook.sh").path)
    }

    /// `KanbanConfig` und alles, was über `supportDirectory` geht (Projektbilder, Watchdog, Doku),
    /// zieht ohne eigenes Zutun mit.
    func testConfigUndAbgeleiteteOrdnerFolgenDemProfil() {
        let privat = temp.appendingPathComponent("profiles/privat", isDirectory: true)
        KanbanPaths.setRoot(privat)

        XCTAssertEqual(KanbanConfig.supportDirectory, privat.path)
        XCTAssertEqual(KanbanConfig.docsRoot, privat.appendingPathComponent("docs").path)
        XCTAssertEqual(ProjectImageStore.directory,
                       privat.appendingPathComponent("images").path)
        XCTAssertEqual(WatchdogStore().path,
                       privat.appendingPathComponent("watchdog.json").path)
    }

    /// Der Sets-Ordner folgt dem Profil, der **Alt-Bestand** nicht: er ist per Definition der Ort
    /// von früher, und `isOurs` erkennt daran die Symlinks, die umgehängt werden dürfen.
    func testSetsOrdnerFolgtDemProfilDerAltbestandNicht() {
        let privat = temp.appendingPathComponent("profiles/privat", isDirectory: true)
        KanbanPaths.setRoot(privat)

        XCTAssertEqual(ClaudeAssetStore.defaultSetsRoot(basePath: "~/code").path,
                       privat.appendingPathComponent("claude").path)
        XCTAssertEqual(ClaudeAssetStore.defaultLegacyRoot.path,
                       temp.appendingPathComponent("claude").path)
    }

    /// `reset()` vergisst den aufgelösten Ordner; der nächste Zugriff fragt `ProfileStore` erneut.
    func testZuruecksetzenLoestErneutAuf() throws {
        KanbanPaths.setRoot(temp.appendingPathComponent("irgendwo", isDirectory: true))
        XCTAssertEqual(KanbanPaths.root.lastPathComponent, "irgendwo")
        KanbanPaths.reset()
        XCTAssertEqual(KanbanPaths.root.path, temp.path)
    }
}
