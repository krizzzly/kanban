import Foundation
import KanbanCore

/// Headless end-to-end check (run via `Kanban --selftest [--project <key>]`): exercises the full
/// pipeline against live data — config → board → sprint → issues → MRs → worktrees → status engine —
/// and prints the resulting column distribution. Exits the process; the UI never starts.
enum SelfTest {
    static func runAndExit() -> Never {
        Task.detached { exit(await run()) }
        dispatchMain()  // keep the process alive (Never) until the detached task calls exit()
    }

    static func run() async -> Int32 {
        do {
            HermesImport.runIfNeeded()
            let cfg = try KanbanConfig.load()
            print("✓ Config \(KanbanConfig.path): \(cfg.projects.count) Projekte, "
                  + "gitlab=\(cfg.hasGitlab), github=\(cfg.hasGithub)")

            let wanted = argValue("--project")
            guard let project = cfg.projects.first(where: { $0.key == wanted }) ?? cfg.projects.first else {
                print("✗ kein Projekt in der Config"); return 1
            }
            print("→ Projekt \(project.key) (\(project.prefix)) @ \(project.jiraBaseUrl)")
            print("  tasksPath = \(project.tasksPathAbsolute)")
            print("  repoDir   = \(project.repoDir)")
            print("  forge     = \(project.forge.map { "\($0.kind.label) \($0.path)" } ?? "—")")

            let jira = JiraClient(config: cfg)
            guard let board = try await jira.board(prefix: project.prefix, baseUrl: project.jiraBaseUrl) else {
                print("✗ kein Board für \(project.prefix)"); return 1
            }
            print("✓ Board #\(board.id) \"\(board.name)\" [\(board.type ?? "?")]")

            let sprints = try await jira.sprints(boardId: board.id, baseUrl: project.jiraBaseUrl,
                                                 states: "active,future,closed")
            print("✓ \(sprints.count) Sprints")
            guard let active = sprints.first(where: { $0.state == "active" }) ?? sprints.first else {
                print("⚠ keine Sprints — fertig"); return 0
            }
            print("→ Sprint #\(active.id) \"\(active.name)\" [\(active.state ?? "?")]")

            let allIssues = try await jira.sprintIssues(sprintId: active.id, baseUrl: project.jiraBaseUrl)
            // The board hides sub-tasks (the story carries the work) — mirror that here.
            let issues = allIssues.filter { !$0.isSubtask }
            let subtaskCount = allIssues.count - issues.count
            print("✓ \(issues.count) Issues (\(subtaskCount) Unteraufgaben ausgeblendet)")

            // Dieselbe Pipeline für beide Forges — welcher Client antwortet, entscheidet die
            // Zuordnung des Projekts, nicht dieser Code.
            var mrs: [MergeRequestRef] = []
            if let forge = project.forge, let client = Self.client(for: forge.kind, config: cfg) {
                mrs = (try? await client.openedAndMergedRequests(projectPath: forge.path)) ?? []
                let drafts = mrs.filter { $0.state == "opened" && $0.draft }.count
                let kürzel = forge.kind.requestAbbreviation
                let threads = mrs.filter { $0.totalDiscussions > 0 }.count
                let approved = mrs.filter(\.approved).count
                print("✓ \(mrs.count) \(kürzel)s (opened+merged) von \(forge.kind.label)"
                      + (drafts > 0 ? ", davon \(drafts) Draft (nicht Review)" : ""))
                print("  Review-Stand: \(approved) approved, \(threads) mit Threads"
                      + (forge.kind == .github && threads == 0
                         ? " (GitHub: 0 kann auch heissen, dass GraphQL nichts liefert — fail-open)"
                         : ""))
            } else if project.forge != nil {
                print("• \(project.forge!.kind.label) übersprungen (kein Token in der Config)")
            } else {
                print("• Forge übersprungen (keine Zuordnung)")
            }

            let worktrees = await WorktreeScanner.scan(repoDir: project.repoDir)
            print("✓ \(worktrees.count) Worktrees")

            // „Mir zugewiesen" holt ein Ticket aus der Sprint-Spalte nach Offen — dieselbe Frage
            // wie auf dem Board, also dieselbe Quelle.
            let me = try? await jira.currentUser(baseUrl: project.jiraBaseUrl)
            let myAccountId = me?.accountId
            let mine = issues.filter { $0.assigneeAccountId != nil && $0.assigneeAccountId == myAccountId }
            print("✓ angemeldet als \(me?.displayName ?? "?") — \(mine.count) Issues mir zugewiesen")

            var dist: [KanbanColumn: Int] = [:]
            for ticket in issues {
                let info = TaskFileLoader.statusMarker(ticketKey: ticket.key, in: project.tasksPathAbsolute)
                let wt = WorktreeScanner.worktree(for: ticket.key, in: worktrees)
                let r = WorkflowStatus.resolve(ticketKey: ticket.key, hasTaskFile: info.exists,
                                               statusMarker: info.marker, worktree: wt, mergeRequests: mrs,
                                               jiraState: ticket.jiraDoneState,
                                               isAssignedToMe: ticket.assigneeAccountId != nil
                                                   && ticket.assigneeAccountId == myAccountId)
                dist[r.column, default: 0] += 1
            }
            print("✓ Spalten-Verteilung:")
            for col in KanbanColumn.ordered { print("    \(col.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)) \(dist[col] ?? 0)") }

            // Freier Modus: dieselbe Pipeline, andere Quelle — die Ticketliste kommt lokal statt
            // aus dem Sprint.
            let local = LocalTickets.discover(tasksDirectory: project.tasksPathAbsolute,
                                              prefix: project.prefix,
                                              worktrees: worktrees, mergeRequests: mrs)
            let untitled = local.filter { $0.summary.isEmpty }.count
            print("✓ Freier Modus: \(local.count) Tickets lokal gefunden"
                  + (untitled > 0 ? " (\(untitled) ohne Titel)" : ""))

            printEpics(issues: issues)
            await printClaudeTimes(issues: issues, project: project)
            print("✅ SELFTEST OK")
            return 0
        } catch {
            print("✗ Fehler: \(error.localizedDescription)")
            return 1
        }
    }

