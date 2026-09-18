---
name: create-worktree
description: Erstelle einen Git-Worktree für einen Task und verankere ihn im Task-File
argument-hint: <TICKET-NUMMER> oder <task-file.md> [--start]
disable-model-invocation: true
---

# CREATE WORKTREE - Git-Worktree für Task anlegen

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `dockerStack`, `stackDomain`,
> `gitlabProjectPath`): stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen
> Projektwert brauchst — nie raten.

Du erstellst einen Git-Worktree für einen bestehenden Task und verankerst den Worktree-Pfad ganz oben im
Task-File.

## Zwei Wege — `dockerStack` entscheidet

**Lies `.claude/project.json`, bevor du irgendetwas tust.** Der Schlüssel `dockerStack` bestimmt den
kompletten Ablauf:

| `dockerStack`        | Weg                                                                            |
|----------------------|--------------------------------------------------------------------------------|
| `true` (oder fehlend)| **Weg A:** `iwf worktree create` — Netbird-Pre-Flight, Image-Build, TLS-Cert, DB-Seed. |
| `false`              | **Weg B:** reiner Git-Worktree (`git worktree add`). Kein `iwf`, kein Stack, kein Netbird. |

Platzhalter in spitzen Klammern (`<PREFIX>`, `<tasksPath>`, `<worktreePrefix>`, `<stackDomain>`) stehen im
Folgenden für die entsprechenden Werte aus `.claude/project.json` — im Task-File landen immer die
**aufgelösten** Werte, keine Platzhalter. `<stackDomain>` gibt es nur auf Weg A; es ist nur die TLD (z.B.
`test`): der Haupt-Stack läuft auf `https://<repo-ordnername>.<stackDomain>`, ein Worktree-Stack auf
`https://<worktree-ordnername>.<stackDomain>` (Ordnername = letzter Pfadbestandteil).

> Vollständige Befehls-/Flag-Referenz zu beiden Wegen:
> `~/Library/Application Support/Kanban/claude/rules/worktree.md`.

## Input

$ARGUMENTS

Akzeptierte Formate:

- **Ticket-Nummer:** `<PREFIX>-1234` → das passende Task-File wird per Glob gesucht (`<tasksPath>/<PREFIX>-1234*.md`)
- **Task-File-Pfad:** `<tasksPath>/<PREFIX>-1234_some_title.md` → direkt nutzen

Flag `--start` (Stack direkt hochfahren) gilt **nur auf Weg A**. Auf Weg B wird es abgelehnt (siehe
Schritt 3B) — es gibt dort keinen Stack, den man starten könnte.

## Voraussetzungen

- Ein Task-File existiert bereits unter `<tasksPath>/`. Falls nein → erst `/get-task <TICKET>` oder
  `/create-task ...` ausführen.
- Aktueller Pfad ist das Haupt-Repository (`<repoDir>`), NICHT ein Worktree.
- **Nur Weg A:** **Netbird-VPN-Tunnel** (nötig für den DB-Sync) — Phase 0 ruft `netbird up` auf
  (idempotent) und wiederholt bei Bedarf per hook-triggernder Rückfrage, bis die Ausgabe
  `Connected`/`Already Connected` meldet.

---

## Workflow

### Phase 0: Pre-Flight — DB-Sync-Verbindung (Netbird) sicherstellen — **nur Weg A**

> **Bei `dockerStack: false` komplett überspringen.** Ohne Stack wird keine DB geseedet, also ist auch
> kein Tunnel nötig. Direkt zu Phase 1.

**Schritt 0: Netbird-Verbindung zum Management sicherstellen (PFLICHT, vor allem anderen)**

`iwf worktree create` seedet die Worktree-DB vom Dev-Server (`.iwf.yml` → `worktree.dbdump`). Das läuft über
die Netbird-VPN-Verbindung zum Management — ohne sie kann die DB **nicht** gesynct werden. `netbird up` ist
idempotent (ist der Tunnel schon oben, meldet es das nur), also als **allererstes** — noch vor der
Eingabe-Normalisierung — ausführen:

```bash
netbird up
```

Beurteile die Ausgabe:

