import XCTest
@testable import KanbanCore

final class StackSweepTests: XCTestCase {
    /// Echte Lage der Maschine, auf der das Feature entstand: zwei volle Stacks, mehrere Stacks mit
    /// nur noch einem übrigen fpm-Container, und das Haupt-Repo auf einem Feature-Branch.
    private let running = [
        "even-3675-nginx", "even-3675-fpm", "even-3675-db",
        "even-3563-nginx", "even-3563-fpm",
        "even-3689-fpm",
        "even-3251-fpm",
        "even-nginx", "even-fpm", "even-db",
        "traefik", "dns",
    ]

    private let worktrees = [
        Worktree(path: "/code/even", branch: "refactor/EVEN-0002_rule_engine"),
        Worktree(path: "/code/even-worktree/even-3675", branch: "feature/EVEN-3675_comment_field"),
        Worktree(path: "/code/even-worktree/even-3563", branch: "feature/EVEN-3563_pdf_export"),
        Worktree(path: "/code/even-worktree/even-3689", branch: "feature/EVEN-3689_thing"),
        Worktree(path: "/code/even-worktree/even-3251", branch: "feature/EVEN-3251_other"),
        Worktree(path: "/code/even-worktree/even-3512", branch: "feature/EVEN-3512_stopped"),
    ]

    private let volumes = [
        "even-3675_dbdata", "even-3675_appcache",
        "even-3563_dbdata", "even-3563_appcache",
        "even-3689_dbdata",
        "even_dbdata",                 // Haupt-Repo
        "even-35630_dbdata",           // fremder Stack, dessen Name mit even-3563 anfängt
    ]
    private let imageTags = [
        "local/even-3675:latest", "local/even-3675-base:latest",
        "local/even-3563:latest", "local/even-3563-base:latest",
        "local/even:latest", "local/even-base:latest",
        "local/even-35630:latest",
    ]

    private func plan(cards: [StackSweepCard], dumps: [String: String] = [:]) -> StackSweepPlan {
        StackSweep.plan(cards: cards, worktrees: worktrees, repoDir: "/code/even",
                        runningContainers: running, projectName: "even",
                        volumes: volumes, imageTags: imageTags, stagedDumps: dumps)
    }

    private var dumpsForAll: [String: String] {
        Dictionary(uniqueKeysWithValues: worktrees.map { ($0.path, "even_dev.sql.gz") })
    }

    func testOnlyStacksWithRunningContainersAreCandidates() {
        // even-3512 hat einen Worktree, aber keinen laufenden Container — nichts abzuräumen.
        let names = plan(cards: []).candidates.map(\.stackName)
        XCTAssertEqual(names, ["even-3251", "even-3563", "even-3675", "even-3689"])
    }

    /// Der wichtigste Fall überhaupt: das Haupt-Repo steht auf `refactor/EVEN-0002_rule_engine`, ein
    /// Ticket-Branch. Ohne die Ausnahme wäre `even-*` ein Kandidat — und ein Sweep würde den
    /// Haupt-Stack abschiessen.
    func testTheMainRepoIsNeverACandidate() {
        let cards = [StackSweepCard(key: "EVEN-0002", column: .done, isWorking: false)]
        XCTAssertFalse(plan(cards: cards).candidates.contains { $0.stackName == "even" })
    }

    func testEinzelnerUebrigerContainerZaehlt() {
        let candidate = plan(cards: []).candidates.first { $0.stackName == "even-3689" }
        XCTAssertEqual(candidate?.runningContainers, 1)
    }

    func testReviewUndDoneSindVorgewaehlt() {
        let cards = [
            StackSweepCard(key: "EVEN-3675", column: .review, isWorking: false),
            StackSweepCard(key: "EVEN-3563", column: .done, isWorking: false),
            StackSweepCard(key: "EVEN-3689", column: .inBearbeitung, isWorking: false),
        ]
        XCTAssertEqual(plan(cards: cards).preselected, ["even-3675", "even-3563"])
    }

