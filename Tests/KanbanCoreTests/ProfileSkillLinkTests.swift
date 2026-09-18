import XCTest
@testable import KanbanCore

/// Skill-Symlinks über Profilgrenzen — die eine Stelle, an der zwei Profile denselben Ort teilen.
///
/// `~/.claude/skills` gehört keinem Profil; dort liegt das Set, das gerade gilt. Damit ein Wechsel
/// dort wirklich umhängt, muss `isOurs` die Links des **anderen** Profils als eigene erkennen —
/// sonst räumt `cleanUp` sie nicht weg, `installSymlink` findet den Zielort belegt und meldet ihn
/// als fremd, und das neue Profil bekäme gar keine Skills, während sichtbar die des alten
/// stehenblieben. Bei Namensgleichheit sticht die User-Ebene die Projektebene, es sähe also auch
/// jedes Projekt weiter die alten.
final class ProfileSkillLinkTests: XCTestCase {
    private var global: URL!        // der globale Datenordner (= Ordner des Vorgabe-Profils)
    private var privatOrdner: URL!  // ein zweites Profil
    private var userDir: URL!       // ~/.claude-Ersatz
    private var codexDir: URL!      // ~/.codex-Ersatz

    override func setUpWithError() throws {
        let basis = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileSkillLinkTests-\(UUID().uuidString)", isDirectory: true)
        global = basis.appendingPathComponent("Kanban", isDirectory: true)
        privatOrdner = global.appendingPathComponent("profiles/privat", isDirectory: true)
        userDir = basis.appendingPathComponent("dotclaude", isDirectory: true)
        codexDir = basis.appendingPathComponent("dotcodex", isDirectory: true)
        try FileManager.default.createDirectory(at: privatOrdner, withIntermediateDirectories: true)

        try legeSet(in: global, name: "arbeitsset", skill: "solve-task")
        try legeSet(in: privatOrdner, name: "privatset", skill: "eigener-skill")

        KanbanPaths.setGlobalRoot(global)
        KanbanPaths.reset()
    }

    override func tearDownWithError() throws {
        KanbanPaths.setGlobalRoot(nil)
        KanbanPaths.reset()
        try? FileManager.default.removeItem(at: global.deletingLastPathComponent())
    }

    /// Ein Set im `claude/`-Ordner eines Profils.
    private func legeSet(in profilOrdner: URL, name: String, skill: String) throws {
        let dir = profilOrdner
            .appendingPathComponent("claude/\(name)/skills/\(skill)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "\(name)/\(skill)".write(to: dir.appendingPathComponent("SKILL.md"),
                                     atomically: true, encoding: .utf8)
    }

    private func store(fuer profilOrdner: URL, formerRoots: [URL]) -> ClaudeAssetStore {
        ClaudeAssetStore(setsRoot: profilOrdner.appendingPathComponent("claude", isDirectory: true),
                         legacyRoot: ClaudeAssetStore.defaultLegacyRoot,
                         formerRoots: formerRoots,
                         userClaudeDir: userDir, userCodexDir: codexDir)
    }

