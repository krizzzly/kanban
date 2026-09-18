---
name: solve-task
description: Implementiere einen durch start-task freigegebenen Lösungsplan, validiere ihn und bereite den Implementation-Handoff für Review vor
argument-hint: <TICKET-NUMMER oder task-file.md> [--no-worktree]
disable-model-invocation: true
---

# SOLVE TASK — Implementierung

> `solve-task` ist der **Execution-Schritt** der Task-Lane.
> Er plant den Task nicht neu und führt keine vollständige Impact-/Quality-Analyse durch.
> Er implementiert ausschließlich einen **aktuellen, freigegebenen Plan** und erzeugt danach einen
> reproduzierbaren Implementation-Handoff für den Review.

```text
get-task
  ↓
start-task
  ├── impact-analysis (Plan)
  └── quality-analysis (Plan)
        ↓
     READY
        ↓
solve-task
  ├── Readiness/Freshness prüfen
  ├── Plan implementieren
  ├── Tests/Static Analysis ausführen
  ├── tatsächlichen Diff dokumentieren
  └── Implementation-Handoff
        ↓
review-task / security-review
```

---

# 1. Projektkontext

Lies zuerst `.claude/project.json` im Repo-Root.

Projektwerte niemals raten.

**`dockerStack: false` heisst: dieses Projekt hat keinen Docker-Stack.** Dann laufen Tests und Analysen
direkt im Worktree (nicht über `docker exec`/`iwf run`), es gibt keine Stack-URL und kein `stackDomain`,
und der Worktree wird mit `git worktree add` angelegt. Alle `iwf`-Beispiele unten gelten nur für Projekte
**mit** Stack.

Zusätzlich lesen:

- `CLAUDE.md` und referenzierte Projekt-Dokumente,
- `.claude/rules/testing.md`,
- vorhandene Code-Review-Learnings,
- projektspezifische Regeln für Übersetzungen, Zeit/Clock, Naming, Migrationen usw.

Projektregeln gehören bevorzugt dorthin und werden hier nicht als allgemeine Architekturregeln dupliziert.

---

# 2. Input und Task-File

Input:

```text
$ARGUMENTS
```

Akzeptiert:

```text
<TICKET-NUMMER oder task-file.md> [--no-worktree]
```

Bei Ticket:

Nur kanonische Task-Files suchen; Derived Artifacts ausschließen:

```bash
find <tasksPath> -maxdepth 1 -type f \
  \( -name "<TICKET>.md" -o -name "<TICKET>_*.md" \) \
  ! -name "<TICKET>_review.md" \
  ! -name "<TICKET>_security_review.md" \
  ! -name "<TICKET>_audit*.md"
```

| Befund | Aktion |
|---|---|
| genau ein File | verwenden |
| mehrere Files | nicht raten; Mehrdeutigkeit melden |
| kein File | `get-task`/`start-task` fehlt → nicht implementieren |
| expliziter Pfad | genau diesen verwenden |

`solve-task` erzeugt **kein neues Task-File**.

---

# 3. Persistenter Workflow-State laden

Lies `.claude/rules/workflow-state.md` vollständig und parse den State aus dem kanonischen Task-File.

Für eine unabhängige `/solve-task`-Session sind maßgeblich:

```text
workflow_state.start_task
workflow_state.impact.plan
workflow_state.quality.plan
```

Legacy-Task ohne State: nicht implementieren, sondern `/start-task <TASK_FILE>` nachholen.

`solve-task` besitzt ausschließlich `workflow_state.solve_task`.

---

# 4. Upstream-Contract: Readiness Gate vor jedem Code-Edit

`solve-task` setzt einen vollständig durch `start-task` vorbereiteten Task voraus.

Pflicht:

- `## Analyse`
- `## Lösungsplan`
- Traceability zu AK/erwartetem Verhalten
- `## Impact-Analyse`
- Quality-Review (`## Lösungsplan-Qualitätsreview` oder äquivalent)
- Abschluss-Checkliste aus `start-task`

