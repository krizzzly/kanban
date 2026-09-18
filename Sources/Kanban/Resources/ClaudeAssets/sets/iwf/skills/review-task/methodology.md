# Review-Task — Methodik für Implementation Conformance & Merge Readiness

Diese Methodik prüft den **tatsächlich implementierten Code eines beliebigen Feature-Branches** gegen:

- fachliche Anforderungen,
- Akzeptanzkriterien,
- freigegebenen Lösungsplan,
- Plan-/Branch-Impact,
- Plan-/Branch-Quality,
- Projektkonventionen,
- Tests und nachgewiesene Validation.

Der Branch darf aus der eigenen `solve-task`-Umsetzung oder von einem anderen Entwickler stammen. `implementation_handoff` ist optional.

Sie wiederholt **nicht** die vollständige Impact- oder Quality-Methodik.

---

# 1. Normalisierter Input

`SKILL.md` liefert:

```yaml
review_context:
  ticket: ...
  task_file: ...
  repository_path: ...
  branch: ...
  parent_branch: ...
  parent_sha: ...
  pre_review_rebase_status: REBASED|ALREADY_UP_TO_DATE
  mr_source_sync: MR_SOURCE_SYNCED|LOCAL_REBASE_NOT_PUSHED|NO_REMOTE_SOURCE_REF|null
  merge_base_sha: ...
  head_sha: ...
  review_source_fingerprint: ...
  working_tree_visibility: true|false
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

Die Methodik verändert diesen Snapshot nicht.

---

# 2. Evidenzregeln

Jedes Finding klassifizieren als:

- `FACT` — direkt aus Code/Diff/Test/Requirement belegbar,
- `INFERENCE` — nachvollziehbare Schlussfolgerung,
- `UNKNOWN` — notwendige Information fehlt.

Keine Findings aus Stilgefühl.

Die Quellen haben **unterschiedliche Rollen** und werden nicht einfach linear gegeneinander priorisiert:

### Normative Quellen — was gelten SOLL

1. Acceptance Criteria / explizite Requirements
2. dokumentierte, akzeptierte Entscheidungen
3. aktuelle Projektregeln / ADRs / `CLAUDE.md`

### Developer Declaration — was der Implementierende angibt getan/entschieden zu haben

4. JIRA-Feld `Lösung` → lokaler Abschnitt `## Lösung`

### Implementation Evidence — was tatsächlich IST

5. tatsächlicher Review-Diff
6. ausführbare Tests / Runtime-Verhalten
7. Branch-Impact / Branch-Quality

### Kontext

8. Plan-Impact / Plan-Quality
9. etablierte lokale Patterns
10. allgemeine Best Practices

Wichtig:

- `## Lösung` kann Intent, Entscheidungen, Annahmen und bewusste Abweichungen erklären.
- `## Lösung` kann aber weder AK noch tatsächliches Code-/Runtime-Verhalten überschreiben.
- Eine dokumentierte Abweichung ist **erklärt**, aber nicht automatisch **akzeptiert**.
- Allgemeine Best Practices dürfen bewusste Projektentscheidungen nicht still überschreiben.

---

# 3. Rebase-/Parent-Evidenz

Die Methodology setzt voraus, dass `SKILL.md` den Feature-Branch **vor dem Review** erfolgreich auf den aktuellen
Remote-Stand des tatsächlichen Parent-/MR-Target-Branches rebased hat.

Prüfe:

```text
parent_branch
parent_sha
pre_review_rebase_status
mr_source_sync
```

Wenn der Rebase nicht erfolgreich abgeschlossen wurde, existiert kein gültiger Review-Snapshot.

Wenn ein MR existiert und:

```text
mr_source_sync = LOCAL_REBASE_NOT_PUSHED
```

darf die lokale Implementation fachlich/technisch reviewed werden, aber:

- MR-bezogene Merge-Readiness bleibt `FAIL`,
- MR-Inline-Kommentare sind gesperrt,
- Report muss den fehlenden Push sichtbar machen.

Der Reviewer bewertet immer gegen den **aufgelösten Parent**, niemals pauschal gegen `develop`.

---

# 4. Plan-Baseline als Soll-Zustand

Das Task-File muss die bereits gelaufenen Plan-Analysen enthalten:

```text
start-task Analyse
→ Lösungsplan
→ Plan Impact
→ Plan Quality
```

Diese Artefakte bilden den Soll-Zustand des Reviews.

Der Reviewer beurteilt nicht, **wer** implementiert hat, sondern ob der konkrete Review-Branch diesem Soll-Zustand
entspricht.

`implementation_handoff` ist nur zusätzliche Evidenz und darf niemals Voraussetzung für fachliche oder technische
Review-Tiefe sein.

---

# 5. JIRA-Lösung ↔ tatsächliche Implementierung reconciliieren

Wenn `## Lösung` vorhanden und nicht leer ist, behandle sie als **Developer Declaration**.

Extrahiere Aussagen in Kategorien:

```text
DECLARED_CHANGE
DECLARED_DECISION
DECLARED_DEVIATION
DECLARED_ASSUMPTION
DECLARED_NOT_IMPLEMENTED
DECLARED_OPERATIONAL_NOTE
DECLARED_TEST_NOTE
```

