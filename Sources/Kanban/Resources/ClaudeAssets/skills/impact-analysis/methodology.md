# Test-Impact-Analyse — Symfony / React / Ant Design (portabel)

Business-Impact, CQRS-Flows, API-Contracts, versteckte Seiteneffekte, Business-Verzweigungen, Risiken und testbare Evidenz.

---

## Zweck dieser Methodik

Diese Methodik beantwortet **nicht erneut, was ein Ticket fachlich will**. Das ist Aufgabe des aufrufenden Workflows
(z.B. `start-task`).

Sie beantwortet:

> Wenn diese geplanten oder tatsächlichen Änderungen gelten: **Welche fachlichen und technischen Flows verändern
> sich, welche bestehenden Regeln können kollidieren, welche Gegenstellen fehlen möglicherweise und was muss
> gezielt verifiziert werden?**

Sie wird von mehreren Workflows verwendet:

- `start-task` — vor der Umsetzung, primär auf Basis des Lösungsplans,
- `review-task` — nach der Umsetzung, primär auf Basis des Branch-Diffs,
- `review-merge` — Review eines Kollegen-MRs, primär auf Basis des MR-Diffs,
- `impact-analysis` — standalone für offene, laufende oder abgeschlossene Tasks.

---

# 1. Normalisierter Input-Contract

> **Routing-Regel:** Argumentauflösung, Standalone-Status-Erkennung, Worktree-Routing und Source-Fingerprint
> erfolgen in `SKILL.md`. Diese Methodik beginnt mit einem bereits normalisierten Analyse-Kontext.


Der aufrufende Workflow liefert konzeptionell:

```text
mode: start-task | review-task | review-merge | impact-analysis
primary_change_source: Lösungsplan | Branch-Diff | MR-Diff | gemergte Commits
repository_snapshot: Worktree/Branch + Vergleichsbasis
functional_context: Task-Beschreibung / Analyse / ACs / bekannte Constraints (optional, aber hilfreich)
output_target: Task-File oder Review-Report
```

## Regeln

1. **Die primäre Änderungsquelle bestimmt, WAS analysiert wird.**
2. Der fachliche Kontext hilft bei der Einordnung, ersetzt aber nie Code/Diff/Config als Nachweis des aktuellen Verhaltens.
3. Diese Methodik erfindet keine Acceptance Criteria und führt keine zweite vollständige Task-Analyse durch.
4. Wenn `impact-analysis` standalone läuft, bestimmt sie Quelle und Status selbst.
5. Datenquelle, Base/Head und Analysemodus werden im Report dokumentiert.

---

# 2. Datenquelle je Modus

| Kontext | Primäre Quelle | Zweck |
|---|---|---|
| `start-task` | **Lösungsplan** | Plan auf Vollständigkeit, Nebeneffekte und Risiken prüfen |
| `review-task` | **git diff** gegen Zielbranch | tatsächliche Implementierung + Testimpact prüfen |
| `review-merge` | **MR-Diff** | Review-Findings, fehlende Gegenstellen und QA-Risiken finden |
| `impact-analysis` offen | Lösungsplan | geplanten Impact bestimmen |
| `impact-analysis` in Arbeit | Branch-Diff | tatsächlichen Zwischenstand analysieren |
| `impact-analysis` abgeschlossen | gemergte Commits | finalen Impact nachvollziehen |


## Repository-Snapshot

Die Methodik verwendet ausschließlich `repository_path`, `base`, `head` und `source_fingerprint` aus dem
normalisierten Skill-Kontext. Sie verändert oder errät diese Werte nicht.


# 3. Portabilität und Projekt-Profil

Die Methodik ist projektübergreifend gleich. Projektspezifisch sind nur wenige Architekturachsen.

**Grundregel:** Reale Registrierung/Config/Code sind maßgeblich; Dokumentation dient als Kontext und kann driften.

Falls ein gepflegtes Profil existiert (`docs/claude/impact-analysis.profile.md` oder definierter Block in `CLAUDE.md`),
als deklarativen Projekt-Hinweis verwenden und gegen den Code plausibilisieren.

## Projekt-Profil bestimmen

| # | Achse | Primäre Ermittlung |
|---|---|---|
| P1 | Ticket-Pattern | zuerst `.claude/project.json.prefix`, sonst `git log --oneline -20` |
| P2 | FE-Sprache | `find assets \( -name '*.tsx' -o -name '*.jsx' \) ...` |
| P3 | FE-Refetch nach Mutation | React Query/RTK/imperatives `.reload()` suchen |
| P4 | FE-Permission-Gating | `fe_actions.yaml` / `fe_views.yaml` + Constraint-Komponenten |
| P5 | Read-Modell | Projection/ReadModel oder QueryHandler + Repo + ModelMapping/ViewModel |
| P6 | Message-Ablage | getrennte Command/Query-Struktur oder feature-basiert |
| P7 | Autorisierung | Permission-Config + `#[IsGranted]` + zusätzliche handgeschriebene Voter |
| P8 | Async/Messenger | `config/packages/messenger.yaml` inkl. routing/transports/retry/middleware |
| P9 | Hochrisiko-Enums | Domain-Type/Status/Strategy/Purpose-Enums |
| P10 | Lifecycle/Recalc | Doctrine Listener/Subscribers/Entity Lifecycle Callbacks |

