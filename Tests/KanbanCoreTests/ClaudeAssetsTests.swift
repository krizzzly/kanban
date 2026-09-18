import XCTest
@testable import KanbanCore

final class ClaudeAssetsTests: XCTestCase {
    private var root: URL!         // Bestand
    private var factory: URL!      // Auslieferungsstand (Bundle-Ersatz)
    private var userDir: URL!      // ~/.claude-Ersatz
    private var codexDir: URL!     // ~/.codex-Ersatz
    private var repo: URL!         // Projekt-Repo

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudeAssetsTests-\(UUID().uuidString)")
        root = base.appendingPathComponent("bestand")
        factory = base.appendingPathComponent("werk")
        userDir = base.appendingPathComponent("dotclaude")
        codexDir = base.appendingPathComponent("dotcodex")
        repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        try werkSet("iwf", skills: ["get-task", "solve-task"], rules: ["worktree"],
                    beschreibung: "Der volle iwf-Satz.")
        try werkSet("swift", skills: ["get-task"], rules: [])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    /// Ein Set im Auslieferungsstand anlegen — so sieht es auch im Repo aus.
    private func werkSet(_ name: String, skills: [String], rules: [String],
                         beschreibung: String? = nil) throws {
        let set = factory.appendingPathComponent("sets/\(name)", isDirectory: true)
        for skill in skills {
            let dir = set.appendingPathComponent("skills/\(skill)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "\(name)/\(skill)".write(to: dir.appendingPathComponent("SKILL.md"),
                                         atomically: true, encoding: .utf8)
        }
        for rule in rules {
            let dir = set.appendingPathComponent("rules", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "\(name)/\(rule)".write(to: dir.appendingPathComponent("\(rule).md"),
                                        atomically: true, encoding: .utf8)
        }
        if let beschreibung {
            try #"{"displayName": "\#(name.uppercased())", "description": "\#(beschreibung)"}"#
                .write(to: set.appendingPathComponent("set.json"), atomically: true, encoding: .utf8)
        }
    }

    private var store: ClaudeAssetStore {
        ClaudeAssetStore(canonicalRoot: root, userClaudeDir: userDir, userCodexDir: codexDir)
    }

    private func set(_ name: String) throws -> ClaudeAssetSet {
        try XCTUnwrap(store.set(named: name))
    }

    // MARK: Inventar

    func testSetInventarAusEinerWurzel() throws {
        try store.syncSets(from: factory)
        XCTAssertEqual(store.sets().map(\.name), ["iwf", "swift"])

        let iwf = try set("iwf")
        XCTAssertEqual(iwf.displayName, "IWF")
        XCTAssertEqual(iwf.description, "Der volle iwf-Satz.")
        XCTAssertEqual(store.assets(.skill, in: iwf).map(\.name), ["get-task", "solve-task"])
        XCTAssertEqual(store.assets(.rule, in: iwf).map(\.name), ["worktree"])
        // Die Id trägt das Set: zwei Sets dürfen denselben Skill-Namen führen.
        XCTAssertEqual(store.assets(.skill, in: iwf)[0].id, "iwf/skills/get-task")

        // Ohne set.json heisst das Set wie sein Ordner.
        XCTAssertEqual(try set("swift").displayName, "swift")
    }

    /// Neben dem Bestand liegt historisch allerlei. Nichts davon ist ein Set, nur weil es ein
    /// Ordner ist — weder ein Backup-Ordner ohne `skills/` noch eine Datei noch `.versions`.
    func testFremdeOrdnerSindKeineSets() throws {
        try store.syncSets(from: factory)
        let fm = FileManager.default
        for müll in ["skills-backup-2026-08-20", "projektkopien-backup-2026-08-07", ".versions"] {
            try fm.createDirectory(at: root.appendingPathComponent("sets/\(müll)"),
                                   withIntermediateDirectories: true)
        }
        try "zip".write(to: root.appendingPathComponent("sets/Christian_RULES_SKILLS_v2.zip"),
                        atomically: true, encoding: .utf8)
        XCTAssertEqual(store.sets().map(\.name), ["iwf", "swift"])
    }

    // MARK: Sync

    /// Die bewusste Umkehr von `seedMissing`: gepflegt wird im Repo, der Bestand wird überschrieben.
    func testSyncUeberschreibtDenBestand() throws {
        try store.syncSets(from: factory)
        let datei = root.appendingPathComponent("sets/iwf/skills/get-task/SKILL.md")
        try "VON HAND EDITIERT".write(to: datei, atomically: true, encoding: .utf8)

        try store.syncSets(from: factory)
        XCTAssertEqual(try String(contentsOf: datei, encoding: .utf8), "iwf/get-task")
    }

    /// Was im Auslieferungsstand gelöscht wurde, ist auch im Bestand weg — sonst bliebe ein
    /// zurückgezogener Skill für immer verlinkbar.
    func testSyncEntferntWasDasWerkNichtMehrHat() throws {
        try store.syncSets(from: factory)
        try FileManager.default.removeItem(at: factory.appendingPathComponent("sets/iwf/skills/solve-task"))
        try store.syncSets(from: factory)
        XCTAssertEqual(store.assets(.skill, in: try set("iwf")).map(\.name), ["get-task"])
    }

    /// Ein von Hand dazugelegtes Set bleibt stehen: überschrieben wird, was wir liefern.
    func testSyncLaesstFremdeSetsInRuhe() throws {
        try store.syncSets(from: factory)
        let eigen = root.appendingPathComponent("sets/eigen/skills/mein-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: eigen, withIntermediateDirectories: true)
        try "meins".write(to: eigen.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        try store.syncSets(from: factory)
        XCTAssertEqual(store.sets().map(\.name), ["eigen", "iwf", "swift"])
    }

    func testSyncSchreibtNichtsBeiGleichemInhalt() throws {
        try store.syncSets(from: factory)
        let datei = root.appendingPathComponent("sets/iwf/skills/get-task/SKILL.md")
        let vorher = try FileManager.default.attributesOfItem(atPath: datei.path)[.modificationDate]
            as? Date
        try store.syncSets(from: factory)
        let nachher = try FileManager.default.attributesOfItem(atPath: datei.path)[.modificationDate]
            as? Date
        XCTAssertEqual(vorher, nachher)
    }

    // MARK: Verlinkung ins Projekt

    func testSetLandetImProjektOrdner() throws {
        try store.syncSets(from: factory)
        let report = store.link(try set("iwf"), toProject: repo.path, agent: .claude)
        XCTAssertTrue(report.isComplete)

        // Skills in .claude/skills, Rules in .claude/rules — und die Links tragen wirklich Inhalt.
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".claude/skills/get-task/SKILL.md"),
                                  encoding: .utf8), "iwf/get-task")
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".claude/rules/worktree.md"),
                                  encoding: .utf8), "iwf/worktree")
        XCTAssertEqual(store.state(of: try set("iwf"),
                                   scope: .project(repoDir: repo.path, agent: .claude)), .linked)
    }

    /// Ein Codex-Projekt bekommt seine Skills in `.codex/skills` — die Rules aber trotzdem nach
    /// `.claude/rules`: die Skills verweisen im Text auf `.claude/rules/…`, und dieser Pfad muss
    /// unter beiden Agents aufgehen (dieselbe Überlegung wie bei `.claude/project.json`).
    func testCodexProjektBekommtSkillsInCodexUndRulesInClaude() throws {
        try store.syncSets(from: factory)
        store.link(try set("iwf"), toProject: repo.path, agent: .codex)
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".codex/skills/get-task/SKILL.md"),
                                  encoding: .utf8), "iwf/get-task")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repo.appendingPathComponent(".claude/rules/worktree.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.appendingPathComponent(".claude/skills/get-task").path))
    }

    /// Zwei Projekte, zwei Sets, **gleichzeitig** — der eigentliche Punkt des Umbaus.
    func testZweiProjekteSehenGleichzeitigVerschiedeneSets() throws {
        try store.syncSets(from: factory)
        let zweitesRepo = repo.deletingLastPathComponent().appendingPathComponent("repo2")
        try FileManager.default.createDirectory(at: zweitesRepo, withIntermediateDirectories: true)

        store.link(try set("iwf"), toProject: repo.path, agent: .claude)
        store.link(try set("swift"), toProject: zweitesRepo.path, agent: .claude)

        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".claude/skills/get-task/SKILL.md"),
                                  encoding: .utf8), "iwf/get-task")
        XCTAssertEqual(try String(contentsOf: zweitesRepo.appendingPathComponent(".claude/skills/get-task/SKILL.md"),
                                  encoding: .utf8), "swift/get-task")
        // Das eine Set hat einen Skill mehr, das andere gar keine Rules.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repo.appendingPathComponent(".claude/skills/solve-task").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: zweitesRepo.appendingPathComponent(".claude/skills/solve-task").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: zweitesRepo.appendingPathComponent(".claude/rules").path))
    }

    /// Der Wechsel des Sets räumt auf, was vom alten übrig ist — sonst stünde ein zurückgezogener
    /// Skill für immer im Projekt.
    func testSetWechselRaeumtDieAltenSymlinksWeg() throws {
        try store.syncSets(from: factory)
        store.link(try set("iwf"), toProject: repo.path, agent: .claude)
        let report = store.link(try set("swift"), toProject: repo.path, agent: .claude)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.appendingPathComponent(".claude/skills/solve-task").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.appendingPathComponent(".claude/rules/worktree.md").path))
        XCTAssertEqual(report.removed.count, 2)
        // Der gleichnamige Skill zeigt jetzt ins neue Set.
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".claude/skills/get-task/SKILL.md"),
                                  encoding: .utf8), "swift/get-task")
    }

    /// Wechselt ein Projekt den Agent, sind die Links im Ordner des alten Überbleibsel.
    func testAgentWechselRaeumtDenAnderenOrdnerWeg() throws {
        try store.syncSets(from: factory)
        store.link(try set("iwf"), toProject: repo.path, agent: .claude)
        store.link(try set("iwf"), toProject: repo.path, agent: .codex)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.appendingPathComponent(".claude/skills/get-task").path))
    }

    // MARK: Fremdes

    func testFremderZielortWirdGemeldetStattUeberschrieben() throws {
        try store.syncSets(from: factory)
        let ziel = repo.appendingPathComponent(".claude/skills/get-task")
        try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "von Hand".write(to: ziel, atomically: true, encoding: .utf8)

        let iwf = try set("iwf")
        let asset = store.assets(.skill, in: iwf)[0]
        let scope = ClaudeLinkScope.project(repoDir: repo.path, agent: .claude)
        guard case .foreign = store.symlinkState(for: asset, scope: scope) else {
            return XCTFail("eine echte Datei am Zielort muss als fremd gelten")
        }
        let report = store.link(iwf, toProject: repo.path, agent: .claude)
        XCTAssertEqual(report.foreign.count, 1)
        XCTAssertEqual(try String(contentsOf: ziel, encoding: .utf8), "von Hand")
        // Der Rest des Sets liegt trotzdem da — ein belegter Zielort blockiert nicht alles.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repo.appendingPathComponent(".claude/skills/solve-task").path))
        guard case .foreign = store.state(of: iwf, scope: scope) else {
            return XCTFail("der Set-Zustand muss den belegten Zielort zeigen")
        }
    }

    /// Ein fremder Symlink (auf etwas ausserhalb unseres Bestands) ist genauso tabu wie eine Datei.
    func testFremderSymlinkBleibtLiegen() throws {
        try store.syncSets(from: factory)
        let fremd = repo.deletingLastPathComponent().appendingPathComponent("woanders")
        try FileManager.default.createDirectory(at: fremd, withIntermediateDirectories: true)
        let ziel = repo.appendingPathComponent(".claude/skills/get-task")
        try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: ziel, withDestinationURL: fremd)

        store.link(try set("iwf"), toProject: repo.path, agent: .claude)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: ziel.path),
                       fremd.path)
    }

    // MARK: Agent-Homes und das alte Modell

    func testStandardSetLandetInBeidenHomes() throws {
        try store.syncSets(from: factory)
        store.link(try set("iwf"), toHomes: AgentKind.allCases)
        for home in [userDir!, codexDir!] {
            XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("skills/get-task/SKILL.md"),
                                      encoding: .utf8), "iwf/get-task")
        }
        // Rules haben im Home keinen Ort — dort gibt es nichts, worauf ein Skill zeigen könnte.
        XCTAssertNil(store.symlinkTarget(for: store.assets(.rule, in: try set("iwf"))[0],
                                         scope: .home(.claude)))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: userDir.appendingPathComponent("rules").path))
    }

    /// Ein Symlink aus dem alten flachen Modell (`claude/skills/<name>`) zeigt in unseren Bestand —
    /// er wird umgehängt, nicht als fremd gemeldet. Sonst wäre `/get-task` nach dem Umbau weg.
    func testAlteHomeSymlinksWerdenAufDasStandardSetUmgehaengt() throws {
        let alt = root.appendingPathComponent("skills/get-task", isDirectory: true)
        try FileManager.default.createDirectory(at: alt, withIntermediateDirectories: true)
        try "alter Bestand".write(to: alt.appendingPathComponent("SKILL.md"),
                                  atomically: true, encoding: .utf8)
        let link = userDir.appendingPathComponent("skills/get-task")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: alt)

        try store.syncSets(from: factory)
        let iwf = try set("iwf")
        XCTAssertEqual(store.symlinkState(for: store.assets(.skill, in: iwf)[0],
                                          scope: .home(.claude)),
                       .otherSet(alt.path))
        store.link(iwf, toHomes: [.claude])
        XCTAssertEqual(try String(contentsOf: link.appendingPathComponent("SKILL.md"),
                                  encoding: .utf8), "iwf/get-task")
    }

    // MARK: Auflösung

    func testProjektSetSonstStandardSet() throws {
        try store.syncSets(from: factory)
        XCTAssertEqual(store.resolve(skillSet: "swift", default: "iwf").set?.name, "swift")
        XCTAssertEqual(store.resolve(skillSet: nil, default: "iwf").set?.name, "iwf")
        XCTAssertEqual(store.resolve(skillSet: "", default: "iwf").set?.name, "iwf")
    }

    /// Ein Set, das es nicht (mehr) gibt: das Standard-Set greift, aber der Name bleibt sichtbar —
    /// sonst arbeitete ein Projekt stillschweigend mit fremden Skills.
    func testFehlendesSetFaelltAufDasStandardSetZurueckUndSagtEs() throws {
        try store.syncSets(from: factory)
        let auflösung = store.resolve(skillSet: "gibts-nicht", default: "iwf")
        XCTAssertEqual(auflösung.set?.name, "iwf")
        XCTAssertEqual(auflösung.missingName, "gibts-nicht")
    }

    /// Ohne Eintrag gilt das einzige vorhandene Set.
    func testOhneStandardSetGiltDasEinzige() throws {
        try FileManager.default.removeItem(at: factory.appendingPathComponent("sets/swift"))
        try store.syncSets(from: factory)
        XCTAssertEqual(store.defaultSet(configured: nil)?.name, "iwf")
        XCTAssertNil(ClaudeAssetStore(canonicalRoot: root.appendingPathComponent("leer"))
            .defaultSet(configured: nil))
    }
}