- Sie meldet **`Connected`** oder **`Already Connected`** → Tunnel steht, weiter mit Phase 1.
- **Alles andere** (Fehler, Login nötig o.ä.) → **Fragerunde** (KEIN `iwf worktree create`):

  1. **Rückfrage stellen** — via `AskUserQuestion` (Tool-Aufruf, damit das Frage-Event den Console-Hook
     triggert; nicht nur als Text ausgeben). Z.B. „Netbird-Tunnel noch nicht verbunden — erneut versuchen?"
     mit den Optionen **„Erneut versuchen"** / **„Abbrechen"**.
  2. Bei **„Erneut versuchen"**: wieder `netbird up`, Ausgabe erneut beurteilen —
     `Connected`/`Already Connected` → Phase 1; sonst zurück zu Punkt 1. **Schleife, bis der Tunnel steht.**
  3. Bei **„Abbrechen"**: Command beenden, keinen Worktree anlegen.

  Grund: Ein Worktree ohne DB-Sync bekäme eine leere/partielle DB.

---

### Phase 1: Eingabe normalisieren

**Schritt 1: Task-File ermitteln**

1. Falls Eingabe nur eine Ticket-Nummer ist (`<PREFIX>-1234`):
   ```bash
   ls <tasksPath>/<PREFIX>-1234*.md
   ```
   - Genau 1 Treffer → verwenden
   - 0 Treffer → STOPP: `❌ Kein Task-File gefunden. Erst /get-task <PREFIX>-1234 ausführen.`
   - Mehrere Treffer → STOPP: Benutzer fragen welches File gemeint ist
2. Falls Eingabe ein Pfad ist: prüfen ob das File existiert.

**Schritt 2: Nummer + Branch-Suffix extrahieren**

Aus dem Dateinamen `<PREFIX>-XXXX[_<english_title>].md` die nackte Ticket-**Nummer** und den englischen Titel
extrahieren. `iwf worktree create` erwartet die **nackte Nummer** als erstes Argument (NICHT `<PREFIX>-XXXX`);
der Worktree-Ordner heisst auf beiden Wegen `<PREFIX>-XXXX`:

| Task-File                                | TICKET          | NUMMER  | SUFFIX                  |
|------------------------------------------|-----------------|---------|-------------------------|
| `<PREFIX>-4460_fix_attachment_list.md`   | `<PREFIX>-4460` | `4460`  | `fix_attachment_list`   |
| `<PREFIX>-4426.md`                       | `<PREFIX>-4426` | `4426`  | _(leer)_                |

---

### Phase 2: Worktree anlegen

**Schritt 3A: Weg A — `iwf worktree create` (`dockerStack: true`)**

```bash
# Mit Branch-Suffix (nur vorbereiten, Stack NICHT starten):
iwf worktree create <NUMMER> <suffix>

# Ohne Suffix:
iwf worktree create <NUMMER>

# Inkl. Stack-Start (nur falls --start im Input):
iwf worktree create <NUMMER> <suffix> --start
```

`iwf worktree create` legt per Default **nur** den Worktree an und bereitet den Stack vor, **startet ihn aber nicht**:

- legt den Worktree an (Konvention: `<worktreePrefix>/<PREFIX>-<NUMMER>`)
- erstellt Branch `feature/<PREFIX>-<NUMMER>[_<suffix>]` von `origin/develop` (local-only, kein Upstream)
- kopiert gitignored Configs (`.env.local`, `docker/run/docker-compose.yml`, `secrets/sensible.env`)
- baut das Image, erstellt TLS-Cert und legt den DB-Seed an
  (`.iwf.yml` → `worktree.dbdump`: lokaler Dump, sonst `dev`)
- schreibt Worktree-Overrides nach `.env.local` (`PROJECT_NAME`, `APP_URL`)

**Stack-Opt-in:** Nur mit `--start` wird der Stack hochgefahren (`iwf stack start` inkl. der `postStart`-Hooks
aus `.iwf.yml` — welche das sind, definiert das Projekt dort; typisch z.B. `iwf yarn dev`). Ohne `--start`
bleibt der Stack unten — später mit `iwf worktree start <NUMMER>` starten.

