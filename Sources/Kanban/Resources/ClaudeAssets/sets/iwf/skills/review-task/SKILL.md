---
name: review-task
description: Rebase und reviewe die eigene oder fremde Implementierung eines Feature-Branches gegen dessen tatsächlichen Parent/MR-Target, Task-File, Plan-Impact, Plan-Quality und Projektregeln
argument-hint: <TICKET-NUMMER oder task-file.md> [--branch <feature-branch>] [--apply] [--comment] [--quality=auto|full|lite|skip]
disable-model-invocation: true
---

# REVIEW TASK — Branch-Review & Merge-Readiness-Orchestrator

> `review-task` reviewt **einen konkreten Feature-Branch** gegen das zugehörige vorbereitete Task-File.
> Dabei ist es unerheblich, ob der Branch in dieser Session durch `solve-task` entstanden ist oder von einem
> anderen Entwickler / einer anderen Session stammt.
>
> **Voraussetzung ist der vorbereitete fachliche Baseline-Kontext im Task-File:**
>
> - `start-task` ist gelaufen,
> - `## Analyse` und `## Lösungsplan` existieren,
> - eine Plan-`## Impact-Analyse` existiert,
> - eine Plan-Quality-Analyse existiert.
>
> Ein `implementation_handoff` aus `solve-task` ist **optional** und nur zusätzliche Evidenz.

```text
                         vorbereitetes Task-File
                    Analyse + Plan + Impact + Quality
                              │
              ┌───────────────┴────────────────┐
              │                                │
     eigene Umsetzung                 fremder Feature-Branch
   (solve-task-Handoff)              (kein Handoff erforderlich)
              │                                │
              └───────────────┬────────────────┘
                              ▼
                         review-task
                              │
                  tatsächlichen Branch prüfen
                              │
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
          Impact(code)   Quality(code)   Conformance
                              │
                              ▼
                       Merge Readiness
```

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `dockerStack`, `stackDomain`,
> `gitlabProjectPath`): stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen
> Projektwert brauchst — nie raten. `dockerStack: false` heisst: kein Docker-Stack — dann gibt es weder
> `stackDomain` noch `iwf`, und Befehle laufen direkt im Worktree.

Die eigentliche Review-Methodik steht ausschließlich in [methodology.md](methodology.md).

---

# 1. Verantwortung dieses Skills

Dieser Skill ist zuständig für:

1. Task, Branch, Worktree und Base auflösen,
2. den **vollständigen zu reviewenden Working-Tree-Snapshot** festnageln,
3. den vorhandenen Plan-/Impact-/Quality-Baseline-Kontext aus dem Task-File validieren,
4. einen optionalen `implementation_handoff` aus `solve-task` als zusätzliche Evidenz/Freshness-Hinweis konsumieren,
5. `impact-analysis/SKILL.md` im Branch-/Working-Tree-Modus aufrufen,
6. `quality-analysis/SKILL.md` im Branch-Modus aufrufen,
7. `methodology.md` für Implementation-Conformance/Code-Review ausführen,
8. Tests/Static Analysis auf dem richtigen Source-Stand verifizieren,
9. optional ein vorhandenes Feature-`security-review` orchestrieren,
10. Report + `review_handoff` erzeugen und optionale Remediation **erst nach dem unveränderten Review-Snapshot** durchführen.

Dieser Skill ist **nicht** zuständig für:

- Plan-Impact selbst nachbauen,
- Architecture-Quality selbst nachbauen,
- Full-App Security Audit,
- ungefragtes Committen/Pushen.

---

# 2. Projektkontext

Lies `.claude/project.json`, danach:

- `CLAUDE.md`,
- referenzierte Architektur-/Konventionsdokumente,
- `.claude/rules/testing.md`,
- vorhandene Code-Review-Learnings,
- Permissions-/Rollen-Doku bei relevanten Änderungen.

Projektregeln sind autoritativ; generische Checklisten dürfen ihnen nicht widersprechen.

## Persistenter Workflow-State

Lies `.claude/rules/workflow-state.md` vollständig.

Bei unabhängiger `/review-task`-Session sind relevant:

```text
workflow_state.task
workflow_state.workspace
workflow_state.start_task
workflow_state.impact.plan
workflow_state.quality.plan
workflow_state.solve_task   # optional
```

`review-task` besitzt `workflow_state.review_task` und darf zusätzlich `workflow_state.task.status` sowie `workflow_state.workspace` ändern, wenn es deren realen Zustand selbst verändert/verifiziert.
Branch-Impact/-Quality schreiben ihre eigenen `.impact.branch` / `.quality.branch`-Slots.

---

# 3. Input

```text
$ARGUMENTS
```

Akzeptiert:

```text
<TICKET-NUMMER oder task-file.md>
[--branch <feature-branch>]
[--apply]
[--comment]
[--quality=auto|full|lite|skip]
```

- `--branch` legt den **zu reviewenden Feature-Branch explizit** fest und ist besonders wichtig beim Review fremder Branches.
- Default ist **review-only**.
- `--apply`: bestätigte Review-Findings dürfen nach Erstellung des Reports remediated werden.
- `--comment`: MR-Kommentare dürfen nach expliziter Nutzeraktion/Flag gepostet werden, falls ein MR existiert.
- `--quality=*`: gewünschter Scope für den Branch-Quality-Review; `lite/skip` dürfen von Quality eskaliert werden.

Keine impliziten extern sichtbaren Schreibaktionen.

---

# 4. Direct-Entry Bootstrap

`review-task` kann direkt mit nur einer Ticket-Nummer gestartet werden:

```text
/review-task <TICKET>
```

Auch wenn lokal noch kein Task-File oder noch keine vollständige `start-task`-Baseline vorhanden ist.

