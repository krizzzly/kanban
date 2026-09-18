---
name: get-task
description: Lade ein JIRA-Ticket, normalisiere das Task-File und bereite optional Worktree/Stack für start-task vor
argument-hint: <TICKET-NUMMER> [--no-worktree] [--stack]
disable-model-invocation: true
---

# GET TASK — JIRA-Ingestion & Task-Bootstrap

> `get-task` ist der **Bootstrap-/Ingestion-Schritt** der Task-Lane.
> Er führt **keine fachliche Analyse, Impact-Analyse oder Quality-Analyse** durch.
> Sein Ergebnis ist ein stabiler, normalisierter Task-Kontext für `start-task`.

## 1. Rolle im Gesamt-Workflow

```text
JIRA
  ↓
get-task
  ├── Ticket laden
  ├── Task-File normalisieren
  ├── Metadaten bereinigen
  ├── verwandte Tasks auflösen
  └── Worktree/Stack vorbereiten
        ↓
start-task
  ├── fachliche Analyse + Lösungsplan
  ├── impact-analysis
  └── quality-analysis
```

`get-task` ruft `start-task` **nicht automatisch** auf; es gibt den nächsten Befehl aus.

---

## 2. Projektkontext

Lies zuerst `.claude/project.json` im Repo-Root.

Benötigte Projektwerte, z.B.:

- `prefix`
- `tasksPath`
- `repoDir`
- `worktreePrefix`
- `dockerStack`
- `stackDomain`
- `gitlabProjectPath`

niemals raten. `dockerStack: false` heisst: kein Docker-Stack — dann gibt es weder `stackDomain` noch
`iwf`, und Befehle laufen direkt im Worktree.

`<repo-ordnername>` = letzter Pfadbestandteil von `repoDir`.

## Workflow-State-Contract

Lies `.claude/rules/workflow-state.md` vollständig.

`get-task` initialisiert bzw. aktualisiert die gemeinsamen Fakten:

```text
workflow_state.task
workflow_state.workspace
```

nach erfolgreicher Normalisierung und realer Worktree-/Stack-Auflösung.

Es besitzt **keinen exklusiven `get_task`-Namespace**: Ticket, Task-File, Workflow-Status, Worktree, Branch,
Stack und Anlagedatum sind langlebige Task-/Workspace-Fakten und werden später auch von anderen Skills verifiziert
oder aktualisiert.

Der direkte `get_task_handoff` bleibt für denselben laufenden Caller bestehen; zwischen Sessions ist der
`workflow_state` maßgeblich.

---

## 3. Input normalisieren

Input:

```text
$ARGUMENTS
```

Akzeptiert:

```text
<TICKET-NUMMER> [--no-worktree] [--stack]
```

Regeln:

- Genau **eine** Ticket-Nummer verwenden.
- `--no-worktree` und `--stack` niemals an Hermes/JIRA weiterreichen.
- `--stack` ohne Worktree ist widersprüchlich:
  - falls gleichzeitig `--no-worktree --stack`: `--stack` ignorieren und sichtbar melden;
  - keinen Stack des Haupt-Repos implizit starten.
- **`--stack` bei `dockerStack: false` wird abgelehnt** — abbrechen, bevor irgendetwas angelegt wird:

  ```
  ❌ --stack gibt es in diesem Projekt nicht: dockerStack ist false, also gibt es keinen Docker-Stack
     zu starten. Ohne das Flag erneut aufrufen — Task-File und Git-Worktree entstehen ganz normal.
  ```

- **Wie der Worktree angelegt wird, entscheidet `dockerStack` in `.claude/project.json`:** `true` (oder
  fehlend) → `iwf worktree create`; `false` → reiner Git-Worktree per `git worktree add` mit
  ermitteltem Basis-Branch.
- Ticket muss zum konfigurierten Projekt-Prefix passen; Abweichung nicht still korrigieren.

> Vollständige Befehls-/Flag-Referenz zu beiden Wegen: `.claude/rules/worktree.md`.

Normalisierte Werte:

```yaml
ticket: <PREFIX>-NNNN
create_worktree: true|false
start_stack: true|false
```

---

## 4. Idempotenz: bestehenden lokalen Zustand zuerst prüfen

