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

            let issues = try await jira.sprintIssues(sprintId: active.id, baseUrl: project.jiraBaseUrl)
            print("✓ \(issues.count) Issues")

            var mrs: [MergeRequestRef] = []
            if cfg.hasGitlab, let path = project.gitlabProjectPath,
               let apiUrl = cfg.gitlabApiUrl, let token = cfg.gitlabApiToken {
                mrs = (try? await GitLabClient(apiBaseUrl: apiUrl, token: token)
                    .openedAndMergedMRs(projectPath: path)) ?? []
                print("✓ \(mrs.count) MRs (opened+merged)")
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
            print("✅ SELFTEST OK")
            return 0
        } catch {
            print("✗ Fehler: \(error.localizedDescription)")
            return 1
        }
    }

    private static func argValue(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
