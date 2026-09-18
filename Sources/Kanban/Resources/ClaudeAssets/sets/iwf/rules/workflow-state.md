# Workflow State — persistenter Skill-Handoff im Task-File

Diese Rule definiert den **einzigen maschinenlesbaren persistenten Workflow-State** für Task-Workflows.

Direkte Skill-Aufrufe dürfen weiterhin kompakte Return-Objekte wie `impact_handoff` oder `quality_handoff`
ausgeben. Sobald ein späterer Skill in einer neuen Session Zustand benötigt, ist jedoch **ausschließlich** der
hier definierte `workflow_state` im kanonischen Task-File maßgeblich.

```text
handoff        = unmittelbarer Return zwischen Caller und Callee
workflow_state = persistenter Handoff zwischen Sessions
```

## 1. Exakte Marker

Der State steht genau einmal im kanonischen Task-File und wird durch diese Marker begrenzt:

~~~markdown
<!-- workflow-state:start -->
```yaml
workflow_state:
  version: 1
  ...
```
<!-- workflow-state:end -->
~~~

Regeln:

- exakt **0 oder 1** State-Blöcke sind zulässig,
- bei 0 Blöcken darf ein Skill den Block initialisieren,
- bei >1 Blöcken: **STOP — WORKFLOW STATE AMBIGUOUS**,
- bei ungültigem YAML / fehlendem Root-Key / unbekannter inkompatibler Version: **STOP**, nicht reparieren/raten,
- State nur im **kanonischen Task-File**, niemals in `<TICKET>_review.md` oder anderen Derived Artifacts,
- der Block steht am Ende des Task-Files; nach ihm keine fachlichen Abschnitte mehr anhängen.

## 2. Schema v1

```yaml
workflow_state:
  version: 1

  get_task:
    ticket: PROJ-123
    task_file: /absolute/or/project/path/PROJ-123_title.md
    status: OPEN | IN_PROGRESS
    branch: feature/PROJ-123_title | null
    worktree: /path/to/worktree | null
    stack: STOPPED | RUNNING | NONE

  start_task:
    plan_fingerprint: <hash>
    planning_base: origin/<parent-or-project-base>
    readiness: READY | BLOCKED
    blocking_reasons: []

  impact:
    plan:
      source_fingerprint: <hash>
      semantic_changes: [C-001]
      impact_paths: [P-001]
      invariants: [INV-001]
      risks:
        critical: []
        high: [R-001]
        medium: []
      open_unknowns: []
      test_matrix_present: true
    branch:
      source_fingerprint: <hash>
      semantic_changes: [C-001]
      impact_paths: [P-001]
      invariants: [INV-001]
      risks:
        critical: []
        high: []
        medium: []
      open_unknowns: []
      test_matrix_present: true

  quality:
    plan:
      review_source_fingerprint: <hash>
      impact_source_fingerprint: <hash>
      effective_scope: FULL | LITE | SKIP
      decision: FREIGEGEBEN | FREIGEGEBEN MIT ÄNDERUNGEN | PLAN/DESIGN ÜBERARBEITEN
      decisions: [D-001]
      findings: [Q-001]
      quality_plan_delta: []
      open_unknowns: []
      security_followup:
        level: NONE | FEATURE_SECURITY_REVIEW | FULL_APP_AUDIT_RECOMMENDED
        reasons: []
        suggested_timing: after-implementation | pre-release | periodic | now
    branch:
      review_source_fingerprint: <hash>
      impact_source_fingerprint: <hash>
      effective_scope: FULL | LITE | SKIP
      decision: FREIGEGEBEN | FREIGEGEBEN MIT ÄNDERUNGEN | PLAN/DESIGN ÜBERARBEITEN
      decisions: [D-001]
      findings: [Q-001]
      quality_plan_delta: []
      open_unknowns: []
      security_followup:
        level: NONE | FEATURE_SECURITY_REVIEW | FULL_APP_AUDIT_RECOMMENDED
        reasons: []
        suggested_timing: after-implementation | pre-release | periodic | now

  solve_task:
    plan_fingerprint: <hash>
    implementation_fingerprint: <hash>
    repository_path: <path>
    branch: <branch>
    base_sha: <sha>
    tests:
      passed: []
      failed: []
      not_run: []
    static_analysis:
      passed: []
      failed: []
      not_run: []
    plan_drift:
      semantic: false
      local_decisions: []
    security_followup:
      level: NONE | FEATURE_SECURITY_REVIEW | FULL_APP_AUDIT_RECOMMENDED
      reasons: []
    ready_for_review: true

  review_task:
    review_source_fingerprint: <hash>
    parent_branch: <branch>
    parent_sha: <sha>
    rebase_status: REBASED | ALREADY_UP_TO_DATE
    mr_source_sync: MR_SOURCE_SYNCED | LOCAL_REBASE_NOT_PUSHED | NO_REMOTE_SOURCE_REF | null
    jira_solution_reconciliation: CONFIRMED | PARTIAL | CONTRADICTED | NOT_VERIFIABLE | NOT_AVAILABLE
    findings:
      blocker: [REV-001]
      fachlich: [REV-002]
      warning: [REV-003]
      hint: [REV-004]
      positive: [POS-REV-001]
    merge_ready: false
    blocking_reasons: []
```