### Beispiel-Detektion

```bash
# FE-Sprache
find assets \( -name '*.tsx' -o -name '*.jsx' \) | sed 's/.*\.//' | sort | uniq -c

# Refetch
rg 'invalidateQueries|invalidatesTags|\.reload\(' assets/

# Read-Modell
ls -d src/Projection src/ReadModel src/Model/Read 2>/dev/null
rg 'ModelMapper|IndexRequest' src/

# Autorisierung
rg -l 'VoterInterface|extends Voter' src/
rg 'IsGranted' src/Controller

# Lifecycle
rg -l 'AsDoctrineListener|AsEntityListener|HasLifecycleCallbacks|getSubscribedEvents|getDependencyList' src/
```

## Config und Runtime-Introspection vor blindem Grep

Wenn Symfony selbst die registrierte Topologie zeigen kann, nutzen:

```bash
bin/console debug:router
bin/console debug:messenger
bin/console debug:container --tag=messenger.message_handler
```

Prinzip:

```text
resolved runtime / deklarative Config
        ↓
registrierter Code
        ↓
Repository-Grep als Discovery / Gegenprobe
```

Ein Grep findet Vorkommen; er beweist nicht automatisch, dass etwas registriert oder erreichbar ist.

---

# Schritt 0 — Analyse-Snapshot festhalten

Bevor inhaltliche Findings entstehen:

```markdown
**Modus:** ...
**Primäre Quelle:** ...
**Base:** <SHA/Branch oder n/a bei Plan>
**Head:** <SHA/Branch oder n/a bei Plan>
**Repository-Kontext:** <Worktree/Pfad>
**Source-Fingerprint:** <stabiler Fingerprint des Plans/Diffs/Commit-Sets>
**Projekt-Profil:** <P2/P5/P7/P8/P10 Kurzform>
```

Damit bleibt die Analyse reproduzierbar und ein später veränderter Branch verfälscht nicht stillschweigend den Kontext.

---

# Schritt 1 — Semantic Change Set erstellen

Die zentrale Analyse-Einheit ist **nicht die Datei**, sondern die beabsichtigte/tatsächliche Verhaltensänderung.

## 1a) Änderungen extrahieren

### Plan-Modus

Aus dem Lösungsplan konkrete Ziel-Symbole und Verhaltensänderungen ableiten:

- Klasse/Methode/Property,
- API-Route/DTO,
- Config-Regel,
- DB-Schema/Daten,
- Frontend-Komponente/State,
- Event/Message/Listener.

Wenn ein Plan nur „Datei X anpassen“ sagt, anhand des aktuellen Codes bestimmen, welches Symbol/Verhalten gemeint ist.

### Diff-Modus

Zusätzlich:

```bash
git diff --name-status <BASE>..<HEAD>
git diff --stat <BASE>..<HEAD>
git diff <BASE>..<HEAD>
```

Auch **gelöschte, umbenannte und verschobene** Symbole erfassen.

## 1b) Semantic-Change-Typen

Typische Änderungen:

- Condition/Guard geändert,
- Default/Nullability geändert,
- Enum Case ergänzt/entfernt,
- Validation geändert,
- Mapping/Serializer geändert,
- API Request/Response geändert,
- Query Predicate/Filter/Sortierung geändert,
- Statusübergang geändert,
- Permission geändert,
- Event/Message hinzugefügt/entfernt,
- Transaktions-/Async-Grenze geändert,
- persistiertes Feld/Constraint/Index geändert,
- Recalc-/Derived-Value-Logik geändert,
- UI-Gating/State/Refetch geändert.

## 1c) Architektur-Schicht und CQRS-Seite markieren

| Schicht | CQRS-Seite |
|---|---|
| Entity / Domain Service | Write/Domain |
| Enum / Domain Predicate | Both |
| Command / Handler | Write |
| Query / Handler | Read |
| Controller | API Boundary |
| Repository | Write/Read |
| Projection / ViewModel / ModelMapping | Read |
| Event / Message / Listener | Write→Read / Side Effect |
| Async Handler | Async |
| Permission/Voter | Security |
| FE API/State | API Contract / Frontend |
| FE UI | Frontend |
| Config | Infrastructure |
| Migration | Persistence |
| Export/Import | Integration |
| Test | Verification |

## 1d) Ergebnis

```markdown
### Semantic Change Set

| ID | Symbol/Contract | Semantic Change | Schicht | CQRS | Quelle |
|---|---|---|---|---|---|
| C1 | `FooHandler::__invoke()` | Guard für Typ X erweitert | Handler | Write | Plan/Diff |
| C2 | `GET /foo` Response | Feld `bar` neu optional | API/DTO | Read | Plan/Diff |
| C3 | `Foo::$bar` | neuer Writer/Recalc | Entity | Both | Plan/Diff |
```

**Completion Rule:** Jeder relevante Plan-/Diff-Bestandteil muss mindestens einem `C#` zugeordnet sein.

