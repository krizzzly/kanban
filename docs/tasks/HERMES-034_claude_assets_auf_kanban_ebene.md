# HERMES-034 - Claude-Assets und Task-Files auf Kanban-Ebene

> 🌳 **REPO**: `/Users/christianhiller/code/kanban`\
> 📅 **Angelegt**: 2026-08-07

### Status
🟡 In Arbeit

Typ: Story

## Beschreibung

Commands, Skills, Rules und die Task-Files liegen heute **pro Projekt-Repo**. Ein neues Projekt
aufzuschalten heisst deshalb: Dateien hin- und herkopieren. Ziel ist, dass **Kanban** diese Dinge
besitzt und bereitstellt — projektunabhängig — und sie in der App **bearbeitbar** sind.

Zwei Ebenen, die im Tab heute vermischt sind und getrennt gehören:
der **Git-Worktree** (Verzeichnis + Branch) und der **Worktree-Stack** (Docker).
Diese Story betrifft nur die Claude-Assets und Task-Files.

## Analyse

### Bestandsaufnahme (2026-08-07 erhoben)

| Ebene | Pfad | Befund |
|---|---|---|
| Commands | `<repo>/.claude/commands/*.md` | bfezvm 14, even 10, zba 16 — **17 verschiedene** insgesamt, 9 in allen dreien |
| Skills | `<repo>/.claude/skills/<name>/` | `impact-analysis`, `quality-analysis` — **byte-identisch** in bfezvm + even (gleiche md5) |
| Rules | `<repo>/.claude/rules/*.md` | bfezvm 8, even 7, zba 1 |
| Task-Files | `<repo>/docs/tasks/*.md` | **284 Dateien** (bfezvm 142, even 142), **0 in Git** |
| User-Ebene | `~/.claude/commands` | existiert, ist **leer** — ungenutzt |
| User-Ebene | `~/.claude/skills` | enthält bereits einen **Symlink** (`kanban-code` → Repo) |

### Die Divergenz ist Drift, keine Absicht

Die 4 Workflow-Commands unterscheiden sich zwischen den Projekten um 80–273 Zeilen. Stichproben
zeigen: es sind **verpasste Backports**, keine Projektspezifika —

- `bfezvm/get-task.md` hat „Status-Block einfügen (PFLICHT)" + „Verwandte Tasks auflösen", even nicht
- `even/get-task.md` hat „Doppelte Feld-Sektionen entfernen (PFLICHT)", bfezvm nicht
- dazu Encoding-Drift (`ausdruecklichen` vs. `ausdrücklichen`)

Echt projektspezifisch sind nur wenige Zeilen (Stack-Hooks, `.claude/rules/worktree.md`-Verweis).

Bei den **Rules** ist es gemischt: `db-access` und `translations` sind identisch, `git-commits`/
`serena-first`/`task` haben kleine Drift, `testing` (19 von 35 Zeilen) und `worktree` (90 Zeilen)
sind **echt** projektspezifisch.

### Wie Claude Code die Ebenen auflöst

- **Commands**: `~/.claude/commands/*.md` gelten in **jedem** Projekt (nativ)
- **Skills**: `~/.claude/skills/<name>/` ebenso — und Claude folgt dort **Symlinks** (belegt durch
  den existierenden `kanban-code`-Symlink)
- **Rules**: **kein** nativer Mechanismus. Sie sind nur Markdown, das referenziert wird — und zwar
  **nicht** von `CLAUDE.md`, sondern von den **Commands** (11 Dateien mit
  `> Vollständige Befehls-/Flag-Referenz zu 'iwf worktree': '.claude/rules/worktree.md'`).
  Das ist ein *relativer* Pfad, der gegen `cwd` (= Repo) auflöst. Genau deshalb mussten Rules bisher
  im Repo liegen — eine Folge dieser Referenzen, keine Eigenschaft von Rules.

### Git-Situation (macht den Umzug unkritisch)

`.claude/` ist in **allen drei Repos gitignored** (`.claude/*`, `.claude/**`, `.claude/`), **0 Dateien
getrackt**. `docs/tasks` ebenso (bfezvm `docs/*`, even `docs/**`), **0 getrackt**. Symlinks oder ein
Umzug betreffen also keine Kollegen.

### Blocker für den Task-File-Umzug