Bevor JIRA/Hermes aufgerufen wird, nur **kanonische Task-Files** suchen.

Abgeleitete Artefakte wie Review-/Security-/Audit-Reports dürfen nicht als Task-File erkannt werden.

```bash
find <tasksPath> -maxdepth 1 -type f \
  \( -name "<TICKET>.md" -o -name "<TICKET>_*.md" \) \
  ! -name "<TICKET>_review.md" \
  ! -name "<TICKET>_security_review.md" \
  ! -name "<TICKET>_audit*.md"
```

Treffer zusätzlich inhaltlich plausibilisieren (Task-Metadaten/JIRA-Inhalt, kein Report-Header).

### Genau ein kanonisches Task-File vorhanden

Nicht blind überschreiben.

Ein vorhandenes `<TICKET>_review.md` ohne echtes Task-File zählt ausdrücklich als **kein Task-File**;
in diesem Fall JIRA-Ingestion normal durchführen.

- vorhandenes File als `TASK_FILE` verwenden,
- prüfen, ob ein gültiger Worktree-Block existiert,
- falls der Benutzer lediglich denselben Task erneut aufruft, Bootstrap-Zustand reparieren/ergänzen,
- JIRA-Inhalt **nicht** automatisch neu generieren und lokale Analyse-/Plan-Abschnitte überschreiben.

Ausgabe kennzeichnen:

```text
♻️ Vorhandenes Task-File wiederverwendet
```

### Mehrere Task-Files vorhanden

Nicht raten.

- Dateien anzeigen,
- wenn exakt eines dem normalisierten Schema `<TICKET>_<english_title>.md` entspricht und die anderen klar alte unnormalisierte Duplikate sind, den Konflikt sichtbar dokumentieren,
- sonst abbrechen, damit kein falsches Task-File überschrieben wird.

### Kein Task-File vorhanden

Hermes/JIRA-Ingestion durchführen.

---

# 5. Neues Task-File aus JIRA erzeugen

Nur wenn lokal noch kein Task-File existiert:

1. `mcp__hermes__generate-claude-task` mit **nur** der Ticket-Nummer aufrufen.
2. Erwartetes Roh-File:
   ```text
   <tasksPath>/<TICKET>.md
   ```
3. Existenz des erzeugten Files verifizieren.
4. Erst danach mit Normalisierung fortfahren.

Bei fehlgeschlagenem MCP-Aufruf oder fehlendem Output-File abbrechen; keinen halbfertigen Worktree erzeugen.

---

# 6. Task-File IMMER normalisieren

> **Wichtig:** Die Normalisierung ist unabhängig davon, ob ein Worktree erzeugt wird.

Damit wird die frühere Lücke geschlossen, bei der `--no-worktree` die Datei als `<TICKET>.md`
belassen konnte, obwohl Downstream und Ausgabe `<TICKET>_<english_title>.md` erwarteten.

## 6.1 Englischen Kurztitel erzeugen

Aus JIRA-Titel/Beschreibung:

- Englisch,
- `snake_case`,
- lowercase,
- ca. 3–6 Wörter,
- fachlich aussagekräftig,
- keine Ticket-Nummer wiederholen.

Beispiel:

```text
PROJ-1234_allow_canton_report_export.md
```

Keinen leeren Suffix erlauben. Falls kein guter Titel ableitbar ist, einen knappen semantischen Fallback
verwenden (`permission_fix`, `report_export`, `data_migration`) statt `tech_fix`, sofern der Task Kontext liefert.

## 6.2 Datei umbenennen

Falls aktuell nur:

```text
<tasksPath>/<TICKET>.md
```

vorhanden ist:

```text
<tasksPath>/<TICKET>_<english_title>.md
```

erzeugen.

Bereits korrekt normalisierte Dateien nicht erneut umbenennen.

## 6.3 Workflow-State initialisieren

Nach Normalisierung des kanonischen Task-Files mindestens:

```yaml
workflow_state:
  version: 1
  task:
    ticket: <TICKET>
    task_file: <TASK_FILE>
    status: OPEN
  workspace:
    worktree: null
    branch: null
    stack:
      status: NONE
      url: null
    created_at: null
```

per Read-Modify-Write persistieren.

Falls bereits ein gültiger State existiert, keine fremden Analyse-Namespaces überschreiben.

