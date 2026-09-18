---
name: quality-analysis
description: Architektur- und Design-Quality-Review nach der Impact-Analyse. Bestimmt FULL, LITE oder SKIP evidenzbasiert.
argument-hint: <task-file.md | TICKET | branch-name> [--full|--lite|--skip] [--plan|--branch]
disable-model-invocation: true
---

# QUALITY ANALYSIS — Skill-Orchestrator

> Diese Datei ist der **Invocation-/Routing-Layer**.
> Die fachliche Quality-Analyse steht ausschließlich in
> [methodology.md](methodology.md).
> Keine Quality-Gates, Principle-Checks oder Pattern-Kataloge hier duplizieren.

## 1. Verantwortung dieses Skills

Dieser Skill ist zuständig für:

1. Review-Gegenstand und Repository-Kontext auflösen,
2. Plan- oder Branch-Modus bestimmen,
3. Impact-Handoff finden und auf Freshness prüfen,
4. fehlende/stale Impact-Analyse über `impact-analysis/SKILL.md` erneuern,
5. optionalen Scope-Wunsch (`FULL/LITE/SKIP`) an die Methodology übergeben,
6. `methodology.md` vollständig ausführen,
7. Quality-Plan-Delta anwenden bzw. dokumentieren,
8. bei semantischem Quality-Delta Impact erneut über den Impact-Sub-Skill prüfen,
9. Ergebnis persistieren und Handoff zurückgeben.

Dieser Skill ist **nicht** zuständig für:

- eigene Impact-Analyse,
- eigene FULL/LITE/SKIP-Kriterien,
- eigene SOLID-/Pattern-Prüflisten.

Diese Regeln stehen ausschließlich in `methodology.md`.

---

# 2. Projektkontext

Lies zuerst `.claude/project.json`.

Projektwerte niemals raten.

## Workflow-State

Lies `.claude/rules/workflow-state.md` vollständig.

`workflow_state.task` und `.workspace` sind lesbare Shared Facts. Dieser Skill verändert sie nicht. Er schreibt ausschließlich seinen Analyse-Slot.

`quality-analysis` besitzt ausschließlich:

```text
workflow_state.quality.plan
workflow_state.quality.branch
```

`review_mode: plan` schreibt `.quality.plan`; `review_mode: branch` schreibt `.quality.branch`.
Plan- und Branch-Slot niemals gegenseitig überschreiben.

---

# 3. Invocation Context

## 3.1 Embedded Invocation

Ein Caller wie `start-task` kann liefern:

```yaml
caller: start-task | review-task | review-merge
review_mode: plan | branch
task_file: <path|null>
ticket: <ticket|null>
repository_path: <repo-or-worktree>
base: <sha-or-branch|null>
head: <sha-or-branch|null>
include_working_tree: true|false
review_source_fingerprint: <optional caller-provided fingerprint>
requested_scope: auto | full | lite | skip
output_target: <task-file-or-review-report>
```

Vorhandenen Kontext verwenden; nicht ohne Grund neu autodetektieren.

## 3.2 Standalone Invocation

Input:

`$ARGUMENTS`

Akzeptiert:

- Task-File
- Ticket-Nummer
- Branch-Name
- kein Argument → aktueller Branch

Optionale Review-Art:

- `--plan`
- `--branch`

Optionale gewünschte Tiefe:

- `--full`
- `--lite`
- `--skip`

Ohne Scope-Flag gilt `requested_scope: auto`.

**Wichtig:** `--full` darf die Analyse vertiefen.
`--lite` und `--skip` sind nur Wünsche. Die Methodology darf anhand ihrer
Triage-Regeln jederzeit auf eine höhere Stufe eskalieren.

---

# 4. Review-Gegenstand auflösen

## Plan-Modus

Erfordert:

- Task-/Feature-Kontext,
- `## Lösungsplan`,
- Repository-/Worktree-Kontext.

