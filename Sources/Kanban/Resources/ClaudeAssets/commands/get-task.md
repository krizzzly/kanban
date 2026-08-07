---
description: Lade ein JIRA-Ticket und erstelle ein Task-File
argument-hint: <TICKET-NUMMER> [--no-worktree] [--stack]
---

# GET TASK - JIRA-Ticket laden

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`):
> stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

Lade das JIRA-Ticket, erstelle ein Task-File im Task-Ordner (`tasksPath` aus `.claude/project.json`) und lege
**per Default** direkt einen Worktree an (ohne Docker-Stack — der Stack wird nur auf ausdrücklichen Wunsch
hochgefahren).

Platzhalter in spitzen Klammern (`<PREFIX>`, `<tasksPath>`, `<worktreePrefix>`, `<stackDomain>`) stehen im
Folgenden für die entsprechenden Werte aus `.claude/project.json` — im Task-File landen immer die
**aufgelösten** Werte, keine Platzhalter. `<stackDomain>` ist nur die TLD (z.B. `test`): der Haupt-Stack
läuft auf `https://<repo-ordnername>.<stackDomain>`, ein Worktree-Stack auf
`https://<worktree-ordnername>.<stackDomain>` (Ordnername = letzter Pfadbestandteil).

## Ticket-Nummer

$ARGUMENTS

## Worktree-Verhalten (Default: Worktree AN, Stack AUS)

- **Standard:** Nach Erstellung des Task-Files wird automatisch ein Worktree angelegt — aber **nur** der
  Worktree (Git-Branch + Configs). Es wird **kein** Docker-Stack gestartet.
- **Stack-Opt-in:** Wenn `$ARGUMENTS` das Flag `--stack` enthält, wird zusätzlich der Docker-Stack
  hochgefahren (`iwf worktree create NNNN <suffix> --start`): TLS-Cert + `iwf stack start` + DB-Seed +
  die `postStart`-Hooks aus `.iwf.yml`.
- **Worktree-Opt-out:** Wenn `$ARGUMENTS` das Flag `--no-worktree` enthält, Worktree-Erstellung überspringen.
- Die Flags `--no-worktree`/`--stack` werden NICHT an das MCP-Tool weitergegeben — nur die Ticket-Nummer.

> Vollständige Befehls-/Flag-Referenz zu `iwf worktree`: `~/Library/Application Support/Kanban/claude/rules/worktree.md`.

## Anweisungen

1. **Verwende das MCP-Tool `mcp__hermes__generate-claude-task`** mit der angegebenen Ticket-Nummer
   (ohne `--no-worktree`/`--stack`-Flags!)
2. Das Tool erstellt automatisch eine Markdown-Datei unter `<tasksPath>/<TICKET-NUMMER>.md`
3. **`### Status`-Block einfügen** (siehe „Status-Block einfügen“) — das MCP-Tool erzeugt die Datei **ohne** Status
4. **Doppelte `## <Feldname>`-Sektionen entfernen** (siehe unten) — `## Weitere Felder` bleibt vollständig
5. Nach erfolgreichem Erstellen, zeige eine Zusammenfassung des Tickets
6. **Prüfe auf verwandte Tasks** (siehe unten)
7. **Worktree anlegen** (siehe unten, ausser `--no-worktree` gesetzt)

## Status-Block einfügen (PFLICHT)

Das MCP-Tool `generate-claude-task` erzeugt die Datei **ohne** `### Status`-Block. Direkt nach der Datei-Erstellung
den Block einfügen — **unmittelbar nach der `Typ:`-Zeile**, vor der ersten `##`-Section (i.d.R. `## Beschreibung`).
Diese Position ist verbindlich und identisch zu `create-task.md` / `create-worktree.md` — **nicht verschieben**
(sonst finden `solve-task` / `create-worktree` / `destroy-worktree` den Block beim Aktualisieren nicht).

```markdown
Typ: <Story/Bug/Task>

### Status
<STATUS-WERT>
```

Wert je nach Worktree-Verhalten (aus `$ARGUMENTS` bestimmt, VOR der Worktree-Erstellung):

- **Default (Worktree wird angelegt):** `🟡 In Arbeit`
- **`--no-worktree` gesetzt (kein Worktree):** `🔴 Offen`

