# Test-Impact-Analyse — Symfony / React / Ant Design (portabel)

Business-Logik-Verzweigungen, Aufwärts-Verfolgung, API-Contract, Read/Write-Impact und QA-Risiken.

Diese Anleitung ist **projekt-neutral** für Symfony-Backend + React/Ant-Design-Frontend mit CQRS-artiger
Command/Query-Trennung (Symfony Messenger). Sie wird von mehreren Commands verwendet:

- `start-task` (Schritt 5b) — **vor** der Umsetzung, basierend auf dem Lösungsplan
- `review-task` (Phase 1d) — **nach** der Umsetzung, basierend auf dem git diff
- `review-merge` (Phase 3b) — beim **Review eines Kollegen-MRs**, basierend auf dem MR-Branch-Diff
- `impact-analysis` — **standalone**, für Tasks in jedem Status (offen, in Bearbeitung, abgeschlossen)

Ziel ist nicht, geänderte Dateien aufzulisten, sondern die fachlichen und technischen Auswirkungen entlang
der betroffenen Flows zu verstehen:

- Was verändert Zustand? (**Write Flow / Command-Seite**)
- Was liest Zustand? (**Read Flow / Query-Seite**)
- Wie wird ein Write auf der Read-Seite sichtbar? (Events, Messenger, Refetch/Invalidierung)
- Welche API-Verträge zwischen Symfony und React ändern sich?
- Welche Business-Logik-Verzweigungen (Enums, Properties, Flags, Schwellenwerte, Rollen) erzeugen Risiko?
- Welche Testbereiche muss QA gezielt prüfen?

---

## Wie diese Anleitung portabel bleibt

Die **Methodik** (Schritt 0–5, Report-Template) ist über alle Symfony/React/AntD-Projekte identisch.
Nur ein kleiner Satz **konkreter Konventionen** unterscheidet die Projekte (z.B. TypeScript vs. JSX,
Read-Model als Projection vs. Doctrine-Repository + ModelMapping, Voter-Verzeichnis vs. coala). Diese
Konventionen werden **nicht** in den Fließtext gebrannt, sondern einmal pro Projekt im **Projekt-Profil**
unten festgehalten — vom Agenten zu Beginn der Analyse **selbst detektiert**.

**Regel:** Wenn im Fließtext ein `‹Profil.X›`-Platzhalter steht, den konkreten Wert aus dem Projekt-Profil
einsetzen. Fließtext-Beispiele mit echten Klassennamen sind mit *„Beispiel"* markiert und dürfen NICHT als
projektweite Wahrheit gelesen werden.

---

## Projekt-Profil zuerst bestimmen (Auto-Detektion)

> ⚠️ **Der Projekt-Doku (`architecture.md`/README) NICHT blind trauen** — sie driftet. Reale Erfahrung:
> eine `architecture.md` behauptete „TypeScript" + „RTK Query", der Code war aber JSX mit imperativem
> Table-`reload()`. **Immer aus dem Code detektieren.**

