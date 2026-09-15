import XCTest
@testable import KanbanCore

final class LocalTicketsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-tickets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ content: String) throws {
        try content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func discover(worktrees: [Worktree] = [], mrs: [MergeRequestRef] = []) -> [Ticket] {
        LocalTickets.discover(tasksDirectory: dir.path, prefix: "EVEN",
                              worktrees: worktrees, mergeRequests: mrs)
    }

    // MARK: - Task-Files

    /// Der Normalfall: Key aus dem Dateinamen, Titel aus der H1 — ganz ohne Jira.
    func testTicketFromTaskFile() throws {
        try write("EVEN-3687_resolve_pendenz.md", """
        <!-- kanban-claude-session: abc -->
        # EVEN-3687 - Trigger Nachtrag eingereicht

        > 🌳 **WORKTREE**: `/x`
        """)

        let tickets = discover()
        XCTAssertEqual(tickets.map(\.key), ["EVEN-3687"])
        XCTAssertEqual(tickets.first?.summary, "Trigger Nachtrag eingereicht")
    }

    /// Review-Files sind Tabs am Ticket, keine eigenen Tickets — sonst stünde jedes Review doppelt
    /// auf dem Board.
    func testReviewFilesAreNotOwnTickets() throws {
        try write("EVEN-3687_umsetzung.md", "# EVEN-3687 - Titel")
        try write("EVEN-3687_review.md", "# Code-Review: EVEN-3687")

        XCTAssertEqual(discover().map(\.key), ["EVEN-3687"])
    }

    /// Fremde Dateien im Ordner bleiben draussen: falsches Präfix, kein Key, oder der Key steht
    /// mitten im Namen.
    func testIgnoresForeignFiles() throws {
        try write("EVEN-1_a.md", "# EVEN-1 - Eins")
        try write("ZBA-9_fremd.md", "# ZBA-9 - Fremdes Projekt")
        try write("notizen.md", "# Notizen")
        try write("notiz_zu_EVEN-2.md", "# Notiz")
        try write("EVEN-3.txt", "kein Markdown")

        XCTAssertEqual(discover().map(\.key), ["EVEN-1"])
    }

    /// Numerisch sortiert, nicht lexikografisch — sonst stünde EVEN-999 hinter EVEN-1000.
    func testSortedNumerically() throws {
        for number in [7, 1000, 999, 42] {
            try write("EVEN-\(number)_x.md", "# EVEN-\(number) - T\(number)")
        }
        XCTAssertEqual(discover().map(\.key), ["EVEN-7", "EVEN-42", "EVEN-999", "EVEN-1000"])
    }

    // MARK: - Worktrees und MRs

    /// Ein Branch ohne Task-File ist trotzdem Arbeit und gehört aufs Board.
    func testWorktreeWithoutTaskFile() {
        let tickets = discover(worktrees: [
            Worktree(path: "/x/even-4711", branch: "feature/EVEN-4711_neuer_kram"),
            Worktree(path: "/x/even", branch: "develop"),
        ])
        XCTAssertEqual(tickets.map(\.key), ["EVEN-4711"])
    }

    /// Ebenso ein MR, dessen Task-File (noch) fehlt — Key aus Branch oder Titel.
    func testMergeRequestWithoutTaskFile() {
        let mr = MergeRequestRef(iid: 651, title: "EVEN-3679 | trigger", state: "opened",
                                 sourceBranch: "feature/EVEN-3679_add", targetBranch: "develop",
                                 mergedAt: nil, webUrl: "https://x")
        XCTAssertEqual(discover(mrs: [mr]).map(\.key), ["EVEN-3679"])
    }