## Doppelte Feld-Sektionen entfernen (PFLICHT)

Der Hermes-Generator schreibt die restlichen JIRA-Felder als Liste unter `## Weitere Felder` — und
rendert einen Teil davon **zusätzlich** als eigene `## <Feldname>`-Überschriften (z.B. `## Rang`,
`## Sprint`, `## Verrechnungstyp`, `## development`, `## Epic-Verknüpfung`,
`## Checklist Progress %`, `## Bereit für Umsetzung?`). Genau diese Doppelung ist das Problem.

- ✅ **`## Weitere Felder` bleibt vollständig erhalten** — kein Feld aus der Liste löschen, auch keine
  JIRA-Buchhaltung (`Rang`, `development`, `Statuskategorie`, Schätzungen …). Die Liste ist das
  gewollte Archiv der Ticket-Metadaten.
- ❌ **Löschen:** jede eigenständige `## <Feldname>`-Sektion, deren Feld schon unter
  `## Weitere Felder` steht — inklusive Überschrift und Wert.
- Eine Feld-Sektion, die **nicht** in `## Weitere Felder` auftaucht, bleibt stehen (kein Datenverlust).
- `## Weitere Felder` selbst wird nie entfernt, solange sie mindestens ein Feld enthält.

Kontrolle nach dem Bereinigen: `grep -n "^## " <tasksPath>/<FILE>.md` — übrig bleiben dürfen nur
inhaltliche Überschriften (`## Beschreibung`, `## Erwartetes Ergebnis / Verhalten`,
`## Akzeptanzkriterien`, ggf. weitere Textfelder) plus `## Weitere Felder` als letzte Sektion.

Hinweis: Eigentlich sollte der Generator die Felder nicht doppelt ausgeben — die saubere Lösung liegt
in `~/code/hermes/mcp-server/modules/jira/`. Bis das dort behoben ist, ist dieser Schritt das
Sicherheitsnetz.

## Verwandte Tasks auflösen

Nach dem Erstellen des Task-Files, prüfe ob das generierte File eine `## Verwandte Tasks` Sektion enthält.
Falls ja, lies für jeden verwandten Task das entsprechende Task-File ein (falls vorhanden unter `<tasksPath>/`).

### Format der Verwandte-Tasks-Sektion

```markdown
## Verwandte Tasks

- **<PREFIX>-XXXX** — Kurzbeschreibung der Beziehung zu diesem Task.
  Task-File: `<tasksPath>/<PREFIX>-XXXX_beschreibung.md`
```

### Auflösungsregeln

1. Suche im generierten Task-File nach der Sektion `## Verwandte Tasks`
2. Für jeden referenzierten Task:
   - Prüfe ob ein Task-File unter `<tasksPath>/<PREFIX>-XXXX*.md` existiert (Glob-Pattern)
   - Falls vorhanden: Lies die ersten 30 Zeilen und fasse den Kontext kurz zusammen
   - Falls nicht vorhanden: Erwähne dass kein lokales Task-File existiert
3. Zeige die verwandten Tasks in der Ausgabe an

## Worktree anlegen (Default — siehe Worktree-Verhalten oben)

**Falls `--no-worktree` NICHT im Input enthalten ist** und das Task-File erfolgreich erstellt wurde:

0. **Task-File-Namen normalisieren (PFLICHT, VOR der Worktree-Erstellung):** Das MCP-Tool legt die Datei als
   `<tasksPath>/<PREFIX>-NNNN.md` **ohne** englischen Titel an. Generiere zuerst aus der (deutschen)
   Ticket-Beschreibung einen kurzen **englischen** Titel (`snake_case`, lowercase, ~3-6 Wörter) und benenne
   die Datei um nach Schema `<tasksPath>/<PREFIX>-NNNN_<english_title>.md`. Erst danach weiter. (Die `comments.json`
   liegt im Unterordner `<PREFIX>-NNNN/` und bleibt über den relativen Link gültig.)
1. Branch-Suffix = der `<english_title>`-Teil des **normalisierten** Dateinamens. **Niemals leer lassen** —
   ein leerer Suffix erzeugt einen namenlosen Branch `feature/<PREFIX>-NNNN` (genau die Lücke, die hier
   geschlossen wird). Findet sich partout kein sinnvoller Titel, lieber einen knappen generischen wählen
   (z.B. `tech_fix`) als gar keinen.