## 4.1 Quality-Entscheidung

Nur implementieren bei:

```text
FREIGEGEBEN
oder
FREIGEGEBEN MIT ÄNDERUNGEN
```

Nicht implementieren bei:

```text
PLAN/DESIGN ÜBERARBEITEN
```

oder blockierenden `R-*`, `Q-*`, `UNKNOWN`s.

## 4.2 Plan-/Impact-/Quality-Freshness

Den aktuellen `## Lösungsplan` genauso fingerprinten wie `impact-analysis/SKILL.md`.

Dann muss gelten:

```text
CURRENT_PLAN_FINGERPRINT
== workflow_state.start_task.plan_fingerprint
== workflow_state.impact.plan.source_fingerprint
== workflow_state.quality.plan.review_source_fingerprint
```

und `workflow_state.start_task.readiness == READY`.

Prüfen:

```text
CURRENT_PLAN_FINGERPRINT
    ==
Impact Source-Fingerprint
    ==
Quality Review-Source-Fingerprint
```

Falls ein erforderlicher Quality→Impact-Recheck dokumentiert ist:

```text
impact_recheck.completed == true
```

### Bei Mismatch

**Nicht implementieren.**

Der Plan wurde nach der Analyse verändert oder die Analyse ist unvollständig.

Ausgabe:

```text
🔴 IMPLEMENTIERUNG NICHT FREIGEGEBEN

Der aktuelle Lösungsplan stimmt nicht mehr mit Impact/Quality überein.
→ `/start-task <TASK_FILE>` erneut ausführen.
```

`solve-task` repariert stale Planung nicht selbst.

---

# 5. Worktree-/Repository-Routing

Der Normalfall ist, dass `get-task`/`start-task` den Worktree bereits vorbereitet haben.

## 5.1 Worktree-Block validieren

Wenn vorhanden:

```bash
git worktree list
git -C <WORKTREE_PATH> branch --show-current
git -C <WORKTREE_PATH> status --short
```

Prüfen:

- Worktree existiert,
- erwarteter Branch ist aktiv,
- Pfad gehört zum aktuellen Ticket.

Dann für die gesamte Umsetzung:

- Source Reads/Writes → absoluter Worktree-Pfad,
- Git → `git -C <WORKTREE_PATH> ...`,
- Task-File/`.claude`/Docs → Haupt-Repo.

## 5.2 Fehlender/staler Worktree

Ohne `--no-worktree` nicht die Bootstrap-Logik duplizieren.

Den idempotenten `get-task/SKILL.md` als Recovery verwenden, damit Worktree-/Statusregeln eine Source of Truth
behalten. Danach erneut validieren.

Mit `--no-worktree` im Haupt-Repo arbeiten, aber niemals fremde lokale Änderungen überschreiben.

---

# 6. Implementation Snapshot

Vor dem ersten Edit dokumentieren:

```yaml
implementation_snapshot:
  ticket: ...
  task_file: ...
  repository_path: ...
  branch: ...
  base_branch: ...
  start_head_sha: ...
  plan_fingerprint: ...
  impact_fingerprint: ...
  quality_fingerprint: ...
  quality_scope: FULL|LITE|SKIP
  security_followup: NONE|FEATURE_SECURITY_REVIEW|FULL_APP_AUDIT_RECOMMENDED
```

## 6.1 Base Branch

Projektkonvention verwenden.

Falls sie nicht explizit dokumentiert ist:

```bash
git symbolic-ref refs/remotes/origin/HEAD --short
```

nicht blind `develop` annehmen.

## 6.2 Bereits vorhandene Änderungen

```bash
git -C <REPO> status --short
git -C <REPO> diff
git -C <REPO> diff --cached
```

Wenn Working Tree nicht clean ist:

1. bestehende Änderungen lesen,
2. gegen Lösungsplan/aktuelles Ticket einordnen,
3. passende Teilimplementierung **fortsetzen**, nicht überschreiben,
4. klar fremde/unzuordenbare Änderungen nicht anfassen.

Keine automatische `stash`, `reset`, `clean`, `checkout --` oder andere destruktive Reparatur.

---

# 7. Already-Solved / In-Progress

Ticket-Historie und Branch prüfen, aber Ticket-Grep nicht allein als Beweis verwenden.

```bash
git log --oneline --all --grep="<TICKET>"
git branch -a | grep -i "<TICKET>"
```

Ein Treffer in Base kann ein früherer Teilfix oder gleichnamiger Folgecommit sein.

**Abgeschlossen** nur behaupten, wenn Task-Status + tatsächliche Änderungen/History eindeutig zum aktuellen
Task passen.

Bei bereits teilweise implementiertem Branch: vorhandenen Diff zuerst verstehen und dann ab dem offenen
Plan-Schritt fortsetzen.

---

# 8. Umsetzung aus dem freigegebenen Plan

Der `## Lösungsplan` ist die Execution-Baseline.

## 8.1 Implementation Checklist erzeugen

Aus jedem Plan-Schritt einen prüfbaren Umsetzungspunkt machen:

```markdown
## Umsetzung

**Plan-Fingerprint:** `<...>`

| Schritt | Status | Artefakte | Verifikation |
|---|---|---|---|
| 1 | ⬜ / 🔄 / ✅ | ... | ... |
```

Keine zweite Planung erzeugen; lediglich Fortschritt und tatsächliche Artefakte dokumentieren.

## 8.2 Plan systematisch abarbeiten

Für jeden Schritt:

1. relevanten vorhandenen Code vollständig genug lesen,
2. bestehende Architektur-/Projektkonventionen verwenden,
3. kleinste plan-konforme Änderung implementieren,
4. zugehörige Tests unmittelbar ergänzen,
5. lokalen/direkten Test soweit sinnvoll direkt ausführen,
6. Umsetzungstabelle aktualisieren.

Nicht alle Änderungen zuerst schreiben und Tests erst am Ende „nachholen“.

---

# 9. Implementation Deviation Protocol

Während der Umsetzung kann Repository-Evidenz zeigen, dass der Plan technisch präzisiert werden muss.

Nicht jede Abweichung ist eine Neuplanung.

## 9.1 Lokale Implementierungsentscheidung — erlaubt

Beispiele:

- Methodenname leicht anders,
- bestehender Helper statt geplantem neuen Helper,
- Test in bestehender Datei statt neuer Datei,
- private Refactoring-Details ohne Verhaltens-/Boundary-Änderung.

Dokumentieren unter:

```markdown
### Implementierungsentscheidungen
```

Impact/Quality bleiben gültig.

## 9.2 Semantische oder architektonische Abweichung — STOPP

Beispiele:

- andere Business-Regel,
- neues/entferntes API-Feld oder Contract,
- zusätzliche Rolle/Berechtigung,
- anderer Status-/Workflow-Pfad,
- neues Event / Message / E-Mail / Pendenz,
- neue Async-Grenze oder Retry-Semantik,
- andere Persistenz-/Migrationsstrategie,
- neue Shared-Abstraktion/Boundary,
- zusätzliche externe Integration,
- neue/entfernte Invariante,
- bewusstes Weglassen eines geplanten Security-/Datenintegritäts-Schritts.

Dann:

1. nicht still weiterimplementieren,
2. Evidenz + vorgeschlagene Planänderung unter `## Implementierungsabweichung` dokumentieren,
3. betroffene Änderungen nicht als final behandeln,
4. zurück zu:

```text
/start-task <TASK_FILE>
```

damit Plan → Impact → Quality erneut konsistent hergestellt werden.

`solve-task` darf keine stale Architektur „durchziehen“.

---

# 10. Tests werden aus Traceability und Risk→Test abgeleitet