Die Bootstrap-Reihenfolge ist verbindlich.

## 4.1 ZUERST existierenden Feature-Branch finden

Bevor `get-task` oder `start-task` ausgeführt werden:

```bash
git branch -a --list "*<TICKET>*"
git worktree list
```

Falls GitLab/MR-Integration verfügbar ist, darf zusätzlich der zugehörige Remote-/MR-Branch zur Auflösung
verwendet werden.

Ergebnis:

```yaml
review_bootstrap:
  existing_feature_branch: <branch>
  existing_worktree: <path|null>
```

Bei mehreren plausiblen Branches ohne eindeutige Zuordnung: nicht raten.

> Ab diesem Moment ist der vorhandene Feature-Branch der Review-Gegenstand.
> Kein Bootstrap-Schritt darf einen zweiten Feature-Branch für denselben Task erzeugen.

## 4.2 Kanonisches Task-File auflösen — HARD GATE

Ein Review benötigt **immer zuerst ein echtes Task-File**.

### Was als Task-File zählt

Zulässig:

```text
<TICKET>.md
<TICKET>_<english_title>.md
```

Nicht als Task-File zählen abgeleitete Artefakte wie:

```text
<TICKET>_review.md
<TICKET>_security_review.md
<TICKET>_audit*.md
```

Task-File-Discovery darf deshalb **niemals** nur mit einem unfiltrierten

```bash
ls <tasksPath>/<TICKET>*.md
```

arbeiten.

Beispiel:

```bash
find <tasksPath> -maxdepth 1 -type f \
  \( -name "<TICKET>.md" -o -name "<TICKET>_*.md" \) \
  ! -name "<TICKET>_review.md" \
  ! -name "<TICKET>_security_review.md" \
  ! -name "<TICKET>_audit*.md"
```

Danach inhaltlich plausibilisieren:

- Ticket-Nummer passt,
- Datei ist **kein** Review-/Audit-Report,
- enthält Task-Metadaten wie `Typ:` / Beschreibung bzw. JIRA-Inhalt.

### Kein Task-File vorhanden → `get-task` MUSS laufen

Dann:

```text
../get-task/SKILL.md
```

mit:

```text
<TICKET> --no-worktree
```

als echten Sub-Workflow ausführen.

Der reale Feature-Branch existiert bereits; `get-task` darf hier nur:

- JIRA laden,
- Task-File normalisieren,
- Metadaten bereinigen.

Es darf keinen konkurrierenden Worktree/Branch anlegen.

### Postcondition nach `get-task` — PFLICHT

`review-task` muss den Handoff konsumieren:

```yaml
get_task_handoff:
  task_file: <TASK_FILE>
```

Danach:

```bash
test -f <TASK_FILE>
```

und das File erneut als **kanonisches Task-File** validieren.

Danach den `workflow_state` gemäß Rule laden. Fehlt er, einen v1-Block initialisieren; keine alten Fingerprints aus
Prosa erraten.

Nur wenn all das erfolgreich ist:

```yaml
task_file_gate:
  status: PASS
  task_file: <resolved-path>
  source: existing | get-task
```

darf der Workflow fortfahren.

Wenn:

- `get-task` fehlschlägt,
- kein `get_task_handoff.task_file` zurückkommt,
- die Datei nicht existiert,
- oder nur ein `_review.md`/anderes Derived Artifact existiert,

dann sofort:

```text
🔴 REVIEW BOOTSTRAP FAILED — TASK-FILE FEHLT
```

und **STOP**.

Insbesondere verboten:

- Review-Report erzeugen,
- `start-task` ohne echtes Task-File starten,
- Branch-Impact/Quality starten,
- ein `_review.md` als Ersatz für das Task-File verwenden.

## 4.3 Parent-/Target-Branch bereits für den Bootstrap auflösen

**Bevor `start-task` nachgeholt wird**, den tatsächlichen Parent bestimmen.

Priorität:

1. offener MR für den exakten Review-Branch → `MR.target_branch`,
2. expliziter Task-/Workflow-Parent,
3. Projekt-Default,
4. Remote-Default als Fallback.

Dieser Parent ist sowohl:

- Planungsbasis für den retrospektiven `start-task`-Bootstrap,
- Rebase-Ziel,
- Diff-/Impact-/Quality-Basis des eigentlichen Reviews.

```yaml
review_parent:
  branch: <PARENT>
  remote_ref: origin/<PARENT>
  source: merge_request | task_context | project_default | remote_default
```

## 4.4 Plan-Baseline fehlt → `start-task` im Review-Bootstrap-Modus

Falls im Task-File eines davon fehlt oder stale ist:

```text
## Analyse
## Lösungsplan
## Impact-Analyse
## Lösungsplan-Qualitätsreview
```

dann `../start-task/SKILL.md` als Embedded Review Bootstrap aufrufen:

```yaml
caller: review-task
mode: review-bootstrap
task_file: <TASK_FILE>
ticket: <TICKET>
existing_feature_branch: <REVIEW_BRANCH>
existing_worktree: <REVIEW_WORKTREE|null>
planning_source: parent
planning_base: origin/<PARENT>
create_worktree: false
switch_branch: false
quality_scope: auto
```

### Unabhängigkeitsregel für die Soll-Baseline

`start-task` erstellt die Soll-Baseline aus:

```text
Task/JIRA
+
Code des tatsächlichen Parent-/MR-Target-Branches
```

Der existierende Feature-Branch darf für operative Informationen verwendet werden:

- Branch-Name,
- Worktree-Pfad,
- Merge-Base,
- MR-Zuordnung.

Sein Implementierungsinhalt darf jedoch nicht zur Ableitung des Soll-Lösungsplans verwendet werden.