Erzeuge:

| Aussage aus `## Lösung` | Typ | Evidenz im Branch/Test | Status | Review-Relevanz |
|---|---|---|---|---|

Status:

- `CONFIRMED` — Code/Test belegt die Aussage
- `PARTIAL` — nur teilweise umgesetzt/belegt
- `CONTRADICTED` — Branch verhält sich anders als dokumentiert
- `NOT_VERIFIABLE` — mit verfügbaren Artefakten nicht belastbar prüfbar

Zusätzlich in Gegenrichtung prüfen:

> Gibt es wesentliche tatsächliche Semantic Changes im Branch, die im Developer-Lösungsfeld überhaupt nicht erwähnt werden?

Das sind nicht automatisch Findings. Sie werden aber relevant, wenn es sich um z.B. handelt:

- neue Business-Regel,
- Permission/Rolle/Tenant-Verhalten,
- Status-/Workflow-Änderung,
- Event/Async/E-Mail/Pendenz,
- Migration/Datenänderung,
- API-/Contract-Änderung,
- externe Integration,
- bewusste Abweichung von AK,
- operational notwendiger Schritt.

## Bewertungsregeln

### Dokumentierte Abweichung

Beispiel:

```text
JIRA Lösung:
„AK 3 wurde bewusst nicht umgesetzt, weil ...“
```

Dann:

1. Reviewer erkennt: **intentional**, nicht versehentlich vergessen.
2. Gegen AK / akzeptierte Entscheidung prüfen.
3. Ohne belegte Freigabe bleibt die Abweichung fachlich offen und kann weiterhin BLOCKER/HIGH sein.

### Widerspruch

Beispiel:

```text
JIRA Lösung:
„Nur Rolle X erhält Zugriff.“

Branch:
Rolle X und ROLE_USER erhalten Zugriff.
```

→ `CONTRADICTED` und Finding gegen die konkrete Berechtigungsimplementierung.

### Undokumentierter Side-Effect

Beispiel:

```text
JIRA Lösung:
„Statusanzeige ergänzt.“

Branch Impact:
zusätzlich Event + E-Mail + Pendenz.
```

→ als **undokumentierter Semantic Change** markieren und gegen Plan/AK prüfen.

### Annahme

Eine im Lösungsfeld dokumentierte Annahme ist nützliche Review-Evidenz:

```text
„Annahme: bestehende Daten enthalten nie Zustand X.“
```

Dann gezielt prüfen:

- beweist Code/DB/Fixture diese Annahme?
- wäre Verhalten bei falscher Annahme sicher?
- müsste daraus Test/Migration/Guard entstehen?

---

# 6. Requirement → Plan → Implementation Traceability

Erzeuge:

| ID | Requirement / AK | Plan-Schritt | Tatsächliche Implementierung | Test/Nachweis | Status |
|---|---|---|---|---|---|

Status:

- `DONE`
- `PARTIAL`
- `MISSING`
- `DEVIATED`
- `UNKNOWN`

Prüfe auch Nicht-Ziele und bewusst unveränderte Fälle.

Ein Plan-Schritt ist nicht allein deshalb „DONE“, weil eine Datei gleichen Namens existiert; Verhalten muss stimmen.

---

# 7. Plan ↔ tatsächliche Semantic Changes

Vergleiche:

```text
Plan Impact C-*
vs.
Branch Impact C-*
```

Klassifiziere:

```text
EXPECTED
MISSING
EXTRA
CHANGED_SEMANTICS
```

Besonders kritisch bei:

- Business-Regeln,
- Rollen/Permissions,
- Status/Workflow,
- API-/Event-Contracts,
- Pendenzen,
- E-Mail-/Notification-Trigger,
- Async/Retry,
- Persistence/Migration,
- externe Integrationen,
- Shared Boundaries.

`EXTRA` oder `CHANGED_SEMANTICS` ohne dokumentierte Reconciliation ist mindestens `HIGH`, je nach Tragweite
`BLOCKER`.

---

# 8. Implementation Correctness

Nur die tatsächlich geänderten/berührten Bereiche prüfen.

## 5.1 Kontrollfluss und Zustände

- Bedingungen vollständig und fachlich korrekt?
- Null/false/0/empty semantisch korrekt unterschieden?
- Early Returns/Exception Paths korrekt?
- Statusübergänge erlauben/verhindern richtige Fälle?
- Partial Mutation bei Fehler möglich?
- implizite Seiteneffekte sichtbar?

## 5.2 Datenfluss

Für geänderte Felder/Contracts:

```text
Input
→ Validation
→ Command/DTO
→ Handler/Service
→ Domain
→ Persistenz
→ Read Model/Response
→ UI/Export/Email/Event
```

Branch Impact liefert die Breite; Review prüft die konkrete Implementierung an den geänderten Stellen.

## 5.3 Persistence

Falls betroffen:

- Mapping/Schema/Migration synchron?
- Bestandsdaten berücksichtigt?
- Nullability/Default semantisch korrekt?
- Constraints und Tenant-Scope korrekt?
- Query Parameter Binding?
- N+1/unnötige Hydration nur als Finding, wenn im konkreten Pfad relevant.
- Transaktionsgrenze korrekt?
- Lost Update/Concurrency bei relevantem Use Case?