Tests sind nicht nur „für neue Controller“.

Primäre Quellen:

1. Acceptance-Criteria-/Behavior-Traceability,
2. Impact `Risk → Test`-Matrix,
3. Quality-Findings/Decisions,
4. projektspezifische Testing-Regeln,
5. tatsächliche Implementation-Deltas.

Für jeden relevanten `R-*` / `INV-*` / AC muss erkennbar sein, welcher automatisierte oder manuelle Nachweis ihn
abdeckt.

## 10.1 Typische Mindestnachweise

| Änderung | Mindestnachweis |
|---|---|
| Business-Invariante | Domain-/Unit-/Use-Case-Test |
| Command/Handler | Use-Case-/Integrationstest |
| Query/Repository | DB-Integrationstest |
| API Contract | Controller-/Contract-Test |
| Permission | erlaubt + verboten |
| Tenant | Cross-Tenant-Negativtest |
| Status/Workflow | erlaubte + verbotene Transition |
| Async/Event | Dispatch + Handler + Duplicate/Retry soweit relevant |
| E-Mail | Trigger + Empfänger + Duplicate-Sicherheit soweit relevant |
| Migration | realistische Bestands-/Randdaten |
| Bugfix | reproduzierender Regressionstest |
| kritische Journey | gezielter E2E-Test zusätzlich, nicht statt tieferer Tests |

## 10.2 Testdaten

Fixture-Tampering im Test ist erlaubt, wenn es die projektübliche, verständliche und isolierte Variante ist.
Keine unnötige Fixture-Vermehrung.

---

# 11. Validation Environment — niemals den falschen Code testen

Die alte Gefahr bleibt zentral:

> Haupt-Stack sieht typischerweise Haupt-Repo-Code, nicht den separaten Worktree.

Deshalb vor jedem Container-Test **Source-Parität** sicherstellen.

## 11.1 Worktree vorhanden

Bevorzugte Reihenfolge:

0. **Bei `dockerStack: false` gibt es keinen Container** — dann ist der projektübliche Befehl aus der
   `CLAUDE.md` direkt im Worktree der richtige und einzige Weg (`cd <WORKTREE_PATH> && swift test`,
   `npm test`, `pytest` …). Die Punkte 1–3 gelten für Projekte **mit** Stack.
1. **Worktree-Stack**, wenn das Projekt containerbasierte Tests vorsieht.
   Falls gestoppt und für die Validierung erforderlich:
   ```bash
   iwf worktree start <NNNN>
   ```
2. Projektunterstützter Host-/Worktree-Runner, falls ohne Container belastbar.
3. Nur wenn beides technisch nicht möglich ist: Validation als **nicht ausgeführt** dokumentieren.

Nie Tests im Haupt-Stack laufen lassen und behaupten, der Worktree sei validiert.

## 11.2 Pflichtregel

„Tests/PHPStan überspringen und dem User überlassen“ ist **kein erfolgreicher Solve-Abschluss**.

Wenn erforderliche Validierung wegen VPN, Stack, Tooling oder Umgebung nicht möglich ist:

```text
🟠 IMPLEMENTIERUNG FERTIG — VALIDIERUNG UNVOLLSTÄNDIG
```

mit konkreten fehlenden Checks.

Keine grüne Abschlussmeldung.

---

# 12. Validation Pipeline

Projektregeln bestimmen konkrete Runner.

Mindestens, soweit relevant:

1. fokussierte geänderte Tests,
2. angrenzende Regressionstests,
3. statische Analyse (`PHPStan` etc.),
4. Frontend Lint/Typecheck/Tests,
5. Build bei Frontend-/Asset-Änderungen,
6. E2E für kritische Journey, falls im Plan/Risk-Matrix vorgesehen.

Keine erfundenen Commands; `CLAUDE.md` / `.claude/rules/testing.md` sind autoritativ.

## Fehler

Fehler nicht nur „wegfixen“.