Damit vermeiden wir:

```text
fertigen Code lesen
→ daraus Plan formulieren
→ denselben Code später gegen diesen Plan reviewen
```

## 4.5 Danach normaler Review — inklusive Branch-Impact

Jetzt existieren bewusst zwei Perspektiven:

```text
SOLL
Task/JIRA + Parent/MR-Target
→ Analyse
→ Lösungsplan
→ Impact(plan)
→ Quality(plan)

IST
Feature-Branch
→ Impact(code)
→ Quality(code)
→ Implementation-Conformance
```

Der Branch-Impact ist **Pflicht** und gerade deshalb besonders wertvoll:
Er findet reale Side-Effects, die der Plan nicht vorausgesehen hat.

Verglichen werden insbesondere:

```text
Plan C-*      ↔ Branch C-*
Plan R-*      ↔ Branch R-*
Plan D-/Q-*   ↔ Branch D-/Q-*
Plan Tests    ↔ tatsächliche Tests
```

---

# 5. Task / Branch / Worktree auflösen

## 4.1 Task-File

Bei Ticket:

```bash
ls <tasksPath>/<TICKET>*.md 2>/dev/null
```

Mehrdeutigkeit nicht raten.

Das Task-File ist die **fachliche Review-Baseline** und gehört nicht notwendigerweise zum gerade in der Shell
ausgecheckten Branch.

## 4.2 Review-Branch

Priorität:

1. explizites `--branch <feature-branch>`,
2. gültiger Branch aus `workflow_state.workspace.branch`,
3. Legacy-Fallback: gültiger Branch aus sichtbarer Worktree-Projektion des Task-Files,
4. aktuell ausgecheckter eindeutig zum Ticket passender Feature-Branch,
5. genau ein lokaler/remote Branch mit Ticket-Nummer.

Bei mehreren möglichen Branches ohne explizite Auswahl: nicht raten.

**Wichtig:** Der Review-Branch darf von einem anderen Entwickler stammen. Es gibt keine Anforderung, dass
`solve-task` in der aktuellen Session oder überhaupt durch diesen Agenten ausgeführt wurde.

## 4.3 Arbeitsort

- existiert ein lokaler Worktree für genau den Review-Branch → dort lesen/reviewen,
- ist der Branch im Haupt-Repo ausgecheckt → dort,
- existiert er nur remote → gegen `origin/<branch>` reviewen.

Bei Remote-only gilt:

```text
working_tree_visibility: false
```

und lokale staged/unstaged Änderungen des Branch-Autors sind naturgemäß nicht sichtbar.

## 4.4 Base

Projektkonvention verwenden; sonst Remote-Default als Hinweis ermitteln:

```bash
git symbolic-ref refs/remotes/origin/HEAD --short
```

Den tatsächlichen Merge-Zielbranch des Projekts verwenden, nicht blind `develop`.

---

# 6. Pre-Review Rebase Gate — PFLICHT

Vor **jedem** eigentlichen Review muss der zu reviewende Feature-Branch auf den **aktuellen Remote-Stand seines
tatsächlichen Parent-/Target-Branches** rebased werden.

Erst nach erfolgreichem Rebase dürfen erzeugt/ausgeführt werden:

- Review-Snapshot / Fingerprint
- Branch-Impact
- Branch-Quality
- Feature-Security-Review
- Tests / Static Analysis
- `REV-*` Findings
- Merge-Readiness

## 6.1 Parent-/Target-Branch auflösen bzw. Bootstrap-Auflösung verifizieren

Der Parent darf **nicht pauschal `develop`** sein. Wurde er bereits im Direct-Entry-Bootstrap aufgelöst, hier gegen aktuellen MR-/Projektkontext verifizieren und unverändert weiterverwenden, sofern noch korrekt.

### A. Merge Request vorhanden

Den MR anhand des **exakten Source-Branches** ermitteln.

Wenn GitLab/Hermes verfügbar ist, z.B.:

```text
get-gitlab-merge-requests
sourceBranch: <REVIEW_BRANCH>
state: opened
```

Dann ist:

```text
MR.target_branch
```

die autoritative Review-/Rebase-Basis.

Beispiele:

```text
feature/PROJ-1234_foo → develop
feature/PROJ-1234_foo → release/2026-09
feature/PROJ-1234_foo → feature/PROJ-1200_parent
```

Bei mehreren offenen MRs desselben Source-Branches mit unterschiedlichen Targets:
**ambiguous parent** → Review stoppen, nicht raten.

### B. Kein MR vorhanden

Dann in dieser Reihenfolge:

1. explizit im Task-/Workflow-Kontext dokumentierter Parent-/Base-Branch,
2. projektspezifischer Default-Base aus `.claude/project.json` / `CLAUDE.md`, falls vorhanden,
3. Remote-Default als Fallback:

```bash
git symbolic-ref refs/remotes/origin/HEAD --short
```

Aufgelösten Parent für den gesamten Review festhalten:

```yaml
review_parent:
  source: merge_request | task_context | project_default | remote_default
  branch: <parent>
  remote_ref: origin/<parent>
  mr: <project>!<iid>|null
```

## 6.2 Remote-Stand aktualisieren

Vor dem Rebase:

```bash
git -C <REVIEW_REPO> fetch origin --prune
git -C <REVIEW_REPO> rev-parse origin/<PARENT>
```

Der Rebase erfolgt gegen:

```text
origin/<PARENT>
```

und nicht gegen einen eventuell veralteten lokalen Parent-Branch.

## 6.3 Vor-Rebase-Zustand dokumentieren

Vor jeder Mutation:

```bash
git -C <REVIEW_REPO> status --short
git -C <REVIEW_REPO> rev-parse HEAD
git -C <REVIEW_REPO> rev-parse origin/<PARENT>
```