---

# Schritt 2 — Historische und fachliche Designintention gezielt prüfen

Historie wird **nach** dem Semantic Change Set betrachtet, damit nicht pauschal jede Datei gleich tief untersucht wird.

## 2a) Wann Historie Pflicht ist

Mindestens für Änderungen an:

- Business-Regeln/Conditions,
- Berechnungslogik,
- Status-/Workflow-Regeln,
- Permissions/Tenant-Filtering,
- Layout-/Report-Heuristiken,
- API-Verträgen mit bestehender Nutzung,
- bewusst ungewöhnlichem/kompliziertem Code,
- Stellen mit widersprüchlichen Tests oder Kommentaren.

Bei rein mechanischen Test-/Rename-/Formatänderungen ist tiefe Historie nicht automatisch sinnvoll.

## 2b) Von Datei-Historie zu Symbol-Historie

```bash
# Datei-Kontext / Renames
git log --all --oneline --follow -- <FILE>

# Wer/warum für konkrete Zeilen
git blame -L <START>,<END> <FILE>

# Funktionshistorie, wenn vom Git-xfuncname unterstützt
git log -L :<methodName>:<FILE>

# Wann wurde ein konkretes Literal/Prädikat eingeführt/entfernt?
git log --all -S '<literal-or-symbol>' -- <FILE>

# Regex-basierte semantische Suche über Diffs
git log --all -G '<regex>' -- <FILE>
```

Danach relevante Commits öffnen:

```bash
git show <SHA> -- <FILE>
```

## 2c) Historie korrekt interpretieren

- Commit-Subject allein genügt nicht.
- `Revert`/`Refactor` nicht automatisch ignorieren; prüfen, ob sie Verhalten verändern.
- Historie ist **Evidenz für frühere Designintention**, nicht automatisch aktuelle Wahrheit.
- Kollidiert alte Intention mit aktueller fachlicher Anforderung, Konflikt explizit dokumentieren.

## 2d) Ergebnis

```markdown
| Change | Datum | Commit/Ticket | Historische Designintention | Relevanz heute |
|---|---|---|---|---|
| C1 | ... | ... | ... | respektieren / überholt / unknown |
```

---

# Schritt 3 — Bidirektionale Impact-Verfolgung

Für jedes `C#` werden **Fan-in** und **Fan-out** verfolgt.

```text
                FAN-IN / CALLERS
                       ↑
UI → Controller → Handler → Service → Entity/Rule
                       ↓
                FAN-OUT / CALLEES
                       ↓
 DB / Event / Queue / Listener / Export / Cache / external API
```

Nur Bottom-Up-Tracing reicht nicht: eine Änderung kann mehrere Entry-Points **und** mehrere Side Effects besitzen.

---

## 3a) Fan-in — Wer nutzt das geänderte Verhalten?

Für geänderte Entity/Service/Enum/DTO/Mapper/Utility etc. alle relevanten Caller bestimmen:

```bash
rg '<ClassName>|<methodName>|<propertyName>' src/ assets/ tests/
```

Ziel:

```text
geändertes Symbol
↑ Handler/Service
↑ Command/Query
↑ Controller/API
↑ Frontend / Integration / CLI / Scheduler
```

Nicht beim ersten Caller stoppen.

---

## 3b) Fan-out — Was beeinflusst das geänderte Verhalten downstream?

Vom geänderten Symbol nach unten verfolgen:

- Repository/Persistenz,
- Domain Events,
- Messenger/Queues,
- Mail/Notifications,
- Exporte/Imports,
- externe APIs,
- Audit/Status-Logs,
- Cache/Invalidation,
- Recalc/Derived Values.

Ein Side Effect zählt auch dann, wenn er nicht direkt im Controller sichtbar ist.

---

## 3c) Write Flow schließen

Wenn Zustand verändert wird:

```text
React/Form/API Client
→ HTTP Route
→ Controller + Validation + Permission
→ Command
→ Handler
→ Domain/Entity/Service
→ Repository/Transaction
→ Event/Message/Lifecycle
→ Side Effect
```

Prüfen:

- User-Aktion und Entry-Point,
- Request-Daten und Validation,
- Permission/Tenant-Kontext,
- Domain-Regeln und Statusübergänge,
- Transaction Boundary,
- Events/Messages,
- Side Effects,
- Idempotenz, falls Wiederholung möglich.

---

## 3d) Read Flow schließen

Wenn Daten gelesen oder dargestellt werden:

```text
React View/Hook
→ API Client
→ HTTP Route
→ Controller
→ Query
→ Handler
→ Repository/Read Model
→ Mapping/DTO/Serializer
→ React Rendering
```

Prüfen:

- Listen-/Detail-/Dashboard-/Export-Consumer,
- Filter/Sorting/Pagination,
- Mandanten-/Rollenfilter,
- DTO-/ViewModel-Felder,
- Nullability/Defaults,
- Enum-/Label-Mapping,
- Frontend-Typen,
- Loading/Error/Empty-State.

---

## 3e) Write→Read-Übergang schließen