Führe die Detektions-Greps **einmal** zu Beginn der Analyse aus und notiere den detektierten Wert je Achse
(im Report-Kopf unter „Projekt-Profil"). Ein Projekt kann optional eine gepflegte Companion-Datei mitliefern
(`docs/claude/impact-analysis.profile.md` oder einen Block in `CLAUDE.md`); existiert die, gilt sie als
Override und die Detektion nur als Gegenprobe.

| # | Achse | Detektion (aus Repo-Root) → notiere den Wert |
|---|-------|-----------------------------------------------|
| P1 | **Ticket-Pattern** | `git log --oneline -20` → Ticket-Prefix (`<PREFIX>-####`) erkennen |
| P2 | **FE-Sprache / Endung** | `find assets \( -name '*.tsx' -o -name '*.jsx' \) \| sed 's/.*\.//' \| sort \| uniq -c` → JSX oder TSX (Mehrheit gewinnt) |
| P3 | **FE-Refetch nach Mutation** | `grep -rl "invalidateQueries\|invalidatesTags\|\.reload(" assets/ \| head` → React-Query/RTK-Tag-Invalidation **oder** imperativer `reload()` |
| P4 | **FE-Permission-Gating** | `ls config/packages/fe_actions.yaml config/packages/fe_views.yaml 2>/dev/null`; `grep -rl "ViewConstraint\|withActionConstraint" assets/` → Config-YAMLs + FE-Constraint-Komponenten (`actions`-Prop) |
| P5 | **Read-Modell** | `ls -d src/Projection src/ReadModel src/Model/Read 2>/dev/null`; sonst `grep -rl "ModelMapper\|IndexRequest" src/ \| head` → Projection/Read-Model **oder** Query-Handler + Doctrine-Repo + ModelMapping + `Model/…List`-ViewModels |
| P6 | **Message-Ablage** | `ls src/Message` → getrennte `Command/`+`Query/`-Ordner **oder** feature-weise `Message/<Feature>/*Command\|*Query` |
| P7 | **Autorisierung** | **Generisch** `grep -rln "VoterInterface\|extends Voter" src/` (findet ALLE Voter-Klassen, name-unabhängig); Regeln: `ls config/packages/coala_permissions.yaml`; Attribut-Namen: `grep -rhoE "IsGranted\(.'[A-Z_]+'" src/Controller \| sort -u`. → Meist **1 generischer** Dispatcher; die Regel liegt in `coala_permissions.yaml` + `#[IsGranted('…')]`, **nicht** im Voter-Body. *Mehr* Voter-Treffer = hand-codierte Regeln außerhalb coala (Extra-Fläche) |
| P8 | **Async-Mechanismus / Queues** | **Primär** `config/packages/messenger.yaml` (+ `when@…`-Overrides): `routing:` = welche Message-Klassen async & auf welche Queue, `transports:` = Lanes, `retry_strategy` = Retry-Politik, `buses:…middleware:` = Pipeline. Fallback `grep -rn "BackgroundJobMessage\|AsyncMessage\|AsMessageHandler" src/` (findet auch synchrone Handler) |
| P9 | **Hochrisiko-Enums** | `find src -path '*Enum*' -name '*.php'` → Type-/Status-/Zweck-Enums der Domäne (jeder Case = Verzweigungs-Risiko, Schritt 3) |
| P10 | **Auto-Recalc / Lifecycle-Listener** | `grep -rln "AsDoctrineListener\|AsEntityListener" src/`; `grep -rln "getDependencyList" src/EventSubscriber/`; `grep -rn "HasLifecycleCallbacks" src/Entity/` → deklarativer `getDependencyList()`-Reverse-Index? sonst `onFlush`-Bodies lesen (Schritt 2e) |

**Deklarative Config vor Code-Grep:** Wo eine Config-Datei die Konvention *deklariert*, ist sie autoritativer
als ein Code-Grep — sie ist vollständig und trennt sauber. Nutze daher als Primärquelle:
`config/packages/messenger.yaml` (Async: `routing:`/`transports:`/`retry_strategy`/Bus-`middleware:` — genauer
als `grep AsMessageHandler`, das auch synchrone Handler findet), `coala_permissions.yaml` (Autorisierungs-Regeln als *Daten* — der Voter ist nur ein generischer Dispatcher;
die zu prüfende Berechtigung steht im `#[IsGranted('…')]`-Attribut am Controller + dem passenden yaml-Eintrag,
P7), `fe_actions.yaml`/`fe_views.yaml` (FE-Gating, P4). Der Code-Grep dient dann nur als Gegenprobe.

**Ausnahme, die der Grep aufdeckt:** Findet `grep -rln "VoterInterface" src/` (P7) *mehr* als den einen
coala-Dispatcher, trägt jeder Extra-Treffer eigene Regeln **außerhalb** coala → zusätzliche
Autorisierungs-Fläche, die separat analysiert werden muss (der interface-basierte Grep ist daher robuster
als ein Verzeichnis-/Namens-Grep wie `src/Voter/`).

Beim Async-Impact zusätzlich aus `messenger.yaml` ablesen (fließt in Schritt 3d „Write→Read" & 4H ein):
welche Queue (Reihenfolge/Latenz für QA-Sichtbarkeit), `retry_strategy.max_retries` (deterministischer
Validierungs-Fehler beim Consume → Retry-Loop kann Worker aushungern) und die Bus-`middleware:`
(z.B. Validierung-on-delivery, realtime-for-async).

**Merke:** Die Achsen, auf denen Projekte differieren, sind wenige und stabil. Alles andere (Write/Read-
Trennung, Verzweigungs-Analyse, QA-Priorisierung) ist projekt-unabhängig.

---

## Modus: Datenquelle bestimmen

| Kontext | Datenquelle | Ziel |
|---------|-------------|------|
| `start-task` | **Lösungsplan** — geplante Datei-Änderungen | Nebeneffekte VOR der Umsetzung erkennen |
| `review-task` | **git diff** — tatsächliche Code-Änderungen | Test-Bereiche für QA identifizieren |
| `review-merge` | **git diff** — MR-Branch des Kollegen | Lücken finden, Findings generieren, QA informieren |
| `impact-analysis` | **Lösungsplan, Branch-Diff oder gemergte Commits** | Impact unabhängig vom Task-Status |

**`start-task`:** Aus dem Lösungsplan ermitteln, welche Dateien/Klassen/Methoden geändert werden sollen.

**`review-task`:** Tatsächlich geänderte Dateien aus dem git diff:

```bash
MERGE_BASE=$(git merge-base HEAD develop)
git diff --name-only $MERGE_BASE..HEAD
git status --short
```

**`review-merge`:** Änderungen des MR-Branches:

```bash
git log --oneline origin/develop..origin/<branch-name>
git show origin/<branch-name> --name-only --oneline
```

**`impact-analysis`:** Zuerst Task, Branch und Status bestimmen. Je nach Status:

- **Offen:** Lösungsplan aus Task-File
- **In Bearbeitung:** Branch-Diff gegen `develop`
- **Abgeschlossen:** gemergte Commits in `develop`

```bash
TICKET="<TICKET-NUMMER>"                 # Prefix aus Profil.P1
git branch -a --list "*${TICKET}*"
git log --oneline develop --grep="$TICKET"
git log --name-only --pretty=format: develop --grep="$TICKET" | sort -u | grep -v "^$"
```

**Wichtig:** Datenquelle immer im Ergebnis dokumentieren (Plan / Diff / gemergter Code).

---

## Schritt 0: Historische Ticket-Verfolgung (PFLICHT, vor allem anderen)

**Warum:** Eine Datei trägt oft Spuren von ≥3 vergangenen Tickets — jedes hat eine Anforderung oder einen
Trade-off zementiert. Ohne diese Historie überschreibt man leicht bewusste Entscheidungen (z.B. eine
Heuristik, die für einen konkreten User-Pain eingeführt wurde). Realer Vorfall: ein Fix wollte initial
`allOnOnePage = false` setzen und hätte damit eine frühere Heuristik („Signatur-Sektion für ≤ 2
Betriebsstätten auf Seite 1 lassen") zerstört.

Dieser Schritt ist **projekt-unabhängig** — er hängt nur an git. Nur das Ticket-Pattern kommt aus `Profil.P1`.

**Befehle (pro zu ändernder Datei):**

```bash
# 1. Direkter Commit-Log der Datei (folgt Renames)
git log --all --oneline --follow <PATH/TO/FILE> | head -15

# 2. Nur Ticket-Commits, die die Datei berühren (Pattern aus Profil.P1)
git log --all --oneline --follow <PATH/TO/FILE> | grep -iE "<TICKET-PREFIX>-[0-9]+" | head -15

# 3. Bei Layout-/Template-/CSS-Dateien zusätzlich nach Begriffsfeld grep'en (manche Tickets berühren
#    das Layout indirekt über andere Files):
git log --all --oneline --grep="<feature-keyword>" | head -10
```

**Dokumentation** — im Ergebnis eine Tabelle der relevanten Treffer:

```markdown
| Datum       | Commit | Ticket      | Wesentliche Aussage / Designintention                     |
|-------------|--------|-------------|-----------------------------------------------------------|
| YYYY-MM-DD  | abc123 | <PREFIX>-XX | Commit-Subject + 1–2 Sätze, WARUM die Regel eingeführt wurde |
```

Pro Treffer NICHT nur das Commit-Subject zitieren, sondern den Diff kurz ansehen (`git show <sha> -- <file>`)
und die **Designintention** in eigenen Worten festhalten. Tickets mit `Revert`/`Refactor` im Subject sind
meist ignorierbar; relevant sind Tickets, die **fachliche Regeln, Heuristiken oder explizite Trade-offs**
zementiert haben.

**Erkenntnis im Plan berücksichtigen:** Kollidiert ein altes Ticket mit dem geplanten Fix → **Plan anpassen**,
bevor implementiert wird: entweder die alte Heuristik respektieren (Fix nur im komplementären Pfad) oder
explizit dokumentieren, warum die alte Entscheidung überholt ist (mit User-Bestätigung).

---

## Schritt 1: Geänderte Dateien kategorisieren

Ordne jede geplante/geänderte Datei einer Architektur-Schicht zu und markiere die **CQRS-Seite**
(Write / Read / Both / Infrastructure). Die Pfad-Muster variieren je Projekt (`Profil.P5/P6/P7`).

| Schicht | CQRS-Seite | Typisches Pfad-Muster | Profil-Hinweis |
|---------|------------|-----------------------|----------------|
| **Entity** | Write / Domain | `src/Entity/` | — |
| **Enum** | Write / Read / Both | `src/Model/Enum/` bzw. `find src -path '*Enum*'` | `Profil.P9` |
| **Domain Service** | Write / Domain | `src/Service/` | — |
| **Command** | Write | `src/Message/…*Command` | `Profil.P6` |
| **CommandHandler** | Write | `src/MessageHandler/…` | — |
| **Query** | Read | `src/Message/…*Query` | `Profil.P6` |
| **QueryHandler** | Read | `src/MessageHandler/…` | — |
| **Controller** | API Boundary | `src/Controller/` | Autorisierung via `Profil.P7` |
| **Repository** | Write / Read | `src/Repository/` | — |
| **Read-Modell / Projection** | Read | `Profil.P5` — Projection ODER `Model/…List` + ModelMapping | `Profil.P5` |
| **Domain Event / Message** | Write → Read / Async | `src/Event/` bzw. `src/Message/Event/` | — |
| **Doctrine-Listener / Lifecycle** | Write → Read / Side Effect (auto bei `flush()`) | `src/EventSubscriber/`; `#[ORM\HasLifecycleCallbacks]` in Entity | `Profil.P10` — s. Schritt 2e |
| **Async-Handler** | Async / Infrastructure | `src/MessageHandler/…` | `Profil.P8` |
| **Autorisierung / Voter** | Write / Read | `Profil.P7` — `src/Voter/` ODER `Service/Security/…` + coala | `Profil.P7` |
| **Frontend API-Layer** | API Contract | `assets/api/` — TS-Client ODER JS-Api-Modul | `Profil.P2` |
| **Frontend State / Hooks** | Frontend | `assets/store/`, `assets/hooks/` | `Profil.P3` |
| **Frontend UI** | Frontend | `assets/components/`, `assets/pages/` | `Profil.P2/P4` |
| **Config** | Infrastructure | `config/`, `translations/`, `.env*` | `fe_views.yaml`/`fe_actions.yaml` bei `Profil.P4` |
| **Migration** | Persistence | `migrations/` | — |
| **Export / Report** | Read / Integration | `src/Model/ExportRawData/`, `src/Service/Export/` | — |
| **Tests** | Test | `tests/`, `assets/**/*.test.*` | — |

Pro Datei dokumentieren:

```markdown
| Schicht | CQRS-Seite | Datei | Einschätzung |
|---------|------------|-------|--------------|
| CommandHandler | Write | `src/MessageHandler/.../SubmitTargetAgreementHandler.php` | Statuswechsel + Event betroffen |
| QueryHandler | Read | `src/MessageHandler/.../ShowTargetAgreementHandler.php` | API-Antwort für Detailansicht betroffen |
| Frontend | Frontend | `assets/pages/.../TargetAgreementDetail.jsx` | Anzeige/Refetch nach Mutation betroffen |
```

**Pflichtfragen in Schritt 1:** Betrifft die Änderung Write? Read? Gibt es eine Verbindung über
Events/Messenger/Refetch? Ist ein API-Contract betroffen? Security/Berechtigung? Async? Bestehende Daten
oder Migrationen?

---

## Schritt 2: Aufwärts-Verfolgung (Bottom-Up Tracing)

Für jede geänderte Datei, die **KEIN** Controller und **KEIN** Frontend ist, den Aufrufpfad aufwärts bis zum
Controller und ggf. bis zur Frontend-Komponente verfolgen. Write Flow und Read Flow getrennt betrachten.

### 2a) Allgemeines Tracing

```text
Entity/Service/Enum/Repository (geändert)
  ↑ verwendet von: Handler(s)
    ↑ verarbeitet: Command/Query
      ↑ dispatched von: Controller(s) → API-Route
        ↑ aufgerufen von: Frontend-Komponente(n) → UI-Bereich
```

**WICHTIG:** ALLE Pfade verfolgen — eine Entity, ein Enum oder ein Service wird oft von vielen Handlern
verwendet. `rg` bevorzugen, `grep` als Fallback.

```bash
rg "TargetAgreement"
rg "getBazgAmount"
rg "SubmitTargetAgreementCommand"
```

### 2b) Write Flow verfolgen

Wenn die Änderung Zustand verändert, einen Command auslöst oder Domain-Logik betrifft:

```text
React-Aktion / Formular
→ API-Request → Symfony-Controller → Command → CommandHandler
→ Domain / Entity / Service → Repository / Transaction
→ Domain Event / Async-Message (Profil.P8) → Side Effect (Mail/Export/…)
```

**Prüfen:** Welche User-Aktion? Welcher Controller dispatched? Welche Request-Daten, Validierung,
Berechtigungen (`Profil.P7`)? Welche Domain-Regeln, Statusübergänge? Welche Events/Messages? Welche Side
Effects (Mail, Export, externe API, Audit-Log)? Synchron oder async (`Profil.P8`)? Eventual Consistency,
die QA beachten muss?

```bash
rg "CommandName|CommandName::class|new CommandName" src/
rg "dispatch\(|MessageBusInterface|HandleTrait|__invoke" src/
rg "AsMessageHandler" src/                 # Async-Handler (Profil.P8)
```

### 2c) Read Flow verfolgen

Wenn die Änderung Daten liest, API-Ausgaben oder Frontend-Anzeige betrifft:

```text
React-View / Hook
→ API-Request → Symfony-Controller → Query → QueryHandler
→ Read-Modell (Profil.P5: Projection ODER Repository + ModelMapping)
→ DTO / Serializer / ViewModel → React-Rendering
```

**Prüfen:** Welche UI liest die Daten? Welche Query/QueryHandler? Welche Repository-Methode / welches
Read-Modell (`Profil.P5`)? Ändert sich das Response-DTO/ViewModel? Serializer-Groups / ModelMapping-Felder?
Neue/entfernte/optionale Felder? Filter, Sortierung, Pagination (bei List-Endpoints via IndexRequest)? Sind
Listen-, Detail- und Dashboard-Ansichten betroffen? FE-Typen/Api-Client betroffen (`Profil.P2`)?

```bash
rg "QueryName|QueryName::class|new QueryName" src/
rg "serialize|Serializer|Normalizer|Groups|ModelMapper|fromArray" src/
rg "IndexRequest|RecordsResponse|RecordResponse" src/     # List/Show bei ModelMapping-Projekten
rg "/api/|callApi|createAsyncThunk" assets/                # FE-Aufruf (Profil.P2/P3)
```

### 2d) Ergebnis dokumentieren (*Beispiel*)

```markdown
### Impact-Pfad: Bericht erstellen (Namen exemplarisch)

#### Write Flow
`ReportListCard.jsx`
→ `POST /parent-entity/{id}/report/{year}`
→ `CreateReportController`  (#[IsGranted('REPORT_CREATE')])
→ `CreateReportCommand`
→ `CreateReportHandler`
→ `ReportDataManager` + `ReportStatusLogWriter`

Risiko: hoch — Statuswechsel, Kopie abhängiger Datensätze, Listen-/Detailansicht muss aktualisiert werden.

#### Read Flow
`ReportList.jsx`
→ `GET /report`  (#[IsGranted('REPORT_MYLIST')])
→ `ListReportsQuery` → `ListReportsHandler` (IndexRequest, RecordsResponse)
→ Repo + ModelMapping → `ReportList::fromArray()`

Risiko: mittel — Restrict-Services filtern nach Mandant/Rolle; neue Felder müssen im ViewModel gemappt sein.
```

### 2e) Automatische Seiteneffekte: Doctrine-Lifecycle-Listener

**Warum ein eigener Schritt:** Doctrine-Listener feuern **out-of-band bei `flush()`** — sie stehen in
KEINER expliziten Aufrufkette (kein `->recalculate()` im Controller/Handler). Die Aufwärts-Verfolgung
(2a–2d) findet sie **strukturell nicht**. Sie sind aber der häufigste Weg, wie ein Write eine abgeleitete
Read-Größe verändert (Recalc von Emissionsfaktoren, Zielpfad-Werten, Massnahmen-Effekten …) — und damit oft
die Ursache von „Feld zeigt 0 / falscher Wert"-Bugs (Schritt 3c).

**Mechanismen (`Profil.P10`):**

- `#[AsDoctrineListener(Events::onFlush|postFlush|prePersist|…)]` — feuert auf Entity-Lifecycle-Events
- `#[AsEntityListener(...)]` — an eine bestimmte Entity gebunden
- Doctrine-`EventSubscriber` (`implements EventSubscriber` + `getSubscribedEvents()`)
- `#[ORM\HasLifecycleCallbacks]` + `#[ORM\PrePersist|PostUpdate|…]` direkt in der Entity

**Reverse-Trace — pro geänderter Entity/Property fragen: „welcher Listener feuert, wenn ich das schreibe?"**

```bash
# Projekte mit deklarativem Dependency-Index (Profil.P10 = getDependencyList): der Entity-/Property-Name
# im Listener-Verzeichnis IST der Reverse-Index:
grep -rln "MonitoringStock\|resultingEmissionFactor" src/EventSubscriber/

# Sonst: alle Lifecycle-Listener + Events auflisten und die onFlush-Bodies lesen, welche Entity-Typen sie
# aus dem UnitOfWork-Changeset ziehen:
grep -rn "AsDoctrineListener\|getSubscribedEvents\|HasLifecycleCallbacks" src/
```

**Prüfen:** Feuert ein Recalc-/Side-Effect-Listener für die geänderte Entity? Deckt seine Dependency-Liste
(bzw. `onFlush`-Logik) das **neue** Feld ab — sonst wird nicht neu gerechnet → stale/0? Timing `onFlush`
(noch in der Transaktion, darf Entities ändern) vs. `postFlush` (nach Commit)? **Rekursion/Performance:**
schreibt der Listener selbst Entities, die wieder Listener triggern? Läuft er bei jedem `flush()`
(Massen-Import → N×)? Diese Seiteneffekte gehören in den Write→Read-Übergang (Schritt 3d) und in die
Test-Bereiche (Schritt 4H).

---

## Schritt 3: Business-Logik-Verzweigungen erkennen

**Der kritischste Teil.** Verzweigungen — durch Enums, Boolean-Flags, Jahres-Vergleiche, Status, Rollen oder
andere Properties — führen bei unvollständiger Umsetzung zu Fehlern. Es geht **NICHT nur um Enums**.

### 3a) Verzweigungs-Stellen im betroffenen Code finden

**Enum-basiert:** `match(`, `switch(`, `->isUzv()`/`->isMnm()`-artige Typ-Prüfungen, `->getType()`/
`->getStatus()`, direkte Enum-Vergleiche (`=== …`), `instanceof`.

**Property-basiert (genauso kritisch):** Jahres-Vergleiche (`getStartYear()`, `getEffectYear()`,
`getEndYear()`), `isVirtual()`, `isCorrectionProcess()`, `isManagedByCanton()`, `skipCompanyRelease()`,
`bazgRelevant`, Null-Checks (`getKinkYear()`), Erstversion-Flags (`isFirstInitialized…()`,
`isFirstYearOfNew…()`), Berechnungs-Flags (`forceRemovalOverAllYears`).

**Schwellenwert-basiert:** Jahres-Schwellen (`getStartYear() >= 2025`), Deadline-Datumsvergleiche, numerische
Grenzwerte exakt auf der Schwelle.

**Status-/Workflow:** Statuswechsel erlaubt/verboten, eingereicht vs. in Bearbeitung, Erst- vs. Folgeversion,
Korrektur- vs. Normalprozess, editierbar vs. in Kraft, parallele/wiederholte Aktionen.

**Security/Rollen (`Profil.P7`):** BFE-, Kantons-, Unternehmens-Benutzer, Admin/Superuser, Mandanten-/
Datenbesitz, Read- vs. Write-Zugriff.

**Frontend:** Conditional Rendering nach Status/Rolle/Typ, Button sichtbar/versteckt (`Profil.P4`),
enabled/disabled, Badge/Label/Übersetzung, Pflicht/optional, Fehleranzeige nach Backend-Response.

### 3b) Enums & Properties im betroffenen Code identifizieren

```bash
# Enums (Namen aus Profil.P9 einsetzen):
rg "TargetAgreementType|TargetAgreementStatus|MonitoringStatus|Purpose|<weitere aus Profil.P9>" <BETROFFENE_DATEIEN>

# Property-Bedingungen:
rg "isVirtual|isCorrectionProcess|isManagedByCanton|skipCompanyRelease|bazgRelevant|getEffectYear|getStartYear|getEndYear|getKinkYear|isFirstInitialized|isFirstYearOfNew|forceRemoval" <BETROFFENE_DATEIEN>
```

### 3c) Datenfluss-Verfolgung bei „Feld nicht befüllt / zeigt 0"-Bugs

**Warum:** Bei Bugs der Form „Wert X wird nicht gesetzt / zeigt 0 (nur bei Typ Y)" sitzt die
typdiskriminierende Logik — *welcher* Enum-/Typ den Wert überhaupt nutzt — oft **nicht** im Write-Pfad, den
man ändert, sondern downstream in der **Lese-/Berechnungsschicht** oder einer **privaten Seiteneffekt-
Methode**. Reine Aufwärts-Verfolgung (Schritt 2) + write-seitige Analyse übersieht das. Realer Vorfall:
ein Import ließ bei einem Vereinbarungs-Typ den per-Energieträger-Ist-Wert leer. Die erste Analyse anchorte
auf dem Import-Guard und behauptete fälschlich, ein anderer Typ verliere die Werte auch, weil (a) nur nach
dem **Setter-Methodennamen** ge-grep't wurde → die direkte Property-Zuweisung in einer
`updateCalculatedValues()`-artigen Methode wurde übersehen; (b) der konsumierende Calculator als Black Box
behandelt wurde — dort lag das kanonische Prädikat (`shouldCalculate…WithEffectiveMonths()`); (c) ein
**widersprechender Test** als „toter Code" wegrationalisiert statt aufgelöst wurde.

**Vorgehen (für das betroffene Feld/Property):**

```bash
# Nach dem PROPERTY-Namen grep'en, nicht nur nach Setter-Methoden → findet auch direkte Zuweisungen
# ($this->feld = …) in Konstruktoren, Calculatoren, Subscribern:
grep -rn "<propertyName>" src/ --include="*.php"
```

- **Alle Writer** klassifizieren (Import? Copy? Versionierung? UI/Command? Calculator/Subscriber/
  Konstruktor?) **UND alle Reader** — nicht beim ersten gefundenen Setter aufhören.
- Die konsumierende **Calc-/Show-Schicht zu Ende lesen** (nicht als Black Box annehmen, Read-Fenster nicht
  zu früh schließen). Dort steht meist das domänen-kanonische Prädikat, das entscheidet, welcher Typ das Feld
  nutzt.
- **Vor** dem Zusammenbauen eines Guards aus Primitiven (`!isMnm()`, `=== EFM`) prüfen, ob der Code das
  Konzept **schon benennt** (`grep -niE "function [a-z]*<konzept>"`) — und dieses Prädikat verwenden
  (Symmetrie zwischen Schreib- und Leseseite).
- Jeden **Widerspruch auflösen** (z.B. ein Test, der das Gegenteil deiner Annahme behauptet) — nie als
  „defensiv/tot" abtun. Der Widerspruch ist meist der Faden zur Wahrheit.
- Ein **Doctrine-Lifecycle-Listener** (Schritt 2e) ist oft der *wahre* Writer — oder der Grund, warum NICHT
  geschrieben wird (das neue Feld fehlt in seiner `getDependencyList()`/`onFlush`). Diesen gegen das
  betroffene Feld prüfen, bevor ein Guard im Command/Handler gebaut wird.

**Optional bei Kritisch-Bugs:** Findings adversarial verifizieren (mehrere unabhängige Beweis-Agents, jeder
soll die These widerlegen, + ein Reconcile-Schritt für Widersprüche) — **als Teil** der Analyse, nicht erst
reaktiv nach User-Skepsis.

### 3d) CQRS-spezifische Verzweigungen

**Write-Seite:** Wird ein Command je nach Status/Rolle/Typ anders behandelt? Domain-Regeln nur für bestimmte
Typen? Event nur in bestimmten Fällen? Ist der Handler idempotent (falls nötig)? Parallel-Konflikte?

**Read-Seite:** Filtert die Query nach Rolle/Mandant/Status (Restrict-Services)? Sind alle Status/Typen im
DTO/ViewModel abgebildet? Wird ein neues Feld gelesen/gemappt? Können alte Datensätze das Feld noch nicht
haben? Unterschiedliche Darstellung in Liste/Detail/Dashboard/Export?

**Write → Read Übergang:** Wird nach Write die Read-Seite aktualisiert? Synchron oder async (`Profil.P8`)?
Muss QA refreshen/warten? Stale Data im Frontend? Wird korrekt neu geladen/invalidiert (`Profil.P3`)?

### 3e) Vollständigkeits-Check

**Bei Enums:** Werden **alle** Cases abgedeckt (`Profil.P9`, z.B. UZV **und** KZV/EVA/EBO)? Gibt es einen
korrekten `default` — oder nur einen Platzhalter? `match` ohne `default`, das bei neuem Case bricht? Gibt es
eine Referenz-Implementierung derselben Verzweigung woanders?

```bash
rg "match.*TargetAgreementType|switch.*TargetAgreementType" src/
rg "TargetAgreementType::UZV|TargetAgreementType::KZV" src/ assets/
```

**Bei Property-Verzweigungen:** Was passiert im *anderen* Zweig (`isVirtual()` true UND false)? Welche
Jahreswerte erzeugen anderes Verhalten — mit verschiedenen Jahren getestet? Null-Fall behandelt? Beide
Boolean-Pfade implementiert und getestet? Grenzfälle exakt auf der Schwelle?

**Bei Security (`Profil.P7`):** Backend geschützt oder nur der FE-Button versteckt? Kennt der Voter alle
neuen Status/Typen? Read-Zugriff ebenso geprüft wie Write? BFE/Kanton/Unternehmen getrennt getestet?
Mandanten-/Datenbesitz auf Query-Seite korrekt?

**Bei React:** Label/Übersetzung für jeden Enum-Wert? Buttons korrekt aktiviert/deaktiviert (`Profil.P4`)?
Fehlerzustände sichtbar? Optionale Felder defensiv gerendert? Listen-/Detailansicht nach Mutation aktualisiert
(`Profil.P3`)?

### 3f) Bekannte Risiko-Verzweigungen

Die **Enum-Namen/Cases** stammen aus `Profil.P9`; die Risiko-Einstufung nach Enum-**Rolle** ist
projekt-unabhängig:

| Enum-Rolle | Risiko | Test-Relevanz |
|------------|--------|---------------|
| Typ-Enum (`TargetAgreementType`) | Sehr hoch | Jeden Typ separat testen — verschiedene Berechnungs-/Workflow-Pfade |
| Status-Enum (`TargetAgreementStatus`, `MonitoringStatus`) | Hoch | Workflow-Übergänge + status-abhängige Berechtigungen |
| Modell-/Strategie-Enum | Hoch | Unterschiedliche Berechnungslogik |
| Zweck-Enum (`Purpose`: CO2/EHS/…) | Mittel | Zweck-spezifische Logik (z.B. BAZG, CO2) |
| Kategorisierungs-Enum (`MeasureType`, `BonusType`) | Mittel | Kategorie-abhängige Verzweigung |
| Regional-Enum (`Canton`) | Niedrig | Kanton-spezifische Sonderfälle |

| Property/Methode | Risiko | Test-Relevanz |
|------------------|--------|---------------|
| `effectYear` / `startYear` | Sehr hoch | Verschiedene Jahre, Grenzwerte |
| `isVirtual()` | Hoch | Virtuelle BS haben keine Locations — andere Code-Pfade |
| `isCorrectionProcess()` | Hoch | Andere Mails, anderer Workflow |
| `isManagedByCanton()` | Hoch | Kanton- vs. BFE-Workflow |
| `bazgRelevant` | Mittel | Steuert BAZG-Datenvalidierung |
| `getKinkYear()` (null/set) | Mittel | Knickjahr-Berechnung komplett anders |
| `isFirstInitialized…()` | Mittel | Erstversion hat andere Regeln |
| `skipCompanyRelease()` | Mittel | Überspringt Prozess-Schritt |
| Jahres-Schwelle (`>= 2025`) | Mittel | Grenzfall genau auf der Schwelle |

| CQRS-Bereich | Risiko | Test-Relevanz |
|--------------|--------|---------------|
| Command erzeugt Event | Hoch | Read-Seite / Side Effect muss folgen |
| Async-Message (`Profil.P8`) | Hoch | QA sieht Änderung evtl. nicht sofort |
| Query-DTO/ViewModel geändert | Hoch | React-Contract kann brechen |
| Refetch/Invalidierung fehlt (`Profil.P3`) | Mittel/Hoch | UI zeigt stale data |
| Voter nur auf Write-Seite (`Profil.P7`) | Hoch | Read-Seite kann Daten leaken |
| FE-Enum-Mapping fehlt | Mittel | UI zeigt falsches/undefiniertes Label |

---

## Schritt 4: Betroffene Test-Bereiche zusammenstellen

Testbereiche aus den Impact-Pfaden und Verzweigungen ableiten.

**A) Betroffene API-Endpunkte** — pro Controller: HTTP-Methode, Route, Zweck, Request-DTO, Response-DTO,
Status-Codes, Security (`Profil.P7`), Command/Query, betroffene React-Consumer.

**B) Betroffene Frontend-Bereiche** — welche Seite/Komponente nutzt den Endpunkt? Welche UI-Interaktion löst
die Logik aus? Welche Hooks/Api-Module (`Profil.P2`), Refetch/Invalidierung (`Profil.P3`)? Welche Forms,
Buttons (`Profil.P4`), Tabellen, Filter, Badges? Loading-/Error-/Empty-State?

**C) API-Contract-Check** — pro Endpoint:

| Frage | Risiko |
|-------|--------|
| Request-Struktur geändert? | FE sendet alte/unvollständige Daten |
| Response-Struktur geändert? | React rendert falsch / bricht |
| Feld neu / entfernt / optional? | UI muss anzeigen / läuft auf `undefined` / erwartet immer Wert |
| Enum erweitert? | Mapping/Label/Übersetzung fehlt |
| HTTP-Status / Fehlerformat geändert? | Error-Handling greift nicht |
| Serializer-Groups / ModelMapping-Felder geändert? | Feld fehlt unerwartet |
| Pagination/Sorting/Filter geändert? | Listen verhalten sich anders |
| Berechtigungslogik geändert (`Profil.P7`)? | Read/Write-Zugriff inkonsistent |

**D) Verzweigungs-Varianten** — pro Verzweigung durchspielen: Enum (jeden Typ aus `Profil.P9`), Property
(virtuell UND nicht), Jahr (Schwellenwert-nah), Boolean (Korrektur- UND Normalprozess), Null (gesetzt UND
nicht), Status (editing/submitted/in_effect), Write→Read (Read-Modell aktualisiert?).

**E) Rollen-basierte Tests (`Profil.P7`)** — BFE-, Kantons-, Unternehmens-, Admin-, unberechtigter Benutzer.
Pro Rolle: Aktion im FE sichtbar? API direkt aufrufbar? Daten lesbar? Query-Filter und Voter konsistent?