Der Review-Gegenstand ist der aktuelle, nach Impact-Reconciliation gültige
Lösungsplan.

## Branch-Modus

Bei reinem Commit-/Remote-Stand:

```bash
TARGET=<resolved-base>
HEAD=<resolved-head>
MERGE_BASE=$(git merge-base "$TARGET" "$HEAD")
git diff "$MERGE_BASE..$HEAD"
```

Bei lokalem Worktree/ausgechecktem Branch und `include_working_tree=true`:

```bash
MERGE_BASE=$(git merge-base HEAD <resolved-base>)
git diff "$MERGE_BASE" --
git status --short
```

Der Review-Gegenstand ist der **tatsächliche aktuelle Branch-/Working-Tree-Stand**.
Untracked versionierte Kandidaten gehören dazu.

Wenn der Caller einen `review_source_fingerprint` für genau diesen Snapshot liefert, verwendet Quality
diesen als Freshness-Basis. Plan und Impact dienen als Soll-/Kontextinformation.

Wenn der Modus nicht eindeutig ist:

- explizite Flags bevorzugen,
- bei bestehendem ungemergtem Branch im standalone Aufruf → Branch,
- sonst bei vorhandenem Lösungsplan → Plan,
- nicht raten, wenn mehrere plausible Ziele bestehen.

---

# 5. Impact-Prerequisite und Freshness

Quality ist downstream von Impact.

Wenn ein kanonisches Task-File existiert, zuerst den zum Modus passenden persistenten State lesen:

```text
review_mode: plan   → workflow_state.impact.plan
review_mode: branch → workflow_state.impact.branch
```

Der State liefert Fingerprint + Referenz-IDs. Für die ausführliche fachliche Evidenz zusätzlich die zugehörige
`## Impact-Analyse` bzw. den Branch-Impact-Report lesen:

- Semantic Changes `C-*`,
- Impact Paths `P-*`,
- Invarianten `INV-*`,
- Risks `R-*`,
- Risk→Test-Matrix,
- Unknowns.

**State entscheidet Freshness; Report liefert Details.**

## Freshness prüfen

Bei unabhängiger Session zuerst den passenden `workflow_state.impact.plan|branch`-Slot lesen. Ein direkter
`impact_handoff` ist nur in derselben laufenden Invocation zusätzlicher Kontext und muss denselben Snapshot-Fingerprint
referenzieren.

Berechne für den aktuellen Review-Gegenstand denselben Source-Fingerprint,
den `impact-analysis/SKILL.md` verwendet.

Impact ist **stale**, wenn:

- kein Impact-Report vorhanden ist,
- der Fingerprint fehlt,
- der Fingerprint nicht zum aktuellen Plan/Diff passt,
- Base/Head nicht mehr zum Branch passen,
- der Lösungsplan seit Impact semantisch geändert wurde.

## Fehlender oder staler Impact

Nicht selbst nachbauen.

Lies und führe den Sub-Skill aus:

```text
../impact-analysis/SKILL.md
```

mit demselben Repository-/Task-Kontext.

Danach den aktualisierten Impact-Handoff übernehmen.

---

# 6. Quality-Snapshot

An die Methodology übergeben:

```yaml
quality_context:
  caller: ...
  review_mode: plan | branch
  requested_scope: auto | full | lite | skip
  task_file: ...
  ticket: ...
  repository_path: ...
  base: ...
  head: ...
  include_working_tree: true|false
  review_source_fingerprint: ...
  impact_source_fingerprint: ...
  impact_handoff: <C/P/INV/R/Test/Unknown refs>
  output_target: ...
```

---

# 7. Methodology ausführen

⚠️ **PFLICHT:** Lies [methodology.md](methodology.md) vollständig und führe
sie mit dem Quality-Snapshot aus.

Die Methodology entscheidet den **effective_scope**:

```text
FULL | LITE | SKIP
```