`HermesConfig` leitet `repoDir` aus dem **ersten Segment von `tasksPath`** ab:

```swift
let firstSegment = tasksPath.split(separator: "/").first   // "even"
let repoDir = basePath + firstSegment                      // ~/code/even
```

Zeigt `tasksPath` in den Kanban-Ordner, **verliert die App das Repo** (Worktree-Scan, Claude-cwd,
Git, MR-Zuordnung). `repoDir` muss also zuerst ein eigener Config-Wert werden.

Zweitens: Claude läuft mit `cwd = repoDir`. Task-Files ausserhalb davon lösen Permission-Prompts aus
→ `permissions.additionalDirectories` in `~/.claude/settings.json` setzen (dieselbe Datei, die
`ClaudeHookInstaller` bereits round-trip-sicher pflegt).

Drittens, positiv: `tasksPath` steuert auch Hermes' `generate-claude-task`. Ist `repoDir` entkoppelt,
zieht **ein** Config-Key beide Tools um — kein Auseinanderlaufen.

Nebenbefund: die Projekte sind schon heute uneinheitlich — bfezvm/even nutzen `docs/tasks`,
zba/reactbp bereits `.claude/tasks`.

## Entscheidungen

1. **Umfang**: 4 Commands + 2 Skills + Rules zentral (`db-access`, `translations`, `git-commits`,
   `serena-first`, `task`); `testing` und `worktree` bleiben projektlokal.
2. **Migration**: konsolidieren und die Projektkopien **entfernen** — sonst bleibt die Drift dort.
3. **Ablage**: alles im Kanban-Ordner, Symlinks in die Claude-Ebenen (Vorschlag des Users).
4. **Keine Projektwerte in den Commands**: weder `EVEN`/`even-` noch Ordner wie `docs/tasks`,
   `even-worktree`, `.test`. Diese Werte kommen aus einer generierten Datei je Projekt.
   Kanban hat sie bereits (`prefix`, `tasksPath`, `repoDir`, `gitlabProjectPath`) — es braucht keine
   neue Konfiguration, nur eine Übersetzung.
5. **Rules-Referenzen**: absolute Pfade in den kanonischen Commands statt Repo-Symlink — der
   Symlink war ein Workaround für ein Problem, das beim Umschreiben ohnehin verschwindet.

## Zielbild

```
~/Library/Application Support/Kanban/
├── claude/commands/   get-task · start-task · solve-task · review-task   (0 Projektwerte)
├── claude/skills/     impact-analysis · quality-analysis
├── claude/rules/      db-access · git-commits · serena-first · task · translations
└── tasks/<projekt>/   die Task-Files (284 Stück ziehen um)

Symlinks:  ~/.claude/commands/<name>.md   → Kanban   (global, jedes Projekt)
           ~/.claude/skills/<name>        → Kanban   (Muster existiert bereits)
```

Je Projekt generiert Kanban `<repo>/.claude/project.json` aus der Hermes-Config
(prefix, tasksPath, worktree-Präfix, Stack-Domain, repoDir, gitlabPath).

## Lösungsplan

### Schritt 1 — Asset-Layer (unblockiert)
- `ClaudeAssets` in Core: kanonischer Ordner, Install/Update/Entfernen, Symlink-Status
- `ClaudeCommandScanner` liest **beide** Ebenen (Repo + User)
  → **verifiziert 2026-08-07** (Claude Code 2.1.222, `claude -p` mit gleichnamigem Command auf beiden
  Ebenen, 2× reproduziert + Gegenprobe): **User sticht Projekt** — das Gegenteil der dokumentierten
  Annahme. Für uns günstig: zentrale Symlinks überstimmen liegengebliebene Projektkopien.

### Schritt 2 — Parametrisierung
- Platzhalter statt Projektwerte in den 4 Commands
- `project.json` je Projekt aus der Hermes-Config generieren, beim Projektwechsel aktualisieren

### Schritt 3 — Konsolidierung
- die 4 Commands zu je einer kanonischen Fassung zusammenführen (verpasste Backports einsammeln)
- 5 Rules ebenso; Projektkopien entfernen