Speichern:

```yaml
pre_review_rebase:
  feature_head_before: ...
  parent_sha: ...
  working_tree_dirty: true|false
  status_before: [...]
```

Keine `reset`, `clean`, `checkout --` oder andere destruktive Bereinigung.

## 6.4 Rebase ausführen

Für lokalen Review-Branch / Worktree:

```bash
git -C <REVIEW_REPO> rebase --autostash origin/<PARENT>
```

`--autostash` erhält staged/unstaged tracked Änderungen soweit Git dies sicher durchführen kann.

Untracked Dateien werden nicht versteckt; kollidieren sie mit dem Rebase, muss Git abbrechen.

### Bereits aktuell

Wenn Git meldet, dass der Branch aktuell ist:

```text
ALREADY_UP_TO_DATE
```

### Erfolgreich rebased

Danach:

```bash
git -C <REVIEW_REPO> status --short
git -C <REVIEW_REPO> rev-parse HEAD
git -C <REVIEW_REPO> merge-base HEAD origin/<PARENT>
```

Speichern:

```yaml
pre_review_rebase:
  status: REBASED | ALREADY_UP_TO_DATE
  feature_head_before: ...
  feature_head_after: ...
  parent_branch: ...
  parent_sha: ...
  working_tree_restored: true|false
```

Der **neue** `HEAD` ist ab jetzt Review-Gegenstand.

## 6.5 Rebase-Konflikt

Bei Konflikt:

```text
🔴 REVIEW BLOCKED — REBASE CONFLICT
```

Keinen Branch-Impact, keine Quality-Analyse und keinen Review-Report über einen halb aufgelösten
Rebase-Zustand erzeugen.

Dokumentieren:

- Parent-Branch
- Parent-SHA
- Feature-HEAD vor Rebase
- Konfliktdateien (`git status --short`)

Konfliktauflösung nicht automatisch erraten.

Review erst fortsetzen, wenn der Rebase erfolgreich abgeschlossen wurde.

## 6.6 Remote/MR-Synchronität nach lokalem Rebase

Ein Rebase verändert Commit-IDs.

Wenn ein MR existiert:

```bash
git -C <REVIEW_REPO> rev-parse HEAD
git -C <REVIEW_REPO> rev-parse origin/<REVIEW_BRANCH>
```

Klassifikation:

```text
MR_SOURCE_SYNCED
LOCAL_REBASE_NOT_PUSHED
NO_REMOTE_SOURCE_REF
```

Bei `LOCAL_REBASE_NOT_PUSHED` darf der **lokale Code-Review** vollständig durchgeführt werden.

Aber:

- keine Inline-MR-Kommentare auf Basis dieses lokal rebased Snapshots,
- `merge_ready` für den tatsächlichen MR nicht auf `true` setzen,
- Blocking Reason `REBASED_BRANCH_NOT_PUSHED`,
- Benutzer muss den rebased Branch selbst pushen,
- `review-task` pusht niemals selbst.

Nach dem Push vor MR-Kommentaren/Merge verifizieren, dass der Remote-MR-Source-SHA dem reviewten rebased SHA entspricht.

---

# 7. Plan-Baseline aus dem Task-File prüfen

Neben den menschenlesbaren Abschnitten muss für einen frischen Plan gelten:

```text
workflow_state.start_task.plan_fingerprint
== workflow_state.impact.plan.source_fingerprint
== workflow_state.quality.plan.review_source_fingerprint
```

Fehlt ein Slot oder passt ein Fingerprint nicht, `start-task` nachholen/reconciliieren. Markdown-Prosa allein ist
keine Freshness-Garantie.

Vor dem Branch-Review muss das Task-File mindestens enthalten:

```text
## Analyse
## Lösungsplan
## Impact-Analyse
## Lösungsplan-Qualitätsreview
```

Zusätzlich das aus JIRA importierte Feld prüfen:

```text
## Lösung
```

`## Lösung` ist **keine Voraussetzung dafür, dass start-task gelaufen ist**, sondern eine zusätzliche
Developer-Evidenzquelle. Wenn vorhanden/gefüllt, muss sie im Review berücksichtigt werden.

Äquivalente Quality-Überschriften sind zulässig, sofern eindeutig erkennbar ist, dass die Plan-Quality-Analyse
gelaufen ist.

Zusätzlich prüfen:

- Plan-Impact basiert auf dem aktuellen Lösungsplan,
- Plan-Quality basiert auf dem aktuellen Lösungsplan/Impact,
- kein dokumentierter Status `PLAN/DESIGN ÜBERARBEITEN`,
- keine unbehandelten blockierenden Plan-`R-*` / `Q-*` / `UNKNOWN`s.

Wenn diese Baseline fehlt oder stale ist:

```text
🔴 REVIEW-BASELINE UNVOLLSTÄNDIG

Der Branch kann nicht belastbar gegen einen freigegebenen Plan reviewed werden.
→ `/start-task <TASK_FILE>`
```

`review-task` darf in diesem Fall keinen vollständigen Merge-Readiness-Status vortäuschen.

Die Plan-Analyse ist der **Soll-Zustand**. Danach werden Impact und Quality nochmals gegen den tatsächlichen
Branch ausgeführt und als **Ist-Zustand** verglichen.

---

# 8. JIRA-Lösungsfeld als Developer-Evidenz erfassen

Falls das Task-File einen Abschnitt

```markdown
## Lösung
```

enthält, stammt dieser aus dem JIRA-Lösungsfeld und beschreibt die vom Developer dokumentierte Umsetzung.

Vor der Branch-Analyse daraus normalisieren:

```yaml
jira_solution_evidence:
  present: true|false
  raw_section: <reference>
  declared_changes: [...]
  declared_decisions: [...]
  declared_deviations: [...]
  declared_assumptions: [...]
  declared_not_implemented: [...]
  declared_operational_notes: [...]
  declared_test_notes: [...]
```

Wichtig:

- `## Lösung` **nicht überschreiben oder umdeuten**.
- Das Feld ist eine **Developer Declaration**, kein Beweis für tatsächliches Verhalten.
- Es darf Requirements/AK nicht überstimmen.
- Es darf aber erklären, ob eine Abweichung bewusst, angenommen oder absichtlich nicht umgesetzt wurde.
- Widersprüche zwischen `## Lösung` und Branch/Test-Evidenz sind explizite Review-Signale.

---

# 9. Review Snapshot — die tatsächliche Review-Basis

Das Review muss committed **und** staged/unstaged Implementierungsänderungen sehen.

## 5.1 Lokaler Worktree / ausgecheckter Branch

```bash
MERGE_BASE=$(git -C <REPO> merge-base HEAD origin/<PARENT>)
git -C <REPO> diff --name-status "$MERGE_BASE"
git -C <REPO> diff "$MERGE_BASE" --
git -C <REPO> status --short
```

`git diff "$MERGE_BASE"` vergleicht den aktuellen Working Tree gegen den Merge-Base und enthält dadurch
committed + staged + unstaged Änderungen an tracked Dateien.

Untracked versionierte Kandidaten separat lesen und hashen.

## 5.2 Remote-only Branch

```bash
MERGE_BASE=$(git merge-base origin/<branch> origin/<PARENT>)
git diff --name-status "$MERGE_BASE..origin/<branch>"
git diff "$MERGE_BASE..origin/<branch>"
```

Dann ausdrücklich:

```text
working_tree_visibility: false
```

Ein Review eines Remote-Branches darf nicht behaupten, lokale uncommitted Änderungen gesehen zu haben.

## 5.3 Review-Fingerprint

Erzeuge einen stabilen Fingerprint aus:

- Base/Merge-Base SHA,
- vollständigem tracked Diff gegen Merge-Base,
- Pfaden + Hashes relevanter untracked Dateien.

Dokumentiere:

```yaml
review_snapshot:
  ticket: ...
  task_file: ...
  repository_path: ...
  branch: ...
  parent_branch: ...
  parent_source: merge_request|task_context|project_default|remote_default
  parent_sha: ...
  pre_review_rebase_status: REBASED|ALREADY_UP_TO_DATE
  mr_source_sync: MR_SOURCE_SYNCED|LOCAL_REBASE_NOT_PUSHED|NO_REMOTE_SOURCE_REF|null
  merge_base_sha: ...
  head_sha: ...
  working_tree_visibility: true|false
  review_source_fingerprint: ...
```

---

# 10. Optionaler `solve-task`-Handoff

Ein `implementation_handoff` ist **kein Prerequisite**.

Bei unabhängiger Session zuerst `workflow_state.solve_task` lesen. Fehlt dieser Namespace bei einem fremden
Feature-Branch, ist das normal. Ein direkter Handoff ist nur zusätzliche Evidenz.

## Falls vorhanden

Vergleiche:

```text
implementation_handoff.implementation_fingerprint
vs.
review_source_fingerprint
```

Bei Gleichheit liefert er zusätzliche Evidenz zu:

- ausgeführten Tests,
- Static Analysis,
- bewusst dokumentierten lokalen Implementierungsentscheidungen,
- Security-Follow-up.

Bei Abweichung:

```text
⚠️ Implementation-Handoff ist stale:
Code wurde nach solve-task verändert.
```

Dann gelten dessen Validation-Ergebnisse nicht automatisch für den aktuellen Review-Snapshot.

## Falls nicht vorhanden

Das ist beim Review eines fremden Feature-Branches **normal**.

Dokumentiere:

```text
implementation_handoff: not_available
implementation_origin: external_or_legacy
```

und reviewe den Branch vollständig anhand von:

```text
Task-File-Baseline
+
tatsächlichem Branch-Diff
+
Branch Impact
+
Branch Quality
+
aktueller Validation
```

Die Review-Tiefe wird dadurch nicht reduziert.

---

# 11. Branch-Impact-Analyse aufrufen

Rufe **nicht** `impact-analysis/methodology.md` direkt auf.

```text
../impact-analysis/SKILL.md
```

Embedded Context:

```yaml
caller: review-task
primary_source: working-tree-diff
task_file: <TASK_FILE>
ticket: <TICKET>
repository_path: <REVIEW_REPO>
base: origin/<PARENT>
head: <HEAD/REF>
include_working_tree: <true|false>
source_fingerprint: <REVIEW_SOURCE_FINGERPRINT>
output_target: <REVIEW_REPORT>
```

Der Impact-Skill liefert den tatsächlichen Branch-Impact:

- `C-*`
- `P-*`
- `INV-*`
- `R-*`
- Risk→Test
- Unknowns

Dieser Branch-Impact darf vom Plan-Impact abweichen. Genau das ist Review-Evidenz.

---

Vor Quality muss gelten:

```text
workflow_state.impact.branch.source_fingerprint == <REVIEW_SOURCE_FINGERPRINT>
```

Andernfalls ist Branch-Impact nicht persistent/fresh und muss erneut ausgeführt werden.

---

# 12. Branch-Quality-Analyse aufrufen

Rufe:

```text
../quality-analysis/SKILL.md
```

Embedded Context:

```yaml
caller: review-task
review_mode: branch
task_file: <TASK_FILE>
ticket: <TICKET>
repository_path: <REVIEW_REPO>
base: origin/<PARENT>
head: <HEAD/REF>
include_working_tree: <true|false>
review_source_fingerprint: <REVIEW_SOURCE_FINGERPRINT>
requested_scope: <auto|full|lite|skip>
output_target: <REVIEW_REPORT>
```