Weitere `create`-Flags bei Bedarf: `--dbdump <env|pfad>` (Seed überschreiben), `--no-cert`, `--no-db`,
`--no-hooks` (nur mit `--start` relevant).

**Wenn der Output fehlerfrei ist**, übernimm Worktree-Pfad / Branch / Stack-Name / URL aus dem
`create`-Output für Phase 3 (falls nicht ausgegeben, nach Konvention ableiten: Worktree
`<worktreePrefix>/<PREFIX>-<NUMMER>`, Stack-Name = Worktree-Ordnername kleingeschrieben, URL =
`https://<worktree-ordnername>.<stackDomain>`).

**Schritt 3B: Weg B — `git worktree add` (`dockerStack: false`)**

Steht `--start` im Input, **hier abbrechen** und sagen warum:

```
❌ --start gibt es in diesem Projekt nicht: dockerStack ist false, also gibt es keinen Docker-Stack
   zu starten. Ohne das Flag erneut aufrufen — der Git-Worktree wird ganz normal angelegt.
```

Sonst: erst den **Basis-Branch ermitteln** (nie hart `develop` annehmen — in einem Repo ohne `develop`
schlüge `git worktree add` fehl, und in einem mit `main` als Default zweigte der Branch vom falschen Stand ab):

```bash
R=<repoDir>
BASE=$(git -C "$R" symbolic-ref --quiet --short refs/remotes/origin/HEAD)   # z.B. "origin/main"
if [ -z "$BASE" ]; then
  for kandidat in origin/develop origin/main develop main; do
    git -C "$R" rev-parse --verify --quiet "$kandidat" >/dev/null && { BASE="$kandidat"; break; }
  done
fi
[ -z "$BASE" ] && BASE=HEAD    # rein lokales Repo ohne origin
echo "Basis-Branch: $BASE"
```

Dann Worktree + Branch in **einem** Schritt:

```bash
git -C <repoDir> worktree add <worktreePrefix>/<PREFIX>-<NUMMER> \
    -b feature/<PREFIX>-<NUMMER>[_<suffix>] --no-track "$BASE"
```

Das legt an: den Worktree-Ordner, den Branch `feature/<PREFIX>-<NUMMER>[_<suffix>]` (local-only, kein
Upstream) vom ermittelten Basis-Branch. Gitignored Configs werden **nicht** kopiert — es gibt keine.

**Schlägt der Befehl fehl** (Branch existiert schon, Pfad belegt, Basis-Branch unbekannt): die Meldung von
`git` unverändert durchreichen, Ursache benennen und **das Task-File nicht anfassen**. Es ist nichts halb
angelegt, das aufgeräumt werden müsste.

---

### Phase 3: Task-File verankern

**Schritt 4: Worktree-Block einfügen**

Lies das Task-File und füge **direkt nach der H1-Titelzeile** (`# <PREFIX>-XXXX - ...`) einen Blockquote ein.
Falls bereits ein Worktree-Block existiert (Quote mit `🌳 **WORKTREE**`), aktualisiere ihn statt einen
neuen einzufügen.

**Weg A (mit Stack)** — fünf Metadaten-Zeilen:

```markdown
> 🎫 **JIRA**: `<jiraBaseUrl>/browse/<PREFIX>-XXXX`\
> 🌳 **WORKTREE**: `<worktreePrefix>/<PREFIX>-XXXX`\
> 🌿 **BRANCH**: `feature/<PREFIX>-XXXX[_<suffix>]`\
> 🐳 **STACK**: `https://<worktree-ordnername>.<stackDomain>` (URL nach Stack-Start)\
> 📅 **Angelegt**: <YYYY-MM-DD>
>
> 🧭 **Routing-Modell für Claude:** cwd bleibt Haupt-Repo. Code-Edits gehen mit absolutem Worktree-Pfad
> in den WORKTREE. Git-Befehle mit `git -C <WORKTREE> ...`. Task-File/CLAUDE.md/Docs aus dem Haupt-Repo.
```

**Weg B (ohne Stack)** — dieselbe Form, aber **ohne die STACK-Zeile**. Nicht auf `-` setzen: eine Zeile, die
nichts sagt, ist schlechter als keine. Dafür nennt der Block den Basis-Branch, von dem abgezweigt wurde:

```markdown
> 🎫 **JIRA**: `<jiraBaseUrl>/browse/<PREFIX>-XXXX`\
> 🌳 **WORKTREE**: `<worktreePrefix>/<PREFIX>-XXXX`\
> 🌿 **BRANCH**: `feature/<PREFIX>-XXXX[_<suffix>]` (von `<BASE>`)\
> 📅 **Angelegt**: <YYYY-MM-DD>
>
> 🧭 **Routing-Modell für Claude:** cwd bleibt Haupt-Repo. Code-Edits gehen mit absolutem Worktree-Pfad
> in den WORKTREE. Git-Befehle mit `git -C <WORKTREE> ...`. Task-File/CLAUDE.md/Docs aus dem Haupt-Repo.
```

Die Metadaten-Zeilen enden auf einen Backslash `\` — das ist ein harter Markdown-Zeilenumbruch. Ohne ihn
kollabiert der Blockquote im gerenderten Task-File zu einer einzigen Zeile. Backslashes beim Einfügen also
mitkopieren, nicht entfernen. (Die **letzte** Metadaten-Zeile — `📅 Angelegt` — braucht keinen.)

Bei `usesJira: false` (`.claude/project.json`) **entfällt** die JIRA-Zeile — in beiden Wegen. Eine Zeile,
die auf ein nicht existierendes Ticket zeigt, ist schlechter als keine.

**Beispiel-Platzierung (Weg A):**

```markdown
# <PREFIX>-4426 - Anhänge werden nicht in der Dateiablage angezeigt

> 🎫 **JIRA**: `<jiraBaseUrl>/browse/<PREFIX>-4426`\
> 🌳 **WORKTREE**: `<worktreePrefix>/<PREFIX>-4426`\
> 🌿 **BRANCH**: `feature/<PREFIX>-4426`\
> 🐳 **STACK**: `https://<worktree-ordnername>.<stackDomain>`\
> 📅 **Angelegt**: 2026-05-27
>
> 🧭 **Routing-Modell für Claude:** cwd bleibt Haupt-Repo. Code-Edits gehen mit absolutem Worktree-Pfad
> in den WORKTREE. Git-Befehle mit `git -C <WORKTREE> ...`. Task-File/CLAUDE.md/Docs aus dem Haupt-Repo.

Typ: Bug

### Status
🟡 In Arbeit
```

> **Bestehende Task-Files nicht rückwirkend umschreiben.** Ein alter Block mit `🐳 **STACK**: -` bleibt, wie
> er ist — nur wenn du ihn ohnehin gerade aktualisierst, gilt die Form oben.

**Schritt 5: Status auf "In Arbeit" setzen**

Falls der Status noch `🔴 Offen` ist, auf `🟡 In Arbeit` aktualisieren.

---

### Phase 4: Zusammenfassung

**Schritt 6: Ergebnis ausgeben**

**Weg A** — übernimm den Output von `iwf worktree create` und ergänze die Task-File-relevanten Infos:

```
✅ TASK BEREIT FÜR WORKTREE-ARBEIT

Ticket:   <PREFIX>-XXXX
Branch:   feature/<PREFIX>-XXXX[_<suffix>]
Worktree: <worktreePrefix>/<PREFIX>-XXXX
Stack:    <worktree-ordnername>
URL:      https://<worktree-ordnername>.<stackDomain>  (nach Stack-Start)
Task:     <tasksPath>/<PREFIX>-XXXX*.md (Worktree-Block verankert, Status 🟡)

🚀 Stack starten (vom Haupt-Repo aus, falls nicht schon mit --start erledigt):
  iwf worktree start <NUMMER>

⚙️  Umsetzung starten (im Haupt-Repo):
  /solve-task <tasksPath>/<PREFIX>-XXXX*.md
```

**Weg B** — ohne Stack-Zeilen, dafür mit dem Basis-Branch (das ist die eine Angabe, die hier nicht aus einer
Konvention folgt):

```
✅ TASK BEREIT FÜR WORKTREE-ARBEIT