**F) Status-basierte Tests** — in welchem Workflow-Status (editing/submitted/in_effect/Korrekturprozess/
abgeschlossen/Erst- vs. Folgeversion)?

**G) Grenzfall-Tests** — Jahres-/Schwellenwert genau auf der Grenze; fehlender optionaler Wert; Erst- vs.
zweite Version; Rundung/negativ/leere Menge/sehr groß; leere Liste / 1 / viele / Pagination; parallele
Doppel-Submit/Save.

**H) Symfony-spezifische Tests** — Controller (Request-Validation, Response-DTO/Serializer, HTTP-Status,
Security), Command-Seite (Handler-Test, Domain-Regel, Statusübergang, Event, Transaktion, Idempotenz),
Query-Seite (Handler, Repository/Read-Modell, Filter/Sortierung/Pagination, Mandantenfilter, DTO-Shape),
Async (`Profil.P8`: Message dispatched, Handler korrekt, Retry/Fehlerfall, Side Effect), Doctrine-Lifecycle
(`Profil.P10`: Recalc-Listener feuert für die geänderte Entity, deckt das neue Feld ab, kein Endlos-/
Massen-Recalc bei `flush()`).

**I) React-spezifische Tests** — Component/Conditional-Rendering, Hook/Api-Aufruf, Form-Validation, Server-
Error-Mapping, Refetch/Invalidierung nach Mutation (`Profil.P3`), Listen- und Detailansicht nach Write,
Loading/Error/Empty-State, E2E für kritische User-Journey.