Quality prüft selbst die Freshness des Branch-Impact.

Der Branch-Quality-Review beantwortet:

> Ist die **tatsächliche Implementierung** architektonisch/qualitativ so gut wie geplant?

`review-task` dupliziert SOLID-/Pattern-/Architecture-Decision-Checks nicht.

---

Vor Security-Follow-up muss gelten:

```text
workflow_state.quality.branch.review_source_fingerprint == <REVIEW_SOURCE_FINGERPRINT>
```

Andernfalls ist Branch-Quality stale/unvollständig.

---

# 13. Feature-Security-Follow-up

Aus Plan-Quality, Branch-Quality und Implementation-Handoff den höchsten Security-Follow-up-Level bestimmen:

```text
NONE
FEATURE_SECURITY_REVIEW
FULL_APP_AUDIT_RECOMMENDED
```

## `FEATURE_SECURITY_REVIEW`

Wenn im Repo ein eigener `security-review/SKILL.md` existiert, diesen gegen **denselben Review-Snapshot**
aufrufen.

Der Security-Review muss denselben `review_source_fingerprint` referenzieren.

Existiert der Skill nicht oder kann er nicht laufen:

```text
security_review: REQUIRED_NOT_RUN
```

als Merge-Readiness-Gap dokumentieren.

## `FULL_APP_AUDIT_RECOMMENDED`

Nicht automatisch `audit-security` starten.

Im Review-Handoff als separate Release-/Assurance-Empfehlung weiterreichen.

---

# 14. Review-Methodology ausführen

⚠️ **PFLICHT:** Lies [methodology.md](methodology.md) vollständig.

Normalisierter Kontext:

```yaml
review_context:
  ticket: ...
  task_file: ...
  repository_path: ...
  branch: ...
  parent_branch: ...
  parent_source: merge_request|task_context|project_default|remote_default
  parent_sha: ...
  pre_review_rebase_status: REBASED|ALREADY_UP_TO_DATE
  mr_source_sync: MR_SOURCE_SYNCED|LOCAL_REBASE_NOT_PUSHED|NO_REMOTE_SOURCE_REF|null
  merge_base_sha: ...
  head_sha: ...
  review_source_fingerprint: ...
  working_tree_visibility: ...
  plan_fingerprint: ...
  implementation_origin: self_solve | external_branch | legacy
  implementation_handoff: <optional|null>
  jira_solution_evidence:
    present: true|false
    declared_changes: [...]
    declared_decisions: [...]
    declared_deviations: [...]
    declared_assumptions: [...]
    declared_not_implemented: [...]
    declared_operational_notes: [...]
    declared_test_notes: [...]
  impact_handoff: ...
  quality_handoff: ...
  security_review_handoff: ...
```

Die Methodology ist die Single Source of Truth für Implementation-Conformance, Findings und Merge Readiness.

Sie enthält auch die **fachlichen Regeln des ursprünglichen `review-task`** (z.B. Command-Validierung/`#[Ignore]`, DateProvider, Permissions, Translation- und Testkonventionen). Diese Regeln dürfen beim Orchestrierungs-Refactoring nicht verloren gehen.

---

# 15. Validation auf exakt dem Review-Snapshot

Tests/Static Analysis sind nur gültig, wenn sie denselben Source-Stand sehen.

Bei Worktree:

- bevorzugt Worktree-eigener Stack,
- oder belastbarer projektspezifischer Worktree-Runner.

Nicht den Haupt-Stack gegen Base laufen lassen und als Branch-Validation ausgeben.

Mindestens die von Risk→Test/Plan/Implementation betroffenen Checks ausführen.

Wenn erforderliche Validation nicht möglich ist:

```text
VALIDATION_GAP
```

und Merge Readiness entsprechend blockieren.

---

# 16. Report-Creation Gate — PFLICHT

Vor dem ersten Schreiben von:

```text
<tasksPath>/<TICKET>_review.md
```

muss gelten:

```yaml
task_file_gate:
  status: PASS
```

und:

```bash
test -f <TASK_FILE>
```

Zusätzlich muss die Plan-Baseline validiert sein.

**Ein Review-Report darf niemals das erste lokale Artefakt eines Tickets sein.**

Reihenfolge:

```text
Task-File
→ start-task Baseline
→ Rebase
→ Branch Analysen
→ erst dann Review-Report
```

Falls `<TICKET>_review.md` bereits existiert, aber kein kanonisches Task-File:

- Report nicht als Task-File verwenden,
- Report als orphaned derived artifact markieren,
- `get-task` ausführen,
- erst nach erfolgreichem Task-File-Gate weiterarbeiten.

---

# 17. Review-Report

Pfad:

```text
<tasksPath>/<TICKET>_review.md
```

Der Report enthält mindestens:

1. Review Snapshot + Fingerprint + Implementation-Origin
2. Plan-Baseline + optional Handoff-Freshness
3. JIRA-Lösung: Developer Declaration ↔ tatsächliche Implementierung
4. Requirement/Plan ↔ Implementation Traceability
5. Branch Impact Summary
6. Branch Quality Summary
7. Feature Security Review / Gap
8. **visuelle Anpassungsgruppen:** 🔴 Blocker / 🟠 Fachliche Findings / 🟡 Warnungen / 🔵 Hinweise / ✅ Positives
9. strukturierte `REV-*`-Finding-Details
10. Validation Results
11. Merge Readiness
12. **`## Umsetzungs-Log` als verpflichtenden letzten Abschnitt**


## Info-Header-Format

Der Review-Report-Header muss **physisch und gerendert zeilenweise** geschrieben werden.