Ticket:   <PREFIX>-XXXX
Branch:   feature/<PREFIX>-XXXX[_<suffix>]  (von <BASE>)
Worktree: <worktreePrefix>/<PREFIX>-XXXX
Task:     <tasksPath>/<PREFIX>-XXXX*.md (Worktree-Block verankert, Status 🟡)

Dieses Projekt hat keinen Docker-Stack (dockerStack: false) — reiner Git-Worktree.

⚙️  Umsetzung starten (im Haupt-Repo):
  /solve-task <tasksPath>/<PREFIX>-XXXX*.md
```

---

## Wichtige Regeln

1. **Erst `.claude/project.json` lesen:** `dockerStack` entscheidet über den ganzen Ablauf. Raten heisst
   hier entweder ein `iwf`-Aufruf ins Leere oder ein fehlender Stack, den alle erwarten.
2. **Nackte Nummer:** `iwf worktree create` erwartet die Ticket-**Nummer** (`4519`), nicht `<PREFIX>-4519`.
   Vom Haupt-Repo aus ausführen (nicht aus einem Worktree).
3. **Stack ist opt-in (Weg A):** Ohne `--start` wird der Stack nur vorbereitet, nicht hochgefahren — erst
   `--start` (bzw. später `iwf worktree start <NUMMER>`) startet ihn. Grund für das Opt-in:
   Ressourcen-Verbrauch, lange Laufzeit, mögliche Konflikte zwischen parallelen Stacks.
4. **`--start` ohne Stack wird abgelehnt** (Weg B) — mit Begründung, nicht stillschweigend ignoriert.
5. **Block-Position:** Worktree-Block IMMER direkt unter H1. Bestehenden Block ersetzen, nicht duplizieren.
   Die STACK-Zeile steht nur auf Weg A.
6. **Branch-Schema:** `feature/<PREFIX>-<NUMMER>[_<english_title>]` — konsistent mit `solve-task`.
7. **Base-Branch:** Weg A = `origin/develop` (iwf-Konvention). Weg B = **ermittelt** (origin/HEAD →
   origin/develop → origin/main → develop → main → HEAD) und in der Zusammenfassung genannt.
8. **Suffix früh vergeben:** Branch-Suffix schon beim Anlegen mitgeben — ein Rename ist nur solange
   lokal/ungepusht gefahrlos.
9. **Secrets-Handling:** `iwf` kopiert `secrets/sensible.env` mit, gibt sie aber NIE im Klartext aus.

---

## Fehlerbehandlung

| Fehler                                                      | Reaktion                                                          |
|-------------------------------------------------------------|-------------------------------------------------------------------|
| `netbird up`-Ausgabe ≠ `Connected`/`Already Connected` (Phase 0, Weg A) | per `AskUserQuestion` erneut versuchen — Schleife bis `Connected`/`Already Connected` |
| Kein Task-File gefunden                                     | Hinweis auf `get-task` oder `create-task` ausgeben                |
| Mehrere passende Task-Files                                 | Benutzer fragen welches gemeint ist                               |
| `iwf` läuft aus einem Worktree heraus                       | Benutzer ins Haupt-Repo schicken                                  |
| `iwf worktree create` bricht ab (z.B. Stack-Konflikt, Cert) | Output prüfen; Eingabe (nackte Nummer) korrekt weitergeben        |
| `--start` bei `dockerStack: false`                          | Ablehnen mit Begründung (Schritt 3B), nichts anlegen              |
| `git worktree add` schlägt fehl (Branch/Pfad belegt)        | Meldung durchreichen, Ursache benennen, **Task-File nicht anfassen** |
| Kein `origin`-Remote (rein lokales Repo)                    | Basis-Branch = `HEAD`; in der Zusammenfassung ausdrücklich nennen |
| Bestehender Worktree, Branch unterscheidet sich             | Benutzer informieren — manuell prüfen                             |

---

Beginne damit, `.claude/project.json` zu lesen und `dockerStack` festzustellen. Auf Weg A dann Phase 0
(Netbird-Check) und erst bei bestehender Management-Verbindung weiter mit Phase 1; auf Weg B direkt
Phase 1.