    private var verlinkteSkills: [String] {
        let dir = userDir.appendingPathComponent("skills", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    /// Der Wechsel hängt wirklich um: die Skills des alten Profils verschwinden, die des neuen
    /// stehen da.
    func testWechselHaengtDieSkillsDesAnderenProfilsUm() throws {
        let arbeit = store(fuer: global, formerRoots: [])
        let arbeitsset = try XCTUnwrap(arbeit.sets().first)
        arbeit.link(arbeitsset, toHomes: [.claude])
        XCTAssertEqual(verlinkteSkills, ["solve-task"])

        let privat = store(fuer: privatOrdner,
                           formerRoots: [global.appendingPathComponent("claude", isDirectory: true)])
        let privatset = try XCTUnwrap(privat.sets().first)
        privat.link(privatset, toHomes: [.claude])

        XCTAssertEqual(verlinkteSkills, ["eigener-skill"],
                       "Der Skill des alten Profils muss verschwinden, sonst überdeckt er den neuen")
    }

    /// **Zurück** ins Vorgabe-Profil — die Richtung, auf die es wirklich ankommt.
    ///
    /// Andersherum trägt schon `legacyRoot`: der `claude/`-Ordner des Vorgabe-Profils **ist** der
    /// alte flache Bestand, seine Links gelten also ohnehin als unsere. Ein Link, den ein zweites
    /// Profil gelegt hat, liegt dagegen unter `profiles/<slug>/claude` — den kennt ohne
    /// `formerRoots` niemand.
    func testZurueckInsVorgabeProfilRaeumtDieLinksDesAnderenWeg() throws {
        let privat = store(fuer: privatOrdner, formerRoots: [])
        privat.link(try XCTUnwrap(privat.sets().first), toHomes: [.claude])
        XCTAssertEqual(verlinkteSkills, ["eigener-skill"])

        let arbeit = store(fuer: global,
                           formerRoots: [privatOrdner.appendingPathComponent("claude",
                                                                             isDirectory: true)])
        arbeit.link(try XCTUnwrap(arbeit.sets().first), toHomes: [.claude])

        XCTAssertEqual(verlinkteSkills, ["solve-task"])
    }

    /// Die Gegenprobe dazu: **ohne** die Wurzel des anderen Profils bleibt dessen Link stehen und
    /// überdeckt weiter. Damit ist belegt, dass `formerRoots` die Ursache ist und nicht ein
    /// Nebeneffekt von `legacyRoot`.
    func testOhneDieWurzelDesAnderenProfilsBleibtDessenLinkStehen() throws {
        let privat = store(fuer: privatOrdner, formerRoots: [])
        privat.link(try XCTUnwrap(privat.sets().first), toHomes: [.claude])
        XCTAssertEqual(verlinkteSkills, ["eigener-skill"])

        let arbeitOhneWissen = store(fuer: global, formerRoots: [])
        arbeitOhneWissen.link(try XCTUnwrap(arbeitOhneWissen.sets().first), toHomes: [.claude])

        XCTAssertEqual(verlinkteSkills, ["eigener-skill", "solve-task"])
    }

    /// Ein Profil **ohne** Set muss die Links des vorigen trotzdem wegräumen — sonst bliebe dessen
    /// Satz liegen und gälte weiter. `linkDefaultSetIntoHomes` stieg dafür früher einfach aus.
    func testEinProfilOhneSetRaeumtDieAltenLinksWeg() throws {
        let arbeit = store(fuer: global, formerRoots: [])
        arbeit.link(try XCTUnwrap(arbeit.sets().first), toHomes: [.claude])
        XCTAssertEqual(verlinkteSkills, ["solve-task"])

        let leeresProfil = global.appendingPathComponent("profiles/leer", isDirectory: true)
        let ohneSet = store(fuer: leeresProfil,
                            formerRoots: [global.appendingPathComponent("claude",
                                                                        isDirectory: true)])
        XCTAssertNil(ohneSet.defaultSet(configured: nil))
        ohneSet.unlinkHomes([.claude])

        XCTAssertEqual(verlinkteSkills, [])
    }

    /// Fremdes bleibt fremd: ein Symlink, der irgendwo anders hinzeigt, wird nie angefasst.
    func testFremdeVerknuepfungenBleibenUnangetastet() throws {
        let fremd = global.deletingLastPathComponent()
            .appendingPathComponent("woanders/skills/fremder-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: fremd, withIntermediateDirectories: true)
        let skills = userDir.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: skills.appendingPathComponent("fremder-skill"), withDestinationURL: fremd)

        let privat = store(fuer: privatOrdner,
                           formerRoots: [global.appendingPathComponent("claude", isDirectory: true)])
        privat.link(try XCTUnwrap(privat.sets().first), toHomes: [.claude])

        XCTAssertEqual(verlinkteSkills, ["eigener-skill", "fremder-skill"])
    }

    /// Die Wurzeln der anderen Profile kommen aus `profiles.json` — nicht aus einer zweiten Liste,
    /// die jemand pflegen müsste.
    func testDieWurzelnDerAnderenProfileStammenAusDerProfilliste() throws {
        ProfileStore.migrateIfNeeded()
        let privat = try ProfileStore.create(name: "Privat")

        let ausSichtDerArbeit = ClaudeAssetStore.otherProfileSetsRoots().map(\.path)
        XCTAssertEqual(ausSichtDerArbeit,
                       [privat.folder.appendingPathComponent("claude").path])

        try ProfileStore.activate(slug: privat.slug)
        let ausSichtVonPrivat = ClaudeAssetStore.otherProfileSetsRoots().map(\.path)
        XCTAssertEqual(ausSichtVonPrivat,
                       [global.appendingPathComponent("claude").path])
    }
}
