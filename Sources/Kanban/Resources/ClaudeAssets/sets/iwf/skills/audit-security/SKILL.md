---
name: audit-security
description: Reproduzierbares Full-Application-Security-Audit mit verifizierten Findings. Eigene Assurance-Lane; keine Remediation, kein Auto-Trigger aus start-task.
argument-hint: "[TICKET-NUMMER] [--target <git-ref>] [--phases 1,3,5] [--resume] [--no-worktree] [--no-dast] [--dry-run]"
disable-model-invocation: true
---

# AUDIT SECURITY — Skill-Orchestrator

> Diese Datei ist der **Invocation-/Routing-Layer**.
> Die fachliche Audit-Methodik steht ausschließlich in [methodology.md](methodology.md).
> Keine Security-Prüflisten, OWASP-Kategorien oder Hotspot-Regeln hier duplizieren.

## 1. Rolle im Gesamt-Workflow

`audit-security` ist **kein regulärer Schritt jedes Feature-Tasks**.

Es ist eine separate **Assurance-Lane für die gesamte Applikation**:

```text
Task-Lane:
get-task
  → start-task
      → impact-analysis
      → quality-analysis
  → solve-task
  → review / security-review

Assurance-Lane:
audit-security
  → gesamte Applikation / definierter Git-Stand
  → verifizierte Security-Findings
  → Remediation-Folgetickets
```

`quality-analysis` kann einen Security-Follow-up empfehlen. Ein Full-App-Audit wird dadurch aber
**nicht automatisch** aus `start-task` gestartet. Es ist teuer, teilweise destruktiv (DAST) und benötigt
einen implementierten, testbaren Stand.

Typische Auslöser:

- periodischer Security-Audit,
- Release-/Go-Live-Gate,
- grundlegende Änderung an AuthN/AuthZ/Tenant-Scoping,
- neue gemeinsame Security-/Rendering-/Upload-/Query-Infrastruktur,
- größere externe Integration,
- Security-Incident oder konkreter Verdacht,
- bewusst angeforderter vollständiger Audit.

---

## 2. Verantwortung dieses Skills

Dieser Skill ist zuständig für:

1. Argumente und Projektkontext auflösen,
2. **zu auditierenden Git-Stand unveränderlich festnageln**,
3. Audit-ID, Worktree und Report-Ziele bestimmen,
4. Resume/Freshness sicher behandeln,
5. Stack-/Target-Safety-Gates erzwingen,
6. Tool-Verfügbarkeit und Versionen inventarisieren,
7. `methodology.md` vollständig ausführen,
8. Register/Report/Repro-Artefakte persistieren,
9. einen kompakten `security_audit_handoff` zurückgeben.

Dieser Skill ist **nicht** zuständig für die eigentliche Security-Analyse.
Diese steht ausschließlich in `methodology.md`.

---

## 3. Projektkontext

Lies zuerst `.claude/project.json`.

Projektwerte wie `prefix`, `tasksPath`, `repoDir`, `worktreePrefix`,
`stackDomain`, `gitlabProjectPath` niemals raten.

`<repo-ordnername>` = letzter Pfadbestandteil von `repoDir`.

---

## 4. Input

`$ARGUMENTS`

Unterstützt:

- `<TICKET-NUMMER>` optional,
- `--target <git-ref>` — zu auditierender Stand; Default `origin/develop`,
- `--phases 1,3,5` — nur ausgewählte Methodology-Phasen,
- `--resume`,
- `--no-worktree`,
- `--no-dast`,
- `--dry-run`.

Ohne Ticket:

```text
AUDIT-ID = audit<YYYYMMDD>
```

Mit Ticket:

```text
AUDIT-ID = <PREFIX>-NNNN
```

`--no-dast` bedeutet **nicht** „DAST bestanden“, sondern „nicht ausgeführt“ mit dokumentierter Coverage-Lücke.

---

## 5. Audit-Source auflösen und fingerprinten