Pflichtformat:

```markdown
**Branch:** `<branch>`\
**Parent/MR-Target:** `<parent>` (`<MR>` falls vorhanden)\
**Merge-Base:** `<sha>` · **Parent HEAD:** `<sha>`\
**Head:** `<sha>` — `<subject>` (`<author>`, `<date>`)\
**Review-Fingerprint:** `<fingerprint>`\
**Implementation-Origin:** `<origin>`\
**Working-Tree:** sichtbar: ja/nein · `<path>` · `git status`: `<status>`\
**Review-Datum:** `<YYYY-MM-DD>`\
**Merge Request:** `<link>` oder `-`\
**Pre-Review-Rebase:** `<status>` · **MR Source Sync:** `<status>`\
**Status:** `<status>`\
**Merge Ready:** **JA / NEIN** — `<Begründung>`
```

**Wichtig:** Die Backslashes am Zeilenende sind Teil des Templates und dürfen beim Schreiben des Reports nicht
weggelassen werden. Einfache Newlines reichen in Markdown nicht zuverlässig aus.

Die fünf visuellen Gruppen sind Teil des **öffentlichen Review-Vertrags** und dürfen bei Refactorings nicht durch eine reine Severity-Liste ersetzt werden:

```text
🔴 Blocker
🟠 Fachliche Findings
🟡 Warnungen
🔵 Hinweise
✅ Positives
```

Interne `REV-*`-IDs und Severity bleiben zusätzlich erhalten.

Jede `REV-*`-Anpassung erscheint genau einmal in einer der vier Anpassungsgruppen und genau einmal im `Umsetzungs-Log`.
`POS-REV-*` erscheint unter `✅ Positives`, aber nicht im Umsetzungs-Log.

Jedes Code-Finding:

```text
path/to/file.ext:new_line
```

bezogen auf den **reviewten Snapshot**.

Gelöschte Zeile:

```text
path/to/file.ext:old_line (old)
```

---

# 18. MR-Kommentare

Nur wenn:

- ein MR eindeutig zum Branch gefunden wurde,
- der Benutzer `--comment` bzw. explizit Kommentieren verlangt,
- Finding-Positionen noch zum **gleichen Review-Fingerprint** passen.

Kommentare **vor** Remediation posten.

Nach Codeänderungen sind alte Line-Positions nicht mehr garantiert gültig.

Wenn Inline-Position nicht kommentierbar ist, darf als allgemeiner MR-Kommentar mit `path:line`-Referenz
gepostet werden. Bei erfolgreichem Posting im `Umsetzungs-Log` die 💬-Spalte für das Finding auf `💬` setzen.

Keine automatischen externen Kommentare.

Bei `LOCAL_REBASE_NOT_PUSHED` sind Inline-MR-Kommentare gesperrt, weil der MR noch nicht denselben Source-Snapshot enthält wie der lokale Review.

---

# 19. Optional Remediation (`--apply`)

Default: Review-only.

Bei `--apply` erst **nachdem der ursprüngliche Review-Report vollständig geschrieben wurde**.

Für ausgewählte Findings:

1. Fix implementieren,
2. Finding als `RESOLVED_PENDING_REVIEW` markieren,
3. Tests/Verification ausführen,
4. neuen Review-Fingerprint erzeugen,
5. `## Umsetzungs-Log` aktualisieren: `✅ Umgesetzt`, Datum, Notiz/Verification,
6. Report-Status (`🟡 Offen` / `🟠 Teilweise` / `🟢 Abgeschlossen`) aus dem Log neu bestimmen.

## Semantischer Fix

Verändert ein Fix Business-Regel, Contract, Permission, Event, Pendenz, Migration, Boundary o.ä.:

```text
review fix
  ↓
start-task reconciliation
  ↓
impact/quality
  ↓
solve/review erneut
```

Nicht still als „kleiner Review-Fix“ behandeln.

## Lokaler Fix

Naming, Import, offensichtlich lokale Null-/Style-/Test-Korrektur ohne semantischen Drift darf im Review
direkt behoben werden.

Nach Remediation ist der ursprüngliche Review-Snapshot historisch; Merge Readiness muss gegen den neuen
Snapshot erneut bestimmt werden.

---

# 20. Review Handoff und persistenter Review-State

Nach finaler Merge-Readiness-Entscheidung:

```text
merge_ready: true  → workflow_state.task.status = MERGE_READY
merge_ready: false → workflow_state.task.status = REVIEW_BLOCKED
```

Danach sichtbare Status-/Workspace-Projektion synchronisieren.

Nach finalem Report den direkten `review_handoff` ausgeben und zusätzlich `workflow_state.review_task` persistieren:

```yaml
review_task:
  review_source_fingerprint: ...
  parent_branch: ...
  parent_sha: ...
  rebase_status: REBASED|ALREADY_UP_TO_DATE
  mr_source_sync: ...
  jira_solution_reconciliation: CONFIRMED|PARTIAL|CONTRADICTED|NOT_VERIFIABLE|NOT_AVAILABLE
  findings:
    blocker: [REV-*]
    fachlich: [REV-*]
    warning: [REV-*]
    hint: [REV-*]
    positive: [POS-REV-*]
  merge_ready: true|false
  blocking_reasons: [...]
```

Nur `workflow_state.review_task` ändern; alle fremden Namespaces erhalten.

## Direkter Handoff