Zuerst klassifizieren:

```text
Implementation Bug
Plan Assumption wrong
Environment/Test Infrastructure
Existing unrelated failure
```

Wenn ein Fix den freigegebenen Plan semantisch verändert → Deviation Protocol.

---

# 13. Post-Implementation Diff

Nach erfolgreicher Umsetzung:

```bash
MERGE_BASE=$(git -C <REPO> merge-base HEAD <BASE>)
git -C <REPO> status --short
git -C <REPO> diff --stat "$MERGE_BASE"
git -C <REPO> diff "$MERGE_BASE"
```

Untracked Files ausdrücklich berücksichtigen.

Dokumentieren:

```markdown
### Tatsächliche Umsetzung

| Plan-Schritt | Tatsächliche Dateien/Symbole | Abweichung |
|---|---|---|
```

Ziel ist **Plan↔Implementation Traceability**, keine neue Impact-Analyse.

## Drift Gate

Vor Abschluss fragen:

- Ist jeder tatsächliche semantische Change durch einen Plan-Schritt gedeckt?
- Wurde jeder Plan-Schritt umgesetzt oder bewusst dokumentiert nicht umgesetzt?
- Sind keine neuen Permissions/Contracts/Events/Migrations-/Async-/Business-Regeln „nebenbei“ hinzugekommen?

Wenn nein → Deviation Protocol, nicht einfach abschließen.

---

# 14. Implementation Fingerprint und Handoff

Da Änderungen laut Workflow **nicht automatisch committed** werden, reicht `HEAD` als Identität nicht.

Erzeuge einen Fingerprint über den tatsächlichen Arbeitsstand, z.B. aus:

- Merge-Base/Base SHA,
- `git diff --binary <MERGE_BASE>` (staged + unstaged gegenüber Base),
- Liste + Hashes untracked versionierter Kandidaten.

Speichere:

```yaml

Nach Validation/Freshness:

```text
ready_for_review: true  → workflow_state.task.status = READY_FOR_REVIEW
ready_for_review: false → workflow_state.task.status = IN_PROGRESS
```

Danach sichtbare Status-/Workspace-Projektion synchronisieren.

implementation_handoff:
  ticket: ...
  plan_fingerprint: ...
  implementation_fingerprint: ...
  repository_path: ...
  branch: ...
  base_sha: ...
  head_sha: ...
  changed_files: [...]
  tests:
    passed: [...]
    failed: [...]
    not_run: [...]
  static_analysis:
    passed: [...]
    failed: [...]
    not_run: [...]
  plan_drift:
    semantic: false
    local_decisions: [...]
  security_followup:
    level: NONE|FEATURE_SECURITY_REVIEW|FULL_APP_AUDIT_RECOMMENDED
    reasons: [...]
  ready_for_review: true|false
```

Dieser Handoff ist für `review-task`/`security-review`; er ersetzt deren Review nicht.

Denselben kompakten Inhalt zusätzlich unter `workflow_state.solve_task` persistieren. Nur diesen Namespace ändern,
State anschließend erneut parsen und `implementation_fingerprint` verifizieren.

---

# 15. JIRA-Lösungsfeld / Task-Dokumentation

Nach der Umsetzung Task-File aktualisieren — **beide Abschnitte werden in die Datei geschrieben, nicht
nur in der Konsole ausgegeben.** Das ist der einzige Schritt dieses Skills, dessen Ergebnis die Session
überdauert: Commit-Message und Verifikationsziel sind danach nirgends sonst, und Kanban liest die
Commit-Message für seinen Commit-Dialog aus `## Commit`.

**Ablauf, in dieser Reihenfolge:**

1. `## JIRA Lösungsfeld` schreiben (Edit/Write auf das Task-File).
2. `## Commit` schreiben.
3. Das Task-File **zurücklesen** und prüfen, dass beide H2-Überschriften wirklich darin stehen.
4. Erst danach die zwei zugehörigen Punkte der Abschluss-Checkliste abhaken (Kapitel 17).