**J) QA-Priorisierung:**

| Priorität | Bereich | Warum |
|-----------|---------|-------|
| P1 | Kritischer Happy Path | Hauptfunktion der Änderung |
| P1 | Negativfall / Berechtigung | Sicherheits-/Workflow-Risiko |
| P1 | Write → Read Sichtbarkeit | Änderung muss in UI sichtbar werden |
| P2 | Regression angrenzender Status/Typen | Bestehendes darf nicht brechen |
| P2 | Listen-/Dashboard-Ansichten | Read-Modell / ViewModel prüfen |
| P2 | API-Contract | React darf nicht durch Backend-Änderung brechen |
| P3 | Edge Cases | Null, Grenzjahr, seltene Rolle, leere Daten |

---

## Schritt 5: Nachfragen formulieren

Gezielte Fragen, die auf **potentielle Lücken** hinweisen (nicht belehren). Fragetypen:

1. **Enum-Vollständigkeit:** „`XHandler` verwendet `TargetAgreementType::UZV`. Wurde `KZV`/`EVA`/`EBO` bewusst
   ausgelassen, oder fehlt die Implementierung?"
2. **Property-Verzweigung:** „Der Code behandelt `isVirtual() === false`. Was passiert bei virtuellen
   Betriebsstätten? Ist der Pfad abgedeckt?"