### Schritt 4 — Editor in den Einstellungen
- Sidebar-Bereich „Claude-Workflow" neben „Benachrichtigungen"
- Markdown-Editor über Commands + Skills + Rules, mit „Auf Auslieferungsstand zurücksetzen"
- Wiederverwendbar: `CodeEditorView` (NSTextView, Syntax-Highlighting, Dark-Theme) existiert bereits
  aus dem Commit-Dialog

### Schritt 5 — Task-File-Umzug (grösster Eingriff)
- `repoDir` in `HermesConfig` von `tasksPath` **entkoppeln** (eigener Config-Wert)
- `permissions.additionalDirectories` auf den Kanban-Tasks-Ordner setzen
- 284 Task-Files migrieren; die Session-Marker darin bleiben gültig (Inhalt, keine Pfade)
- Hermes' `generate-claude-task` zieht über denselben `tasksPath` mit

## Migrationsplan Schritt 5 (abzustimmen — noch NICHT ausgeführt)

Voraussetzungen sind gebaut: `repoDir`-Override + absoluter `tasksPath` funktionieren (Tests), die
Assets sind zentral. Der Umzug selbst, **pro Projekt einzeln** (erst eines testweise):

1. **Vorher**: alle offenen Claude-Consoles/Sessions des Projekts beenden (cwd/Kontext zeigen sonst
   auf alte Pfade); Hermes-Daemon merken (braucht am Ende Neustart für den neuen `tasksPath`).
2. `permissions.additionalDirectories` in `~/.claude/settings.json` um
   `~/Library/Application Support/Kanban/tasks/` ergänzen (round-trip wie `ClaudeHookInstaller`) —
   **vor** dem Umzug, sonst Permission-Prompts.
3. Task-Files kopieren (erst `rsync`, löschen erst nach Verifikation):
   `<repo>/docs/tasks/` → `~/Library/Application Support/Kanban/tasks/<key>/`
   (inkl. `<TICKET>/`-Unterordner mit `comments.json` — relative Links bleiben gültig).
4. Hermes-Config je Projekt: `tasksPath` absolut auf den neuen Ordner, **gleichzeitig**
   `repoDir: "<key>"` setzen (sonst verliert die App das Repo — der alte Ableitungsweg greift nicht mehr).
5. Kanban: Config neu laden, prüfen: Offen-Spalte (hängt an Task-File-Existenz), Task-Tabs,
   ⏱-Zeiten (Session-Ids stehen im Inhalt, keine Pfade — bleiben gültig), Commit-Button.
   Hermes: `generate-claude-task` erzeugt neue Files am neuen Ort (selber Config-Key).
6. Erst wenn alles grün: alte `docs/tasks/` leeren/löschen. **Kein** Symlink zurücklassen —
   zwei Wahrheiten wären schlimmer als ein sauberer Schnitt.
7. **Rollback** = Dateien zurückkopieren + die zwei Config-Werte zurückdrehen.

## Risiken

- **Schritt 5** kann laufende Abläufe brechen (Hermes-MCP, Worktrees, offene Sessions) — zuletzt und
  einzeln machen
- Präzedenz Projekt- vs. User-Command **vor** Schritt 1 verifizieren
- Permission-Prompts: erst `additionalDirectories`, dann migrieren

## Nächste Schritte
- [x] Präzedenz Projekt-/User-Command empirisch prüfen → **User sticht Projekt** (CC 2.1.222)
- [x] Schritt 1 bauen (Asset-Layer + Scanner-Union) — `ClaudeAssetStore` + erweiterter
  `ClaudeCommandScanner` (beide Ebenen, `shadowedProjectURL`)
- [x] Platzhalter-Stil: ⚙️-Block + `<PREFIX>`/`<tasksPath>`/`<worktreePrefix>`/`<stackDomain>`-Verweise
  auf `.claude/project.json`; alle 4 Commands + 5 Rules + 2 Skills konsolidiert (0 Projektwerte, grep-geprüft)
- [x] `project.json`-Generierung beim Projektwechsel (`ClaudeProjectFile`, schreibt nur bei Änderung)
- [x] Editor in den Einstellungen („Claude-Workflow": Bestand editieren, Symlinks verwalten,
  Auslieferungsstand zurücksetzen)
- [x] `repoDir` von `tasksPath` entkoppelt (optionaler Config-Override, abwärtskompatibel)
- [ ] Task-Umzug (Schritt 5) — Plan oben, mit User abstimmen und **pro Projekt einzeln** ausführen