## 5.4 Async / Events / Email / Pendenzen

Falls betroffen:

- Dispatch exakt am geplanten Punkt?
- doppelte Ausführung/retry-safe?
- Payload ausreichend, aber nicht unnötig sensitiv?
- Consumer behandelt stale state?
- Pendenz entsteht/verschwindet korrekt?
- Empfänger korrekt und autoritativ abgeleitet?
- Side Effect nach Partial Failure konsistent?

---

# 9. Project-Conventions Review

Dieser Abschnitt enthält die **fachlichen Review-Regeln**, die aus dem ursprünglichen `review-task` erhalten
bleiben müssen. Sie gehören in die Methodology, nicht in die Orchestrierungs-`SKILL.md`.

Grundregel:

> Erst Projektregeln / `CLAUDE.md` / referenzierte Rules lesen, dann gegen den konkreten Diff prüfen.

Keine Regel mechanisch auf ein Projekt anwenden, in dem das zugrunde liegende Pattern nicht existiert.
Wo die Regel aber durch das Projekt festgelegt ist, ist sie verbindlich.

---

## 7.1 Namespaces, Sprache und Kommentare

### PHP Namespaces

Namespaces grundsätzlich importieren:

```php
use App\Entity\Foo\Bar;
use App\Service\SomeService;
```

und nicht ohne Grund vollqualifiziert inline im eigentlichen Code verwenden.

Finding, wenn der Branch entgegen der Projektkonvention neue Inline-FQCNs einführt.

### Sprache

Sofern die Projektkonvention nichts anderes sagt:

| Element | Sprache |
|---|---|
| Branch-Namen | Englisch |
| Commit-Messages | Englisch |
| Code-Kommentare | Englisch |
| Variablen/Funktionen/Klassen | Englisch |

### Kommentare

Prüfen:

- keine Ticket-Nummern in normalen Inline-Kommentaren/PHPDoc,
- keine AI-/Agent-Historie,
- Kommentar beschreibt **aktuellen Zustand / Warum**, nicht „was früher war“,
- keine auskommentierten Altimplementierungen.

Projektdefinierte Ausnahmen wie Ticket-Referenzen in Doctrine-Migrationsbeschreibungen respektieren.

---

## 7.2 Commit-Konvention

Commits des Feature-Branches gegen die Projektkonvention prüfen.

Wenn im Projekt festgelegt:

```text
<TICKET-NUMMER> | <Beschreibung auf Englisch>
```

Prüfen:

- richtige Ticket-Nummer,
- Pipe-Trenner,
- englische Beschreibung,
- kein `Co-Authored-By`, falls projektweit verboten,
- keine AI-/Agent-Erwähnung.

Ein falscher Commit-Text ist normalerweise kein Code-Blocker, aber vor Merge zu korrigieren, wenn die
Projektpolicy dies verlangt.

---

## 7.3 Übersetzungen

Wenn das Projekt die Regel „nur deutsche Source-Translations pflegen“ verwendet:

- neue/geänderte UI-Texte nur in den vorgesehenen deutschen Translation-Dateien,
- keine unnötigen parallelen FR/IT-Änderungen,
- keine hardcodierten User-facing Strings in PHP/React/Twig,
- Translation-Key folgt dem lokalen Schema,
- bestehende Keys wiederverwenden, wenn semantisch identisch.

Nicht pauschal neue Übersetzungsarchitektur erfinden.

---

## 7.4 Backend — PHP/Symfony

Für relevante geänderte Stellen prüfen:

- keine unnötig hardcodierten fachlichen IDs/Magic Strings, wenn das Projekt dafür Enum/VO/Konstante hat,
- Doctrine Query-Werte werden gebunden und nicht aus Request-/Userdaten in Query-Strings interpoliert,
- Exception-Handling ist bewusst; keine leeren `catch`-Blöcke oder stilles Fail-open,
- Controller bleiben gemäß Projektarchitektur dünn,
- Businesslogik liegt im vorgesehenen Domain-/Application-/Handler-Layer,
- vorhandene Restrict-/Permission-/Tenant-Mechanismen werden benutzt statt parallel neu gebaut,
- bestehende Model-/DTO-/Mapping-Konventionen werden eingehalten,
- keine neue Framework-/Architekturmechanik erfunden, die das Projekt bereits löst.

Nur konkrete Verstöße als Finding aufnehmen.

---

## 7.5 Zeit & Datum — DateProvider / Clock

Wenn das Projekt einen zentralen Date-/Clock-Provider verwendet, ist dies ein **Mandatory Gate**.

Für „jetzt“ nicht direkt:

```php
new \DateTimeImmutable()
new \DateTime()
time()
```

verwenden, wenn die Projektregel den DateProvider verlangt.

Für das bekannte DateProvider-Pattern:

```php
use Coala\DateProviderBundle\Service\DateProvider\DateProviderInterface;

$now = $this->dateProvider->getCurrentDateImmutable();
```

Prüfen:

- `now` wird in Service-/Handler-Schicht aus dem Provider bezogen,
- Entity/Repository erhält `$now` als Parameter, wenn dies die Projektarchitektur vorsieht,
- Tests verwenden dieselbe gepinnte/gewarpte Uhr,
- keine echten Kalenderdaten, die gegen eine gepinnte Testzeit driften.

Direkte Systemzeit in solcher Businesslogik ist ein Correctness-Finding, nicht nur Style.

---

## 7.6 Command-Validierung — CQRS

### Durchgängiges CQRS-/Command-Pattern

Wenn das Projekt Commands/Queries systematisch über Symfony Messenger / Application Bus verarbeitet, gilt:

> **Alle Properties in Command-Klassen MÜSSEN Validation-Constraints haben oder explizit als nicht zu
> validieren markiert sein.**

Projektübliche Ausnahme:

```php
#[Ignore]
```

für Properties, die bewusst nicht durch den Command-Validator validiert werden.

Beispiel:

```php
readonly class CreateUserCommand
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Email]
        public string $email,

        #[Assert\NotNull]
        #[Assert\Positive]
        public int $companyId,

        #[Ignore]
        public ?int $createdBy = null,
    ) {}
}
```

Review-Fragen:

1. Hat **jede** Command-Property einen Constraint oder den projektüblichen `#[Ignore]`-Marker?
2. Passt der Constraint zur fachlichen Semantik und Nullability?
3. Werden verschachtelte Arrays/Collection-Inhalte ebenfalls sinnvoll validiert?
4. Gibt es neue Properties, die durch Mapping/Deserialisierung befüllbar sind, aber ungeprüft bleiben?
5. Fehlt nur ein Attribut, oder ist die Validierung fachlich an der falschen Schicht?

Typische Basissignale, abhängig vom Typ:

| Art | Typische Constraints |
|---|---|
| Pflicht-String | `NotBlank` |
| Optionaler String | fachlich passende `Length`/Format-Constraints |
| E-Mail | `Email` |
| Pflicht-ID/Integer | `NotNull`, ggf. `Positive` |
| Array/Collection | `NotNull` / `Count` / `All` / `Valid` nach Semantik |
| Enum | `NotNull` bzw. projektüblicher Enum-Validator |

**Nicht mechanisch:** Ein Constraint ist kein Selbstzweck. Das Review prüft, ob der Command an seiner Boundary
einen klaren Validierungsvertrag besitzt.

### Messenger nur punktuell

Wenn das Projekt Messenger nur für einzelne Async-Messages verwendet:

- Message bleibt Datencontainer,
- Validierung dort, wo untrusted/fachlich relevante Eingabe eintritt,
- Retry-/Failure-Verhalten bewusst,
- keine pauschale „jede Message-Property braucht Assert“-Regel erzwingen, wenn die Projektarchitektur das
  nicht vorsieht.

---

## 7.7 Berechtigungen, Rollen und Tenant

Bei Controller-, Query-, Workflow-, Export-/Download- oder Berechtigungsänderungen die projektspezifische
Permissions-/Rollen-Dokumentation lesen.

Prüfen, soweit im Projekt vorhanden:

- Permission/Rolle korrekt definiert,
- Backend erzwingt sie; Frontend-Gating ist nur UX,
- Controller/Application Boundary besitzt den richtigen Check,
- Object-Level Authorization vorhanden, wenn das konkrete Objekt geschützt werden muss,
- List-/Search-Endpunkte nutzen das projektübliche Restrict-/Scoping-Pattern,
- Rollen nicht unnötig breit (`ROLE_USER` o.ä.),
- Tenant-/Mandanten-Sichtbarkeit und Schreibzugriff korrekt,
- Frontend-Views/Actions stimmen mit Backend-Rechten überein,
- direkte API-Nutzung kann kein nur im UI verstecktes Feature umgehen.

Bei Multi-Tenant-Änderungen mindestens einen negativen Cross-Tenant-Nachweis erwarten, sofern der Pfad
relevant ist.

---

## 7.8 Frontend — React/TypeScript

Nur wenn der Branch React/TypeScript betrifft:

- keine versehentlichen `console.log`/Debug-Artefakte,
- Props/DTOs entsprechend Projektstandard typisiert,
- Translation-System verwendet,
- Permission-/View-/Action-Gating folgt den Projektmechanismen,
- Server bleibt Source of Truth für sicherheits-/fachlich relevante Entscheidungen,
- `useMemo`/`useCallback` **nicht mechanisch** fordern; nur bei realem Referential-/Performance-Grund,
- unnötig große/mehrfach verantwortliche Komponenten als Finding nur bei konkreter Wartbarkeits-/Testproblematik,
- AntD-/Form-/Table-Patterns des Projekts wiederverwenden,
- neue API-Felder/Enums vollständig in Mapping/Rendering/Filter/Actions nachvollziehen.

Die frühere „> 200 Zeilen = extrahieren“-Faustregel ist höchstens ein Signal, kein automatisches Finding.

---

## 7.9 Frontend — Twig / klassischer JS-/SCSS-Stack

Nur wenn relevant:

- User-facing Text über Translation-System,
- Twig Escaping bleibt aktiv,
- `|raw` nur bewusst und mit belegter Sanitization/Trust Boundary,
- Assets an der projektüblichen Stelle,
- vorhandene Build-/Entry-Konventionen beibehalten,
- wiederkehrende Templates nur dann extrahieren, wenn echte Wiederverwendung/Kohäsion entsteht,
- Build muss für betroffene Assets erfolgreich laufen.

---

## 7.10 Pattern-Compliance / Golden Paths

Für geänderte Bereiche:

1. 1–3 wirklich vergleichbare Implementierungen im Projekt suchen,
2. prüfen, ob der Branch den etablierten Golden Path verwendet,
3. Abweichung nur als Finding werten, wenn sie:
   - unnötige Parallelarchitektur,
   - zusätzliche Kopplung,
   - Regelduplizierung,
   - schlechtere Testbarkeit,
   - oder konkrete Inkonsistenz erzeugt.

Projekt-Patterns wie z.B. CQRS, RestrictList, ModelMapping, FeViewRenderer, AsyncTable, ProcessStep,
Form-Success-Listener oder Soft-Delete sind **projektspezifische Beispiele**, keine universellen Vorschriften.

---

## 7.11 Review-Learnings und bekannte Gotchas

Vor dem Review:

- `CLAUDE.md`,
- referenzierte Code-Review-Learnings,
- relevante `.claude/rules/*`

lesen.

Ein dokumentierter projektspezifischer Gotcha ist höher zu gewichten als eine generische Best Practice.

Wenn der Branch einen bereits dokumentierten Fehler erneut einführt, Finding explizit auf diesen lokalen
Learning-/Rule-Nachweis stützen.

---

# 10. Diff Hygiene

Prüfe explizit:

- Debug-Code / `console.log` / dumps
- auskommentierter Altcode
- TODO/FIXME ohne Ticket/Begründung
- versehentlich geänderte Lockfiles/Generated Files
- untracked notwendige Dateien vergessen?
- tote Imports / tote Methoden
- unerwartete Formatierungs-Massenänderungen
- Secrets/Test-Credentials
- temporäre Feature Flags
- Migration vorhanden, aber Mapping vergessen (oder umgekehrt)
- Translation nur teilweise ergänzt
- API-Contract geändert, Consumer vergessen
- Snapshot/Test-Fixtures unbeabsichtigt massiv geändert

Nur tatsächlich relevante Punkte melden.

---

# 11. Test Review

Tests werden gegen folgende Quellen geprüft:

1. Requirements/AK
2. Branch Impact `R-* → Test`
3. `INV-*`
4. Branch Quality
5. tatsächliche Semantic Changes
6. `.claude/rules/testing.md`

Die projektspezifische Testing-Rule ist verbindlich.

---

## 9.1 Allgemeine Test-Qualität

Prüfe:

- Verhalten statt Implementierungsdetails,
- positive + negative Fälle,
- relevante Rollen/Tenants,
- Status-/Typvarianten,
- Boundary Values,
- Regression bei Bugfix,
- deterministische Uhr/Fixtures,
- Assertions können nicht leer passieren,
- keine überbreiten E2E-Tests als Ersatz für gezielte Tests,
- Async: Retry/Duplicate/Order soweit Risiko vorhanden.

Ein Test ist nicht allein deshalb gut, weil er grün ist.

---

## 9.2 Controller-/Endpoint-Tests

Wenn das Projekt Controller-Tests nach dem etablierten Pattern verlangt:

- für jeden **neuen Controller/Endpoint** passender Controller-Test,
- Naming entspricht der Projektregel, z.B.
  `src/Controller/.../FooController.php` → `tests/Controller/.../FooTest.php`,
- mindestens Happy Path,
- Forbidden `403` für unzureichende Berechtigung,
- Unauthorized `401`, falls der Endpoint authentifizierungspflichtig und dieser Fall im Testsystem sinnvoll ist,
- Object-/Tenant-Negativfall, wenn Branch Impact dies verlangt,
- bestehende Fixture-Sets/Helpers statt parallelem Testframework.

Wenn das Projekt `userAccessProvider` / gruppierte Access-Tests verwendet, dagegen prüfen.

---

## 9.3 Projekt-Testhelpers

Falls im Projekt vorhanden, gezielt prüfen:

- `loadFixtures()` / projektübliche Fixture-Mechanik,
- rollenbasierte `TestUsers::...` statt ad-hoc Credentials,
- `checkResponseAndGetRecordsData()` statt manuellem JSON-Decoding,
- `checkActionsFromRecordData()` für Action-Sichtbarkeit,
- Filter-Tests mit `assertNotEmpty()` vor Schleifen, damit sie nicht leer „grün“ werden,
- Pagination-/Search-Test bei relevanten List-Endpunkten,
- DateProvider/Clock statt echter Systemzeit.

Diese Namen sind nur verbindlich, wenn die Projekt-Testing-Rule sie tatsächlich definiert.

---

## 9.4 Business-Logik / Use Cases

Bei geänderter Businesslogik:

- Domain-/Unit-Test für reine Regel,
- Handler-/Use-Case-/Integrationstest für Application Flow,
- vorhandene Tests erweitern, wenn derselbe Use Case bereits dort abgedeckt wird,
- Decision-Table-/Enum-/Statusvarianten aus Impact berücksichtigen,
- Bugfix erhält reproduzierenden Regressionstest.