    /// Ein laufender Turn hält den Stack: die Session arbeitet noch, auch wenn die Spalte „fertig" sagt.
    func testEinLaufenderTurnHaeltDenStack() {
        let cards = [StackSweepCard(key: "EVEN-3675", column: .review, isWorking: true)]
        let candidate = plan(cards: cards).candidates.first { $0.stackName == "even-3675" }
        XCTAssertEqual(candidate?.isFinished, true)          // sichtbar als fertig
        XCTAssertEqual(candidate?.isPreselected, false)      // aber nicht vorgewählt
    }

    func testStacksOhneKarteBleibenOhneSpalte() {
        // Sprint-Modus: EVEN-3251 liegt in einem alten Sprint, also auf keiner Karte. Geraten wird
        // nicht — ohne Spalte ist der Stack sichtbar, aber nicht vorgewählt.
        let candidate = plan(cards: []).candidates.first { $0.stackName == "even-3251" }
        XCTAssertNil(candidate?.column)
        XCTAssertNil(candidate?.ticketKey)
        XCTAssertEqual(candidate?.isPreselected, false)
    }

    func testDieNummerKommtAusDemOrdnernamen() {
        XCTAssertEqual(plan(cards: []).candidates.first { $0.stackName == "even-3675" }?.number, "3675")
    }

    /// Zuordnung über den Ordnernamen, wenn der Worktree keinen Branch hat (Detached Head).
    func testWorktreeOhneBranchWirdUeberDenOrdnerZugeordnet() {
        let plan = StackSweep.plan(
            cards: [StackSweepCard(key: "EVEN-3675", column: .review, isWorking: false)],
            worktrees: [Worktree(path: "/code/even-worktree/even-3675", branch: nil)],
            repoDir: "/code/even", runningContainers: ["even-3675-fpm"], projectName: "even")
        XCTAssertEqual(plan.candidates.first?.ticketKey, "EVEN-3675")
    }

    /// EVEN-351 darf nicht auf `even-3512` passen — dieselbe Falle wie bei den Board-Spalten.
    func testTeilnummernPassenNicht() {
        let plan = StackSweep.plan(
            cards: [StackSweepCard(key: "EVEN-351", column: .done, isWorking: false)],
            worktrees: [Worktree(path: "/code/even-worktree/even-3512", branch: "feature/EVEN-3512_x")],
            repoDir: "/code/even", runningContainers: ["even-3512-fpm"], projectName: "even")
        XCTAssertNil(plan.candidates.first?.ticketKey)
    }

    /// Container-Präfixe zählen mit Bindestrich: `even-356-` trifft `even-3563-fpm` nicht.
    func testStackPraefixIstNichtMehrdeutig() {
        let plan = StackSweep.plan(
            cards: [], worktrees: [Worktree(path: "/code/even-worktree/even-356", branch: nil)],
            repoDir: "/code/even", runningContainers: ["even-3563-fpm"], projectName: "even")
        XCTAssertTrue(plan.candidates.isEmpty)
    }

    func testWaisenWerdenBenanntAberNichtAngefasst() {
        // even-3999 läuft, hat aber keinen Worktree — `iwf worktree stop` greift dort nicht.
        let plan = StackSweep.plan(
            cards: [], worktrees: worktrees, repoDir: "/code/even",
            runningContainers: running + ["even-3999-fpm"], projectName: "even")
        XCTAssertEqual(plan.orphanStacks, ["even-3999"])
        XCTAssertFalse(plan.candidates.contains { $0.stackName == "even-3999" })
    }

    /// Der Haupt-Stack (`even-fpm`) und die geteilte Infrastruktur (`traefik`, `dns`) sind keine
    /// Waisen — sie haben kein `<projekt>-<zahl>`-Muster.
    func testHauptStackUndRouterSindKeineWaisen() {
        XCTAssertTrue(plan(cards: []).orphanStacks.isEmpty)
    }
}