Explizit beantworten:

- Wie wird ein Write sichtbar?
- synchron oder eventual consistent?
- Projection/Recalc/Event/Queue?
- Refetch/Invalidierung im FE?
- welche UI kann stale bleiben?
- welche Warte-/Retry-Semantik muss QA kennen?

---

## 3f) Implizite / versteckte Kanten

### Doctrine Lifecycle / Recalc

Diese stehen oft nicht in einer normalen Call Chain.

Suchen:

```bash
rg 'AsDoctrineListener|AsEntityListener|getSubscribedEvents|HasLifecycleCallbacks|getDependencyList' src/
rg '<EntityName>|<propertyName>' src/EventSubscriber src/ 2>/dev/null
```

Prüfen:

- feuert Listener für die geänderte Entity/Property?
- ist das neue Feld in Dependency-Listen enthalten?
- `onFlush` vs `postFlush` Timing,
- Rekursion,
- Massen-Import/N×-Recalc,
- schreibt der Listener Felder, die wiederum Listener triggern?

### Messenger / Async

Primär `messenger.yaml` lesen:

- Routing,
- Transport/Queue,
- Retry Strategy,
- Middleware,
- Failure Transport.

Ein `AsMessageHandler`-Grep allein beweist nicht, dass eine Message async läuft.

### Weitere implizite Kanten

Je nach Projekt:

- Cache tags/invalidation,
- Scheduler/Cron,
- Feature Flags,
- Event Subscriber,
- ORM callbacks,
- Serializer groups,
- Config-driven permissions/views.

---

## 3g) Impact-Pfade dokumentieren

```markdown
### Impact-Pfad P1 — <Name>

**Changes:** C1, C3
**Entry Points:** ...
**Write:** `UI → Route → Controller → Command → Handler → Domain → DB`
**Hidden/Async:** `Listener → Message → Handler`
**Read:** `UI → Route → Query → ReadModel → DTO → Component`
**External/Side Effects:** ...
**Write→Read Visibility:** ...
```

Ein Pfad ist erst „geschlossen“, wenn keine relevante Kante nur mit „irgendwo danach“ beschrieben wird.

---

# Schritt 4 — Business-Verhalten modellieren

## 4a) Verzweigungen finden

Nicht nur Enums betrachten.

### Enum-/Typ-basiert

- `match`, `switch`, Enum-Vergleiche,
- `isUzv()`-/`isMnm()`-artige Predicates,
- Strategy/Type/Purpose/Status.

### Property-/Flag-basiert

- Boolean Flags,
- `null` vs gesetzt,
- `isVirtual()`, `isCorrectionProcess()` etc.,
- Start-/End-/Effect-Year,
- Erst-/Folgeversion,
- Datenbesitz/Tenant.

### Schwellenwerte

- Jahres-/Datumsgrenzen,
- numerische Grenzwerte,
- exakt `==`, `<`, `>=` an der Schwelle.

### Workflow / Security

- Statusübergänge,
- Rollen,
- Backend Permission,
- FE-Gating,
- direkte API-Nutzung trotz verstecktem Button.

---

## 4b) Fachliche Invarianten identifizieren

Eine Invariante ist stärker als ein einzelner Branch, z.B.:

```text
submitted entities sind immutable
Tenant A darf Daten von Tenant B nie lesen
sum(details) == total
ein Status darf nur über erlaubte Übergänge wechseln
erfolgreicher Write muss gemäß Konsistenzmodell lesbar werden
```

**Wichtig:** Invarianten nur aus Task/Code/Tests/Domain-Doku ableiten, nicht erfinden.

Dokumentieren:

```markdown
| ID | Invariante | Quelle | Durch C# gefährdet? | Verifikation |
|---|---|---|---|---|
| INV-1 | ... | Test/Code/Task | ja/nein | ... |
```

---

## 4c) Decision Tables bei kombinierten Bedingungen

Wenn Verhalten von ≥2 unabhängigen Dimensionen abhängt, nicht nur jede Dimension einzeln auflisten.

Beispiel:

```markdown
| Type | Virtual | Correction | Status | Erwartung |
|---|---|---|---|---|
| UZV | false | false | editing | ... |
| UZV | true | false | editing | ... |
| KZV | false | true | editing | ... |
```

Regeln:

1. unmögliche Kombinationen eliminieren,
2. kritische Kombinationen vollständig testen,
3. für verbleibende große Matrizen mindestens sinnvolle pairwise-/repräsentative Abdeckung,
4. Boundary-Werte separat behandeln.

Keine kartesische Testexplosion ohne Risikobegründung.

---

## 4d) Data Lineage für relevante Felder

Pflicht bei Bugs/Änderungen der Form:

- „Feld wird nicht gesetzt“,
- „zeigt 0/null/falschen Wert“,
- „nur Typ X betroffen“,
- neuer persistierter/abgeleiteter Wert,
- Mapping-/Serializer-/Export-Änderung.

Verfolge:

```text
Input
→ Request/DTO
→ Command/Writer
→ Entity/DB
→ Recalc/Listener/Calculator
→ Query/Mapper/ViewModel
→ API Response
→ React
→ Export/Integration
```

