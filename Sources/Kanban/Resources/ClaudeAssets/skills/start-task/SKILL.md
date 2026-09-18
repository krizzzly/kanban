---
name: start-task
description: Analysiere einen vorbereiteten JIRA-Task, erstelle einen verifizierbaren Lösungsplan und orchestriere Impact- und Quality-Sub-Skills
argument-hint: <TICKET-NUMMER oder task-file.md> [--no-worktree] [--quality=auto|full|lite|skip]
disable-model-invocation: true
---

# START TASK — Analyse & Lösungsplanung

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`)
> stehen in `.claude/project.json` im Repo-Root. Lies diese Datei zuerst; Projektwerte niemals raten.

`start-task` ist der **Analyse- und Planungs-Workflow** zwischen `get-task` und `solve-task`.

Er führt **keine Umsetzung** durch.

## Persistenter Workflow-State

Lies `.claude/rules/workflow-state.md` vollständig.

Bei unabhängiger Session `workflow_state.task` + `workflow_state.workspace` aus dem Task-File verwenden; ein
direkter `get_task_handoff` ist nur innerhalb derselben laufenden Invocation zusätzlicher Kontext.

`start-task` besitzt `workflow_state.start_task` und darf zusätzlich den **shared factual state**
`task/workspace` aktualisieren, wenn es Worktree-Recovery selbst real verifiziert oder den Workflow-Status ändert.
`impact-analysis` und `quality-analysis` schreiben ihre State-Slots selbst; `start-task` liest sie nur.

---

## Verantwortung und Handoff

### Erwarteter Upstream

Normalfall:

```text
get-task
  ↓
normalisiertes Task-File + optionaler Worktree
  ↓
start-task
```

`get-task` ist die Source of Truth für:

- JIRA-Ingestion,
- verlustfreie Task-File-Normalisierung,
- Dateinamen-Normalisierung,
- Worktree-Erstellung,
- initialen Status/Worktree-Block.

`start-task` **verifiziert** diesen Zustand nur und repariert fehlende Vorbereitung ausschließlich als
Kompatibilitäts-/Recovery-Pfad für direkt übergebene oder ältere Task-Files.

### Downstream und Sub-Skills

`start-task` erzeugt:

1. eine fachlich/technische Analyse,
2. einen konkreten Lösungsplan,
3. Traceability zu Akzeptanzkriterien bzw. erwartetem Verhalten,
4. einen **Embedded-Aufruf von `impact-analysis/SKILL.md`**,
5. Plan-Reconciliation anhand des `impact_handoff`,
6. einen **Embedded-Aufruf von `quality-analysis/SKILL.md`**,
7. die finale Synchronisierung von Plan, Impact und Quality.

`start-task` kennt dabei **nicht** die internen Analyseschritte der beiden Sub-Skills.
Es kennt nur deren Invocation Contracts und Handoffs.

Danach übernimmt `solve-task`.

---

## Input

**Input:** `$ARGUMENTS`

Erlaubt:

```text
<TICKET-NUMMER oder task-file.md> [--no-worktree] [--quality=auto|full|lite|skip]
```

- `--no-worktree` gilt nur, wenn noch kein gültiger Worktree existiert.
Im Embedded-Mode `review-bootstrap` gilt unabhängig davon: `create_worktree=false` und `switch_branch=false`.
- `--quality=auto` ist Default.
- `--quality=full` erzwingt einen FULL-Review.
- `--quality=lite` und `--quality=skip` sind Wünsche an `quality-analysis`; dessen Methodology darf bei
  belegten Triggern auf eine höhere Stufe eskalieren.
- Diese Flags niemals an JIRA-/MCP-Aufrufe weiterreichen.

---

# Phase 0 — Task-File, Repository-Snapshot und Routing bestimmen

## 0a) Task-File auflösen

### Argument ist eine Ticket-Nummer

Nur kanonische Task-Files suchen; Derived Artifacts ausschließen:

```bash
find <tasksPath> -maxdepth 1 -type f \
  \( -name "<TICKET-NUMMER>.md" -o -name "<TICKET-NUMMER>_*.md" \) \
  ! -name "<TICKET-NUMMER>_review.md" \
  ! -name "<TICKET-NUMMER>_security_review.md" \
  ! -name "<TICKET-NUMMER>_audit*.md"