3. **Jahres-/Schwellenwert:** „Logik nutzt `getEffectYear()` im Vergleich. Mit verschiedenen Jahren getestet?
   Was passiert exakt bei Start 2025?"
4. **Null-Behandlung:** „Code prüft `getKinkYear() !== null`. Ist der null-Fall ebenfalls korrekt behandelt?"
5. **Seiteneffekte:** „`XService` wird von 5 Handlern verwendet. Wurden `YHandler`/`ZHandler` berücksichtigt?"
6. **Multi-Tenant:** „Änderung betrifft Daten, die BFE und Kantone sehen. Beide Mandanten korrekt geprüft?"
7. **Status-Abhängigkeit:** „Logik greift im Status `editing`. Verhalten bei `in_effect`?"
8. **Boolean-Interaktion:** „Code prüft `isCorrectionProcess()`. Korrektur- UND Normal-Workflow getestet?"
9. **Fehlende Abdeckung:** „Plan-Schritt X behandelt Variante A, aber nicht B. Beabsichtigt?"
10. **Write/Read-Sichtbarkeit:** „Command ändert Status. Read-Seite synchron oder async (`Profil.P8`)
    aktualisiert — wie prüft QA die Sichtbarkeit?"
11. **Bestandsdaten:** „Müssen bestehende Datensätze nachmigriert/neu berechnet werden, damit sie korrekt
    erscheinen?"