Nach dem **Property-Namen** suchen, nicht nur nach Setter:

```bash
rg '<propertyName>' src/ assets/
```

Alle Writer und Reader klassifizieren.

### Kanonische Domain-Predicates wiederverwenden

Bevor ein neuer Guard aus primitiven Checks gebaut wird, prüfen, ob das Konzept bereits benannt ist:

```bash
rg -n 'function .*<concept>|<existingPredicate>' src/
```

Schreib- und Leseseite sollten dasselbe fachliche Prädikat verwenden, wenn sie dasselbe Konzept ausdrücken.

### Widersprüche sind Signal, nicht Rauschen

Wenn ein Test/anderer Flow die aktuelle Annahme widerlegt:

- nicht als „defensiv“, „tot“ oder „veraltet“ wegargumentieren,
- Ursache auflösen,
- ggf. als `UNKNOWN`/Risk dokumentieren.

---

## 4e) Vollständigkeitscheck der Business-Matrix

Prüfen:

- alle Enum Cases,
- true/false,
- null/set,
- Status vorher/nachher,
- Rollen erlaubt/verboten,
- Schwellenwert darunter/genau/darüber,
- Erst-/Folgeversion,
- normal/correction,
- bestehende Alt-Datensätze.

---

# Schritt 5 — Cross-Cutting Impact Sweep

Für jeden Bereich mindestens Status setzen:

```text
not affected | affected | unknown
```

Nur betroffene/unklare Bereiche vertiefen.

---

## 5a) Persistenz, Migration und Deployment-Kompatibilität

Prüfen:

- Schemaänderung?
- nullable ↔ non-null?
- Default geändert?
- Backfill/Recalc für Bestandsdaten?
- Unique/FK/Index?
- Datenformat/JSON/Enum geändert?
- Query-/Index-Performance?
- Rollout-Zwischenzustände kompatibel?

Besonders:

```text
alte App + neues Schema
neue App + neues Schema
```

Falls Rolling Deployment möglich ist, zusätzlich Kompatibilität während gemischter Versionen betrachten.

---

## 5b) Security / Tenant / Datenbesitz

Prüfen:

- Backend schützt Write **und** Read,
- FE versteckt nicht nur optisch,
- Permission-Config und Controller-Attribut konsistent,
- Query-Restrict-/Tenant-Filter,
- Admin/Superuser-Sonderpfade,
- direkte API-Nutzung,
- neue Status/Typen in Permission-Regeln.

---

## 5c) Async / Eventual Consistency / Reliability

Prüfen:

- Message wirklich async?
- Queue/Lane/Reihenfolge,
- at-least-once → Handler idempotent?
- Duplicate Message,
- Out-of-order,
- Retry deterministisch sicher?
- Poison Message / Failure Transport,
- alte bereits persistierte Messages schema-kompatibel?
- Write→Message-Atomizität.

Kritischer Fehlerfall:

```text
DB COMMIT erfolgreich
↓
Message Dispatch/Persistierung fehlgeschlagen
```

Wenn Architektur diesen Zustand zulässt, als Konsistenzrisiko dokumentieren.

---

## 5d) Concurrency / Transaction Boundaries

Prüfen:

- Doppel-Click / Doppel-Submit,
- zwei Browser-Tabs,
- zwei Benutzer ändern dieselbe Entity,
- Lost Update,
- Optimistic/Pessimistic Locking,
- Unique-Constraint-Race,
- Handler mehrfach ausgeführt,
- read-after-write,
- Transaktion über mehrere Aggregate/Repositories.

Nur dort vertiefen, wo die Änderung tatsächliche Konkurrenz-/Idempotenzfläche berührt.

---

## 5e) Cache / Performance / Volumen

Prüfen:

- Cache invalidiert?
- N+1 / zusätzlicher Query pro Row?
- Listener bei jedem Flush?
- Import/Export große Mengen?
- neue Sortierung/Filter ohne Index?
- Frontend mehrfaches Refetch?

Keine Performance-Spekulation ohne konkreten Pfad.

---

## 5f) Integrationen / Audit / Observability / Localization

Je nach Änderung:

- externe API Contract,
- Mail/Notification,
- Export/Import,
- Audit-/Statuslog,
- Logs/Metrics bei neuem Failure Mode,
- Übersetzungen/Enum Labels,
- Feature Flags,
- Accessibility bei UI-Verhaltensänderungen.

---

# Schritt 6 — Missing-Counterpart / Symmetry Check

Viele Review-Bugs entstehen nicht durch falschen Code, sondern durch eine **fehlende parallele Änderung**.

Für jedes `C#` nach erwartbaren Gegenstellen suchen.

## Typische Symmetrien

