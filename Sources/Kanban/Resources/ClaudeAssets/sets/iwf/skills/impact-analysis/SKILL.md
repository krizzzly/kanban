---
name: impact-analysis
description: Evidenzbasierte Impact-Analyse für Plan, Branch, MR/PR oder gemergte Änderungen. Kann standalone oder als Sub-Skill aufgerufen werden.
argument-hint: <task-file.md | TICKET | branch-name | MR-/PR-Nummer> [--plan|--branch|--merged]
disable-model-invocation: true
---

# IMPACT ANALYSIS — Skill-Orchestrator

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `dockerStack`, `stackDomain`,
> `gitlabProjectPath`): stehen in `.claude/project.json` im Repo-Root. Platzhalter wie
> `<PREFIX>`/`<tasksPath>` stehen für diese Werte. `dockerStack: false` heisst: kein Docker-Stack — dann
> gibt es weder `stackDomain` noch `iwf`, und Befehle laufen direkt im Worktree.
>
> Diese Datei ist der **Invocation-/Routing-Layer**.
> Die fachliche Analyse steht ausschließlich in [methodology.md](methodology.md).
> Keine Analyseschritte aus `methodology.md` hier duplizieren.

## 1. Verantwortung dieses Skills

Dieser Skill ist zuständig für:

1. Projektkontext und Argumente auflösen,
2. Caller-/Standalone-Kontext normalisieren,
3. Task-File, Repository/Worktree, Base/Head und primäre Datenquelle bestimmen,
4. einen reproduzierbaren Source-Fingerprint erzeugen,
5. `methodology.md` vollständig ausführen,
6. das Ergebnis am richtigen Ziel dokumentieren,
7. einen kompakten Handoff an den Caller zurückgeben.

Dieser Skill ist **nicht** zuständig für:

- Semantic-Change-Analyse,
- Fan-in/Fan-out,
- Invarianten,
- Data Lineage,
- Risk Scoring,
- Testableitung,
- Quality-Entscheidungen.

Diese Logik gehört ausschließlich in `methodology.md`.

---

# 2. Projektkontext

Lies zuerst `.claude/project.json` im Repo-Root.

Projektwerte wie `prefix`, `tasksPath`, `repoDir`, `worktreePrefix`,
`stackDomain`, `gitlabProjectPath` niemals raten.

## Workflow-State

Lies `.claude/rules/workflow-state.md` vollständig.

`workflow_state.task` und `.workspace` sind lesbare Shared Facts. Dieser Skill verändert sie nicht. Er schreibt ausschließlich seinen Analyse-Slot.

`impact-analysis` besitzt ausschließlich:

```text
workflow_state.impact.plan
workflow_state.impact.branch
```

`primary_source: plan` schreibt `.impact.plan`; Branch/Working-Tree/MR/Merged schreibt `.impact.branch`.
Plan- und Branch-Slot niemals gegenseitig überschreiben.

---

# 3. Invocation Context

Der Skill unterstützt zwei Aufrufarten.

## 3.1 Embedded Invocation

Wenn ein Caller wie `start-task`, `review-task` oder `review-merge` bereits
einen normalisierten Kontext liefert, diesen verwenden und nicht unnötig
erneut autodetektieren.

Erwarteter Kontext:

```yaml
caller: start-task | review-task | review-merge
primary_source: plan | branch-diff | working-tree-diff | mr-diff | merged-commits
task_file: <path|null>
ticket: <ticket|null>
repository_path: <repo-or-worktree>
base: <sha-or-branch|null>
head: <sha-or-branch|null>
include_working_tree: true|false
source_fingerprint: <optional caller-provided fingerprint>
output_target: <task-file-or-review-report>
```

## 3.2 Standalone Invocation

Input:

`$ARGUMENTS`

Akzeptiert:

- Task-File
- Ticket-Nummer
- Branch-Name
- MR-/PR-Nummer (`!123`, `#123` oder `123` — GitLab schreibt `!`, GitHub `#`)
- kein Argument → aktueller Branch (`git branch --show-current`)

Optionale explizite Modus-Hinweise:

- `--plan`
- `--branch`
- `--merged`

Explizite Angaben schlagen Autodetektion.

---

# 4. Standalone-Kontext auflösen

## 4.1 Ticket und Task-File

Ticket aus Argument, Branch oder Task-File ableiten.

Falls Ticket bekannt:

Nur kanonische Task-Files suchen; Derived Artifacts ausschließen:

```bash
find <tasksPath> -maxdepth 1 -type f \
  \( -name "<TICKET>.md" -o -name "<TICKET>_*.md" \) \
  ! -name "<TICKET>_review.md" \
  ! -name "<TICKET>_security_review.md" \
  ! -name "<TICKET>_audit*.md"
```

Bei genau einem Treffer verwenden.

Bei mehreren Treffern den aktuellsten/inhaltlich passenden Treffer nicht
raten; die Mehrdeutigkeit als `UNKNOWN` dokumentieren, sofern der Caller
sie nicht bereits aufgelöst hat.

## 4.2 Worktree-Routing

Wenn das Task-File einen gültigen `WORKTREE`-Block enthält:

- Source-Reads aus `src/`, `assets/`, `tests/`, `templates/`, `config/`,
  `migrations/` auf den Worktree routen,