12. **Refetch (`Profil.P3`):** „Nach der Mutation wird nur die Detailansicht neu geladen. Muss auch die
    Listen-/Dashboard-Ansicht aktualisiert werden?"
13. **API-Contract:** „Response enthält ein neues optionales Feld. Sind FE-Typen/Mapping, Label und
    Empty-State angepasst (`Profil.P2`)?"
14. **Security (`Profil.P7`):** „Button ist für Rolle X versteckt. Verhindert der Voter denselben Zugriff auch
    bei direktem API-Aufruf?"
15. **Async (`Profil.P8`):** „Änderung dispatcht eine Message. Ist der Handler idempotent bei
    Mehrfach-Verarbeitung?"

---

## Report-Template

Im Ergebnis (Task-File unter `## Impact-Analyse` bzw. Review-Report unter `## Test-Impact-Analyse`):

```markdown
## Test-Impact-Analyse (für Test-Ingenieur)

**Durchgeführt am:** <DATUM>
**Basis:** <Lösungsplan / Branch-Diff / MR-Diff / gemergte Commits>
**Status bei Analyse:** <Offen / In Bearbeitung / Review / Abgeschlossen>
**Projekt-Profil:** <FE-Sprache · Read-Modell · Autorisierung · Async — Kurzform aus P2/P5/P7/P8>

### 0) Historische Ticket-Verfolgung

| Datum | Commit | Ticket | Wesentliche Aussage / Designintention |
|-------|--------|--------|----------------------------------------|
| … | … | … | … |

### Betroffene Schichten

| Schicht | CQRS-Seite | Geänderte Dateien | Einschätzung |
|---------|------------|-------------------|--------------|
| … | … | … | … |

### Aufwärts-Verfolgung (Impact-Pfade)

#### Pfad 1: <Name>
**Write Flow:** `React` → `Route` → `Controller` → `Command` → `Handler` → `Domain` → `Event/Message` → `Side Effect`
**Read Flow:** `React` → `Route` → `Controller` → `Query` → `Handler` → `Read-Modell` → `DTO/ViewModel` → `Component`
**Risiko:** niedrig / mittel / hoch / sehr hoch
**Begründung:** …
**Relevante Tests:** …

### API-Contract-Check

| Endpoint | Request geändert? | Response geändert? | Enum/Status betroffen? | React betroffen? | Risiko |
|----------|-------------------|--------------------|-------------------------|------------------|--------|
| `GET /api/…` | Nein | Ja | Ja | Ja | Hoch |

### Business-Logik-Verzweigungen (Risiko-Analyse)

**Enum-Verzweigungen:**
| Enum | Cases | Abgedeckt? | Risiko |
|------|-------|------------|--------|
| `TargetAgreementType` | UZV, KZV, EVA, EBO | ✅ / ⚠️ | Sehr hoch |

**Property-Verzweigungen:**
| Property | Varianten | Abgedeckt? | Risiko |
|----------|-----------|------------|--------|
| `isVirtual()` | true / false | ✅ / ⚠️ | Hoch |

**CQRS-Verzweigungen:**
| Bereich | Varianten | Abgedeckt? | Risiko |
|---------|-----------|------------|--------|
| Write → Read | Command → Read-Modell/Side-Effect folgt | ✅ / ⚠️ | Hoch |
| Refetch | Detail + Liste aktualisiert (Profil.P3) | ✅ / ⚠️ | Mittel |

**Details:**
- ⚠️ `XHandler:42` — nur UZV behandelt, KZV/EVA/EBO fehlen
- ⚠️ `YService:55` — nur false-Pfad für `isVirtual()`
- ✅ `ZHandler:88` — alle Varianten abgedeckt

### Symfony-spezifische Risiken
- [ ] Write-Zugriff backendseitig geschützt (Profil.P7)
- [ ] Read-Zugriff backendseitig geschützt
- [ ] Voter kennt neue Status/Typen
- [ ] Async: Message dispatched / Handler idempotent / Side Effect folgt (Profil.P8)
- [ ] Doctrine-Lifecycle: Recalc-Listener feuert & deckt neues Feld ab / kein Endlos-Recalc (Profil.P10, Schritt 2e)
- [ ] Migration nötig/geprüft · Bestandsdaten betroffen · Index/Performance

### React-spezifische Risiken
- [ ] FE-Typen/Api-Client aktualisiert (Profil.P2)
- [ ] Enum-Mapping / Label / Übersetzung vorhanden
- [ ] Refetch/Invalidierung nach Mutation (Profil.P3)
- [ ] Listen- und Detailansicht aktualisieren sich korrekt
- [ ] FE-Gating korrekt (Profil.P4) · Loading/Error/Empty-State geprüft

### Was muss getestet werden?

#### P1 — Muss
- [ ] `PUT /api/…` — Beschreibung
- [ ] Kritischer Happy Path
- [ ] Write → Read Sichtbarkeit (Aktion → Detail → Liste; ggf. async-Wartezeit)
- [ ] Berechtigungen: erlaubte Rolle / verbotene Rolle / direkter API-Aufruf

#### P2 — Sollte
- [ ] Seite X → Tab Y → Aktion Z
- [ ] Verzweigungs-Varianten (jeder Typ aus Profil.P9; Status editing/in_effect; virtuell/nicht; Korrektur/Normal)
- [ ] Regression: bestehender Status / Liste / Export unverändert

#### P3 — Optional
- [ ] parallele Aktionen · Bestandsdaten-Migration · Retry/Dead-Letter · Import/Export · große Datenmengen · seltene Rolle

### Nachfragen an Developer
1. ❓ …
2. ❓ …
```