Der alte separate:

```markdown
### Status
🔴 Offen
```

Abschnitt ist ab jetzt nur Legacy. Nach erfolgreicher State-Initialisierung kann er entfernt werden; der sichtbare
Status erscheint in der Status-/Workspace-Projektion direkt unter der H1.

---

# 7. Generiertes JIRA-Markdown bereinigen

## 7.1 Doppelte Feld-Sektionen entfernen

`## Weitere Felder` ist das vollständige Metadatenarchiv.

Wenn ein Feld dort bereits enthalten ist, eine zusätzliche eigenständige

```markdown
## <Feldname>
...
```

Sektion entfernen.

Regeln:

- `## Weitere Felder` nie wegen dieser Deduplication löschen.
- Keine eigenständige Sektion entfernen, wenn das Feld nicht unter `## Weitere Felder` vorkommt.
- Inhaltliche Sektionen erhalten:
  - `## Beschreibung`
  - `## Erwartetes Ergebnis / Verhalten`
  - `## Akzeptanzkriterien`
  - `## Verwandte Tasks`
  - andere echte Freitextfelder.

Kontrolle:

```bash
grep -n "^## " <TASK_FILE>
```

Diese Bereinigung ist ein Safety-Net für den Hermes-Generator; die eigentliche Generator-Ursache kann separat behoben werden.

---


## JIRA-Feld `Lösung` erhalten

Falls Hermes/JIRA ein Feld `Lösung` als eigenen Abschnitt

```markdown
## Lösung
...
```

liefert, ist dieser Abschnitt **inhaltliche Developer-Evidenz** und muss unverändert erhalten bleiben.

Regeln:

- nicht als technische Task-Metadaten umdeuten,
- nicht durch Commit-Message/Test-URL ersetzen,
- nicht bei Feld-Deduplication löschen, solange er nicht lediglich ein leerer Duplikat-Renderer desselben JIRA-Felds ist,
- spätere Workflows (`review-task`) dürfen diesen Abschnitt als Developer Declaration auswerten.


# 8. Verwandte Tasks auflösen

Falls `## Verwandte Tasks` vorhanden:

Für jede referenzierte Ticket-Nummer:

```bash
ls <tasksPath>/<RELATED-TICKET>*.md 2>/dev/null
```

Wenn vorhanden:

- Titel/Status lesen,
- relevante Task-Beschreibung bzw. Beziehung knapp erfassen,
- **keine Analyse-/Planlogik aus verwandten Tasks automatisch in den aktuellen Task kopieren**.

Wenn nicht vorhanden:

```text
kein lokales Task-File vorhanden
```

melden.

`get-task` lädt verwandte Tickets nicht rekursiv aus JIRA; das würde den Bootstrap unkontrolliert verbreitern.

---

# 9. Worktree-Zustand auflösen

Nur falls `create_worktree=true`.

## 9.1 Vorhandenen Worktree zuerst erkennen

Task-File auf vorhandenen Worktree-Block prüfen:

```markdown
> 🌳 **WORKTREE**: `...`
> 🌿 **BRANCH**: `...`
```

Zusätzlich Git/IWF-Zustand verifizieren.

### Gültiger Worktree existiert

Wiederverwenden.

- keinen zweiten Worktree anlegen,
- `workflow_state.task.status = IN_PROGRESS`,
- Branch-/Worktree-Werte aus dem realen Zustand übernehmen,
- bei `--stack`: Stack nur starten, falls er nicht bereits läuft.

### Worktree-Block vorhanden, Worktree fehlt

Stale Block entfernen/aktualisieren und danach neuen Worktree erzeugen.

### Kein Worktree vorhanden

Neu erzeugen.

---

# 10. Worktree erzeugen

Branch-Suffix = `<english_title>`.

**Mit Docker-Stack** (`dockerStack: true` oder fehlend):

```bash
iwf worktree create NNNN <english_title>
```

`NNNN` = nackte Ticket-Nummer.

**Ohne Docker-Stack** (`dockerStack: false`) — reiner Git-Worktree vom ermittelten Basis-Branch:

```bash
git -C <repoDir> worktree add <worktreePrefix>/<PREFIX>-NNNN \
    -b feature/<PREFIX>-NNNN_<english_title> --no-track "$BASE"
```