| Änderung | Mögliche Gegenstellen |
|---|---|
| Enum erweitert | Validator, Serializer, FE Label, Translation, Filter, Export, Fixtures, Tests |
| API Response geändert | DTO/ViewModel, FE Type/Mapper, List + Detail, Export |
| Create geändert | Update/Copy/Import/Versionierung |
| Write geändert | Read/Recalc/Projection/Refetch |
| Permission geändert | Read + Write + FE-Gating + Tests |
| Property geändert | alle Writer + alle Reader + Lifecycle Dependency |
| Status geändert | Buttons, Transition Guard, Mail, Permissions, List Filter |
| Import geändert | UI-Write/Copy/Export/Calculator |
| List geändert | Show/Dashboard/Export |
| Sync Flow geändert | Async Handler / Retry / eventual read |

Vorgehen:

```bash
rg '<concept|enum|property|route|dto>' src/ assets/ tests/ config/
```

Nicht jede gefundene Symmetrie muss geändert werden. Entscheidend ist, sie bewusst als:

```text
covered | intentionally unaffected | missing | unknown
```

zu klassifizieren.

---

# Schritt 7 — Findings als Evidenz-basierten Risk Register führen

Ab hier keine losen, mehrfach wiederholten Warnlisten mehr. Findings zentral erfassen.

## 7a) Evidence Discipline

Jede wesentliche Aussage ist eine von:

- **FACT** — direkt belegt,
- **INFERENCE** — aus Facts abgeleitet,
- **UNKNOWN** — nicht ausreichend entscheidbar.

Ein Risk braucht konkrete Evidenz oder muss als Hypothese/Unknown gekennzeichnet werden.

Beispiel:

```markdown
### R-04 — Recalc könnte bei Änderung von `bar` fehlen

**Evidence (FACT):** `FooListener::getDependencyList()` enthält `foo`, aber nicht `bar`.
**Evidence (FACT):** `FooCalculator` liest `bar`.
**Inference:** Änderung von `bar` könnte keinen Recalc triggern.
**Confidence:** high
**Verification:** Integrationstest `bar ändern → flush → result neu berechnet`.
```

## 7b) Risiko-Kriterien

### Impact

- **critical** — Security/Data Leak/Data Loss/falsche regulatorische oder geschäftskritische Ergebnisse,
- **high** — zentraler Business-Flow, falscher Status/Berechnung, mehrere Consumer,
- **medium** — lokaler Flow/Regression mit Workaround,
- **low** — kosmetisch/eng begrenzt.

### Likelihood

- high — Hauptpfad / realistische Kombination,
- medium — legitimer Nebenpfad,
- low — seltene/enge Voraussetzung.

### Detectability

- low detectability = besonders riskant: silent corruption, async/stale, später sichtbarer Fehler,
- high detectability = sofortiger UI/API-Fehler.

Keine pseudo-genaue Mathematik nötig. Die Dimensionen sollen die Priorisierung nachvollziehbar machen.

## 7c) Zentraler Risk Register

```markdown
| ID | Change/Path | Finding | Evidence | Impact | Likelihood | Detectability | Confidence | Status |
|---|---|---|---|---|---|---|---|---|
| R1 | C1/P1 | ... | file:symbol | high | high | low | high | open |
```

`Status`:

```text
open | covered by plan | confirmed defect | intentionally accepted | unknown
```

**Regel:** High/Critical darf am Ende nicht kommentarlos offen bleiben.

### 7d) Kritische Findings adversarial verifizieren

Bei `critical` Findings oder überraschenden High-Risk-Thesen aktiv versuchen, die eigene These zu widerlegen:

- alternativen Caller/Writer/Reader suchen,
- bestehende Tests lesen/ausführen,
- Runtime-/Config-Gegenbeleg prüfen,
- historische Gegenentscheidung suchen.

Erst danach `confirmed defect` setzen. Nicht mehrere Agents voraussetzen; entscheidend ist **unabhängige Gegen-Evidenz**.

---

# Schritt 8 — Test-Impact aus Risiken und Flows ableiten

Tests sind Ergebnis der Impact-Analyse, nicht eine generische Checkliste.

## 8a) Risk→Test Traceability

Jedes relevante Risiko bekommt:

- bestehenden Test, der angepasst/erweitert wird,
- neuen Test,
- oder explizite Begründung, warum andere Verifikation genügt.

```markdown
| Risk | Test/Verifikation | Ebene | Muss neu/geändert? |
|---|---|---|---|
| R1 | `FooHandlerTest::...` | Domain/Integration | ändern |
| R2 | `GET /foo` verbotene Rolle | Controller/API | neu |
```

## 8b) Testebenen gezielt wählen

### Symfony / Backend

- Domain/Entity/Service für Business-Regeln,
- Handler für Command/Query-Verhalten,
- Controller/API für Contract + Validation + Security,
- Integration für Doctrine Listener/Recalc/Transaction,
- Messenger Handler + Retry/Idempotenz bei Async,
- Repository für Filter/Sorting/Pagination/Tenant.

### React / Frontend

- Component/Conditional Rendering,
- API Mapper/Hook/State,
- Form Validation/Error Mapping,
- Refetch/Invalidation,
- List + Detail nach Write,
- E2E nur für kritische User Journey / cross-layer Verhalten.

## 8c) API-Contract-Check

Pro betroffenem Endpoint:

| Frage | Risiko |
|---|---|
| Request geändert? | FE/Consumer sendet falsche Form |
| Response geändert? | Consumer rendert/mapped falsch |
| Feld neu/weg/optional? | `undefined`/Nullability/Backward Compatibility |
| Enum erweitert? | Mapping/Label/Translation |
| HTTP Status/Error Shape geändert? | Error Handling |
| Filter/Sorting/Pagination geändert? | Listenregression |
| Permission geändert? | Datenzugriff |

## 8d) Varianten ableiten

Aus Decision Table/Invarianten/Risk Register statt pauschal alles testen:

- kritische Enum Cases,
- Status vorher/nachher,
- true/false,
- null/set,
- Grenze darunter/genau/darüber,
- erlaubte/verbotene Rolle,
- alt/neu Bestandsdaten,
- Write→Read Sichtbarkeit,
- Retry/Duplicate nur wenn async relevant.

## 8e) QA-Priorisierung

### P1 — Muss

- kritischer Happy Path,
- High/Critical Risk,
- Negativ-/Permission-Fall bei Security,
- Write→Read-Sichtbarkeit bei geänderten Writes,
- Datenmigration/Bestandsdaten, wenn betroffen.

### P2 — Sollte

- angrenzende Varianten/Regression,
- List/Detail/Dashboard/Export-Counterparts,
- API-Contract-Nebenpfade,
- relevante Boundary Cases.

### P3 — Optional / risikobasiert

- seltene Kombinationen,
- große Datenmengen,
- Failure Transport,
- exotische Rollen,
- nichtkritische UI-Edges.

---

# Schritt 9 — Offene Fragen nur aus echten Unknowns ableiten

Keine generischen Fragen erzeugen, die Code/Config bereits beantworten kann.

Eine Frage ist sinnvoll, wenn:

1. ein `UNKNOWN` nach Repository-/Historienanalyse bestehen bleibt **und**
2. unterschiedliche Antworten zu anderem Verhalten/Plan/Test führen.

Beispiele:

- „Die historische Regel hält Signatur X auf Seite 1, das aktuelle AC verlangt aber Y. Soll die alte Heuristik bewusst entfallen?“
- „Für Bestandsdaten existiert kein Recalc-Pfad. Soll die Migration bestehende Datensätze backfillen oder gilt die Änderung nur für neue Daten?“
- „API-Response wird optional erweitert; ist ein externer Consumer außerhalb des Repos bekannt?“

Priorität:

```text
blocking / high-impact → zuerst
non-blocking → dokumentieren
```

---

# Schritt 10 — Caller-Handoff

Die Methodik liefert nur den fachlichen Handoff. **Persistenz, Planmutation und Folge-Skill-Aufrufe übernimmt `SKILL.md` bzw. der Caller.**

## `start-task`

- Plan-Lücken → Lösungsplan anpassen.
- Traceability/Testplan aktualisieren.
- Betroffene Impact-Pfade nach Planänderung erneut verifizieren.
- Kein `high/critical` Risk ohne Plan/Test/gezielte Rückfrage stehen lassen.

## `review-task`

- tatsächliche Implementierung gegen Task/Plan und Impact prüfen,
- Findings + Test-Impact dokumentieren,
- geplante, aber nicht implementierte Changes als Missing Counterpart/Scope Gap markieren.

## `review-merge`

- Review-Findings evidenzbasiert formulieren,
- Severity + betroffenen Flow + konkrete Verifikation nennen,
- keine spekulativen „könnte vielleicht“-Findings ohne Evidenz als Defect ausgeben.

## standalone

- Report ohne Caller-spezifische Mutation abschließen.

---

# Completion Gate

Die Analyse ist erst abgeschlossen, wenn:

```markdown
- [ ] Analysemodus + Quelle + Repository-Snapshot dokumentiert
- [ ] Projekt-Profil bestimmt bzw. relevanter Teil verifiziert
- [ ] Semantic Change Set vollständig
- [ ] relevante Designhistorie geprüft
- [ ] Fan-in pro Business-Change untersucht
- [ ] Fan-out / Side Effects untersucht
- [ ] Write Flow geschlossen, falls betroffen
- [ ] Read Flow geschlossen, falls betroffen
- [ ] Write→Read-Sichtbarkeit geklärt
- [ ] Lifecycle/Async/Config-getriebene versteckte Kanten geprüft
- [ ] Business-Verzweigungen + Invarianten geprüft
- [ ] Decision Table bei kombinierten Bedingungen erstellt, falls nötig
- [ ] Data Lineage für relevante Felder geschlossen, falls nötig
- [ ] Persistence/Security/Async/Concurrency/Cross-Cutting Sweep klassifiziert
- [ ] Missing-Counterpart/Symmetry Check durchgeführt
- [ ] Risk Register erstellt
- [ ] jeder High/Critical Risk hat Plan/Test/Acceptance/Question
- [ ] Tests auf Risiken/Flows zurückgeführt
- [ ] offene Unknowns explizit dokumentiert
```

Wenn ein Punkt **nicht betroffen** ist, explizit als `n/a` markieren statt ihn stillschweigend auszulassen.

---

# Report-Template