    /// Das Task-File gewinnt beim Titel: sein H1 ist gepflegter Text, ein Branchname ist ein Slug.
    func testTaskFileTitleWinsOverBranch() throws {
        try write("EVEN-3687_x.md", "# EVEN-3687 - Sprechender Titel")
        let tickets = discover(worktrees: [Worktree(path: "/x", branch: "feature/EVEN-3687_slug")])
        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets.first?.summary, "Sprechender Titel")
    }

    // MARK: - Karten ohne Ticketnummer (freier Modus)

    private func openMR(_ iid: Int, _ title: String, _ branch: String,
                        state: String = "opened", draft: Bool = false) -> MergeRequestRef {
        MergeRequestRef(iid: iid, title: title, state: state, sourceBranch: branch,
                        targetBranch: "develop", mergedAt: nil, webUrl: "https://x/\(iid)",
                        draft: draft)
    }

    /// Ein offener MR ohne `<PREFIX>-<zahl>` fiel bisher ganz vom Brett — genau die Arbeit, aus der
    /// man im freien Modus noch einen Task machen will. Der Key ist GitLabs eigene MR-Schreibweise.
    func testAnOpenMergeRequestWithoutATicketNumberBecomesACard() {
        let tickets = discover(mrs: [openMR(130, "Frontend-Testing", "feature/playwright")])
        XCTAssertEqual(tickets.map(\.key), ["!130"])
        XCTAssertEqual(tickets.first?.summary, "Frontend-Testing")
        XCTAssertEqual(tickets.first?.sourceBranch, "feature/playwright")
        XCTAssertTrue(tickets.first?.isBranchOnly ?? false)
    }

    /// **Nur offene.** Ein gemergter MR ohne Nummer ist erledigte Geschichte, aus der nichts mehr zu
    /// erstellen ist — in `zba` sind das 10 von 14, sie würden Done mit Altlasten füllen.
    func testMergedMergeRequestsWithoutANumberStayOut() {
        let mrs = [openMR(128, "add GitLab pipeline", "feature/pipeline", state: "merged"),
                   openMR(107, "test creation", "feature/test-creation", state: "merged")]
        XCTAssertTrue(discover(mrs: mrs).isEmpty)
    }

    /// Ein Draft ist offen und gehört dazu — die Spalte entscheidet danach die Ableitung, nicht
    /// diese Liste (er landet in „In Bearbeitung", nicht in Review).
    func testADraftIsStillListed() {
        XCTAssertEqual(discover(mrs: [openMR(133, "Draft: E2E", "feature/e2e", draft: true)])
                        .map(\.key), ["!133"])
    }

    /// Ein MR **mit** Nummer bleibt sein Ticket — er darf nicht zusätzlich als `!iid` auftauchen.
    func testANumberedMergeRequestIsNotDuplicated() {
        let tickets = discover(mrs: [openMR(651, "EVEN-3679 | trigger", "feature/EVEN-3679_add")])
        XCTAssertEqual(tickets.map(\.key), ["EVEN-3679"])
    }

    /// Die Nummer darf auch nur im Titel stehen — dann ist es ebenfalls kein Ticket ohne Nummer.
    func testTheNumberMayLiveInTheTitleAlone() {
        let tickets = discover(mrs: [openMR(77, "EVEN-42 | Umbau", "feature/umbau")])
        XCTAssertEqual(tickets.map(\.key), ["EVEN-42"])
    }

    /// Ohne Titel bleibt der Branch — eine namenlose Karte wäre nicht wiederzuerkennen.
    func testTheBranchIsTheFallbackTitle() {
        XCTAssertEqual(discover(mrs: [openMR(9, "", "feature/nur-branch")]).first?.summary,
                       "feature/nur-branch")
    }

    /// Der jüngste MR zuerst — er ist der, an dem gerade liegt.
    func testNewestFirst() {
        let tickets = discover(mrs: [openMR(3, "a", "f/a"), openMR(9, "b", "f/b"), openMR(5, "c", "f/c")])
        XCTAssertEqual(tickets.map(\.key), ["!9", "!5", "!3"])
    }

    /// Karten ohne Nummer stehen **hinter** den nummerierten, damit die gewohnte Liste vorn bleibt.
    func testNumberedTicketsComeFirst() throws {
        try write("EVEN-1_a.md", "# EVEN-1 - Eins")
        let tickets = discover(mrs: [openMR(9, "ohne Nummer", "feature/x")])
        XCTAssertEqual(tickets.map(\.key), ["EVEN-1", "!9"])
    }

    // MARK: - Titel-Parsing

    func testTitleSeparators() {
        XCTAssertEqual(LocalTickets.title(inHead: "# EVEN-1 - Mit Bindestrich"), "Mit Bindestrich")
        XCTAssertEqual(LocalTickets.title(inHead: "# EVEN-1 | Mit Pipe"), "Mit Pipe")
        XCTAssertEqual(LocalTickets.title(inHead: "# EVEN-1: Mit Doppelpunkt"), "Mit Doppelpunkt")
        XCTAssertEqual(LocalTickets.title(inHead: "# EVEN-1 – Mit Gedankenstrich"), "Mit Gedankenstrich")
        // Ohne Trenner bleibt die ganze Überschrift stehen.
        XCTAssertEqual(LocalTickets.title(inHead: "# Nur ein Titel"), "Nur ein Titel")
        // Die H1 muss nicht die erste Zeile sein (Session-Id-Kommentar davor).
        XCTAssertEqual(LocalTickets.title(inHead: "<!-- x -->\n# EVEN-1 - Titel"), "Titel")
        XCTAssertNil(LocalTickets.title(inHead: "## Nur H2\nText"))
    }

    // MARK: - Task-Files an `!<iid>`-Karten

    /// Der Grund für `!<iid>`-Task-Files: ohne sie verschwände mit dem Merge auch das Task-File samt
    /// Review vom Brett — `branchTickets` kennt nur **offene** MRs. Das File hält die Karte am Leben.
    func testATaskFileKeepsTheCardAfterTheMerge() throws {
        try write("!49_cli_version_option.md", """
        # !49 - CLI-Option --version

        > 🌿 **BRANCH**: `feature/cli-version-option`
        """)

        let tickets = discover(mrs: [openMR(49, "add --version", "feature/cli-version-option",
                                            state: "merged")])
        XCTAssertEqual(tickets.map(\.key), ["!49"])
        XCTAssertEqual(tickets.first?.summary, "CLI-Option --version")
        // Der Branch stammt aus dem Präambel-Block — nur so hängt der gemergte MR weiter an der Karte.
        XCTAssertEqual(tickets.first?.sourceBranch, "feature/cli-version-option")
        XCTAssertTrue(tickets.first?.isBranchOnly ?? false)
    }

    /// Solange der MR offen ist, dürfen File und MR **nicht** zwei Karten ergeben. Der Titel des
    /// Task-Files gewinnt, der Branch kommt weiter vom MR.
    func testTaskFileAndOpenMergeRequestAreOneCard() throws {
        try write("!49_task.md", "# !49 - Titel aus dem File")

        let tickets = discover(mrs: [openMR(49, "Titel aus dem MR", "feature/cli-version-option")])
        XCTAssertEqual(tickets.map(\.key), ["!49"])
        XCTAssertEqual(tickets.first?.summary, "Titel aus dem File")
        XCTAssertEqual(tickets.first?.sourceBranch, "feature/cli-version-option")
    }

    /// Wie bei nummerierten Tickets ist ein Review ein Tab, keine eigene Karte.
    func testMRReviewFileIsNotItsOwnCard() throws {
        try write("!49_review.md", "# Code-Review: !49")
        XCTAssertTrue(discover().isEmpty)
    }

    /// Der Key muss am Anfang stehen — sonst würde jede Notiz, die eine MR-Nummer erwähnt, zur Karte.
    func testMRKeyMustBeAnchoredAtTheStart() throws {
        try write("notiz_zu_!49.md", "# Notiz")
        XCTAssertTrue(discover().isEmpty)
    }

    /// Ohne `🌿 BRANCH`-Block bleibt die Karte bestehen, nur ohne Branch-Bezug — kein Absturz, und
    /// `isBranchOnly` stimmt weiterhin, damit das Kontextmenü „Task erstellen" zeigt.
    func testTaskFileWithoutABranchBlockStillBecomesACard() throws {
        try write("!77_ohne_branch.md", "# !77 - Ohne Branch")
        let tickets = discover()
        XCTAssertEqual(tickets.map(\.key), ["!77"])
        XCTAssertEqual(tickets.first?.sourceBranch, "")
        XCTAssertTrue(tickets.first?.isBranchOnly ?? false)
    }

    /// Auch mit Task-Files gilt: nummerierte Tickets zuerst, MR-Karten danach, jüngste zuerst.
    func testMRTaskFilesKeepTheirOrder() throws {
        try write("EVEN-1_a.md", "# EVEN-1 - Eins")
        try write("!12_alt.md", "# !12 - Alt")
        let tickets = discover(mrs: [openMR(30, "neu", "feature/neu")])
        XCTAssertEqual(tickets.map(\.key), ["EVEN-1", "!30", "!12"])
    }

    // MARK: - Sortierung

    func testTicketNumberOrdering() {
        XCTAssertTrue(TicketNumber.isAscending("EVEN-999", "EVEN-1000"))
        XCTAssertFalse(TicketNumber.isAscending("EVEN-1000", "EVEN-999"))
        XCTAssertTrue(TicketNumber.isAscending("BFEZVM-1", "EVEN-1"))
        XCTAssertTrue(TicketNumber.isAscending("even-1", "EVEN-2"))   // Gross-/Kleinschreibung egal
    }

    // MARK: - Board-Modus

    /// Ohne Sprint gibt es keine Sprint-Spalte: sie heisst „in Jira eingeplant, lokal noch nichts da".
    func testFreeModeHasNoSprintColumn() {
        XCTAssertEqual(BoardMode.sprint.columns, KanbanColumn.ordered)
        XCTAssertFalse(BoardMode.free.columns.contains(.sprint))
        XCTAssertEqual(BoardMode.free.columns, [.offen, .inBearbeitung, .review, .done])
    }
}