// MARK: - Tiefe Stufe (Volumes + Images)

extension StackSweepTests {
    private func candidate(_ name: String, dumps: [String: String] = [:]) -> StackSweepCandidate? {
        plan(cards: [], dumps: dumps).candidates.first { $0.stackName == name }
    }

    /// Beide Volumes, nicht nur `_dbdata`: das `appcache`-Volume ist auf dieser Maschine das
    /// grössere (24,1 GB in 41 Stücken gegen 9,9 GB) — geratene Namen hätten es liegen lassen.
    func testBeideVolumesGehoerenZumStack() {
        XCTAssertEqual(candidate("even-3675")?.volumes, ["even-3675_appcache", "even-3675_dbdata"])
    }

    /// Auch das `-base`-Image — genau das, was iwfs eigenes `worktree destroy` stehen lässt.
    func testBasisImageGehoertDazu() {
        XCTAssertEqual(candidate("even-3675")?.imageTags,
                       ["local/even-3675-base:latest", "local/even-3675:latest"])
    }

    /// `even-3563` darf `even-35630` nicht mitnehmen — bei Volumes trennt der Unterstrich, bei
    /// Images der Bindestrich.
    func testFremderStackMitGleichemPraefixBleibtVerschont() {
        XCTAssertFalse(candidate("even-3563")?.volumes.contains("even-35630_dbdata") ?? true)
        XCTAssertFalse(candidate("even-3563")?.imageTags.contains("local/even-35630:latest") ?? true)
    }

    func testOhneDumpKeinTiefesAbraeumen() {
        XCTAssertEqual(candidate("even-3675")?.canDeepClean, false)
        XCTAssertEqual(candidate("even-3675", dumps: dumpsForAll)?.canDeepClean, true)
    }

    /// Ein Stack ohne Volumes und ohne Image hat nichts zu löschen — dann ist „tief" keine Option,
    /// auch mit Dump.
    func testOhneArtefakteKeinTiefesAbraeumen() {
        let plan = StackSweep.plan(
            cards: [], worktrees: [Worktree(path: "/code/even-worktree/even-3689", branch: nil)],
            repoDir: "/code/even", runningContainers: ["even-3689-fpm"], projectName: "even",
            volumes: [], imageTags: [],
            stagedDumps: ["/code/even-worktree/even-3689": "even_dev.sql.gz"])
        XCTAssertEqual(plan.candidates.first?.canDeepClean, false)
    }

    func testDieBefehleDerTiefenStufe() {
        let target = candidate("even-3675", dumps: dumpsForAll)!
        XCTAssertEqual(StackSweep.deepCleanCommands(target), [
            "docker volume rm 'even-3675_appcache' 'even-3675_dbdata'",
            "docker image rm 'local/even-3675-base:latest' 'local/even-3675:latest'",
        ])
    }

    /// Leere Listen ergeben keinen Befehl — ein `docker volume rm` ohne Argumente wäre nur ein
    /// Fehler im Log.
    func testKeinBefehlOhneArtefakte() {
        let bare = StackSweepCandidate(stackName: "even-1", number: "1", worktreePath: "/x",
                                       ticketKey: nil, column: nil, runningContainers: 1,
                                       isWorking: false)
        XCTAssertTrue(StackSweep.deepCleanCommands(bare).isEmpty)
    }

    /// Das Haupt-Repo-Volume/-Image darf nirgends auftauchen — `even_dbdata` beginnt nicht mit
    /// `even-3675_`, `local/even:latest` ist nicht `local/even-3675`.
    func testHauptRepoArtefakteTauchenNichtAuf() {
        for c in plan(cards: [], dumps: dumpsForAll).candidates {
            XCTAssertFalse(c.volumes.contains("even_dbdata"), c.stackName)
            XCTAssertFalse(c.imageTags.contains("local/even:latest"), c.stackName)
            XCTAssertFalse(c.imageTags.contains("local/even-base:latest"), c.stackName)
        }
    }
}
