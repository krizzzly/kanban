---
name: create-worktree
description: Erstelle einen Git-Worktree für einen Task und verankere ihn im Task-File
argument-hint: <TICKET-NUMMER> oder <task-file.md> [--start]
disable-model-invocation: true
---

# CREATE WORKTREE - Git-Worktree für Task anlegen

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`):
> stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

Du erstellst einen Git-Worktree für einen bestehenden Task, indem du `iwf worktree create` aufrufst und
anschliessend den Worktree-Pfad ganz oben im Task-File verankerst.

Platzhalter in spitzen Klammern (`<PREFIX>`, `<tasksPath>`, `<worktreePrefix>`, `<stackDomain>`) stehen im
Folgenden für die entsprechenden Werte aus `.claude/project.json` — im Task-File landen immer die
**aufgelösten** Werte, keine Platzhalter. `<stackDomain>` ist nur die TLD (z.B. `test`): der Haupt-Stack
läuft auf `https://<repo-ordnername>.<stackDomain>`, ein Worktree-Stack auf
`https://<worktree-ordnername>.<stackDomain>` (Ordnername = letzter Pfadbestandteil).

> Vollständige Befehls-/Flag-Referenz zu `iwf worktree`: `~/Library/Application Support/Kanban/claude/rules/worktree.md`.

## Input

$ARGUMENTS

Akzeptierte Formate:

- **Ticket-Nummer:** `<PREFIX>-1234` → das passende Task-File wird per Glob gesucht (`<tasksPath>/<PREFIX>-1234*.md`)
- **Task-File-Pfad:** `<tasksPath>/<PREFIX>-1234_some_title.md` → direkt nutzen

## Voraussetzungen

- Ein Task-File existiert bereits unter `<tasksPath>/`. Falls nein → erst `/get-task <TICKET>` oder
  `/create-task ...` ausführen.
- Aktueller Pfad ist das Haupt-Repository (`<repoDir>`), NICHT ein Worktree.
- **Netbird-VPN-Tunnel** (nötig für den DB-Sync) — Phase 0 ruft `netbird up` auf (idempotent) und
  wiederholt bei Bedarf per hook-triggernder Rückfrage, bis die Ausgabe `Connected`/`Already Connected` meldet.

---

## Workflow

### Phase 0: Pre-Flight — DB-Sync-Verbindung (Netbird) sicherstellen

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
extrahieren. `iwf worktree create` erwartet die **nackte Nummer** als erstes Argument (NICHT `<PREFIX>-XXXX`):

| Task-File                                | TICKET          | NUMMER  | SUFFIX                  |
|------------------------------------------|-----------------|---------|-------------------------|
| `<PREFIX>-4460_fix_attachment_list.md`   | `<PREFIX>-4460` | `4460`  | `fix_attachment_list`   |
| `<PREFIX>-4426.md`                       | `<PREFIX>-4426` | `4426`  | _(leer)_                |

---

### Phase 2: `iwf worktree create` aufrufen

**Schritt 3: Worktree (+ optional Stack) anlegen**

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

---

### Phase 3: Task-File verankern

**Schritt 4: Worktree-Block einfügen**

Lies das Task-File und füge **direkt nach der H1-Titelzeile** (`# <PREFIX>-XXXX - ...`) einen Blockquote ein.
Falls bereits ein Worktree-Block existiert (Quote mit `🌳 **WORKTREE**`), aktualisiere ihn statt einen
neuen einzufügen.

**Einzufügender Block** (mit aufgelösten Werten, keine Platzhalter):

```markdown
> 🌳 **WORKTREE**: `<worktreePrefix>/<PREFIX>-XXXX`\
> 🌿 **BRANCH**: `feature/<PREFIX>-XXXX[_<suffix>]`\
> 🐳 **STACK**: `https://<worktree-ordnername>.<stackDomain>` (URL nach Stack-Start)\
> 📅 **Angelegt**: <YYYY-MM-DD>
>
> 🧭 **Routing-Modell für Claude:** cwd bleibt Haupt-Repo. Code-Edits gehen mit absolutem Worktree-Pfad
> in den WORKTREE. Git-Befehle mit `git -C <WORKTREE> ...`. Task-File/CLAUDE.md/Docs aus dem Haupt-Repo.
```

Die vier Metadaten-Zeilen (WORKTREE/BRANCH/STACK/Angelegt) enden auf einen Backslash `\` — das ist ein
harter Markdown-Zeilenumbruch. Ohne ihn kollabiert der Blockquote im gerenderten Task-File zu einer
einzigen Zeile. Backslashes beim Einfügen also mitkopieren, nicht entfernen.

**Beispiel-Platzierung:**

```markdown
# <PREFIX>-4426 - Anhänge werden nicht in der Dateiablage angezeigt

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

**Schritt 5: Status auf "In Arbeit" setzen**

Falls der Status noch `🔴 Offen` ist, auf `🟡 In Arbeit` aktualisieren.

---

### Phase 4: Zusammenfassung

**Schritt 6: Ergebnis ausgeben**

Übernimm den Output von `iwf worktree create` und ergänze die Task-File-relevanten Infos:

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

---

## Wichtige Regeln

1. **Nackte Nummer:** `iwf worktree create` erwartet die Ticket-**Nummer** (`4519`), nicht `<PREFIX>-4519`.
   Vom Haupt-Repo aus ausführen (nicht aus einem Worktree).
2. **Stack ist opt-in:** Ohne `--start` wird der Stack nur vorbereitet, nicht hochgefahren — erst `--start`
   (bzw. später `iwf worktree start <NUMMER>`) startet ihn. Grund für das Opt-in: Ressourcen-Verbrauch,
   lange Laufzeit, mögliche Konflikte zwischen parallelen Stacks.
3. **Block-Position:** Worktree-Block IMMER direkt unter H1. Bestehenden Block ersetzen, nicht duplizieren.
4. **Branch-Schema:** `feature/<PREFIX>-<NUMMER>[_<english_title>]` — konsistent mit `solve-task`.
5. **Base-Branch:** Neue Branches IMMER von `origin/develop`.
6. **Suffix früh vergeben:** Branch-Suffix schon beim `create` mitgeben — ein Rename ist nur solange
   lokal/ungepusht gefahrlos.
7. **Secrets-Handling:** `iwf` kopiert `secrets/sensible.env` mit, gibt sie aber NIE im Klartext aus.

---

## Fehlerbehandlung

| Fehler                                                      | Reaktion                                                          |
|-------------------------------------------------------------|-------------------------------------------------------------------|
| `netbird up`-Ausgabe ≠ `Connected`/`Already Connected` (Phase 0) | per `AskUserQuestion` erneut versuchen — Schleife bis `Connected`/`Already Connected` |
| Kein Task-File gefunden                                     | Hinweis auf `get-task` oder `create-task` ausgeben              |
| Mehrere passende Task-Files                                 | Benutzer fragen welches gemeint ist                               |
| `iwf` läuft aus einem Worktree heraus                       | Benutzer ins Haupt-Repo schicken                                  |
| `iwf worktree create` bricht ab (z.B. Stack-Konflikt, Cert) | Output prüfen; Eingabe (nackte Nummer) korrekt weitergeben        |
| Bestehender Worktree, Branch unterscheidet sich             | Benutzer informieren — manuell prüfen                             |

---

Beginne mit Phase 0: Pre-Flight (Netbird-Check). Nur bei bestehender Management-Verbindung weiter mit
Phase 1: Eingabe normalisieren.