Schlägt das fehl (Branch existiert schon, Pfad belegt): Meldung durchreichen und den Worktree-Block
**nicht** schreiben — das Task-File steht ja schon, nur ohne Worktree.

Bei `--stack`:

```bash
iwf worktree create NNNN <english_title> --start
```

Nach Erfolg **realen Output verifizieren**:

- Worktree-Pfad existiert,
- Git-Worktree gültig,
- erwarteter Branch aktiv.

Erst dann:

```yaml
workflow_state:
  task:
    status: IN_PROGRESS
  workspace:
    worktree: <resolved-path>
    branch: <resolved-branch>
    stack:
      status: STOPPED | RUNNING
      url: <url|null>
    created_at: <YYYY-MM-DD|null>
```

setzen und die sichtbare Projektion aus diesem State neu rendern.

---

# 11. Sichtbare Status-/Workspace-Projektion

Direkt unter der H1 den aktuellen `workflow_state.task` + `workflow_state.workspace` menschenlesbar rendern:

```markdown
> 🎫 **JIRA**: `<jiraBaseUrl>/browse/<PREFIX>-NNNN`\
> 📌 **STATUS**: <mapped human status>\
> 🌳 **WORKTREE**: `<resolved-worktree-path | ->`\
> 🌿 **BRANCH**: `<resolved-feature-branch | ->`\
> 🐳 **STACK**: `<none | stopped | failed | running: https://...>`\
> 📅 **ANGELEGT**: <YYYY-MM-DD | ->
>
> 🧭 **Routing-Modell für Claude:** cwd bleibt Haupt-Repo. Source-Code-Reads/-Edits gehen mit absolutem
> Worktree-Pfad in den WORKTREE. Git-Befehle mit `git -C <WORKTREE> ...`.
> Task-File, `CLAUDE.md`, `.claude/*` und zentrale Docs aus dem Haupt-Repo.
```

Bei `usesJira: false` (`.claude/project.json`) **entfällt** die JIRA-Zeile — eine Zeile, die auf ein
nicht existierendes Ticket zeigt, ist schlechter als keine. Fehlt `jiraBaseUrl`, ebenso.

Die Projektion ist **nicht** die maschinenlesbare Wahrheit. Immer zuerst State aktualisieren, danach rendern.

Wenn Stack später gestartet/gestoppt wird, zuerst `workflow_state.workspace.stack` aktualisieren und danach diese
Projektion synchronisieren.

---

# 12. `--no-worktree`

Wenn `create_worktree=false`:

- kein Worktree anlegen,
- keinen Stack starten,
- `workflow_state.task.status = OPEN`,
- `workspace.worktree = null`,
- `workspace.branch = null`,
- `workspace.stack.status = NONE`,
- keine erfundenen Werte schreiben,
- sichtbare Projektion aus diesem State rendern.

Das Task-File ist trotzdem vollständig normalisiert.

---

# 13. Handoff an `start-task`

Persistenter Handoff zwischen Sessions:

```yaml
workflow_state:
  version: 1
  task:
    ticket: <TICKET>
    task_file: <TASK_FILE>
    status: OPEN|IN_PROGRESS
  workspace:
    worktree: <path|null>
    branch: <branch|null>
    stack:
      status: NONE|STOPPED|RUNNING|FAILED
      url: <url|null>
    created_at: <YYYY-MM-DD|null>
```

Per Read-Modify-Write gemäß `.claude/rules/workflow-state.md` persistieren.

Für den unmittelbaren Caller zusätzlich in der Ausgabe:

```yaml
get_task_handoff:
  ticket: <TICKET>
  task_file: <TASK_FILE>
  status: OPEN|IN_PROGRESS
  workspace:
    worktree: <path|null>
    branch: <branch|null>
    stack:
      status: NONE|STOPPED|RUNNING|FAILED
      url: <url|null>
    created_at: <YYYY-MM-DD|null>
  related_tasks: [...]