Vor Worktree-Erstellung:

```bash
TARGET_REF=<explizites --target oder origin/develop>
git fetch --all --prune
AUDIT_SOURCE_SHA=$(git rev-parse "$TARGET_REF^{commit}")
```

Der Audit gilt für **genau diesen Commit**.

Dokumentiere:

```yaml
audit_source:
  target_ref: ...
  sha: ...
  dirty: false
  source_fingerprint: <sha>
```

### `--no-worktree`

Wenn direkt im Haupt-Repo gearbeitet wird und der Tree dirty ist:

```bash
git status --porcelain
git diff
git diff --cached
```

Dann:

- `dirty: true`,
- zusätzlichen Hash der lokalen Diffs in den Fingerprint aufnehmen,
- im Report sichtbar warnen.

Ein Audit gegen einen unklaren/mutierenden Stand ist nicht reproduzierbar.

---

## 6. Resume-Semantik

Bei `--resume`:

1. bestehendes Findings-Register + Audit-Metadaten lesen,
2. bisherigen `source_fingerprint` mit aktuellem Audit-Source vergleichen.

### Fingerprint identisch

Offene Phasen fortsetzen; abgeschlossene Phasen nicht unnötig wiederholen.

### Fingerprint abweichend

Nicht still weiterarbeiten.

- Register/Report **nicht überschreiben**,
- neuen Durchlauf `N+1` eröffnen,
- codeabhängige erledigte Phasen als `STALE` markieren,
- nur artefaktunabhängige Evidenz übernehmen,
- betroffene Phasen gegen den neuen Stand neu ausführen.

---

## 7. Audit-Worktree

Default: eigener Worktree/Branch nur für Audit-Artefakte und Repro-Tests.

```bash
iwf worktree create <NR|auditYYYYMMDD> comprehensive_security_audit
```

Der neue Audit-Branch muss vom `AUDIT_SOURCE_SHA` ausgehen. Falls das IWF-Command nicht explizit von
diesem SHA erzeugt, nach Erstellung verifizieren:

```bash
git -C "$WT" merge-base --is-ancestor "$AUDIT_SOURCE_SHA" HEAD
git -C "$WT" rev-parse HEAD
```

Audit-Artefakte dürfen den auditierten Quellstand nicht unbemerkt verändern.

---

## 8. Stack-/Target-Safety-Gate

Aktive Security-Scans dürfen **niemals** gegen Prod oder eine ungeklärte Remote-Umgebung laufen.

Vor DAST oder zustandsverändernden Requests:

1. Zielhost muss dem lokalen/projektspezifischen Dev-/Test-Stack entsprechen,
2. `APP_ENV`/Runtime-Kontext verifizieren,
3. Audit-Source-Parität prüfen.

### Source-Parität

Container-/Stack-Tests sind nur gültig, wenn der laufende Stack denselben Quellstand repräsentiert.

Wenn Haupt-Stack ≠ `AUDIT_SOURCE_SHA` oder Audit-Repro-Code benötigt wird:

```bash
iwf worktree start <AUDIT-ID/NUMMER>
```

und gegen den Worktree-Stack laufen.

**Fail closed:** Kann die Zielumgebung nicht sicher als nicht-produktiv identifiziert werden, keine aktive DAST-Phase starten.

---

## 9. Tool-Preflight

Vor der Methodology ein Tool-Manifest erstellen:

```markdown
| Tool | Version/Image-Digest | Verfügbar? | Geplante Phase |
|---|---|---|---|
```

Regeln:

- Projekt-Abhängigkeiten für den Audit **nicht** verändern, nur um ein Tool zu installieren.
- Bevorzugt vorhandene Binaries, projektvorhandene Tools oder gepinnte disposable Container.
- Bei Container-Tools Version/Digest dokumentieren; keine Reproduzierbarkeit nur über moving tag behaupten.
- Fehlt ein Tool: Phase/Teilprüfung als `NOT RUN` + Grund dokumentieren; manuelle Ersatzprüfung soweit möglich.
- Keine stillen Installationen, die Repo oder Lockfiles verändern.