---

## 9.5 Async / Events / E-Mail / Pendenzen

Wenn relevant:

- Dispatch/Trigger wird getestet,
- Consumer/Handler wird getestet,
- relevante Retry-/Duplicate-Semantik,
- Empfängerableitung,
- Status-/Pendenz-Folgezustand,
- Berechtigungs-/Tenant-Semantik des Folgeeffekts.

Nicht jedes Event benötigt einen riesigen End-to-End-Test; Testebene dem Risiko entsprechend wählen.

---

## 9.6 Fixture-Tampering

Runtime-Anpassung bestehender Fixtures ist zulässig, wenn:

- lokal im Test,
- fachlich klar,
- keine versteckte globale Abhängigkeit,
- verständlicher als neue Fixture-Dateien.

Kein Fixture-Bloat nur um einen einzelnen Zustand zu erzeugen.

---

## 9.7 Coverage Matrix

| Requirement / Risk | Test | Ebene | Ausgeführt? | Ergebnis |
|---|---|---|---:|---|

Ein Test, der nicht ausgeführt wurde, ist kein bestandener Nachweis.

---
# 12. Validation Review

Falls ein `implementation_handoff` existiert, nimm dessen Ergebnisse nur, wenn dessen Fingerprint noch zum Review-Snapshot passt. Fehlt er, ist das **kein Gap**; der Review führt die erforderliche Validation selbst gegen den aktuellen Branch-Snapshot aus.

Sonst Tests/Static Analysis erneut ausführen.

Klassifikation:

- `PASS`
- `FAIL`
- `NOT_RUN`
- `STALE`

`FAIL` ist Blocker.
`NOT_RUN` bei einem erforderlichen Check ist mindestens High/Blocker je nach Risiko.

Bestehende, nachweislich unabhängige Baseline-Fehler getrennt dokumentieren statt dem Feature zuzuschreiben.

---

# 13. Branch Impact / Quality / Security konsumieren

## 10.1 Impact

Nicht wiederholen; nur reviewrelevante Resultate referenzieren:

- neue/unerwartete `C-*`,
- `CRITICAL/HIGH R-*`,
- offene Unknowns,
- Risk→Test-Gaps.

## 10.2 Quality

Referenzieren:

- `D-*`,
- offene `Q-*`,
- Branch-Quality-Decision,
- Designabweichungen gegenüber Plan.

## 10.3 Security

Wenn Feature-Security-Review erforderlich:

- Findings referenzieren,
- nicht selbst vollständigen Security-Review nachbauen.

Full-App-Audit-Empfehlung separat als Assurance-Follow-up behandeln.

---

# 14. Findings

IDs bleiben stabil und maschinenlesbar:

```text
REV-001
REV-002
...
```

## 14.1 Zwei Achsen: Severity und visuelle Review-Gruppe

Die interne **Severity** steuert Gates/Risiko. Die **Darstellungsgruppe** steuert die menschlich scanbare Review-Ausgabe.
Beides ist bewusst getrennt.

Visuelle Gruppen:

| Gruppe | Bedeutung |
|---|---|
| 🔴 **Blocker** | Technisches/Security-/Validation-Problem, das vor Merge behoben werden muss |
| 🟠 **Fachliche Findings** | Requirement, AK, Lösung, Business-Regel oder semantischer Plan-Drift; standardmäßig merge-blockierend, solange nicht explizit akzeptiert |
| 🟡 **Warnungen** | Relevantes nicht-blockierendes Problem, das behoben werden sollte |
| 🔵 **Hinweise** | Optionale Verbesserung / lokale Empfehlung |
| ✅ **Positives** | Konkrete, belegte gute Lösung; kein Finding |

Zuordnung:

- `REQUIREMENT`, `SOLUTION-MISMATCH` und fachlicher `DRIFT` → normalerweise `🟠 Fachliche Findings`.
- Security-/Tenant-/Datenverlust-/rote Build-/Test-Gates → normalerweise `🔴 Blocker`.
- Nicht-blockierende Correctness-/Wartbarkeits-/Konventionslücken → `🟡 Warnungen`.
- rein optionale Verbesserung → `🔵 Hinweise`.
- Die Gruppe darf nicht genutzt werden, um Severity künstlich herunterzustufen.

Format eines Findings:

```markdown
## REV-001 — <präziser Titel>

- **Darstellung:** 🔴 Blocker / 🟠 Fachlich / 🟡 Warnung / 🔵 Hinweis
- **Severity:** BLOCKER / HIGH / MEDIUM / LOW
- **Merge Blocking:** true / false
- **Category:** REQUIREMENT / SOLUTION-MISMATCH / CORRECTNESS / TEST / CONVENTION / DRIFT / VALIDATION / SECURITY-GAP
- **Status:** OPEN / RESOLVED_PENDING_REVIEW / ACCEPTED / DISMISSED
- **Location:** `path/file.ext:line` oder Task/Requirement
- **Evidence Type:** FACT / INFERENCE / UNKNOWN
- **Evidence:** ...
- **Expected:** ...
- **Actual:** ...
- **Risk:** ...
- **Required Change:** ...
- **Required Verification:** ...
```

