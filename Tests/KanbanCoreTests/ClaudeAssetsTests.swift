import XCTest
@testable import KanbanCore

final class ClaudeAssetsTests: XCTestCase {
    private var setsRoot: URL!     // der gepflegte Ordner (im Betrieb: das Kanban-Repo)
    private var legacyRoot: URL!   // der alte flache Bestand aus dem Modell vor den Sets
    private var userDir: URL!      // ~/.claude-Ersatz
    private var codexDir: URL!     // ~/.codex-Ersatz
    private var repo: URL!         // Projekt-Repo

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudeAssetsTests-\(UUID().uuidString)")
        setsRoot = base.appendingPathComponent("kanban/Sources/Kanban/Resources/ClaudeAssets/sets")
        legacyRoot = base.appendingPathComponent("altbestand")
        userDir = base.appendingPathComponent("dotclaude")
        codexDir = base.appendingPathComponent("dotcodex")
        repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        try lege("iwf", skills: ["get-task", "solve-task"], rules: ["worktree"],
                 beschreibung: "Der volle iwf-Satz.")
        try lege("swift", skills: ["get-task"], rules: [])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: setsRoot.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent())
    }

    /// Ein Set anlegen — so, wie es im Repo gepflegt daliegt.
    private func lege(_ name: String, skills: [String], rules: [String],
                      beschreibung: String? = nil) throws {
        let set = setsRoot.appendingPathComponent(name, isDirectory: true)
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
        ClaudeAssetStore(setsRoot: setsRoot, legacyRoot: legacyRoot,
                         userClaudeDir: userDir, userCodexDir: codexDir)
    }

    private func set(_ name: String) throws -> ClaudeAssetSet {
        try XCTUnwrap(store.set(named: name))
    }

    // MARK: Inventar

    func testSetInventarAusDemGepflegtenOrdner() throws {
        XCTAssertTrue(store.setsRootExists)
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

    /// Ein verschobenes oder nie ausgechecktes Repo ist der Preis der direkten Verlinkung — es darf
    /// nicht in einen Absturz laufen, sondern muss benennbar sein.
    func testFehlenderSetsOrdnerIstKeinFehler() {
        let leer = ClaudeAssetStore(setsRoot: setsRoot.appendingPathComponent("gibts-nicht"))
        XCTAssertFalse(leer.setsRootExists)
        XCTAssertTrue(leer.sets().isEmpty)
        XCTAssertNil(leer.defaultSet(configured: nil))
    }

    /// In einem gewachsenen Ordner liegt allerlei herum. Nichts davon ist ein Set, nur weil es ein
    /// Ordner ist — weder ein Backup-Ordner ohne `skills/` noch eine Datei noch `.versions`.
    func testFremdeOrdnerSindKeineSets() throws {
        let fm = FileManager.default
        for müll in ["skills-backup-2026-08-20", "projektkopien-backup-2026-08-07", ".versions"] {
            try fm.createDirectory(at: setsRoot.appendingPathComponent(müll),
                                   withIntermediateDirectories: true)
        }
        try "zip".write(to: setsRoot.appendingPathComponent("Christian_RULES_SKILLS_v2.zip"),
                        atomically: true, encoding: .utf8)
        XCTAssertEqual(store.sets().map(\.name), ["iwf", "swift"])
    }

    // MARK: Kein Zwischenstand

    /// Der Kern des Modells: verlinkt wird auf den **gepflegten** Ordner. Eine Änderung dort ist
    /// sofort im Projekt zu lesen — ohne Sync, ohne Neustart, ohne zweite Kopie.
    func testAenderungAmGepflegtenOrdnerWirktSofortImProjekt() throws {
        store.link(try set("iwf"), toProject: repo.path, agent: .claude)
        let imProjekt = repo.appendingPathComponent(".claude/skills/get-task/SKILL.md")
        XCTAssertEqual(try String(contentsOf: imProjekt, encoding: .utf8), "iwf/get-task")

        try "frisch editiert".write(to: setsRoot.appendingPathComponent("iwf/skills/get-task/SKILL.md"),
                                    atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: imProjekt, encoding: .utf8), "frisch editiert")

        // Und eine neue Beiwerk-Datei reist mit: der Symlink zeigt auf das Verzeichnis.
        try "Methodik".write(to: setsRoot.appendingPathComponent("iwf/skills/get-task/methodology.md"),
                             atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".claude/skills/get-task/methodology.md"),
                                  encoding: .utf8), "Methodik")
    }

    // MARK: Verlinkung ins Projekt

    func testSetLandetImProjektOrdner() throws {
        let report = store.link(try set("iwf"), toProject: repo.path, agent: .claude)
        XCTAssertTrue(report.isComplete)

        // Skills in .claude/skills, Rules in .claude/rules — und die Links tragen wirklich Inhalt.
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".claude/skills/get-task/SKILL.md"),
                                  encoding: .utf8), "iwf/get-task")
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".claude/rules/worktree.md"),
                                  encoding: .utf8), "iwf/worktree")
        XCTAssertEqual(store.state(of: try set("iwf"),
                                   scope: .project(repoDir: repo.path, agent: .claude)), .linked)
        // Der Symlink zeigt auf den gepflegten Ordner, nicht auf eine Kopie. Verglichen wird
        // aufgelöst: unter macOS ist `/var` selbst ein Symlink auf `/private/var`.
        let ziel = try FileManager.default.destinationOfSymbolicLink(
            atPath: repo.appendingPathComponent(".claude/skills/get-task").path)
        XCTAssertEqual(URL(fileURLWithPath: ziel).resolvingSymlinksInPath().path,
                       setsRoot.appendingPathComponent("iwf/skills/get-task")
                           .resolvingSymlinksInPath().path)
    }

    /// Ein Codex-Projekt bekommt seine Skills in `.codex/skills` — die Rules aber trotzdem nach
    /// `.claude/rules`: die Skills verweisen im Text auf `.claude/rules/…`, und dieser Pfad muss
    /// unter beiden Agents aufgehen (dieselbe Überlegung wie bei `.claude/project.json`).
    func testCodexProjektBekommtSkillsInCodexUndRulesInClaude() throws {
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
        store.link(try set("iwf"), toProject: repo.path, agent: .claude)
        store.link(try set("iwf"), toProject: repo.path, agent: .codex)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repo.appendingPathComponent(".claude/skills/get-task").path))
    }

    // MARK: Fremdes

    func testFremderZielortWirdGemeldetStattUeberschrieben() throws {
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

    /// Ein fremder Symlink (auf etwas, das uns nicht gehört) ist genauso tabu wie eine Datei.
    func testFremderSymlinkBleibtLiegen() throws {
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

    /// Ein Symlink aus dem alten flachen Modell (`<Application Support>/Kanban/claude/skills/<n>`)
    /// gehört uns — er wird umgehängt, nicht als fremd gemeldet. Sonst wäre `/get-task` mit dem
    /// Umbau eingefroren.
    func testAlteHomeSymlinksWerdenAufDasStandardSetUmgehaengt() throws {
        let alt = legacyRoot.appendingPathComponent("skills/get-task", isDirectory: true)
        try FileManager.default.createDirectory(at: alt, withIntermediateDirectories: true)
        try "alter Bestand".write(to: alt.appendingPathComponent("SKILL.md"),
                                  atomically: true, encoding: .utf8)
        let link = userDir.appendingPathComponent("skills/get-task")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: alt)

        let iwf = try set("iwf")
        XCTAssertEqual(store.symlinkState(for: store.assets(.skill, in: iwf)[0],
                                          scope: .home(.claude)),
                       .otherSet(alt.path))
        store.link(iwf, toHomes: [.claude])
        XCTAssertEqual(try String(contentsOf: link.appendingPathComponent("SKILL.md"),
                                  encoding: .utf8), "iwf/get-task")
        // Der alte Bestand selbst bleibt liegen — gelöscht wird nur der Symlink.
        XCTAssertTrue(FileManager.default.fileExists(atPath: alt.path))
    }

    // MARK: Auflösung

    func testProjektSetSonstStandardSet() throws {
        XCTAssertEqual(store.resolve(skillSet: "swift", default: "iwf").set?.name, "swift")
        XCTAssertEqual(store.resolve(skillSet: nil, default: "iwf").set?.name, "iwf")
        XCTAssertEqual(store.resolve(skillSet: "", default: "iwf").set?.name, "iwf")
    }

    /// Ein Set, das es nicht (mehr) gibt: das Standard-Set greift, aber der Name bleibt sichtbar —
    /// sonst arbeitete ein Projekt stillschweigend mit fremden Skills.
    func testFehlendesSetFaelltAufDasStandardSetZurueckUndSagtEs() throws {
        let auflösung = store.resolve(skillSet: "gibts-nicht", default: "iwf")
        XCTAssertEqual(auflösung.set?.name, "iwf")
        XCTAssertEqual(auflösung.missingName, "gibts-nicht")
    }

    /// Ohne Eintrag gilt das einzige vorhandene Set.
    func testOhneStandardSetGiltDasEinzige() throws {
        try FileManager.default.removeItem(at: setsRoot.appendingPathComponent("swift"))
        XCTAssertEqual(store.defaultSet(configured: nil)?.name, "iwf")
    }

    /// Ohne Eintrag in der Config liegen die Sets im Kanban-Repo unter dem Basis-Pfad — eine
    /// Konvention, die überschreibbar bleibt.
    func testVorgabePfadZeigtInsKanbanRepo() {
        XCTAssertEqual(ClaudeAssetStore.defaultSetsRoot(basePath: "/Users/x/code").path,
                       "/Users/x/code/kanban/Sources/Kanban/Resources/ClaudeAssets/sets")
    }
}