```yaml
review_handoff:
  ticket: ...
  task_file_gate:
    status: PASS
    task_file: ...
    source: existing|get-task
  parent:
    branch: ...
    source: merge_request|task_context|project_default|remote_default
    sha: ...
    mr: ...|null
  pre_review_rebase:
    status: REBASED|ALREADY_UP_TO_DATE
    head_before: ...
    head_after: ...
  mr_source_sync: MR_SOURCE_SYNCED|LOCAL_REBASE_NOT_PUSHED|NO_REMOTE_SOURCE_REF|null
  review_source_fingerprint: ...
  upstream:
    implementation_origin: self_solve | external_branch | legacy
    implementation_handoff_available: true|false
    implementation_handoff_fresh: true|false|null
    plan_fingerprint: ...
    plan_impact_fingerprint: ...
    plan_quality_fingerprint: ...
  jira_solution:
    present: true|false
    reconciliation_status: CONFIRMED|PARTIAL|CONTRADICTED|NOT_VERIFIABLE|NOT_AVAILABLE
    contradictions: [...]
    undocumented_implementation_changes: [...]
  impact:
    source_fingerprint: ...
    critical: [R-*]
    high: [R-*]
  quality:
    source_fingerprint: ...
    decision: ...
    findings: [Q-*]
  security:
    level: ...
    status: NOT_REQUIRED|PASSED|FAILED|REQUIRED_NOT_RUN
    findings: [...]
  review_findings:
    visual_groups:
      blocker: [REV-*]
      fachlich: [REV-*]
      warnings: [REV-*]
      hints: [REV-*]
      positives: [POS-REV-*]
    severity:
      blocker: [REV-*]
      high: [REV-*]
      medium: [REV-*]
      low: [REV-*]
  implementation_log:
    open: [REV-*]
    implemented: [REV-*]
    skipped: [REV-*]
    rejected: [REV-*]
    mr_commented: [REV-*]
  validation:
    passed: [...]
    failed: [...]
    not_run: [...]
  merge_ready: true|false
  blocking_reasons: [...]
```

---

# 21. Merge-Readiness Gate

`merge_ready: true` nur wenn:

- `workflow_state.impact.branch.source_fingerprint` und `workflow_state.quality.branch.review_source_fingerprint`
  exakt dem aktuellen Review-Fingerprint entsprechen,

- kanonisches Task-File existiert und `task_file_gate=PASS`,
- Pre-Review-Rebase gegen den aktuellen tatsächlichen Parent/MR-Target erfolgreich war,
- bei vorhandenem MR dessen Source-SHA dem reviewten rebased SHA entspricht,
- Task/AK/Plan gegen Implementierung erfüllt,
- JIRA-Lösung gegen tatsächliche Implementierung reconciled; keine blockierenden Widersprüche,
- kein ungeklärter semantischer Plan-Drift,
- Branch-Impact keine unbehandelten `CRITICAL/HIGH` Risiken enthält,
- Branch-Quality nicht `PLAN/DESIGN ÜBERARBEITEN` fordert,
- keine Blocker-/High-Review-Findings offen sind,
- erforderliche Tests/Static Analysis bestanden haben,
- erforderlicher Feature-Security-Review bestanden hat,
- keine blockierenden Unknowns/Coverage-Gaps bestehen.

`FULL_APP_AUDIT_RECOMMENDED` blockiert einen normalen Feature-Merge nicht automatisch, außer eure
Projekt-/Release-Policy macht den Full Audit explizit zum Gate.

---

# 22. Abschluss

## Merge-ready

```text
✅ REVIEW ABGESCHLOSSEN — MERGE-READY

Ticket: <TICKET>
Review-Fingerprint: <...>

Impact: <...>
Quality: <...>
Security: <...>
Validation: <...>

Offene Hinweise: <n>
Blocker: 0

📄 <review-report>
```

## Nicht merge-ready

```text
🔴 REVIEW ABGESCHLOSSEN — NICHT MERGE-READY

Blockierende Punkte:
- ...

📄 <review-report>
```

Nicht automatisch committen/pushen/mergen.

---

# Starte jetzt

1. Ticket und existierenden Feature-Branch/Worktree auflösen.
2. **Kanonisches Task-File suchen; Derived Artifacts (`*_review.md` etc.) explizit ausschließen.**
3. Falls kein Task-File: `get-task <TICKET> --no-worktree` als Sub-Workflow ausführen.
4. `get_task_handoff.task_file` konsumieren und mit `test -f` + Inhaltscheck verifizieren.
5. Wenn Task-File-Gate nicht `PASS`: **STOP — keinen Review-Report erzeugen.**
6. `workflow_state` laden/validieren; bei Legacy-Task v1 initialisieren, aber keine Fingerprints raten.
7. tatsächlichen Parent bestimmen — bei MR ist `target_branch` autoritativ.
8. `git fetch origin --prune`.
9. Falls Plan-Baseline fehlt/stale: `start-task` im Embedded `review-bootstrap` gegen `origin/<PARENT>` ausführen.
10. Feature-Branch mit `git rebase --autostash origin/<PARENT>` aktualisieren; bei Konflikt Review stoppen.
11. MR-Source-Synchronität nach Rebase prüfen.
12. Plan-Baseline validieren.
13. `## Lösung` aus JIRA als Developer-Evidenz erfassen.
14. Review-Snapshot + Fingerprint des rebased Feature-Branches bilden.
15. optionalen Implementation-Handoff einordnen.
16. Branch-Impact gegen denselben Parent aufrufen.
17. Branch-Quality gegen denselben Parent aufrufen.
18. ggf. Feature-Security-Review.
19. `methodology.md` ausführen.
20. Validation auf exakt diesem Snapshot.
21. **Erst jetzt** `<TICKET>_review.md` schreiben — mit 🔴/🟠/🟡/🔵/✅-Gruppen und verpflichtendem `## Umsetzungs-Log` am Ende.
22. `workflow_state.review_task` persistieren und Parser-Postcondition prüfen.
23. Review-Handoff + Merge-Readiness ausgeben.