Severity:

| Severity | Bedeutung |
|---|---|
| `BLOCKER` | falsches fachliches Verhalten, Security-/Tenant-Verletzung, Datenverlust/-korruption, Build/Test-Gate rot, zentrale AK fehlt |
| `HIGH` | wesentliche Plan-/Architekturabweichung, relevante Test-/Validation-Lücke, hohes Regressionsrisiko |
| `MEDIUM` | relevante Correctness-/Wartbarkeits-/Konventionslücke ohne unmittelbares hohes Systemrisiko |
| `LOW` | lokale Verbesserung, nicht merge-blockierend |

Keine Findings wie „SOLID beachten“ oder „mehr Tests“.

---

# 15. Positive Findings

Nur konkrete, belegte Positiva:

```markdown
## Positive Findings

- `POS-REV-001` — Cross-Tenant-Negativtest deckt den neuen Object-Level-Check explizit ab.
```

Nicht künstlich Lob erzeugen, wenn nichts Besonderes vorliegt.

---

# 16. Merge Readiness

Matrix:

| Gate | Status | Evidenz |
|---|---|---|
| Parent/Pre-Review-Rebase | PASS/FAIL/UNKNOWN | |
| MR Source Sync | PASS/FAIL/N/A | |
| Requirements/AK | PASS/FAIL/UNKNOWN | |
| Plan Traceability | | |
| Semantic Drift | | |
| Branch Impact | | |
| Branch Quality | | |
| Feature Security | | |
| Tests | | |
| Static Analysis/Build | | |
| Project Conventions | | |

`merge_ready=true` nur bei keinen blockierenden Gaps.

---

# 17. Report-Template

Die visuelle Gruppierung ist **Pflicht**. Ein Review darf nicht nur eine technische BLOCKER/HIGH/MEDIUM/LOW-Liste ausgeben.

## Header-Format — PFLICHT

Der Info-Header ist eine kompakte Metadatenliste. Markdown kollabiert einfache Zeilenumbrüche innerhalb eines Absatzes.
Deshalb gilt:

> **Jede Metadatenzeile im Header endet mit einem Backslash `\` als hartem Markdown-Zeilenumbruch.**
> Nur die letzte Header-Zeile vor `---` hat keinen Backslash.

Nicht so:

```markdown
**Branch:** ...
**Parent:** ...
**Head:** ...
```

weil Renderer daraus einen Fließtext machen können.

Sondern:

```markdown
**Branch:** ...\
**Parent:** ...\
**Head:** ...
```

Keine Metadaten in eine einzige physische Markdown-Zeile schreiben.


```markdown
# Code-Review: <TICKET>

**Branch:** `<branch>`\
**Parent/MR-Target:** `<parent>` (`<MR-Referenz>` falls vorhanden)\
**Merge-Base:** `<merge-base-sha>` · **Parent HEAD:** `<origin/parent-sha>`\
**Head:** `<feature-head-sha>` — `<commit-subject>` (`<author>`, `<commit-date>`)\
**Review-Fingerprint:** `<fingerprint>`\
**Implementation-Origin:** eigene `solve-task`-Umsetzung / fremder Feature-Branch / Legacy\
**Working-Tree:** sichtbar: ja/nein · `<worktree-path>` · `git status`: sauber / geändert\
**Review-Datum:** `<YYYY-MM-DD>`\
**Merge Request:** `<MR-Link>` oder `-`\
**Pre-Review-Rebase:** REBASED / ALREADY_UP_TO_DATE · **MR Source Sync:** `<status>`\
**Status:** 🟡 Offen / 🟠 Teilweise / 🟢 Abgeschlossen\
**Merge Ready:** **JA / NEIN** — `<kurze Begründung>`

---

## Zusammenfassung

[1-2 Sätze: Was macht der Branch? Was ist das zentrale Review-Ergebnis?]

---

## Geprüfte Dateien

- `...`

---

## JIRA-Lösung ↔ tatsächliche Implementierung

| Aussage | Typ | Evidenz | Status | Relevanz |
|---|---|---|---|---|

---

## Requirement → Plan → Implementation

| Requirement/AK | Plan | Implementierung | Status | Evidenz |
|---|---|---|---|---|

---

## Semantic Change Reconciliation

| Plan C-* | Branch C-* | Status | Kommentar |
|---|---|---|---|

---

## Anpassungen

### 🔴 Blocker

- [ ] **REV-001** — `src/File.php:42` — präzise Kurzbeschreibung

### 🟠 Fachliche Findings

- [ ] **REV-002** — Anforderung/AK/Lösung/Business-Regel nicht oder falsch umgesetzt

### 🟡 Warnungen

- [ ] **REV-003** — `src/File.php:88` — relevantes nicht-blockierendes Problem

### 🔵 Hinweise

- [ ] **REV-004** — `src/Handler.php:33` — optionale Verbesserung

### ✅ Positives

- **POS-REV-001** — konkrete, belegte gute Lösung

> Leere Gruppen bleiben sichtbar und enthalten `— Keine —`, damit der Report vollständig scanbar bleibt.

---

## Finding-Details

### REV-001 — <Titel>