```

### Handoff-Postcondition

Vor Ausgabe des Handoffs:

```bash
test -f <TASK_FILE>
```

und verifizieren, dass `<TASK_FILE>` ein kanonisches Task-File und **kein** Derived Artifact (`*_review.md` etc.) ist.

Ohne diese Postcondition gilt `get-task` als fehlgeschlagen und darf keinen erfolgreichen Handoff ausgeben.

State-Postcondition:

- exakt ein State-Block,
- parsebares YAML,
- `workflow_state.version == 1`,
- `workflow_state.task.task_file == <TASK_FILE>`,
- `workflow_state.task.ticket == <TICKET>`,
- sichtbare Status-/Workspace-Projektion entspricht dem State.

Ohne diese Postcondition ebenfalls kein erfolgreicher Handoff.

`start-task` darf diese Angaben verifizieren, muss aber JIRA-Ingestion und Dateinormalisierung nicht nochmals regulär ausführen.
Seine entsprechende Logik ist nur Recovery für Legacy-/manuell angelegte Task-Files.

---

# 14. Ausgabe

```text
✅ TASK VORBEREITET

Ticket:    <TICKET>
Task-File: <TASK_FILE>
Status:    <🔴 Offen | 🟡 In Arbeit>
Worktree:  <Pfad | nicht angelegt>
Branch:    <Branch | —>
Stack:     <RUNNING URL | STOPPED | NONE>

## <TICKET> — <Titel>
Typ: <Story/Bug/Task>

### Beschreibung
<kurze Zusammenfassung>

### Akzeptanzkriterien
<vorhanden / keine expliziten>

### Verwandte Tasks
<Kurzliste>

👉 Nächster Schritt:
`/start-task <TASK_FILE>`
```

Falls Worktree vorhanden, Stack aber aus:

```text
🐳 Optional: `iwf worktree start <NNNN>`
```

Nur bei tatsächlich laufendem Stack URL ausgeben.

---

# 15. Fehlerbehandlung

| Situation | Verhalten |
|---|---|
| Hermes/JIRA nicht erreichbar | abbrechen; kein Worktree |
| Hermes erzeugt kein File | abbrechen; kein Worktree |
| mehrere mehrdeutige Task-Files | nicht raten |
| Rename-Ziel existiert bereits | nicht überschreiben; Konflikt melden |
| Worktree-Erstellung schlägt fehl | Status bleibt `🔴 Offen`; kein falscher Worktree-Block |
| Worktree-Block stale | Block reparieren, realen Zustand als Wahrheit verwenden |
| `--stack` + `--no-worktree` | Stack nicht starten; Widerspruch sichtbar melden |
| Stack-Start schlägt fehl | Worktree bleibt gültig; `STACK: stopped/failed`, Status kann `🟡 In Arbeit` bleiben |
| verwandtes Task-File fehlt | Hinweis; kein harter Fehler |

---

# 16. Wichtige Regeln

1. **Idempotent:** erneuter Aufruf zerstört keine lokale Analyse/Planung.
2. **Normalize first:** Task-File immer normalisieren, unabhängig vom Worktree.
3. **State follows reality:** Status/Stack/Worktree erst nach realer Verifikation setzen.
4. **JIRA-Ingestion ≠ Analyse:** keine fachlichen Annahmen oder Lösungsplanung in `get-task`.
5. **Persistenter Handoff:** Task-File ist die Source of Truth für `start-task`.
6. **Keine Duplikation:** `start-task` besitzt nur Recovery für fehlende Bootstrap-Schritte.
7. **Kein impliziter Haupt-Stack:** `--stack` gilt nur zusammen mit dem Task-Worktree.
8. **Keine stillen Überschreibungen:** lokale Task-Arbeit hat Vorrang vor erneutem Generator-Output.
9. **Derived Artifacts sind keine Task-Files:** `*_review.md`, Security-/Audit-Reports nie als Task-Bootstrap-Quelle verwenden.
10. **Workflow-State:** `task`/`workspace` nur aus real verifiziertem Zustand aktualisieren; Analyse-Namespaces erhalten.

---

# Starte jetzt

1. `.claude/project.json` lesen.
2. Input normalisieren.
3. bestehenden Task-/Worktree-Zustand prüfen.
4. nur falls nötig JIRA via Hermes laden.
5. Task-File normalisieren/bereinigen.
6. optional Worktree/Stack vorbereiten.
7. `workflow_state.task` + `.workspace` persistieren, Projektion synchronisieren + Parser-Postcondition prüfen.
8. Handoff + `/start-task` ausgeben.