Nicht jeder Namespace muss existieren. Ein fehlender Namespace bedeutet: dieser Workflow-Schritt hat für den
aktuellen Task noch keinen persistenten State geschrieben.

## 3. Ownership

Jeder Skill besitzt nur seinen Namespace:

| Skill | darf schreiben |
|---|---|
| `get-task` | `workflow_state.get_task` |
| `start-task` | `workflow_state.start_task` |
| `impact-analysis` | `workflow_state.impact.plan` oder `.branch` |
| `quality-analysis` | `workflow_state.quality.plan` oder `.branch` |
| `solve-task` | `workflow_state.solve_task` |
| `review-task` | `workflow_state.review_task` |

**Fremde Namespaces niemals löschen, normalisieren oder neu serialisieren, indem deren Bedeutung verändert wird.**
Bei einem Update: bestehenden State lesen → eigenen Namespace ersetzen/ergänzen → alle fremden Namespaces
unverändert erhalten → genau einen Block zurückschreiben.

## 4. Read-Modify-Write-Vertrag

Vor jedem State-Zugriff:

1. kanonisches Task-File sicher auflösen,
2. Marker exakt suchen,
3. 0/1/>1 Blöcke unterscheiden,
4. YAML parsen,
5. `workflow_state.version == 1` prüfen.

Beim Schreiben:

1. vollständigen aktuellen Block lesen,
2. nur den eigenen Namespace aktualisieren,
3. unbekannte Felder anderer Namespaces erhalten,
4. genau einen YAML-Block zwischen denselben Markern schreiben,
5. Datei erneut lesen und Parser-Postcondition prüfen.

## 5. Freshness

Freshness wird **nicht** über Zeitstempel, Überschriften oder Textinterpretation bestimmt, sondern über Fingerprints.

Beispiele:

```text
workflow_state.start_task.plan_fingerprint
== workflow_state.impact.plan.source_fingerprint
== workflow_state.quality.plan.review_source_fingerprint
```

→ Plan-Impact und Plan-Quality passen zum aktuellen Plan.

Wenn sich der Plan-Fingerprint ändert, bleiben alte Namespaces erhalten, sind aber durch den Fingerprint-Mismatch
objektiv **STALE**. Andere Skills müssen sie neu erzeugen; sie dürfen nicht still so tun, als wären sie frisch.

Für Branch-Review analog:

```text
review fingerprint
== workflow_state.impact.branch.source_fingerprint
== workflow_state.quality.branch.review_source_fingerprint
```

## 6. Plan- und Branch-Sicht niemals überschreiben

Impact und Quality besitzen absichtlich zwei Slots:

```text
impact.plan     = Soll-/Plan-Analyse
impact.branch   = Ist-/Code-Analyse
quality.plan    = Soll-/Plan-Quality
quality.branch  = Ist-/Code-Quality
```

Ein `review-task` darf daher niemals `impact.plan` oder `quality.plan` durch Branch-Ergebnisse ersetzen.
Der Soll↔Ist-Vergleich benötigt beide gleichzeitig.

## 7. Direkte Handoffs

Direkte Returns bleiben bestehen:

```text
get_task_handoff
impact_handoff
quality_handoff
implementation_handoff
review_handoff
```

Regel:

- gleicher laufender Caller-Stack → direkten Handoff verwenden,
- neue Session / unabhängiger Skill-Aufruf → `workflow_state` verwenden,
- wenn beides vorhanden ist → Fingerprints vergleichen; bei Widerspruch ist der persistente State nicht automatisch
  falsch und der direkte Handoff nicht automatisch richtig: gegen den aktuellen Source-Snapshot verifizieren.

## 8. Legacy-Task-Files ohne State

Ein bestehendes Task-File ohne `workflow_state` ist zulässig.

Migration:

- Block mit `version: 1` initialisieren,
- **keine** alten Fingerprints/Entscheidungen aus Prosa erraten,
- jeder Skill schreibt seinen Namespace erst, wenn er den zugrunde liegenden Snapshot in der aktuellen Ausführung
  wirklich bestimmt bzw. verifiziert hat,
- `review-task` darf für fehlenden Plan-State `start-task` nachholen,
- vorhandene menschenlesbare `## Impact-Analyse` / `## Lösungsplan-Qualitätsreview` bleiben erhalten, sind aber ohne
  passenden State/Fingerprint keine maschinenlesbare Freshness-Garantie.

## 9. State ist kein Report

Der Block bleibt kompakt:

- IDs statt vollständiger Finding-Texte,
- Fingerprints statt Diff-Inhalte,
- Status statt Begründungsprosa.

Die vollständigen Erklärungen bleiben in:

- `## Analyse`
- `## Lösungsplan`
- `## Impact-Analyse`
- `## Lösungsplan-Qualitätsreview`
- `## Lösung`
- `## Commit`
- `<TICKET>_review.md`

Der State ist ein maschinenlesbarer Index/Vertrag, kein zweiter Report.