- Git-Inspektion mit `git -C <WORKTREE> ...`,
- Task-File, `.claude/*`, `CLAUDE.md` und zentrale Docs aus dem Haupt-Repo lesen.

Ohne gültigen Worktree den aufgelösten Repository-Pfad verwenden.

## 4.3 Primäre Datenquelle bestimmen

Priorität:

1. expliziter Modus,
2. expliziter MR,
3. expliziter Branch,
4. ungemergter Feature-Branch zum Ticket,
5. gemergte Ticket-Commits,
6. vorhandener Lösungsplan.

### Plan

Primäre Quelle: `## Lösungsplan` im Task-File.

### Branch / Working Tree

Für einen reinen Commit-/Remote-Branch:

```bash
TARGET=<resolved-base>
HEAD=<resolved-head>
MERGE_BASE=$(git merge-base "$TARGET" "$HEAD")
git diff "$MERGE_BASE..$HEAD"
```

Für einen lokal ausgecheckten Branch/Worktree mit `include_working_tree=true` muss die primäre Quelle den
**gesamten aktuellen Working Tree gegen den Merge-Base** enthalten:

```bash
MERGE_BASE=$(git merge-base HEAD <resolved-base>)
git diff "$MERGE_BASE" --        # committed + staged + unstaged tracked changes
git status --short               # untracked zusätzlich inventarisieren
```

Untracked versionierte Kandidaten müssen in Semantic Change Set und Fingerprint einbezogen werden.

Wenn der Caller bereits einen `source_fingerprint` für exakt diesen Working-Tree-Snapshot liefert, diesen
übernehmen statt einen abweichenden zweiten Snapshot zu konstruieren.

### MR

MR-Branch/Base über die vorhandene GitLab-/Projektintegration auflösen.
Danach denselben Merge-Base-/Diff-Mechanismus verwenden.

### Gemerged

Ticket-Commits im Zielbranch bestimmen und die tatsächlich zugehörigen
Änderungen als Quelle verwenden.

Wenn keine belastbare Quelle bestimmt werden kann: nicht raten; mit
konkretem `UNKNOWN` abbrechen.

---

# 5. Reproduzierbarer Analyse-Snapshot

Vor der Methodology einen Snapshot erzeugen:

```yaml
caller: ...
mode: plan | branch | mr | merged
primary_source: ...
ticket: ...
task_file: ...
repository_path: ...
base: ...
head: ...
source_fingerprint: ...
```

## Source-Fingerprint

Der Fingerprint identifiziert genau den analysierten Stand.

- **Plan:** stabiler Hash des aktuellen `## Lösungsplan`-Inhalts.
- **Branch/MR ohne Working-Tree-Änderungen:** `BASE_SHA + HEAD_SHA`.
- **Working-Tree-Diff:** Hash aus Merge-Base/Base SHA + vollständigem tracked Diff gegen Merge-Base +
  Pfaden/Hashes relevanter untracked Dateien.
- **Merged:** sortierte relevante Commit-SHAs bzw. daraus abgeleiteter Hash.

Für Text kann z.B. `git hash-object --stdin` verwendet werden.

Der Fingerprint muss im Report stehen. Downstream-Skills verwenden ihn
zur Freshness-Prüfung.

---

# 6. Methodology ausführen

⚠️ **PFLICHT:** Lies [methodology.md](methodology.md) vollständig und führe
sie mit dem normalisierten Invocation Context aus.

Die Methodology ist die **Single Source of Truth** für die Impact-Analyse.

Keine Kurzfassung der Schritte aus `methodology.md` hier pflegen.

---

# 7. Ergebnis persistieren

## Task-File vorhanden

Impact-Report unter:

```markdown
## Impact-Analyse
```

einfügen oder die bestehende Impact-Analyse für denselben
`source_fingerprint` aktualisieren.

Eine ältere Analyse mit anderem Fingerprint nicht kommentarlos als aktuell
ausgeben. Entweder ersetzen und Historie kenntlich machen oder als stale
markieren.

## Workflow-State persistieren

Wenn ein kanonisches Task-File vorhanden ist, den kompakten Handoff immer zusätzlich in den passenden State-Slot
schreiben:

```yaml
impact:
  <plan|branch>:
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
```

Nur den gewählten Slot ändern.

## Review-Caller

Wenn der Caller ein Review-Report-Ziel vorgibt, den ausführlichen Report dorthin schreiben. Der kompakte State wird
im Task-File dennoch persistiert, sofern ein kanonisches Task-File existiert.

## Kein persistentes Ziel

Report in der Ausgabe vollständig zurückgeben.

---

# 8. Handoff an Caller

Am Ende immer einen kompakten Handoff liefern:

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

Der Handoff enthält Referenzen auf die Methodology-Ergebnisse, keine zweite
Zusammenfassung derselben Analyse. Derselbe kompakte Inhalt wird im passenden State-Slot persistiert.

---

# 9. Abschluss

Standalone zusätzlich kurz ausgeben:

```text
🔍 IMPACT-ANALYSE: <TICKET/FEATURE>
Basis: <plan/branch/mr/merged>
Fingerprint: <...>
Risiken: Critical <n> · High <n> · Medium <n>
Unknowns: <n>
Dokumentiert in: <ziel>
```

Bei Embedded Invocation den Handoff an den Caller zurückgeben.
