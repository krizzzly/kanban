## Worktrees & Per-Worktree-Stacks via `iwf worktree`

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`):
> stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

Worktrees **und** ihre eigenen Docker-Stacks werden über das globale `iwf`-Tool verwaltet. Das ersetzt
die alten projektlokalen Bash-Skripte — bei Neuanlage/Abriss immer `iwf worktree …` benutzen.
Konfiguration liegt deklarativ in `.iwf.yml` (siehe unten).

### Befehle

| Aktion                                       | Befehl                                        |
|----------------------------------------------|-----------------------------------------------|
| Anlegen (nur vorbereiten, **nicht** starten) | `iwf worktree create <NR> [<suffix>]`         |
| Anlegen **und** Stack hochfahren             | `iwf worktree create <NR> [<suffix>] --start` |
| Stack später starten                         | `iwf worktree start <NR>`                     |
| Stack stoppen (Worktree + Volume bleiben)    | `iwf worktree stop <NR>`                      |
| Worktree + Stack komplett abräumen           | `iwf worktree destroy <NR> [flags]`           |

- **`<NR>`** = nackte Ticket-Nummer (z.B. `3574`), **nicht** `<PREFIX>-3574`.
- Optionaler **`<suffix>`** = englischer Branch-Titel in snake_case, z.B.
  `iwf worktree create 3574 migrate_sms_to_ecall`. Suffix schon beim Anlegen mitgeben
  (Branch-Rename ist nur solange lokal/ungepusht gefahrlos).
- Alle `iwf worktree …`-Befehle vom **Haupt-Repo** aus aufrufen (`<repoDir>`), nicht aus einem
  Worktree heraus.

### `create` — Flags

- *(Default)* baut das Image, erstellt TLS-Cert + DB-Seed, **startet den Stack aber nicht**.
- `--start` — fährt den Stack danach hoch und führt die `postStart`-Hooks aus (s.u.).
- `--branch <name>` — bestehenden Branch (lokal oder origin) auschecken statt einen neuen
  `feature/<PREFIX>-<NR>`-Branch anzulegen; Worktree-Verzeichnis, Stack-Name und URL kommen weiterhin aus `<NR>`.
- `--dbdump <env|pfad>` — DB-Seed überschreiben: Server-Env (`dev`/`qa`/`prod`) **oder** ein Dump-File-Pfad.
  Default kommt aus `.iwf.yml` → `worktree.dbdump` (falls nicht gesetzt: `dev`).
- `--no-cert` / `--no-db` / `--no-hooks` — jeweiligen Schritt überspringen (`--no-hooks` nur mit `--start` relevant).

### `destroy` — Flags

- `-f` / `--force` — Bestätigungs-Prompts überspringen. **Für Claude-getriggerte Aufrufe IMMER `--force`**
  (Claude kann nicht interaktiv `y` eingeben).
- `--delete-branch` — löscht zusätzlich den lokalen `feature/*`-Branch (GEFÄHRLICH bei ungemergt). Default:
  Branch **bleibt**. Vor `--delete-branch` prüfen: `git log develop --oneline --grep="<PREFIX>-<NR>"`.
- `--keep-data` — benanntes DB-Volume behalten (z.B. wenn der Worktree später neu aufgesetzt wird).

`start` und `stop` haben **keine** Optionen. `stop` ist das Inverse von `start`: Container + Netzwerk runter,
aber Image, DB-Volume, Worktree-Verzeichnis und Branch bleiben → `iwf worktree start <NR>` bringt alles zurück.
Voller Teardown (inkl. Volume/Image/Branch) nur über `destroy`.

### Naming

`iwf worktree create 3574 <suffix>` ergibt (iwf-Defaults des Projekts):

- Worktree: `<worktreePrefix>/<PREFIX>-3574`
- Branch:   `feature/<PREFIX>-3574[_<suffix>]` (von `origin/develop`, local-only — kein Upstream)
- Stack:    `<worktree-ordnername>` kleingeschrieben (z.B. `projekt-3574`),
  URL `https://<worktree-ordnername>.<stackDomain>`

> Die Worktree-/Branch-Namen hängen an den iwf-Defaults bzw. `.iwf.yml` → `worktree.branchPrefix` /
> `worktree.parentDir`; Stack-Name/URL kommen aus dem `{name}`-Token. **Im Zweifel die exakten Werte
> aus dem `create`-Output übernehmen.**

### Was die `.iwf.yml` steuert (ersetzt die Skript-Internas)

- `worktree.dbdump`: Seed-Reihenfolge — erst ein ggf. konfigurierter lokaler Dump, sonst Server-Env (`dev`).
  → Ein frischer Stack wird beim `create` automatisch geseedet; das klassische „`SQLSTATE[42S22] Unknown
  column`"-Problem (frischer Worktree mit partieller DB) entfällt i.d.R.
- `stack.hooks.postStart`: läuft bei **jedem** `iwf stack start` (also auch bei `iwf worktree create --start`
  und `iwf worktree start`). Welche Hooks das sind, definiert das Projekt dort — typisch z.B. `iwf yarn dev`
  (Frontend-Dev-Server), teils auch Auth-/Fixture-Provisionierung. Hooks müssen idempotent bleiben.

### Routing für Claude

- `iwf worktree …`-Befehle vom **Haupt-Repo** aus aufrufen — sie nehmen die `<NR>`, kein `cd` nötig.
- cwd bleibt Haupt-Repo: Code-Edits mit absolutem Worktree-Pfad, Git mit `git -C <worktree> …`,
  Task-File/CLAUDE.md/Docs/`.claude/` aus dem Haupt-Repo.
- ⚠️ Die Container des **Haupt-Stacks** (`<repo-ordnername>-fpm` etc.) sehen NUR den Haupt-Repo-Stand, NICHT
  den Worktree-Code. Container-basierte Tests/PHPStan gegen den Worktree daher entweder im Worktree-eigenen
  Stack laufen lassen (`docker exec <worktree-ordnername>-fpm ./vendor/bin/paratest tests/…` bzw.
  `cd <worktree> && iwf run phpstan` — `iwf` liest `PROJECT_NAME` aus der Worktree-`.env.local`, funktioniert
  also nur mit cwd im Worktree) oder dem User zur Validierung überlassen.
- Bei YAML-/Metadata-Änderungen vor einem Test-Lauf den Test-Cache des Worktree-Stacks wipen:
  `docker exec <worktree-ordnername>-fpm sh -lc 'rm -rf var/cache/test_* var/cache/test'`.

### Serena pro Worktree aktivieren (Pflicht bei aktivem Worktree-Routing, falls Serena läuft)

Serena läuft **project-less** (`claude-code`-Kontext, kein `--project` beim Start) — jede Claude-Session hat
einen eigenen Serena-Prozess und muss ihr Projekt selbst wählen. Deshalb: **sobald Worktree-Routing aktiv ist**
(WORKTREE-Block gelesen), **einmalig** `mcp__serena__activate_project` mit dem absoluten WORKTREE-Pfad aufrufen
(`<worktreePrefix>/<PREFIX>-<NR>`).

- Ohne Aktivierung zeigen Serenas Symbol-Tools auf das zuletzt aktive Projekt (oft das Hauptrepo) und sehen die
  Worktree-Änderungen **nicht**.
- Ist das Tool deferred/nicht sichtbar: zuerst per Tool-Suche laden (`select:mcp__serena__activate_project`).
- Nur **einmal pro Session** nötig; bei Parallelbetrieb aktiviert jede Session ihren eigenen Worktree unabhängig
  (eigener Serena-Prozess pro Session).
- Bei `--no-worktree`: Serena aufs Hauptrepo aktivieren (bzw. unverändert lassen).
