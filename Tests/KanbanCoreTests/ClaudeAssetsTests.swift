import XCTest
@testable import KanbanCore

final class ClaudeAssetsTests: XCTestCase {
    private var root: URL!         // kanonischer Bestand
    private var factory: URL!      // Auslieferungsstand (Bundle-Ersatz)
    private var userDir: URL!      // ~/.claude-Ersatz

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudeAssetsTests-\(UUID().uuidString)")
        root = base.appendingPathComponent("canonical")
        factory = base.appendingPathComponent("factory")
        userDir = base.appendingPathComponent("dotclaude")
        for kind in ["commands", "rules"] {
            try FileManager.default.createDirectory(
                at: factory.appendingPathComponent(kind), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(
            at: factory.appendingPathComponent("skills/impact-analysis"), withIntermediateDirectories: true)
        try "get".write(to: factory.appendingPathComponent("commands/get-task.md"),
                        atomically: true, encoding: .utf8)
        try "db".write(to: factory.appendingPathComponent("rules/db-access.md"),
                       atomically: true, encoding: .utf8)
        try "skill".write(to: factory.appendingPathComponent("skills/impact-analysis/SKILL.md"),
                          atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private var store: ClaudeAssetStore { ClaudeAssetStore(canonicalRoot: root, userClaudeDir: userDir) }

    // MARK: Seeding

    func testSeedCopiesMissingAssets() throws {
        let seeded = try store.seedMissing(from: factory)
        XCTAssertEqual(Set(seeded.map(\.id)),
                       ["commands/get-task", "rules/db-access", "skills/impact-analysis"])
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("commands/get-task.md"),
                                  encoding: .utf8), "get")
    }

    func testSeedLeavesEditedAssetsAlone() throws {
        try store.seedMissing(from: factory)
        try "EDITIERT".write(to: root.appendingPathComponent("commands/get-task.md"),
                             atomically: true, encoding: .utf8)
        let seeded = try store.seedMissing(from: factory)
        XCTAssertTrue(seeded.isEmpty)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("commands/get-task.md"),
                                  encoding: .utf8), "EDITIERT")
    }

    func testResetOverwritesWithFactoryVersion() throws {
        try store.seedMissing(from: factory)
        let asset = store.assets(.command)[0]
        try "EDITIERT".write(to: asset.url, atomically: true, encoding: .utf8)
        try store.resetToFactory(asset, from: factory)
        XCTAssertEqual(try String(contentsOf: asset.url, encoding: .utf8), "get")
    }

    // MARK: Symlinks

    func testInstallAndRemoveSymlink() throws {
        try store.seedMissing(from: factory)
        let command = store.assets(.command)[0]
        try store.installSymlink(for: command)
        XCTAssertEqual(store.symlinkState(for: command), .linked)

        // Der Link funktioniert wirklich: Lesen über den Symlink liefert den Bestand.
        let link = userDir.appendingPathComponent("commands/get-task.md")
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "get")

        try store.removeSymlink(for: command)
        XCTAssertEqual(store.symlinkState(for: command), .notInstalled)
    }

    func testForeignFileIsNeverClobbered() throws {
        try store.seedMissing(from: factory)
        let command = store.assets(.command)[0]
        let target = userDir.appendingPathComponent("commands/get-task.md")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "fremd".write(to: target, atomically: true, encoding: .utf8)

        guard case .foreign = store.symlinkState(for: command) else {
            return XCTFail("echte Datei muss als fremd erkannt werden")
        }
        XCTAssertThrowsError(try store.installSymlink(for: command))
        try store.removeSymlink(for: command)   // darf Fremdes nicht löschen
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "fremd")
    }

    func testRulesGetNoSymlink() throws {
        try store.seedMissing(from: factory)
        let rule = store.assets(.rule)[0]
        XCTAssertNil(store.symlinkTarget(for: rule))
        XCTAssertThrowsError(try store.installSymlink(for: rule))
        XCTAssertTrue(store.installAllSymlinks().keys.allSatisfy { $0.kind != .rule })
    }

    func testSkillSymlinkPointsAtDirectory() throws {
        try store.seedMissing(from: factory)
        let skill = store.assets(.skill)[0]
        try store.installSymlink(for: skill)
        let linked = userDir.appendingPathComponent("skills/impact-analysis/SKILL.md")
        XCTAssertEqual(try String(contentsOf: linked, encoding: .utf8), "skill")
    }
}