anhand ihrer Triage-Regeln.

Der Skill entscheidet diese Kriterien nicht selbst.

---

# 8. Plan-/Code-Reconciliation

## Plan-Modus

Wenn die Methodology einen `Quality Plan Delta` erzeugt:

1. bestätigte Änderungen in den Lösungsplan integrieren,
2. neue/entfernte Semantic Changes als Delta festhalten,
3. feststellen, ob `impact_recheck_required=true`.

## Branch-Modus

Keine stille Codeänderung.

Erforderliche Code-Änderungen als Review-Findings/Handoff dokumentieren,
sofern der aufrufende Workflow nicht ausdrücklich Implementierung verlangt.

---

# 9. Impact-Recheck nach Quality-Delta

Wenn die Methodology meldet:

```yaml
impact_recheck_required: true
```

darf Quality die Impact-Analyse **nicht selbst nachbauen**.

Stattdessen erneut:

```text
../impact-analysis/SKILL.md
```

gegen den **reconciliierten Plan** bzw. aktuellen Review-Gegenstand ausführen.

Danach:

1. neuen Impact-Fingerprint übernehmen,
2. neue/geänderte `C-*`, `INV-*`, `R-*` und Tests in den Quality-Kontext
   zurückführen,
3. prüfen, ob diese Änderungen eine Quality-Entscheidung invalidieren.

## Stabilitätsregel

Falls der erneute Impact neue `HIGH/CRITICAL`-Risiken, neue
Architekturtreiber oder neue FULL-Trigger erzeugt, den Quality-Review einmal
gegen den aktualisierten Impact nachziehen.

Keine unbeschränkte Schleife:

- maximal zwei Quality↔Impact-Reconciliation-Zyklen,
- danach verbleibende Instabilität als `UNKNOWN` / offene Architekturentscheidung
  dokumentieren und nicht künstlich „grün“ rechnen.

---

# 10. Ergebnis persistieren

## Task-File

Plan-Modus:

```markdown
## Lösungsplan-Qualitätsreview
```

Branch-Modus:

```markdown
## Qualitätsreview (Branch)
```

verwenden.

Die Methodology liefert das konkrete Report-Format.

## `SKIP`

Auch `SKIP` wird knapp dokumentiert:

- effective_scope: SKIP
- Fingerprint
- Begründung
- relevante Impact-Referenzen

So ist nachvollziehbar, dass Quality bewusst triagiert und nicht vergessen wurde.

---

## Workflow-State persistieren

Wenn ein kanonisches Task-File vorhanden ist, den kompakten Quality-Handoff in den zum Modus passenden Slot schreiben:

```yaml
quality:
  <plan|branch>:
    review_source_fingerprint: ...
    impact_source_fingerprint: ...
    effective_scope: FULL|LITE|SKIP
    decision: FREIGEGEBEN | FREIGEGEBEN MIT ÄNDERUNGEN | PLAN/DESIGN ÜBERARBEITEN
    decisions: [D-*]
    findings: [Q-*]
    quality_plan_delta: [ΔQ-*]
    open_unknowns: [...]
    security_followup:
      level: NONE | FEATURE_SECURITY_REVIEW | FULL_APP_AUDIT_RECOMMENDED
      reasons: [...]
      suggested_timing: after-implementation | pre-release | periodic | now
```

Nur den gewählten Slot ändern.

---

# 11. Handoff an Caller

Immer zurückgeben:

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

---

# 12. Abschluss

Standalone:

```text
🧭 QUALITY-ANALYSE: <TICKET/FEATURE>
Modus: <Plan/Branch>
Scope: <FULL/LITE/SKIP>
Entscheidung: <...>
Findings: High <n> · Medium <n> · Low <n>
Impact-Recheck: <nicht nötig / durchgeführt>
Dokumentiert in: <ziel>
```

Embedded Invocation: Handoff an den Caller zurückgeben.