    /// 🎨 Epic coverage of the sprint, after sub-tasks inherited their story's epic — the same
    /// resolution the board runs, so a missing colour on a card is explainable from here.
    private static func printEpics(issues: [Ticket]) {
        let resolved = EpicResolution.inheritFromParents(issues)
        let withEpic = resolved.compactMap(\.epic)
        print("✓ Epics: \(withEpic.count) von \(resolved.count) Tickets mit Epic")
        var counts: [EpicRef: Int] = [:]
        for epic in withEpic { counts[epic, default: 0] += 1 }
        for (epic, count) in counts.sorted(by: { $0.value > $1.value }) {
            print("    \(epic.hex) \(epic.paletteKey ?? epic.colorName ?? "—")"
                  + "  \(epic.label) — \(count) Tickets")
        }
        let inherited = resolved.enumerated().filter { issues[$0.offset].epic == nil && $0.element.epic != nil }
        if !inherited.isEmpty { print("    davon \(inherited.count) von der Story geerbt (Unteraufgaben)") }
        let missing = resolved.count - withEpic.count
        if missing > 0 { print("    \(missing) Tickets ohne Epic") }
    }

    /// ⏱ Cumulated Claude time per ticket, derived from Claude Code's own transcripts. Also reports
    /// how long the (uncached, worst-case) parse took — transcripts reach tens of megabytes.
    private static func printClaudeTimes(issues: [Ticket], project: ProjectConfig) async {
        // Same resolution as the board (see ClaudeSessionResolution) — otherwise this check would
        // report a different reality than the app shows.
        var sessionIds: [String: String] = [:]
        for ticket in issues {
            if let sid = ClaudeSessionResolution.resolve(
                taskFileId: TaskFileLoader.peekSessionId(ticketKey: ticket.key, in: project.tasksPathAbsolute),
                storeId: SessionIdStore.peek(forTicket: ticket.key),
                cwd: project.repoDir) {
                sessionIds[ticket.key] = sid
            }
        }
        let started = Date()
        let timings = await ClaudeTimingStore.shared.timings(sessionIds: sessionIds, cwd: project.repoDir)
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "✓ Claude-Zeiten: %d von %d Sessions mit Transkript (%.2fs Parse)",
                     timings.count, sessionIds.count, elapsed))
        for (key, timing) in timings.sorted(by: { $0.value.total > $1.value.total }) {
            let open = timing.openTurn == nil ? "" : "  · letzter Turn ohne Abschluss"
            print("    \(key.padding(toLength: 16, withPad: " ", startingAt: 0))"
                  + " \(TimeFormatting.compact(timing.total).padding(toLength: 9, withPad: " ", startingAt: 0))"
                  + " \(timing.turnCount) Turns · ⌀ \(TimeFormatting.compact(timing.average ?? 0))"
                  + " · inkl. Wartezeit \(TimeFormatting.compact(timing.wallTotal))\(open)")
        }
        print("    Σ Sprint: \(TimeFormatting.compact(timings.values.reduce(0) { $0 + $1.total }))")
    }

    /// Der Client zur Forge eines Projekts — nil, wenn sie nicht konfiguriert ist.
    private static func client(for kind: ForgeKind, config: AppConfig) -> (any ForgeClient)? {
        switch kind {
        case .gitlab: return GitLabClient(config: config)
        case .github: return GitHubClient(config: config)
        }
    }

    private static func argValue(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