---

## 10. Audit-Verhalten

Unverhandelbar:

1. **Befundung, keine Remediation.**
2. **Kein bestätigtes Finding ohne Verifikation.**
3. `UNVERIFIZIERT` bleibt sichtbar von bestätigten Findings getrennt.
4. Negative Ergebnisse und widerlegte Hypothesen dokumentieren.
5. Tool-Rohoutput ist Evidenzquelle, kein Finding.
6. Über Tools hinweg deduplizieren.
7. Keine Secrets/Token/Passwörter im Klartext in Register, Report oder Chat schreiben.
8. Audit-Artefakte nicht automatisch committen.

Repro-Code darf nur die Verwundbarkeit reproduzieren, nicht beheben.

---

## 11. Methodology ausführen

⚠️ **PFLICHT:** Lies [methodology.md](methodology.md) vollständig und führe sie mit diesem normalisierten Kontext aus:

```yaml
security_audit_context:
  audit_id: ...
  ticket: ...
  repository_path: ...
  audit_worktree: ...
  target_ref: ...
  audit_source_sha: ...
  source_fingerprint: ...
  requested_phases: all|[...]
  resume: true|false
  dast_enabled: true|false
  dry_run: true|false
  report_path: ...
  findings_path: ...
  task_file: ...
  tool_manifest: ...
```

`methodology.md` ist die Single Source of Truth für Phasen, Coverage, Verifikation, Severity und Report-Inhalt.

---

## 12. Deliverables

| Artefakt | Ort |
|---|---|
| Findings-Register | `<tasksPath>/<AUDIT-ID>_findings.md` |
| Security-Report | `<tasksPath>/<AUDIT-ID>_security_report.md` |
| Repro-Artefakte | `<WT>/tests/Security/` bzw. explizit dokumentierter Audit-Ordner |
| Task-Status | vorhandenes Task-File, falls Ticket-basiert |

### Repro-Test-Lifecycle

Ein Audit-Repro-Test darf zeigen, dass die Verwundbarkeit **aktuell existiert** und deshalb grün sein.

Er darf jedoch nicht ungeprüft als dauerhafter Regressionstest in den Hauptbranch übernommen werden:

```text
Audit-Repro:
"bösartiges Payload überlebt" → grün

Remediation-Ticket:
Test invertieren/ersetzen →
"bösartiges Payload wird blockiert" → grün
```

Diese Übergabe muss in der Remediation-Roadmap stehen.

---

## 13. Handoff

Am Ende:

```yaml
security_audit_handoff:
  audit_id: ...
  source_fingerprint: ...
  audit_source_sha: ...
  run: ...
  coverage:
    completed_phases: [...]
    skipped_phases: [...]
    stale_phases: [...]
  findings:
    critical: [SEC-*]
    high: [SEC-*]
    medium: [SEC-*]
    low: [SEC-*]
    unverified: [SEC-*]
  cross_tenant_findings: [SEC-*]
  verified_positive_controls: [POS-*]
  coverage_gaps: [...]
  remediation_tickets_required: true|false
  repro_artifacts_present: true|false
```

---

## 14. Abschlussausgabe

```text
🔐 SECURITY-AUDIT ABGESCHLOSSEN — <AUDIT-ID>

Source: <target-ref> @ <sha>
Fingerprint: <...>
Durchlauf: <N>

Findings: Critical <n> · High <n> · Medium <n> · Low <n>
Unverifiziert: <n>
Cross-Tenant: <n>
Coverage-Gaps: <n>

Report: <...>
Register: <...>
Repro-Artefakte: <...>
```

Bei `--dry-run` nur Scope, Source-Fingerprint, Angriffsflächeninventar und geplante Coverage ausgeben.
