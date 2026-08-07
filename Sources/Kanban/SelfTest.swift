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
            let cfg = try HermesConfigLoader.load()
            print("✓ Config: \(cfg.projects.count) Projekte, gitlab=\(cfg.hasGitlab)")

            let wanted = argValue("--project")
            guard let project = cfg.projects.first(where: { $0.key == wanted }) ?? cfg.projects.first else {
                print("✗ kein Projekt in der Config"); return 1
            }
            print("→ Projekt \(project.key) (\(project.prefix)) @ \(project.jiraBaseUrl)")
            print("  tasksPath = \(project.tasksPathAbsolute)")
            print("  repoDir   = \(project.repoDir)")
            print("  gitlab    = \(project.gitlabProjectPath ?? "—")")

            let jira = JiraClient(email: cfg.jiraEmail, apiToken: cfg.jiraApiToken)
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

            var mrs: [MergeRequestRef] = []
            if cfg.hasGitlab, let path = project.gitlabProjectPath,
               let apiUrl = cfg.gitlabApiUrl, let token = cfg.gitlabApiToken {
                mrs = (try? await GitLabClient(apiBaseUrl: apiUrl, token: token)
                    .openedAndMergedMRs(projectPath: path)) ?? []
                let drafts = mrs.filter { $0.state == "opened" && $0.draft }.count
                print("✓ \(mrs.count) MRs (opened+merged)" + (drafts > 0 ? ", davon \(drafts) Draft (nicht Review)" : ""))
            } else {
                print("• GitLab übersprungen (keine Zuordnung)")
            }

            let worktrees = await WorktreeScanner.scan(repoDir: project.repoDir)
            print("✓ \(worktrees.count) Worktrees")

            var dist: [KanbanColumn: Int] = [:]
            for ticket in issues {
                let info = TaskFileLoader.statusMarker(ticketKey: ticket.key, in: project.tasksPathAbsolute)
                let wt = WorktreeScanner.worktree(for: ticket.key, in: worktrees)
                let r = WorkflowStatus.resolve(ticketKey: ticket.key, hasTaskFile: info.exists,
                                               statusMarker: info.marker, worktree: wt, mergeRequests: mrs)
                dist[r.column, default: 0] += 1
            }
            print("✓ Spalten-Verteilung:")
            for col in KanbanColumn.ordered { print("    \(col.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)) \(dist[col] ?? 0)") }

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

    private static func argValue(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