```

| Befund | Aktion |
|---|---|
| Genau ein File | Als `<TASK_FILE>` verwenden |
| Mehrere Files | Dateien anzeigen und ABBRECHEN — nicht raten |
| Kein File | Den **authoritativen `get-task`-Sub-Skill** aus `../get-task/SKILL.md` ausführen; danach dessen finales `<TASK_FILE>` übernehmen |

Beim Fallback zu `get-task` dessen Regeln **nicht hier nachimplementieren oder verkürzt duplizieren**. Ein `--no-worktree` aus dem `start-task`-Input wird an diesen Fallback weitergereicht.

### Argument ist ein Pfad

- Existenz und Lesbarkeit prüfen.
- Als `<TASK_FILE>` verwenden.

Ohne gültiges Task-File kann `start-task` nicht fortfahren.

---

## 0a.1) Workflow-State laden

Nach Auflösung des kanonischen Task-Files den markierten State parsen.

- kein State: Legacy-/neuen v1-Block initialisieren, aber keine alten Fingerprints aus Prosa erraten,
- ein State: `version == 1` prüfen,
- mehrere/malformed States: STOP.

Falls `workflow_state.task`/`.workspace` existieren, Task-File/Pfad/Branch/Worktree gegen die Realität verifizieren.

---

## 0b) Task-File-Kopf und Worktree-Block lesen

Lies den Kopf des Task-Files und suche nach:

```markdown
> 🌳 **WORKTREE**: `<path>`\
> 🌿 **BRANCH**: `<branch>`\
```

### Routing-Regeln

| Zustand | Aktion |
|---|---|
| State vorhanden, Pfad existiert, Branch passt | `WORKTREE_ROUTING=active` |
| State/Legacy-Projektion vorhanden, aber Legacy-Branch ohne Titel-Suffix | Recovery 0c-legacy: Branch sicher normalisieren, dann Routing aktivieren |
| Workspace-State vorhanden, Pfad ungültig | Veralteten Block entfernen; danach Recovery-Pfad 0c |
| Kein Workspace, `--no-worktree` | `WORKTREE_ROUTING=off`; Recovery-Pfad 0d |
| Kein Workspace, Default | Recovery-Pfad 0c |

Bei aktivem Worktree-Routing:

- Source-Code (`src/`, `assets/`, `tests/`, `templates/`, `config/`, `migrations/` …) aus dem Worktree lesen.
- Git-Inspektion mit `git -C <WORKTREE_PATH> ...`.
- Task-File, `CLAUDE.md`, `.claude/*`, zentrale Docs aus dem Haupt-Repo lesen.
- Nicht versehentlich Source-Code aus Haupt-Repo und Worktree mischen.

---

## 0c) Recovery: fehlenden Worktree vorbereiten

Dieser Pfad ist **nur** nötig, wenn `get-task` nicht vorher gelaufen ist oder ein älteres Task-File vorliegt.

1. Stelle sicher, dass der Dateiname dem Schema entspricht:

```text
<TICKET-NUMMER>_<english_title>.md
```

2. Falls nicht: denselben Normalisierungsstandard wie `get-task` verwenden.
3. Aus dem finalen Namen `<english_title>` bestimmen.
4. Worktree anlegen:

```bash
iwf worktree create NNNN <english_title>
```

5. Nach Erfolg Worktree-Block im Format von `get-task` einfügen und Status auf `🟡 In Arbeit` setzen.
6. `WORKTREE_ROUTING=active`.

Die detaillierten Worktree-Regeln stehen in `.claude/rules/worktree.md` und werden hier nicht dupliziert.

### 0c-legacy) Gültiger Worktree mit suffixlosem Legacy-Branch

Wenn ein älteres Task-File bereits einen gültigen Worktree besitzt, der Branch aber nur
`feature/<PREFIX>-NNNN` heißt:

1. finalen normalisierten `<english_title>` bestimmen,
2. lokalen Branch im Worktree auf `feature/<PREFIX>-NNNN_<english_title>` umbenennen,
3. falls der alte Branch bereits remote existiert: neuen Branch pushen und erst danach den alten Remote-Branch löschen,
4. `🌿 **BRANCH**:` im Task-File aktualisieren.

Keine Force-Pushes verwenden.

---

## 0d) Recovery ohne Worktree (`--no-worktree`)

Vor einem automatischen Branch-Wechsel zuerst prüfen:

```bash
git status --short
```

Wenn uncommittete Änderungen vorhanden sind:

- **kein** automatisches `reset`, `stash` oder Überschreiben,
- Zustand klar melden und ABBRECHEN.

Wenn sauber:

```bash
git checkout develop
git pull --ff-only
```

`--ff-only` verhindert unerwartete Merge-Commits.

---

## 0e) Already-Solved-/In-Progress-Check

Ticket-Nummer aus `<TASK_FILE>` bestimmen und den tatsächlichen Git-Zustand prüfen:

```bash
git log --oneline --all --grep='<TICKET-NUMMER>'
git branch -a --list '*<TICKET-NUMMER>*'
git log --oneline develop --grep='<TICKET-NUMMER>'
```

Bei Worktree-Routing entsprechend `git -C <WORKTREE_PATH>` verwenden, soweit sinnvoll.

### Status ableiten

| Befund | Task-Status |
|---|---|
| Ticket-Commits in `develop` | `🟢 Abgeschlossen` |
| Feature-Branch mit Ticket-Commits, nicht gemerged | `🟡 In Arbeit` |
| Keine Branch-/Commit-Spuren | `🔴 Offen` bzw. ab Analysebeginn `🟡 In Arbeit` |

Den Status im Task-File mit dem nachgewiesenen Zustand synchronisieren.

**Auch bei bereits implementierten Tasks:** Analyse durchführen. Der Input für spätere Impact-Analyse ändert sich dann von Plan zu tatsächlichem Codezustand, falls der Caller-Kontext das verlangt.

---

## Workflow-Status nach erfolgreichem Start

Nach finalem Readiness-Gate:

```text
READY → workflow_state.task.status = READY_FOR_IMPLEMENTATION
BLOCKED → workflow_state.task.status = IN_PROGRESS
```

Danach sichtbare Status-/Workspace-Projektion aus dem State synchronisieren.

---

# Phase 1 — Kontext verstehen

## Schritt 1: Projekt- und Task-Dokumentation lesen

1. `CLAUDE.md` im Projekt-Root lesen, falls vorhanden.
2. Von dort referenzierte Architektur-/Konventionsdokumente lesen, soweit für den Task relevant.
3. `<TASK_FILE>` vollständig lesen.
4. Explizit extrahieren:
   - Beschreibung / Problem,
   - erwartetes Ergebnis / Verhalten,
   - Akzeptanzkriterien,
   - verwandte Tasks,
   - bekannte Constraints / Hinweise.
5. Referenzierte lokale Task-Files nur dann vertieft lesen, wenn ihre Beziehung für die aktuelle Änderung relevant ist.

**Keine fachlichen Anforderungen erfinden.** Fehlende Informationen bleiben zunächst `unknown`.

---

## Schritt 2: Aktuelles Verhalten im Code verifizieren

Bevor eine Lösung geplant wird:

- Einstiegspunkt(e) des betroffenen Flows finden,
- relevantes aktuelles Verhalten im Code nachvollziehen,
- bestehende Tests suchen,
- bestehende ähnliche Implementierungen suchen,
- Konfiguration prüfen, wenn sie Verhalten deklariert.

Ziel: Ticket-Aussage und aktuellen Codezustand gegeneinander prüfen.

### Evidence Discipline

Während der Analyse zwischen drei Kategorien unterscheiden:

- **FACT** — direkt durch Task, Code, Config, Test oder Git belegt,
- **INFERENCE** — plausible Schlussfolgerung aus Facts,
- **UNKNOWN** — nicht ausreichend belegbar.

Eine Inference niemals als Fact in den Lösungsplan schreiben.

---

# Phase 2 — Fachliche und technische Analyse

## Schritt 3: Analyse dokumentieren

Unter `## Analyse` mindestens:

```markdown
## Analyse

**Art der Änderung:** <Feature | Bugfix | Refactoring | UI | Daten | Security | ...>

### Fachlicher Kontext
- **Aktuelles Verhalten:** ...
- **Erwartetes Verhalten:** ...
- **Warum:** ...

### Betroffene Bereiche
- Backend: ...
- Frontend: ...
- Datenbank/Persistenz: ...
- Config/Security/Async/Integration: ...

### Technische Einordnung
...

### Evidenz / Annahmen
- FACT: ...
- INFERENCE: ...
- UNKNOWN: ...
```

Nur tatsächlich relevante Kategorien aufführen; keine künstlichen Abschnitte füllen.

---

## Schritt 4: Spezifische Vorabprüfungen

### Berechtigungen

Falls Rollen/Permissions betroffen sind:

- Backend-Gating und FE-Gating identifizieren,
- bestehende Controller-/Permission-Tests suchen,
- erlaubte und verbotene Rollen im Plan berücksichtigen.

Beispiel:

```bash
grep -r '<ControllerName>' tests/Controller/ --include='*.php' -l
```

### Datenmigration

Falls bestehende Daten verändert, transformiert oder neu berechnet werden müssen:

- Schema-Migration vs. Datenmigration unterscheiden,
- projektüblichen Mechanismus aus Dokumentation/Code bestimmen,
- Backfill/Recalc/Bestandsdaten explizit planen,
- keine Migrationsart aus Gewohnheit raten.

### Externe / asynchrone Nebenwirkungen

Falls der Flow externe APIs, Mail, Queue, Scheduler oder andere Side Effects berührt, im Analyseabschnitt kenntlich machen. Die vollständige Risikoanalyse erfolgt später zentral in `impact-analysis`.

---

## Schritt 5: Unklarheiten auflösen

Vor einer Rückfrage zuerst alles lokal Beantwortbare aus:

- Task,
- Projekt-Doku,
- Code,
- Tests,
- Config,
- Git-Historie

prüfen.

Nur dann nachfragen, wenn ein `UNKNOWN` die Lösung **materiell** verändert (z.B. anderes fachliches Verhalten, Datenverlust-Risiko, Security, inkompatible API).

Nicht-blockierende Unsicherheiten dokumentieren und mit einer defensiven Planannahme kennzeichnen, statt unnötig zu stoppen.

---

# Phase 3 — Lösungsplan

## Schritt 6: Konkreten Plan erstellen

Unter `## Lösungsplan` einen implementierbaren Plan erstellen.

Jeder Plan-Schritt sollte möglichst enthalten:

- betroffene Datei/Klasse/Symbol,
- beabsichtigte Verhaltensänderung,
- warum diese Änderung nötig ist,
- zugehörigen Test bzw. Verifikation.

Beispiel:

```markdown
## Lösungsplan

### Backend
1. `src/.../FooHandler.php::handle()`
   - Guard für ... anpassen, damit ...
   - bestehende Invariante ... beibehalten
   - Test: `tests/.../FooHandlerTest.php`

### Frontend
2. `assets/.../FooPage.tsx`
   - neues Response-Feld ... darstellen
   - Empty-State für `null`
   - Test: Component/E2E ...

### Persistenz
3. ...

### Tests
4. ...
```

### Planregeln

- Tests für jede geänderte Business-Logik einplanen.
- Bestehende Tests bevorzugt erweitern, wenn sie bereits die relevante Verantwortung besitzen.
- Keine rein dateibasierte To-do-Liste; jeder Schritt beschreibt die Verhaltensabsicht.
- Keine spekulativen Änderungen „vorsichtshalber“ aufnehmen.

---

## Schritt 7: Acceptance-Criteria-/Behavior-Traceability

Wenn explizite Akzeptanzkriterien existieren, unterhalb des Plans eine Zuordnung anlegen:

```markdown
### Traceability

| AC | Plan-Schritt(e) | Verifikation |
|---|---|---|
| AC-1 | 1, 4 | Controller-/Integrationstest |
| AC-2 | 2, 5 | Component/E2E |
```

Wenn es keine formalen ACs gibt, stattdessen die explizit formulierten erwarteten Verhaltenspunkte verwenden.

**Nicht künstlich neue Acceptance Criteria erfinden.**

---

# Phase 4 — Impact-Sub-Skill

## Schritt 8: `impact-analysis/SKILL.md` aufrufen

Rufe **nicht** `impact-analysis/methodology.md` direkt auf.

Verwende ausschließlich:

```text
../impact-analysis/SKILL.md
```

Der Impact-Skill ist verantwortlich für:

- normalisierten Analyse-Snapshot,
- Source-Fingerprint,
- Ausführung seiner eigenen `methodology.md`,
- Persistenz von `## Impact-Analyse`,
- Rückgabe des `impact_handoff`.

`start-task` kennt oder dupliziert die internen Impact-Schritte nicht.

### Embedded Invocation Context

Übergebe:

```yaml
caller: start-task
primary_source: plan
task_file: <TASK_FILE>
ticket: <TICKET-NUMMER>
repository_path: <WORKTREE_PATH oder Haupt-Repo>
base: null
head: null
output_target: <TASK_FILE>
```

Die aktuelle `## Analyse`, Task-Beschreibung, Akzeptanzkriterien und der aktuelle
`## Lösungsplan` stehen über das Task-File als fachlicher Kontext zur Verfügung.

### Impact-Handoff verarbeiten

Erwarte mindestens:

```yaml
impact_handoff:
  source_fingerprint: ...
  semantic_changes: [C-*]
  impact_paths: [P-*]
  invariants: [INV-*]
  risks:
    critical: [R-*]
    high: [R-*]
    medium: [R-*]
  open_unknowns: [...]
  test_matrix_present: true|false
  caller_reconciliation_required: true|false
```

### Plan-Reconciliation gehört zu `start-task`

Wenn `caller_reconciliation_required=true` oder bestätigte Findings zeigen, dass der Plan:

- einen notwendigen Counterpart übersieht,
- eine Invariante/Designintention verletzt,
- einen Write-/Read-/Async-/Lifecycle-Pfad nicht berücksichtigt,
- eine relevante Business-Variante auslässt,
- eine Migration/Security-/Concurrency-Lücke enthält,
- oder einen erforderlichen Test nicht plant,

dann:

1. `## Lösungsplan` anpassen,
2. Traceability aktualisieren,
3. **den Impact-Sub-Skill erneut gegen den neuen Plan aufrufen**.

Nicht versuchen, den alten Impact-Report manuell „zurechtzupatchen“.
Der geänderte Plan besitzt einen neuen Source-Fingerprint.

### Stabilitätsregel

Maximal zwei Plan→Impact-Reconciliation-Zyklen innerhalb von `start-task`.

Falls danach noch `CRITICAL/HIGH`-Risiken ohne belastbare Behandlung oder wesentliche `UNKNOWN`s bestehen:

- nicht künstlich freigeben,
- als blockierende offene Punkte dokumentieren,
- späteren Quality-/Solve-Schritt entsprechend kennzeichnen.

---

# Phase 5 — Quality-Sub-Skill

## Schritt 9: `quality-analysis/SKILL.md` aufrufen

Nach einem stabilen Impact-Stand rufe **nicht** `quality-analysis/methodology.md` direkt auf.

Verwende:

```text
../quality-analysis/SKILL.md
```

Der Quality-Skill ist verantwortlich für:

- Prüfung der Impact-Freshness,
- ggf. erneuten Aufruf von `impact-analysis/SKILL.md`,
- Entscheidung des effektiven Scopes `FULL` / `LITE` / `SKIP`,
- Ausführung seiner eigenen `methodology.md`,
- Quality-Plan-Delta,
- ggf. Impact-Recheck nach semantischem Quality-Delta,
- Persistenz des Quality-Reviews,
- Rückgabe des `quality_handoff`.

`start-task` dupliziert weder Triage-Regeln noch Quality-Gates, Principles oder Pattern-Regeln.

### Gewünschten Quality-Scope bestimmen

Aus `$ARGUMENTS`:

```text
kein Flag           → requested_scope: auto
--quality=auto      → requested_scope: auto
--quality=full      → requested_scope: full
--quality=lite      → requested_scope: lite
--quality=skip      → requested_scope: skip
```

`lite` und `skip` sind keine Garantie; die Quality-Methodology darf eskalieren.

### Embedded Invocation Context

```yaml
caller: start-task
review_mode: plan
task_file: <TASK_FILE>
ticket: <TICKET-NUMMER>
repository_path: <WORKTREE_PATH oder Haupt-Repo>
base: null
head: null
requested_scope: <auto|full|lite|skip>
output_target: <TASK_FILE>
```

Der Quality-Skill findet und validiert die aktuelle `## Impact-Analyse` selbst.
`start-task` übergibt keine nachgebauten Quality-Kriterien.

### Quality-Handoff verarbeiten

Erwarte mindestens:

```yaml
quality_handoff:
  review_source_fingerprint: ...
  impact_source_fingerprint: ...
  requested_scope: ...
  effective_scope: FULL|LITE|SKIP
  decision: FREIGEGEBEN | FREIGEGEBEN MIT ÄNDERUNGEN | PLAN/DESIGN ÜBERARBEITEN
  decisions: [D-*]
  findings: [Q-*]
  quality_plan_delta: [ΔQ-*]
  impact_recheck:
    required: true|false
    completed: true|false
  security_followup:
    level: NONE | FEATURE_SECURITY_REVIEW | FULL_APP_AUDIT_RECOMMENDED
    reasons: [...]
    suggested_timing: after-implementation | pre-release | periodic | now
  open_unknowns: [...]
```

### Verantwortung nach Rückkehr

Der Quality-Skill führt seine eigene Quality↔Impact-Reconciliation durch.

`start-task` führt einen empfohlenen `audit-security` **nicht automatisch** aus. Es dokumentiert den `security_followup` für die spätere Review-/Release-Phase. Ein Full-App-Audit vor Implementierung würde einen noch nicht existierenden Systemstand prüfen.

`start-task` prüft danach nur noch:

1. Ist der im Task-File stehende Lösungsplan die vom Quality-Review freigegebene/reconciliierte Fassung?
2. Stimmen `review_source_fingerprint` und aktueller Planstand überein?
3. Falls ein Impact-Recheck erforderlich war: `completed=true`?
4. Gibt es offene blockierende `Q-*`, `R-*` oder `UNKNOWN`s?

Wenn der Quality-Skill `PLAN/DESIGN ÜBERARBEITEN` zurückgibt oder ein erforderlicher Impact-Recheck
nicht abgeschlossen ist, darf `start-task` nicht „Bereit zur Umsetzung“ melden.


# Phase 6 — Abschluss

## Schritt 10: Completion Gate

Vor Abschluss muss gelten:

```markdown
## Abschluss-Checkliste

- [x] Task-File und Repository-Snapshot eindeutig bestimmt
- [x] Already-Solved-/In-Progress-Check durchgeführt
- [x] Projekt-/Task-Dokumentation gelesen
- [x] aktuelles Verhalten im Code verifiziert
- [x] Analyse dokumentiert
- [x] Lösungsplan erstellt
- [x] Acceptance Criteria / erwartetes Verhalten auf Plan + Tests gemappt
- [x] `impact-analysis/SKILL.md` mit Embedded Context ausgeführt
- [x] `impact_handoff` verarbeitet und notwendige Plan-Anpassungen eingearbeitet
- [x] finaler Impact-Fingerprint passt zum aktuellen Lösungsplan
- [x] keine ungeklärten high/critical Impact-Risiken ohne Plan/Test/gezielte Rückfrage
- [x] `quality-analysis/SKILL.md` mit Embedded Context ausgeführt
- [x] effektiver Quality-Scope (`FULL` / `LITE` / `SKIP`) dokumentiert
- [x] Quality-Plan-Delta und ggf. Impact-Recheck durch Quality vollständig reconciled
- [x] finaler Quality-Fingerprint passt zum aktuellen Lösungsplan
- [ ] Lösung implementiert
- [ ] Tests/PHPStan ausgeführt und bestanden
- [ ] JIRA Lösungsfeld ausgefüllt
- [ ] Änderungen committed
```

Nur die Planungs-/Analyse-Punkte werden hier bereits abgehakt.

### Readiness Gate

`🟡 Bereit zur Umsetzung` nur wenn:

- Quality `decision` = `FREIGEGEBEN` oder `FREIGEGEBEN MIT ÄNDERUNGEN`,
- alle bestätigten notwendigen Quality-Änderungen im Plan enthalten sind,
- erforderliche Impact-Rechecks abgeschlossen sind,
- keine unbehandelten `CRITICAL/HIGH` Impact-Risiken verbleiben,
- keine blockierenden Quality-Findings/Unknowns verbleiben,
- finaler Plan-, Impact- und Quality-Fingerprint konsistent sind.

Andernfalls:

```text
🔴 PLAN/DESIGN MUSS ÜBERARBEITET WERDEN
```

und **nicht** zu `solve-task` weiterleiten.

## Schritt 11: Persistenten Start-State schreiben

Jetzt — **nach** dem Readiness Gate — `workflow_state.start_task` schreiben:

```yaml
start_task:
  plan_fingerprint: <FINAL_PLAN_FINGERPRINT>
  planning_base: <resolved-base-or-parent>
  readiness: READY | BLOCKED
  blocking_reasons: [...]
```

Für `READY` muss gelten:

```text
workflow_state.start_task.plan_fingerprint
== workflow_state.impact.plan.source_fingerprint
== workflow_state.quality.plan.review_source_fingerprint
```

Nur `workflow_state.start_task` ändern; fremde Namespaces erhalten. Anschließend den State erneut parsen und die
Postcondition verifizieren.

---

## Abschlussausgabe

```text
📋 ANALYSE & PLANUNG ABGESCHLOSSEN

Ticket: <TICKET-NUMMER>
Branch: <BRANCH oder --no-worktree>
Worktree: <Pfad oder nicht angelegt>
Status: <🟡 Bereit zur Umsetzung | 🔴 Plan/Design muss überarbeitet werden>

## Zusammenfassung
<1–2 Sätze>

## Lösungsplan
<Kompakte Liste der finalen Plan-Schritte>

## Traceability
<AC/Behavior vollständig abgedeckt: ja/nein; offene Punkte>

## Impact-Analyse
- Source-Fingerprint: <...>
- Semantic Changes: <Anzahl>
- Impact-Pfade: <Anzahl>
- High/Critical Risks: <Anzahl>
- Plan-Anpassungen aus Impact-Handoff: <ja/nein + kurz>

## Quality-Analyse

- Requested Scope: <auto/full/lite/skip>
- Effective Scope: <FULL / LITE / SKIP>
- Entscheidung: <FREIGEGEBEN / FREIGEGEBEN MIT ÄNDERUNGEN / PLAN/DESIGN ÜBERARBEITEN>
- Review-Fingerprint: <...>
- Findings: <Anzahl / wichtigste>
- Plan-Anpassungen aus Quality: <ja/nein + kurz>
- Impact-Recheck: <nicht nötig / durchgeführt>
- Security-Follow-up: <NONE / FEATURE_SECURITY_REVIEW / FULL_APP_AUDIT_RECOMMENDED> — <Timing/Grund>
- Offene blockierende Unknowns: <Anzahl>

<nur wenn Readiness Gate erfüllt:>
👉 Zur Umsetzung: `/solve-task <TASK_FILE>`
```

Nach dieser Meldung STOPPEN. Keine Implementierung beginnen.

Zusätzlich unmittelbarer Return:

```yaml
start_task_handoff:
  plan_fingerprint: <...>
  readiness: READY|BLOCKED
  blocking_reasons: [...]
```

Zwischen Sessions ist `workflow_state.start_task` maßgeblich.

---

## Wichtige Regeln

1. **Keine Umsetzung:** `start-task` analysiert und plant nur.
2. **Upstream respektieren:** `get-task`-Bootstrap nicht unnötig wiederholen.
3. **Keine destruktive Git-Reparatur:** kein automatisches `reset`, `stash`, Force-Push.
4. **Evidence vor Annahme:** Code/Config/Test prüfen, bevor geraten wird.
5. **Sub-Skill-Grenzen:** `start-task` ruft `impact-analysis/SKILL.md` und `quality-analysis/SKILL.md` auf — niemals deren `methodology.md` direkt.
6. **Single Source of Truth:** Impact- und Quality-Regeln bleiben in den jeweiligen Sub-Skills; `start-task` kennt nur Contracts/Handoffs.
7. **Plan ist verhaltensorientiert:** nicht nur geänderte Dateien aufzählen.
8. **Impact ist ein Feedback-Loop:** Impact-Handoffs dürfen den Plan verändern; danach Impact neu fingerprinten.
9. **Quality ist downstream von Impact:** Freshness und Quality↔Impact-Reconciliation liegen im Quality-Sub-Skill.
10. **Keine ungeklärten kritischen Risiken verschweigen.**
11. Branch-/Dateinamen auf Englisch nach Projektkonvention.
12. Projektkonventionen aus `CLAUDE.md` und — falls vorhanden — `docs/claude/code_review_learnings.md` berücksichtigen.
13. Namespaces gemäß Projektkonvention importieren (`use` statt unnötig vollqualifizierter Namen im Code).
14. Übersetzungsregeln aus der projektspezifischen Translation-Rule befolgen; keine hardcodierten UI-Strings einplanen.
15. Dieser Workflow erfordert gründliche Analyse (`ULTRATHINK` im Claude-Workflow, falls dort unterstützt).
16. **Workflow-State:** nur `workflow_state.start_task` schreiben; Plan-Impact/-Quality aus deren State-Slots lesen.

---

Beginne mit Phase 0.