Im Task-File unter `## Impact-Analyse`, im Review unter `## Test-Impact-Analyse`.
Nicht betroffene Detailsektionen dürfen im finalen Report weggelassen oder kompakt als `n/a` markiert werden — die Completion-Gate-Prüfung bleibt trotzdem Pflicht.

```markdown
## Test-Impact-Analyse

**Durchgeführt am:** <DATUM>
**Modus:** <start-task | review-task | review-merge | standalone>
**Basis:** <Plan | Branch-Diff | MR-Diff | merged commits>
**Base/Head:** <...>
**Repository-Kontext:** <...>
**Projekt-Profil:** <FE · Read Model · Security · Async · Lifecycle>

### 1) Semantic Change Set

| ID | Symbol/Contract | Semantic Change | Schicht | CQRS | Quelle |
|---|---|---|---|---|---|
| C1 | ... | ... | ... | ... | ... |

### 2) Historische Designintention

| Change | Commit/Ticket | Designintention | Relevanz heute |
|---|---|---|---|
| C1 | ... | ... | ... |

### 3) Impact-Pfade

#### P1 — <Name>
**Changes:** C1, C2
**Fan-in / Entry:** ...
**Write:** ...
**Hidden/Async:** ...
**Read:** ...
**Write→Read:** ...
**External/Side Effects:** ...

### 4) Business-Verhalten

#### Invarianten
| ID | Invariante | Quelle | Gefährdet? | Verifikation |
|---|---|---|---|---|
| INV-1 | ... | ... | ... | ... |

#### Decision Table
<nur wenn nötig>

#### Data Lineage
<nur wenn nötig>

### 5) API-Contract-Check

<nur wenn API-Verträge betroffen sind>

| Endpoint | Request | Response | Status/Error | Security | Consumer | Risiko |
|---|---|---|---|---|---|---|
| ... | ... | ... | ... | ... | ... | ... |

### 6) Cross-Cutting Sweep

| Bereich | Status | Relevanz / Finding |
|---|---|---|
| Persistence/Migration | affected / n/a / unknown | ... |
| Security/Tenant | ... | ... |
| Async/Consistency | ... | ... |
| Concurrency/Transaction | ... | ... |
| Cache/Performance | ... | ... |
| Integration/Audit/Localization | ... | ... |

### 7) Missing Counterparts

| Change | Counterpart | Status | Begründung |
|---|---|---|---|
| C1 | List/Show/... | covered / missing / unaffected / unknown | ... |

### 8) Risk Register

| ID | Change/Path | Finding | Evidence | Impact | Likelihood | Detectability | Confidence | Status |
|---|---|---|---|---|---|---|---|---|
| R1 | ... | ... | ... | ... | ... | ... | ... | ... |

### 9) Risk→Test Matrix

| Risk | Test/Verifikation | Ebene | Priorität |
|---|---|---|---|
| R1 | ... | ... | P1 |

### 10) Was muss QA testen?

#### P1 — Muss
- [ ] ...

#### P2 — Sollte
- [ ] ...

#### P3 — Optional
- [ ] ...

### 11) Offene Unknowns / Nachfragen

1. ...

### 12) Caller-Handoff

**Plan-/Implementierungsanpassungen erforderlich:** <ja/nein>
- ...

**High/Critical offen:** <0 / Liste>
```

---

# Qualitätskriterien

## Gute Impact-Analyse

- arbeitet von **Semantic Changes**, nicht bloß Dateilisten,
- trennt tatsächliche Evidenz von Schlussfolgerungen,
- untersucht Fan-in **und** Fan-out,
- schließt Write-, Read- und Write→Read-Pfade,
- findet implizite Listener/Async-/Config-Kanten,
- prüft Invarianten und kombinierte Business-Entscheidungen,
- verfolgt relevante Datenfelder von Writer bis Consumer,
- sucht bewusst nach fehlenden Gegenstellen,
- führt Findings in einem zentralen Risk Register,
- koppelt High/Critical-Risiken an konkrete Tests oder Entscheidungen,
- dokumentiert echte Unknowns statt sie mit Annahmen zu füllen.

## Schlechte Impact-Analyse

- listet nur geänderte Dateien,
- stoppt beim Handler,
- behandelt den ersten gefundenen Setter/Caller als vollständig,
- vermischt Fact und Vermutung,
- erzeugt pauschale QA-Checklisten ohne Bezug zu Risiken,
- ignoriert Read-Seite, Refetch, Lifecycle oder Async,
- übersieht parallele Implementierungen/List-vs-Show/Import-vs-UI,
- erklärt widersprechende Tests vorschnell als „toten Code“,
- übernimmt Dokumentation ungeprüft als Runtime-Wahrheit,
- meldet spekulative Risiken ohne Evidenz als Defect.

---

# Merksatz

Nicht fragen:

> Welche Dateien wurden geändert?

Sondern:

> **Welche semantischen Verhaltensänderungen entstehen, wer ruft sie auf, was beeinflussen sie downstream,
> welche Invarianten und Gegenstellen hängen daran, und welche Evidenz/Testabdeckung brauchen wir, um das Risiko
> kontrolliert freizugeben?**