Steht einer der Abschnitte nach dem Rücklesen nicht in der Datei, bleibt sein Checklistenpunkt offen
und die Abschlussausgabe nennt ihn als fehlend. Ein Haken ohne Abschnitt ist eine Falschaussage über
die eigene Arbeit — sie fällt erst auf, wenn jemand die Commit-Message sucht und sie nicht mehr gibt.

## JIRA Lösungsfeld

```markdown
## JIRA Lösungsfeld

### Für Test-Ingenieur

**Manuelle Testanleitung**
- Rolle:
- Seite/Endpoint:
- Vorbedingungen:

**Testschritte**
1. ...
2. ...

**Automatische Nachweise**
- ...

### Für Kunde

<verständliche Beschreibung des gelösten Problems und neuen Verhaltens>

**Entscheidungen, Abweichungen, Annahmen**
- **Entscheidung:** ...
- **Abweichung von AK:** ...
- **Annahme:** ...
- **Bewusst nicht umgesetzt:** ...
- **Wichtig zu wissen:** ...
```

Wenn keine Abweichung/Annahme existiert:

```text
Keine Abweichungen von den Akzeptanzkriterien, keine offenen Annahmen.
```

Nicht einfach den Block weglassen.

## Commit

> `## Lösung` ist für das aus JIRA importierte Developer-Lösungsfeld reserviert und darf von `solve-task`
> nicht überschrieben werden.

```markdown
## Commit

**Commit-Message:** `<TICKET> | <English description>`

**Verifikationsziel:** <URL / Endpoint / Testkommando / anderer konkreter Entry Point>
**Warum hier:** ...
```

### UI-URL

Bei einem tatsächlich sichtbaren UI-Feature eine konkrete Worktree-URL verwenden.

Routen nicht raten.

### Kein sinnvoller UI-Entry-Point

Bei reinem Backend-, Worker-, Migration- oder Infrastrukturverhalten **keine Fake-URL erfinden**.

Dann stattdessen den konkreten Endpoint/Test/Command als primäres Verifikationsziel dokumentieren und,
falls hilfreich, zusätzlich die nächstgelegene App-Seite nennen.

---

# 16. Status-Semantik

`solve-task` bedeutet:

```text
Implementierung abgeschlossen
≠
Task gemerged/abgeschlossen
```

Deshalb `### Status` **nicht automatisch auf `🟢 Abgeschlossen` setzen**, solange Review/Commit/Merge noch ausstehen.

Wenn das bestehende Projekt nur `🔴 Offen / 🟡 In Arbeit / 🟢 Abgeschlossen` kennt:

```text
🟡 In Arbeit
```

beibehalten und im Handoff:

```text
ready_for_review: true
```

dokumentieren.

Falls das Projekt explizit einen `Bereit für Review`-Status definiert, diesen verwenden.

---

# 17. Abschluss-Checkliste

Im Task-File:

```markdown
## Abschluss-Checkliste

- [x] Planning Readiness/Freshness geprüft
- [x] Lösungsplan vollständig umgesetzt
- [x] Plan↔Implementation Drift Gate bestanden
- [x] Tests ergänzt
- [x] erforderliche Tests ausgeführt und bestanden
- [x] erforderliche statische Analyse/Builds ausgeführt und bestanden
- [x] JIRA Lösungsfeld ausgefüllt
- [x] `## Commit` mit Commit-Message + Verifikationsziel geschrieben
- [x] Implementation-Handoff dokumentiert
- [ ] Review durchgeführt
- [ ] Security-Follow-up durchgeführt (falls erforderlich)
- [ ] Änderungen vom Benutzer committed
- [ ] Änderungen gemerged
```

Nicht erfüllte Punkte bleiben offen; keine Checkmarks „auf Vertrauensbasis“.

Die Checkliste ist eine Vorlage, kein Protokoll: sie wird **nicht** als Block übernommen. Die beiden
Punkte `JIRA Lösungsfeld ausgefüllt` und `` `## Commit` … geschrieben `` dürfen nur abgehakt werden,
nachdem das Task-File zurückgelesen wurde und die Abschnitte darin stehen (Kapitel 15).

