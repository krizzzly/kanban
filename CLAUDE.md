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
| 2 | Review | **non-draft** opened MR for `<TICKET>` exists | GitLab `merge_requests?state=opened` |
| 3 | In Bearbeitung | task-file `### Status` = 🟡 In Arbeit | task-file marker |
| 4 | Offen | task-file `<TICKET>*.md` exists OR worktree branch `*<TICKET>*` exists | local FS + `git worktree` |
| 5 | Sprint | otherwise | Jira (default) |

Cards carry badges (📄 file · 🌳 worktree · 🔀#iid MR) so it's visible *why* a card is where it is.

**Draft-MRs** sind in GitLab `state == "opened"`, aber nicht review-reif — sie schieben die Karte
**nicht** nach Review (weder direkt noch über `shouldAutoSetReview`). `GitLabClient` erkennt den Draft
am `draft`-Flag, dem Legacy-`work_in_progress` oder einem `Draft:`/`WIP:`-Titelpräfix. Die Karte bleibt
in ihrer Arbeitsspalte und trägt statt 🔀 ein **🚧#iid**-Badge (orange), damit sichtbar ist, warum sie
trotz MR nicht in Review steht.

**Unteraufgaben** (`issuetype.subtask`, sprachunabhängig) erscheinen **nicht** als eigene Karten — die
Story trägt die Arbeit. `AppModel.refresh` filtert sie aus der Sprint-Liste; `--selftest` meldet, wie
viele ausgeblendet wurden. (Damit ist die Epic-Vererbung auf Sub-Tasks auf dem Board gegenstandslos —
Stories tragen ihr Epic ohnehin selbst; `EpicResolution` bleibt für den Selftest erhalten.)

## Zeitmessung (⏱ Claude-Zeit pro Prompt + Antwort, kumuliert)

Genauso derived: die Zeit wird **nicht** getrackt, sondern aus Claude Codes eigenem Transcript
(`~/.claude/projects/<cwd-slug>/<session>.jsonl`) gelesen — rückwirkend für alle Sessions, ohne Hook
und ohne eigenen State.

- **Ein Turn** = ein Prompt + alles, was Claude darauf tut. Alle Einträge eines Turns tragen dieselbe
  `promptId` (auch die Tool-Results); Claudes Assistant-Einträge tragen keine → sie verlängern den
  offenen Turn. Eine neue `promptId` öffnet den nächsten Turn.
- **Dauer** = Claudes eigene Messung (`system/turn_duration` → `durationMs`), wo vorhanden (~81 % der
  Turns). Sonst Summe der Lücken zwischen den Einträgen des Turns, jede Lücke gekappt auf
  `ClaudeTurnAccumulator.idleGapCap` (10 min) — ohne Kappung landet Wartezeit auf den *User*
  (Permission-Prompt, Rückfrage) in der Messung; ein einzelner verwaister Turn kam so auf 30 h.
- Auch Claudes eigene Zahl ist **nicht** immer idle-frei: ein über Nacht am Permission-Prompt
  stehender Turn kam als 11,2 h zurück, bei 47 min Aktivität im Transcript. Sie darf die beobachtete
  Aktivität deshalb um höchstens eine weitere Kappungslücke übersteigen (1 von 774 gemeldeten Turns
  betroffen). Preis: eine echte 40-min-Stille (ein Build) zählt 20 min.
- Geschätzte **und** gekappte Turns sind im UI mit „≈" markiert (`ClaudeTurn.isExact`).
- **Kumuliert** pro Ticket (Karten-Badge ⏱), pro Session (Chip im Detail-Header, Klick → Turn-Liste
  mit Gesamt/⌀/längster Turn/„inkl. Wartezeit") und pro Sprint (Toolbar).
- **Live**: läuft ein Turn, tickt der Zähler grün. Ob ein Turn *läuft* (statt abgebrochen zu sein)
  sagt das Transcript nicht — dafür zählt `AppModel.runningTurnStart` frisches mtime **oder** die
  tmux-Pane-Analyse (`PaneAttention.isWorking`).
- Transcripts werden **inkrementell** getailt (`TranscriptTail`): der erste Blick parst die Datei
  (bis zu ~15 MB), jeder weitere nur das Angehängte. `swift run Kanban --selftest` gibt die Zeiten
  pro Ticket samt Parse-Dauer aus.

### Jira-Zeit buchen (Unterpunkt „Gebuchte Zeit")

Die ⏱-Zeit lässt sich am Tagesende als Jira-Worklog buchen — direkt über die Jira-REST-API
(`POST /rest/api/3/issue/<KEY>/worklog`, dieselbe Basic-Auth wie beim Lesen; der Hermes-Daemon kennt
nur `fetch`, kein Worklog-Kommando).

- **Immer auf 15 min aufgerundet** (`WorklogBooking`), und zwar die *kumulierte* Gesamtzeit, nicht der
  Tagesdelta — das vermeidet Rundungs-Drift.
- **Keine Doppelbuchung**: `WorklogLedger` (lokal, `~/Library/Application Support/Kanban/worklog.json`,
  wie [[stale-release-build]]-nahe UI-State) merkt pro Ticket `bookedSeconds`. Gebucht wird nur
  `aufrunden15(gemessen) − bereitsGebucht` — ein 15-min-Vielfaches ≥ 0, das **0** wird, sobald nichts
  Neues gearbeitet wurde. Eintrag ins Ledger erst **nach** erfolgreichem Jira-Write, damit ein
  abgelehnter Write keine Zeit als gebucht markiert. Das Ledger ist die App-eigene Buchungshistorie;
  von Hand in Jira gebuchte Worklogs sieht es nicht.
- **UI**: Unterpunkt im ⏱-Popover (`Gebucht` / `Offen zum Buchen` + Buchen-Button je Ticket),
  Sammel-Buchung über den Toolbar-Button „X buchen" → `BookingSheet` (Übersicht + Bestätigung),
  ✓ am Karten-Badge wenn vollständig gebucht.

## Commit (Button im Detail-Header, links neben der ⏱-Zeit)

- Sichtbar, sobald es etwas zu committen gibt: **Task-File oder Worktree** vorhanden — bewusst *nicht*
  an den Status-Marker gebunden (nachbessern passiert in Review genauso wie bei 🟢 Abgeschlossen).
  Auf reinen Jira-Tickets bleibt er aus, weil `commitDirectory` dort auf das Haupt-Repo zurückfiele
  und `git add -A` fremde Änderungen mitnähme.
- **Message-Vorschlag** kommt aus dem Task-File: `## Lösung` → `**Commit-Message:** \`TICKET | …\``
  (`CommitMessage`; `## Lösungsplan` wird bewusst nicht verwechselt). Fehlt sie, wird `TICKET | ` als
  Stub vorgeschlagen.
- **Amend** braucht keine Message (`--amend --no-edit`), der Push dazu ist immer
  **`--force-with-lease`** — nie ein blankes `--force`, damit ein fremder Push nicht überschrieben wird.
- Diff-Ansicht im GitLab-Stil (`DiffParser`): Dateiliste links, Diff rechts, Additions hellgrün /
  Deletions hellrot, zwei Nummern-Spalten. Untracked Files haben keine HEAD-Seite und werden deshalb
  über `git diff --no-index /dev/null <file>` gezeigt.

### Welche Session-Id gehört zum Ticket?

Ein Ticket kann **zwei** Ids tragen und sie widersprechen sich: Wird es geöffnet, bevor ein Task-File
existiert, erzeugt die App eine Id in `sessions.json` und startet Claude damit; legt diese Console
dann das Task-File an, stand im Marker früher eine **neu erfundene** Id. Das Task-File gewann — die
App zeigte auf eine Konversation, die es nie gab (24 von 35 Tickets divergent, davon 17 ohne
Transcript auf der Task-File-Id: keine ⏱-Zeit, keine Hook-Attention, und eine neue Console hätte
statt Resume leer gestartet).

`ClaudeSessionResolution.resolve` entscheidet über das Transcript auf der Platte: eine Id, unter der
Claude wirklich lief, hat eins. Bei zwei Transcripts gewinnt das Task-File (dort gehört die Id hin —
`sessions.json` enthält historisch auch Ids fremder Tickets). `setupTerminal` schreibt die aufgelöste
Id in **beide** Speicher zurück, damit sie nicht wieder auseinanderlaufen; das Board selbst löst nur
lesend auf.

## Epics (Farbcode auf der Karte, ausgeschrieben im Header)

- Quelle ist das Agile-Feld `epic` der Sprint-Issues — eine Extra-Anfrage braucht es nicht.
- **Farbe**: nur `epic.color.key` (`color_1`…`color_14`, identisch zum `ghx-label-N` des Epics)
  unterscheidet Epics. Das neuere `issueColor` liefert auf dieser Jira-Instanz für **jedes** Epic
  `purple` — darauf gebaut wäre das ganze Board einfarbig. `EpicColors.paletteNames` ist Jiras eigene
  Zuordnung `color_N` → Farbname (aus `greenhopper/1.0/xboard/plan/backlog/epics.json`, das pro Epic
  `epicColor` **und** `color` liefert); der Name geht über `EpicColors.palette` auf einen Hex.
- **Unteraufgaben** tragen kein `epic`, nur `parent`. `EpicResolution.inheritFromParents` holt das
  Epic von der Story — lokal aus derselben Sprint-Liste, ohne weiteren Request (im EVEN-Sprint
  betrifft das 15 von 34 Tickets). Story nicht im Sprint → kein Epic statt geraten.
- UI: `EpicColorStripe` (Farbbalken links auf der Karte) + `EpicPill` (Epic ausgeschrieben im
  Detail-Header, direkt nach dem Task-File/Feature-Branch). `--selftest` listet die Epic-Verteilung.

## Gemerkte Auswahl (Projekt + Sprint überleben den Neustart)

`SelectionStore` (UserDefaults, **nicht** die Hermes-Config — das ist lokaler UI-State) hält das
zuletzt gewählte Projekt und je Projekt den gewählten Sprint. `SprintSelection.resolve` stellt ihn
wieder her, solange er auf dem Board liegt — auch einen geschlossenen, denn die Wahl war Absicht und
der Picker markiert ihn „✓"; kennt das Board die Id nicht mehr, gewinnt der aktive Sprint.
`Kanban --select <TICKET>` sticht die Erinnerung.

## Claude-Assets auf Kanban-Ebene (HERMES-034)

Kanban **besitzt** die 4 Workflow-Commands (get/start/solve/review-task), 2 Skills (impact-/
quality-analysis) und 5 Rules (db-access, git-commits, serena-first, task, translations) kanonisch —
konsolidiert aus bfezvm/even/zba (die Drift dort waren verpasste Backports).

- **Drei Orte**: Auslieferungsstand im App-Bundle (`Sources/Kanban/Resources/ClaudeAssets`, SPM-
  Resource) → editierbarer Bestand `~/Library/Application Support/Kanban/claude/` (Seeding beim
  App-Start: Fehlendes kopieren, Editiertes nie anfassen) → **Symlinks** nach `~/.claude/{commands,
  skills}` (gelten in jedem Projekt). Rules werden **nicht** verlinkt (kein nativer Mechanismus).
- **Präzedenz empirisch verifiziert** (CC 2.1.222, 2026-08-07): bei Namensgleichheit sticht die
  **User-Ebene** die Projektkopie — Gegenteil der verbreiteten Doku-Annahme. `ClaudeCommandScanner`
  liest beide Ebenen, überdeckte Projektkopien stehen in `shadowedProjectURL`.
- **Keine Projektwerte in den Assets**: Platzhalter `<PREFIX>`/`<tasksPath>`/`<worktreePrefix>`/
  `<stackDomain>` (nur die TLD; Hosts = `<ordnername>.<stackDomain>`) verweisen auf
  `<repo>/.claude/project.json`, das `ClaudeProjectFile` beim Projektwechsel aus der Hermes-Config
  generiert (schreibt nur bei inhaltlicher Änderung; `.claude/` ist überall gitignored).
- **Editor**: Einstellungen → „Claude-Workflow" — CodeEditorView über den Bestand, Symlink-Status/
  -Verwaltung je Asset, „Auf Auslieferungsstand zurücksetzen" (aus dem Bundle).
- `repoDir` ist von `tasksPath` **entkoppelt** (`modules.jira.projects.<key>.repoDir`, optional;
  absolut/`~`/relativ zum Basis-Pfad) — ohne Override gilt weiter das erste `tasksPath`-Segment.
  Der Task-File-Umzug selbst (Schritt 5) steht noch aus; Plan im Task-File.

## Architecture

```
Sources/
├── KanbanCore/            pure logic, no UI (testable)
│   ├── Claude/            ClaudeAssets (kanonischer Bestand + Seeding + Symlinks) +
│   │                      ClaudeProjectFile (generiert <repo>/.claude/project.json)
│   ├── Config/            HermesConfig — decode ~/.hermes/config.json (repoDir-Override je Projekt)
│   ├── Domain/            Ticket, KanbanColumn, TaskSection, Worktree, MergeRequestRef, CardBadge,
│   │                      EpicRef + EpicColors (Jira-Palette) + EpicResolution (Sub-Task erbt Epic)
│   ├── Jira/              JiraClient (Agile REST) + models + SprintSelection (Reihenfolge/Restore)
│   ├── GitLab/            GitLabClient (list MRs) + models
│   ├── Git/               WorktreeScanner (`git worktree list --porcelain`) + BranchParent
│   │                      (Abzweig-Basis abgeleitet: Kandidaten = langlebige Branches + Worktree-
│   │                      Checkouts (Branches stacken!), Gewinner = wenigste fehlende Commits
│   │                      (min ahead); backup/*-Snapshots ausgeschlossen, Kind-Branches via ahead==0)
│   │                      + BranchStack (ganzer Wald fürs Hierarchie-Popover am ←-Chip: Commit-Menge
│   │                      jenseits der Basis je Branch, Parent = größte echte Teilmenge, leere
│   │                      Mengen (gemergt/frisch) adoptieren nichts; 1 rev-list pro Branch)
│   ├── Net/               HostGuardDelegate (drops auth on cross-host redirect)
│   ├── Status/            WorkflowStatus precedence engine
│   ├── Tasks/             TaskFile (glob + H2 parser + status marker) + TaskFileWatcher
│   └── Timing/            ClaudeTurn/-SessionTiming, ClaudeTurnAccumulator (transcript → turns),
│                          ClaudeTimingStore (incremental tail + cache), TimeFormatting
└── Kanban/                SwiftUI/AppKit app
    ├── App.swift          @main, Window
    ├── AppModel.swift     @Observable: config/selection/sprints/issues/MRs/worktrees/columns/refresh
    ├── ContentView.swift  VStack(TopBar, HSplitView(Board, Detail))
    ├── TopBar/            project + sprint picker + refresh + Σ Claude-Zeit des Sprints
    ├── Settings/          SettingsSheet (~/.hermes/config.json) + SelectionStore (gemerkte Auswahl)
    ├── Board/             BoardSidebar / ColumnSection / TicketCard / EpicViews (Stripe + Pill)
    ├── Detail/            DetailView / TaskTabsView / TerminalPlaceholderView
    ├── Timing/            ClaudeTimeBadge (Karte) / ClaudeTimeChip + Popover (Turn-Liste + Buchen) / BookingSheet
    └── Theme/             MarkdownTheme (ported from kanban-code's chatMarkdownTheme)
```

## Config (read from `~/.hermes/config.json`)

- `basePath` (e.g. `~/code`) — tasksPath + repoDir are resolved relative to it.
- `modules.jira.{baseUrl,email,apiToken}` + `modules.jira.projects.<key>.{prefix,tasksPath,baseUrl?}`.
  Auth = `Authorization: Basic base64(email:apiToken)`.
- `modules.gitlab.{baseUrl,apiToken}` + `modules.gitlab.projects.<key>.{path}`.
  **Same key** as the Jira project → mapping. Auth = `PRIVATE-TOKEN` header. API base `${baseUrl}/api/v4`.
- Local repo dir for worktree scan = `basePath/<first segment of tasksPath>` (e.g. `even/docs/tasks` → `~/code/even`)
  — **ausser** `modules.jira.projects.<key>.repoDir` ist gesetzt (absolut, `~` oder relativ zum Basis-Pfad).
  `tasksPath` darf ebenfalls absolut sein (für den Task-File-Umzug nach Application Support).

## Build / run

```bash
swift build
swift run Kanban
swift test          # KanbanCore unit tests (WorkflowStatus engine)
```

## Not in step 1 (deliberately)

- The embedded terminal + persistent (tmux) sessions — own follow-up step; only a placeholder zone here.
- Writing to Jira/GitLab, drag&drop between columns, own kanban config UI.