- **Darstellung:** 🔴 Blocker
- **Severity:** BLOCKER
- **Merge Blocking:** true
- **Category:** ...
- **Status:** OPEN
- **Location:** `...`
- **Evidence Type:** FACT
- **Evidence:** ...
- **Expected:** ...
- **Actual:** ...
- **Risk:** ...
- **Required Change:** ...
- **Required Verification:** ...

[für jedes REV-* wiederholen]

---

## Branch Impact
...

## Branch Quality
...

## Security Follow-up
...

---

## Validation

### Tests
...

### Static Analysis / Build
...

---

## Merge-Readiness Gates

| Gate | Status | Evidenz |
|---|---|---|
| ... | ... | ... |

---

## Umsetzungs-Log

| Finding | Gruppe | Status | Umgesetzt am | 💬 MR | Notizen |
|---|---|---|---|---|---|
| REV-001 | 🔴 | ⬜ Offen | - | ⬜ | - |
| REV-002 | 🟠 | ⬜ Offen | - | ⬜ | - |
| REV-003 | 🟡 | ⬜ Offen | - | ⬜ | - |
| REV-004 | 🔵 | ⬜ Offen | - | ⬜ | - |

**Legende:**
- `⬜ Offen` — Finding besteht, nicht umgesetzt
- `✅ Umgesetzt` — Korrektur durchgeführt und verifiziert
- `⏭️ Übersprungen` — bewusst nicht umgesetzt
- `❌ Abgelehnt` — Finding nach Gegenprüfung verworfen / vom Verantwortlichen abgelehnt
- 💬-Spalte: `⬜` nicht als MR-Kommentar veröffentlicht | `💬` veröffentlicht
```

## 17.1 Regeln für den Umsetzungs-Log

Der `## Umsetzungs-Log` ist **immer der letzte fachliche Abschnitt des Review-Reports** und niemals optional.

Beim initialen Review:

- jede `REV-*`-Anpassung bekommt genau eine Zeile,
- Status zunächst `⬜ Offen`, sofern nicht bereits im selben Lauf nachweislich resolved/dismissed,
- `POS-REV-*` wird nicht in den Umsetzungs-Log aufgenommen,
- MR-Kommentar-Status wird über die 💬-Spalte gepflegt.

Bei `--apply` oder späterer Bearbeitung:

- erfolgreicher Fix + Verifikation → `✅ Umgesetzt`, Datum setzen, Verifikationsnotiz,
- bewusst nicht bearbeitet → `⏭️ Übersprungen`, Begründung notieren,
- Finding widerlegt/abgelehnt → `❌ Abgelehnt`, Begründung notieren,
- als MR-Kommentar veröffentlicht → 💬 setzen.

Der Report-Status folgt dem Log:

```text
🟡 Offen         = mindestens ein relevantes Finding offen
🟠 Teilweise     = ein Teil bearbeitet, relevante Findings noch offen/übersprungen
🟢 Abgeschlossen = alle merge-relevanten Findings resolved/akzeptiert und Gates erfüllt
```

Der Umsetzungs-Log ist die historische Audit-Spur. Bereits vorhandene Zeilen nicht löschen; Status/Notizen aktualisieren.

---

# 18. Adversarialer Gegencheck

Für jedes BLOCKER/HIGH:

1. Versuche das Finding mit Code/Test/Framework-Verhalten zu widerlegen.
2. Prüfe, ob das angeblich fehlende Verhalten in einem anderen Layer liegt.
3. Prüfe, ob die Zeile wirklich im reviewten Snapshot existiert.
4. Prüfe, ob das Problem bereits durch einen Test nachweislich verhindert wird.
5. Prüfe, ob es ein Baseline-/Altproblem außerhalb des Branch-Diffs ist.

Bleibt es bestehen, Evidenz präzisieren.

---

# 19. Completion Gate

Review fertig erst wenn:

- [ ] Parent/MR-Target eindeutig aufgelöst
- [ ] Pre-Review-Rebase erfolgreich abgeschlossen
- [ ] MR-Source-Synchronität dokumentiert
- [ ] Plan-Baseline (Analyse + Plan + Plan-Impact + Plan-Quality) validiert
- [ ] Review-Fingerprint feststeht
- [ ] Info-Header mit harten Markdown-Zeilenumbrüchen (`\\`) gerendert
- [ ] Working-Tree-Sichtbarkeit dokumentiert
- [ ] JIRA-Lösung gegen tatsächliche Implementierung reconciled (falls vorhanden)
- [ ] Requirement/Plan/Implementation tracebar
- [ ] Branch Impact aktuell
- [ ] Branch Quality aktuell
- [ ] Security Follow-up geklärt
- [ ] Tests/Static Analysis auf aktuellem Snapshot bewertet
- [ ] jedes BLOCKER/HIGH adversarial geprüft
- [ ] keine Roh-Hypothesen als Findings ausgegeben
- [ ] visuelle Gruppen 🔴/🟠/🟡/🔵/✅ vollständig ausgegeben
- [ ] `## Umsetzungs-Log` vorhanden und enthält jede `REV-*`-Anpassung
- [ ] Merge-Readiness-Gates ausgefüllt
- [ ] Report ohne Chat verständlich