---

# 18. Abschlussausgabe

## Erfolgreich validiert

```text
✅ IMPLEMENTIERUNG ABGESCHLOSSEN — BEREIT FÜR REVIEW

Ticket: <TICKET>
Plan-Fingerprint: <...>
Implementation-Fingerprint: <...>

## Zusammenfassung
...

## Tatsächliche Änderungen
...

## Validation
- Tests: <...>
- Static Analysis: <...>
- Build/E2E: <...>

## Security Follow-up
<NONE / FEATURE_SECURITY_REVIEW / FULL_APP_AUDIT_RECOMMENDED>

## Verifikationsziel
<URL/Endpoint/Test/Command — bei `dockerStack: false` ein Befehl
(`cd <WORKTREE_PATH> && <projektüblicher Befehl>`), nie eine erfundene https-Zeile>

## Commit-Message
<TICKET> | <English description>

👉 Nächster Schritt: Review des tatsächlichen Diffs.
```

## Validation unvollständig

```text
🟠 IMPLEMENTIERUNG FERTIG — VALIDIERUNG UNVOLLSTÄNDIG

Fehlende Nachweise:
- ...

Nicht als „erfolgreich abgeschlossen“ ausgeben.
```

## Semantischer Plan-Drift

```text
🔴 UMSETZUNG PAUSIERT — PLAN MUSS RECONCILED WERDEN

Neue Repository-Evidenz verändert den freigegebenen Plan:
- ...

→ `/start-task <TASK_FILE>`
```

---

# 19. Unverhandelbare Regeln

0. **JIRA-`## Lösung` ist Developer-Evidenz:** niemals überschreiben; technische Solve-Metadaten unter `## Commit` speichern.


1. **Implementiere nur einen aktuellen, freigegebenen Plan.**
2. **Keine stale Fingerprints ignorieren.**
3. **Keine fremden lokalen Änderungen überschreiben.**
4. **Keine semantischen Planabweichungen still implementieren.**
5. **Tests aus AC/Impact-Risiken/Quality ableiten, nicht nur aus Dateitypen.**
6. **Nie den Haupt-Stack als Worktree-Validation ausgeben.**
7. **Keine erfolgreiche Abschlussmeldung bei nicht ausgeführter Pflicht-Validation.**
8. **Nicht automatisch committen oder pushen.**
9. **Keine Ticket-Nummern oder AI-Historie in normalen Code-Kommentaren.**
10. **Kommentare beschreiben den aktuellen Zustand, nicht die Änderungshistorie.**
11. **Workflow-State:** `workflow_state.solve_task` ist der persistente Implementation-Handoff; der direkte Return bleibt zusätzlich bestehen.
11. **Projektregeln für Clock/DateProvider, Übersetzungen, Namespaces, Tests und Migrationen befolgen.**
12. **`solve-task` ist Execution; Impact/Quality bleiben eigene Sub-Skills.**
13. **Full-App `audit-security` wird hier nicht automatisch gestartet.**
14. **Security-Follow-up wird an Review/Release weitergereicht.**

---

# Starte jetzt

1. Task-File + Projektkontext auflösen.
2. Readiness-/Freshness-Gate prüfen.
3. Worktree/Routing validieren.
4. Implementation Snapshot erstellen.
5. vorhandenen Diff einordnen.
6. Plan schrittweise implementieren + Tests.
7. Validation Pipeline ausführen.
8. Diff/Drift Gate + Implementation-Handoff.
9. Task-File/JIRA-Lösungsfeld und `## Commit` finalisieren.
10. als „Bereit für Review“ abschließen — nicht als gemergten Task.