---

## Qualitätskriterien

**Gute Impact-Analyse:** trennt Write/Read sauber · verfolgt Commands bis Domain/Events/Side-Effects ·
verfolgt Queries bis DTO/ViewModel und React · prüft API-Verträge · berücksichtigt Eventual Consistency und
Refetch · prüft Enums, Properties, Status, Rollen, Flags, Grenzwerte · prüft Security backend- UND
frontendseitig · benennt konkrete QA-Szenarien · priorisiert nach Risiko · dokumentiert Unsicherheiten als
gezielte Nachfragen · setzt `‹Profil.X›` konsequent auf die echten Projektwerte.

**Schlechte Impact-Analyse:** listet nur geänderte Dateien · vermischt Command/Query · stoppt beim Handler ·
ignoriert Read-Modell/Async · ignoriert React-Consumer und API-Contract · prüft keine Enums/Properties/
Statusübergänge · vergisst Security/Voter · nennt nur generische Tests · übernimmt Fließtext-Beispiele
(UZV/MNM etc.) ungeprüft als projektweite Wahrheit.

---

## Merksatz

Nicht fragen:

> Welche Dateien wurden geändert?

Sondern fragen:

> Welche fachlichen Flows ändern sich, welche Read-/Write-Pfade sind betroffen, wo verzweigt die
> Business-Logik, und was muss QA testen, damit die Änderung sicher freigegeben werden kann?