2. `iwf worktree create NNNN <english_title>` ausführen (NNNN = nackte Ticket-Nummer, NICHT `<PREFIX>-NNNN`).
   **Falls `--stack` im Input enthalten ist**, `--start` anhängen:
   `iwf worktree create NNNN <english_title> --start`.
3. Nach erfolgreichem Script-Lauf den Worktree-Block direkt unter die H1 des Task-Files einfügen:

   ```markdown
   > 🌳 **WORKTREE**: `<worktreePrefix>/<PREFIX>-NNNN`\
   > 🌿 **BRANCH**: `feature/<PREFIX>-NNNN_<english_title>`\
   > 🐳 **STACK**: `https://<worktree-ordnername>.<stackDomain>`\
   > 📅 **Angelegt**: <YYYY-MM-DD>
   >
   > 🧭 **Routing-Modell für Claude:** cwd bleibt Haupt-Repo. Code-Edits gehen mit absolutem Worktree-Pfad
   > in den WORKTREE. Git-Befehle mit `git -C <WORKTREE> ...`. Task-File/CLAUDE.md/Docs aus dem Haupt-Repo.
   ```

   Alle Platzhalter mit den aufgelösten Werten aus `.claude/project.json` füllen. Die Stack-URL ist erst
   nach Stack-Start erreichbar.

   `iwf worktree create` legt per Default **nur** den Worktree an (Branch + Configs + vorbereiteter Stack,
   aber NICHT gestartet). Mit `--start` wird der Stack zusätzlich hochgefahren — dann komplett durchlaufen
   lassen. Der Stack kann auch später gestartet werden: `iwf worktree start NNNN`.

**Falls `--no-worktree` gesetzt:** Worktree-Schritt komplett überspringen, in der Ausgabe entsprechend hinweisen.

## Ausgabe

Nach dem Laden des Tickets, gib folgende Informationen aus:

```
✅ Task-File erstellt: <tasksPath>/<TICKET-NUMMER>_<english_title>.md
📊 Status: [🟡 In Arbeit / 🔴 Offen (--no-worktree)]
🌳 Worktree: [Pfad / "nicht angelegt (--no-worktree)"]

## <TICKET-NUMMER> - <Titel>

**Typ:** <Story/Bug/Task>

### Beschreibung
<Kurze Zusammenfassung>

### Akzeptanzkriterien
<Falls vorhanden, auflisten>

### Verwandte Tasks
<Falls vorhanden: Liste mit Kurzbeschreibung und ob lokales Task-File existiert>

---

👉 Zur Analyse & Planung: `/start-task <tasksPath>/<TICKET-NUMMER>_<english_title>.md`
[falls Stack hochgezogen (--stack):]
🌐 URL: https://<worktree-ordnername>.<stackDomain>
[sonst:]
🐳 Stack bei Bedarf starten: `iwf worktree start <NUMMER>`
```

**Wichtig:** Nur wenn der Stack tatsächlich hochgezogen wurde (`--stack` → `iwf worktree create … --start`
durchgelaufen), als **letzte Zeile** der Ausgabe die fertige URL `https://<worktree-ordnername>.<stackDomain>` anzeigen. Falls
Teile des Stack-Setups fehlschlugen (z.B. DB-Seed ohne VPN), das kurz vermerken, aber die URL trotzdem zeigen
— der Stack ist auch ohne Dev-DB erreichbar. **Ohne `--stack`** stattdessen den `iwf worktree start`-Hinweis
zeigen (keine URL, da kein Stack läuft).

## Bei Fehlern

Falls das MCP-Tool `mcp__hermes__generate-claude-task` nicht erreichbar ist, gib folgende Meldung aus:

```
❌ JIRA-Ticket konnte nicht geladen werden

Das Hermes MCP-Tool ist nicht verbunden. Bitte stelle sicher, dass:
1. Der Hermes MCP-Server läuft
2. Du in JIRA eingeloggt bist

Versuche es erneut mit: /get-task <TICKET-NUMMER>
```

---

Führe jetzt das MCP-Tool aus mit der Ticket-Nummer: $ARGUMENTS
