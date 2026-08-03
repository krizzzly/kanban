# Kanban (HERMES-034)

A standalone native macOS app: a **sprint board + task-file cockpit** for Claude-Code work.
Reduced to a single view — top bar (project + sprint picker), a vertical Kanban board on the
left, and the structured task-file content as tabs on the right.

This project is **independent of Hermes** — it reads `~/.hermes/config.json` to discover
projects + credentials, and can **edit** that file via the settings sheet (gear button; round-trip
über `ConfigStore`, Backup als `config.json.bak`). The Hermes **repo** itself is never modified.

## Key idea: derived workflow status (NOT Jira status)

A ticket's column is derived from the **real local artifact state**, never from a manually
maintained Jira field. The board is therefore always honest and read-only — no card is ever
dragged by hand.

Columns (fixed order): `Sprint → Offen → In Bearbeitung → Review → Done`

Precedence (top-down, first match wins):

| # | Column | Condition | Source |
|---|---|---|---|
| 1 | Done | merged MR for `<TICKET>` exists | GitLab `merge_requests?state=merged` |
| 2 | Review | opened MR for `<TICKET>` exists | GitLab `merge_requests?state=opened` |
| 3 | In Bearbeitung | task-file `### Status` = 🟡 In Arbeit | task-file marker |
| 4 | Offen | task-file `<TICKET>*.md` exists OR worktree branch `*<TICKET>*` exists | local FS + `git worktree` |
| 5 | Sprint | otherwise | Jira (default) |

Cards carry badges (📄 file · 🌳 worktree · 🔀#iid MR) so it's visible *why* a card is where it is.

## Architecture

```
Sources/
├── KanbanCore/            pure logic, no UI (testable)
│   ├── Config/            HermesConfig — decode ~/.hermes/config.json
│   ├── Domain/            Ticket, KanbanColumn, TaskSection, Worktree, MergeRequestRef, CardBadge
│   ├── Jira/              JiraClient (Agile REST) + models
│   ├── GitLab/            GitLabClient (list MRs) + models
│   ├── Git/               WorktreeScanner (`git worktree list --porcelain`)
│   ├── Net/               HostGuardDelegate (drops auth on cross-host redirect)
│   ├── Status/            WorkflowStatus precedence engine
│   └── Tasks/             TaskFile (glob + H2 parser + status marker) + TaskFileWatcher
└── Kanban/                SwiftUI/AppKit app
    ├── App.swift          @main, Window
    ├── AppModel.swift     @Observable: config/selection/sprints/issues/MRs/worktrees/columns/refresh
    ├── ContentView.swift  VStack(TopBar, HSplitView(Board, Detail))
    ├── TopBar/            project + sprint picker + refresh
    ├── Board/             BoardSidebar / ColumnSection / TicketCard
    ├── Detail/            DetailView / TaskTabsView / TerminalPlaceholderView
    └── Theme/             MarkdownTheme (ported from kanban-code's chatMarkdownTheme)
```

## Config (read from `~/.hermes/config.json`)

- `basePath` (e.g. `~/code`) — tasksPath + repoDir are resolved relative to it.
- `modules.jira.{baseUrl,email,apiToken}` + `modules.jira.projects.<key>.{prefix,tasksPath,baseUrl?}`.
  Auth = `Authorization: Basic base64(email:apiToken)`.
- `modules.gitlab.{baseUrl,apiToken}` + `modules.gitlab.projects.<key>.{path}`.
  **Same key** as the Jira project → mapping. Auth = `PRIVATE-TOKEN` header. API base `${baseUrl}/api/v4`.
- Local repo dir for worktree scan = `basePath/<first segment of tasksPath>` (e.g. `even/docs/tasks` → `~/code/even`).

## Build / run

```bash
swift build
swift run Kanban
swift test          # KanbanCore unit tests (WorkflowStatus engine)
```

## Not in step 1 (deliberately)

- The embedded terminal + persistent (tmux) sessions — own follow-up step; only a placeholder zone here.
- Writing to Jira/GitLab, drag&drop between columns, own kanban config UI.
