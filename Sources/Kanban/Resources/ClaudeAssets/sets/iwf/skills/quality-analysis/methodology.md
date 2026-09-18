# Qualitäts-Analyse — Architektur- und Design-Fitness nach der Impact-Analyse

Reusable Methodik für den Qualitäts-Review eines neuen oder wesentlich erweiterten Features gegen die
bestehende Architektur, fachliche Modellierung, Coding Principles, Qualitätsattribute und geeignete
Design Patterns.

Die Methodik ist **downstream der Impact-Analyse** gedacht. Sie analysiert nicht erneut den Blast Radius,
sondern beantwortet eine andere Frage:

> **Ist die geplante beziehungsweise implementierte Lösung eine gute, nachvollziehbare und langfristig
> tragfähige Art, den bereits verstandenen Impact umzusetzen?**

Sie wird vom `quality-analysis`-Skill beziehungsweise von explizit darauf verweisenden Workflows aufgerufen.
Sie implementiert das Feature nicht.

---

# 1. Position im Gesamtworkflow

Der bevorzugte Ablauf ist:

```text
get-task
   ↓
start-task
   ├─ Task / Akzeptanzkriterien verstehen
   └─ Lösungsplan erstellen
        ↓
impact-analysis
   ├─ Semantic Change Set
   ├─ Impact-Pfade / Data Lineage
   ├─ Invarianten / Decision Tables
   ├─ Cross-Cutting Impact
   ├─ Risk Register
   └─ Risk → Test Traceability
        ↓
start-task / Caller-Reconciliation
   └─ Lösungsplan anhand der Impact-Findings korrigieren
        ↓
quality-analysis   ← DIESE METHODIK
   ├─ Architekturentscheidungen sichtbar machen
   ├─ Fit zur bestehenden Codebasis prüfen
   ├─ Verantwortungen / Grenzen / Abstraktionen prüfen
   ├─ Evolution und Änderungsverstärkung prüfen
   ├─ Patterns nur bei nachgewiesenem Design-Druck prüfen
   └─ Lösungsplan bzw. Code qualitativ verbessern
        ↓
Delta-Impact-Reconciliation, falls Quality den Plan semantisch verändert
        ↓
solve-task / Review
```

## Verantwortungsgrenze

**Impact-Analyse fragt:**

- Was ändert sich semantisch?
- Wer nutzt die Änderung und was beeinflusst sie downstream?
- Welche Business-Varianten, Invarianten, Datenflüsse und Side Effects sind betroffen?
- Welche Risiken entstehen?
- Was muss getestet werden?

**Quality-Analyse fragt:**

- Sind Verantwortungen richtig geschnitten?
- Liegt fachliches Wissen an einer klaren autoritativen Stelle?
- Passen neue Grenzen und Abhängigkeiten zur Architektur?
- Ist die Lösung einfacher als nötig oder komplexer als nötig?
- Unterstützt die Struktur belegte Änderungsachsen ohne spekulative Generalisierung?
- Ist ein Pattern wirklich durch Design-Druck gerechtfertigt?
- Ist der Plan so präzise, dass die Implementierung keine wesentlichen Designentscheidungen improvisieren muss?

**Regel:** Ein bereits dokumentiertes Impact-Finding wird nicht als neues Quality-Finding dupliziert, außer
seine **Ursache ist eine konkrete Architektur-/Designentscheidung**, die diese Methodik bewerten muss.

---

# 2. Modi

| Modus | Review-Gegenstand | Typischer Zeitpunkt |
|---|---|---|
| **Plan-Modus** | finaler, nach Impact-Reconciliation aktualisierter `## Lösungsplan` | vor der Implementierung, vor allem bei neuen Features |
| **Branch-Modus** | tatsächlicher Feature-Branch-Diff | nach Implementierung oder bei Architekturreview |

Im Fließtext bezeichnet **Review-Gegenstand** den Plan oder den implementierten Code.

## 2.1 Wann die vollständige Quality-Analyse besonders sinnvoll ist

Vollständigen Review bevorzugen bei mindestens einem dieser Signale:

- neues fachliches Feature über mehrere Schichten,
- neues Aggregate / Entity / Value Object / Domain-Konzept,
- neuer Status-/Freigabe-/Lebenszyklus,
- neue externe Integration oder neuer Provider,
- neue API-Familie oder dauerhaftes Contract-Modell,
- neuer asynchroner Prozess,
- neue gemeinsame Abstraktion / Library / Framework-Schicht,
- neues Read Model / Projection / Reporting-Konzept,
- substanzielle Datenmodell- oder Migrationsentscheidung,
- Feature mit mehreren Typ-/Strategievarianten,
- Feature mit hohen oder kritischen Impact-Risiken,
- bewusste Abweichung vom etablierten Architekturpfad.

Für kleine lokale Bugfixes, reine Text-/Styling-Änderungen oder triviale Anpassungen kann der Caller einen
verkürzten Review verwenden. Die Impact-Analyse entscheidet aber weiterhin über den tatsächlichen Blast Radius.

---


## 2.2 Quality-Scope-Triage: `FULL`, `LITE` oder `SKIP`

Die **Review-Art** (Plan/Branch) und die **Review-Tiefe** (FULL/LITE/SKIP) sind zwei getrennte Achsen.
Der Caller bestimmt den Review-Gegenstand; diese Methodik bestimmt anhand des bereits bekannten Impact die
angemessene Review-Tiefe. Ein `requested_scope` aus `SKILL.md` ist nur eine Präferenz: `FULL` darf erzwingen,
`LITE`/`SKIP` dürfen durch die Triage jederzeit nach oben eskaliert werden. Die Entscheidung wird im Report dokumentiert und darf nicht stillschweigend erfolgen.

### `FULL` — vollständige Quality-Analyse

`FULL` ist verpflichtend, sobald **mindestens eines** der folgenden Signale vorliegt:

- komplett neues oder wesentlich erweitertes fachliches Feature über mehrere Schichten,
- neue oder veränderte **Rollen-, Berechtigungs-, Object-Level-Authorization- oder Tenant-Semantik**,
- neuer oder veränderter **Status-/Freigabe-/Pendenzen-/Lebenszyklus**,
- neue fachliche Events oder bestehende Events mit neuen Consumers / Side Effects,
- neuer oder veränderter **E-Mail-/Benachrichtigungsfluss**, insbesondere async oder statusgetrieben,
- neuer asynchroner Prozess, Queue-/Retry-/Idempotenz-Entscheid oder Eventual Consistency,
- neue zentrale Business-Regel, Berechnung, Policy oder mehrere fachliche Varianten,
- neues Aggregate / Entity / Value Object / Read Model / Projection,
- neue externe Integration / Provider / Datei- oder Import-/Export-Schnittstelle,
- neuer dauerhafter API-/Event-/Command-/Query-Contract,
- neue gemeinsam verwendete Abstraktion, Shared-Komponente oder neue Modulgrenze,
- Schema-/Datenmigration mit fachlicher Bedeutung,
- `HIGH`/`CRITICAL` Impact-Risiko oder mehrere gekoppelte `MEDIUM`-Risiken,
- relevante Parallelität, Lost-Update-, Duplicate- oder Double-Submit-Gefahr,
- bewusste Abweichung vom etablierten Architekturpfad.

Bei komplexen Business-Web-Applikationen mit vielen Nutzern, Rollen, Berechtigungen, Events, E-Mails, Pendenzen
und umfangreicher Business-Logik ist `FULL` für neue Features der **Default**.

### `LITE` — fokussierter Quality-Review

`LITE` ist zulässig, wenn **alle** folgenden Aussagen zutreffen:

- die Änderung folgt einem klar belegten bestehenden **Golden Path**,
- sie führt **keine neue Architekturgrenze** und keine neue fachliche Variationsachse ein,
- Rollen-/Tenant-/Status-/Event-/E-Mail-/Async-Semantik bleibt strukturell unverändert,
- keine neue zentrale Shared-Abstraktion entsteht,
- Impact enthält keine offenen `HIGH`/`CRITICAL`-Risiken,
- die Änderung ist fachlich lokal und die betroffenen Invarianten/Contracts sind bereits etabliert.

`LITE` bedeutet **nicht oberflächlich**. Es prüft mindestens:

1. Quality Snapshot + Freshness,
2. Impact-Handoff,
3. Golden-Path-/Architecture-Fit,
4. Mandatory Gates für tatsächlich betroffene Bereiche,
5. Rule/Knowledge Ownership,
6. Tests/Evidence,
7. Quality Findings,
8. Quality Plan Delta,
9. Delta-Impact-Reconciliation, falls Quality etwas semantisch verändert.

Change-Amplification, Pattern-Fit und ADR-Prüfung werden in `LITE` nur aktiviert, wenn während des Reviews
ein konkreter Design Pressure sichtbar wird.

### `SKIP` — keine separate Quality-Analyse

`SKIP` ist nur zulässig, wenn **alle** folgenden Kriterien erfüllt sind:

- rein lokale Änderung ohne neue Business-Regel oder neue Architekturentscheidung,
- keine Änderung an Rollen/Berechtigungen/Tenant, Status/Pendenzen, Events, E-Mail, Async oder Integration,
- kein Contract-/Schema-/Datenmodell-Impact,
- keine neue Abstraktion, keine neue wiederverwendete Komponente,
- Impact-Risiko niedrig und vollständig durch bestehende Tests/Patterns abgedeckt,
- Umsetzung entspricht einem bereits etablierten Golden Path ohne strukturelle Abweichung.

Typische Kandidaten: reine Text-/Übersetzungs-/Styling-Anpassungen oder sehr kleine lokale Bugfixes ohne
fachliche beziehungsweise architektonische Änderung.

**Fail-safe-Regel:** Sobald Unsicherheit besteht, ob `SKIP` oder `LITE` genügt, die höhere Stufe wählen.
Sobald Rollen/Berechtigungen, Workflow/Pendenzen, Events/E-Mail/Async oder zentrale Business-Regeln betroffen
sind, ist mindestens `FULL` erforderlich.

### Triage dokumentieren

```markdown
### Quality-Scope

- Entscheidung: FULL / LITE / SKIP
- Auslöser: <C-*/R-*/INV-* oder konkrete Änderung>
- Begründung: ...
- Nicht ausgeführte Schritte: <nur bei LITE/SKIP, mit Grund>
```

`SKIP` beendet die Methodik nach dokumentierter Triage. `LITE` und `FULL` fahren mit dem Workflow fort.

### Praktische Aktivierungsmatrix

| Änderung | Default-Scope | Begründung |
|---|---|---|
| Text, Übersetzung, rein visuelles Styling | `SKIP` | keine fachliche/architektonische Entscheidung |
| kleiner lokaler Bugfix ohne Business-Regel-/Contract-Änderung | `LITE` | Regression + Fit prüfen, aber keine breite Architekturprüfung |
| neues Feld entlang bestehendem CRUD-/API-/UI-Golden-Path | `LITE` | bestehende Struktur verifizieren; bei neuer Semantik hochstufen |
| neue Business-Regel / Berechnung / fachliche Validierung | `FULL` | Rule Ownership, Invarianten, Varianten, Nachweise |
| neue Rolle/Berechtigung/Object-Level-Authorization/Tenant-Regel | `FULL` | Security- und Ownership-Entscheidung |
| neuer Status, Freigabeschritt oder Pendenz | `FULL` | Workflow-/State-/Concurrency-/Audit-Design |
| neues Event oder neuer Event-Consumer | `FULL` | Kopplung, Delivery/Failure Ownership, Side Effects |
| neuer oder geänderter E-Mail-/Notification-Trigger | `FULL` | Duplicate Safety, Trigger Ownership, Audit, Async-Failure |
| neuer Queue-/Background-Prozess | `FULL` | Retry, Idempotenz, Eventual Consistency, Operability |
| neue externe Integration / Provider | `FULL` | Boundary, Adapter, Contract, Failure Model |
| neues Aggregate / Entity / Read Model | `FULL` | Ownership und Persistenz-/Contract-Entscheidungen |
| neue Shared-Abstraktion / Framework-Komponente | `FULL` | langfristige Kopplung und Change Amplification |
| internes Refactoring entlang bestehender Boundaries | `LITE` | Strukturfit prüfen; bei Boundary-Änderung `FULL` |
| Cross-Module-Refactoring oder neue Boundary | `FULL` | Architekturentscheidung selbst ist Review-Gegenstand |

Die Matrix ist ein **Default**, kein Ersatz für Evidenz. Ein einzelner `FULL`-Trigger überstimmt mehrere
`LITE`-Signale.

# 3. Normalisierter Input-Contract

> **Routing-Regel:** Argumentauflösung, Review-Modus, Repository-/Worktree-Routing, Impact-Freshness und
> eventuelle erneute Aufrufe von `impact-analysis` erfolgen in `SKILL.md`. Diese Methodik konsumiert einen
> normalisierten Quality-Kontext.


Die Quality-Analyse **setzt vorhandene Upstream-Arbeit voraus** und übernimmt sie, statt sie zu duplizieren.

## 3.1 Pflichtinput im Plan-Modus

1. Task-/Feature-Kontext mit Problem, Ziel und vorhandenen Akzeptanzkriterien,
2. ein expliziter `## Lösungsplan`,
3. die zu diesem Plan gehörende Impact-Analyse oder ein begründeter Hinweis, warum keine nötig war,
4. Repository-/Worktree-Kontext,
5. relevante Projektkonventionen beziehungsweise `CLAUDE.md`/ADRs.

Fehlt im Plan-Modus ein Lösungsplan, **keinen eigenen Initialplan rekonstruieren**. Das ist Verantwortung von
`start-task`. Falls die Methodik standalone aufgerufen wurde, zuerst den zuständigen Upstream-Workflow ausführen.

## 3.2 Erwarteter Impact-Handoff

Wenn vorhanden, übernimmt diese Methodik direkt:

- Semantic-Change-IDs (`C1`, `C2`, ...),
- Impact-Pfade,
- fachliche Invarianten (`INV-*`),
- Decision Tables,
- Data Lineage,
- Cross-Cutting Sweep,
- Missing-Counterpart-Ergebnisse,
- Risk-Register-IDs (`R-*`),
- Risk→Test-Matrix,
- offene `UNKNOWN`s,
- Projekt-Profil / erkannte Architekturkonventionen.

Diese Artefakte sind die **Single Source of Truth für Impact**.

## 3.3 Output-Contract

Die Quality-Analyse liefert:

1. einen **Quality Input Snapshot**,
2. die **Architecture Decision Surface**,
3. aktivierte Qualitätsprofile,
4. einen **Quality Finding Register** (`Q-*`),
5. bestätigte beziehungsweise abgelehnte Pattern-Kandidaten,
6. einen **Architecture Decision Log** für wesentliche Entscheidungen,
7. im Plan-Modus einen überarbeiteten Lösungsplan,
8. im Branch-Modus priorisierte erforderliche Code-Änderungen,
9. eine **Delta-Impact-Entscheidung**,
10. eine Freigabeentscheidung.

---

# 4. Verbindliche Arbeitsregeln

## 4.1 FACT / INFERENCE / UNKNOWN

Jede wesentliche Aussage wird gedanklich einer Kategorie zugeordnet:

- **FACT** — direkt durch Task, Code, Test, Config, ADR, Git-Historie oder Impact-Analyse belegt.
- **INFERENCE** — Schlussfolgerung aus belegten Fakten.
- **UNKNOWN** — für die Entscheidung relevante Information ist nicht belegt.

`INFERENCE` nie als `FACT` formulieren. Ein `UNKNOWN` nicht durch eine elegante Architekturannahme verdecken.

## 4.2 Upstream-Evidenz wiederverwenden

Wenn die Impact-Analyse einen Datenfluss, eine Invariante, einen Risk oder einen betroffenen Consumer bereits
belegt hat, diese Evidenz referenzieren. Nur erneut in den Code einsteigen, wenn:

- die Aussage für eine Quality-Entscheidung genauer verstanden werden muss,
- widersprüchliche Evidenz auftaucht,
- der Plan seit der Impact-Analyse geändert wurde,
- der Impact-Snapshot veraltet ist.

## 4.3 Bestehende Architektur vor allgemeiner Theorie

Priorität bei Designentscheidungen:

1. fachliche Anforderungen und explizite Invarianten,
2. Security-/Privacy-/Datenintegritätsanforderungen,
3. bestätigte Impact-Risiken,
4. ADRs und verbindliche Architekturregeln,
5. etabliertes Muster im aktuellen Bounded Context / Modul,
6. belegte nahe Änderungsrichtung,
7. allgemeine Coding Principles,
8. Design Patterns,
9. persönliche Stilpräferenz.

## 4.4 Patterns sind Resultat von Design-Druck

Ein Pattern wird nicht gesucht, weil ein Katalog existiert. Es darf nur ernsthafter Kandidat werden, wenn ein
konkreter **Design Pressure** nachgewiesen ist, zum Beispiel:

- wiederkehrende fachliche Variationsachse,
- Provider-Leak über eine Architekturgrenze,
- verteiltes fachliches Wissen,
- komplexer Lebenszyklus,
- wiederkehrende optionale Cross-Cutting-Behavior,
- variable Verarbeitungspipeline,
- komplexe valide Objekterzeugung.

Ohne Design-Druck: **kein Pattern einführen**.

## 4.5 Kein mechanisches DRY

Unterscheide:

- identischen Text,
- syntaktisch ähnlichen Code,
- zufällig ähnliche Implementierungen,
- mehrfach gepflegtes **fachliches Wissen**.

Nur die letzte Kategorie ist automatisch ein starker Kandidat für Zentralisierung.

## 4.6 Quality-Review darf Impact verändern — aber nicht stillschweigend

Wenn eine Quality-Empfehlung neue Dateien, neue Contracts, andere Datenflüsse, neue Events, andere
Transaktionsgrenzen, neue Persistenz oder eine andere Security-/Async-Struktur erzeugt, ist das ein
**semantischer Plan-Delta**. Dieser muss nach Schritt 12 wieder durch die Impact-Methodik reconciled werden.

## 4.7 Mandatory Quality Gates

Diese Gates sind für jedes substanzielle neue Feature zu beantworten; `nicht relevant` ist erlaubt, aber muss
begründbar sein:

- **Ownership Gate:** Wo lebt jede zentrale neue fachliche Regel autoritativ?
- **Boundary Gate:** Welche neuen oder veränderten Modul-/Layer-/Provider-Grenzen entstehen?
- **State Gate:** Falls Lebenszyklus/Status betroffen ist: Wo sind Transitionen und Guards autoritativ?
- **Contract Gate:** Falls ein dauerhafter Contract entsteht: Wer besitzt ihn und wie darf er evolvieren?
- **Failure Gate:** Falls Async/Integration betroffen ist: Wo wird Failure-Semantik lokal beherrscht?
- **Abstraction Gate:** Welche neue Abstraktion wird eingeführt und welcher konkrete Design Pressure bezahlt sie?
- **Evidence Gate:** Wie wird jede zentrale neue Regel beziehungsweise Architekturannahme nachgewiesen?
- **Freshness Gate:** Beschreiben Plan, Impact und Quality denselben Stand?

Ein Gate darf nicht durch „Framework macht das schon“ geschlossen werden, ohne den tatsächlich verwendeten
Projektmechanismus zu belegen.

---

# Workflow

**Scope-Regel:** `FULL` führt alle aktivierten Schritte aus. `LITE` führt nur die in Abschnitt 2.2 genannten
Pflichtteile plus alle durch konkrete Evidenz ausgelösten Profile aus. `SKIP` endet nach der dokumentierten
Triage. Ein Schritt wird in `LITE` nicht allein deshalb ausgeführt, weil er existiert; er braucht ein Signal
aus Impact, Golden-Path-Abweichung oder Repository-Evidenz.


# Schritt 0 — Quality Snapshot und Freshness prüfen

Vor der Bewertung festhalten:

```markdown
### Quality Snapshot

Zusätzlich dokumentieren:

- `review_source_fingerprint`
- `impact_source_fingerprint`
- `requested_scope`
- `effective_scope`


- Modus: Plan / Branch
- Quality-Scope: FULL / LITE / SKIP
- Task: <Ticket/Feature>
- Task-File: <Pfad>
- Repository/Worktree: <Pfad>
- Review-Basis: <Plan-Version / Commit / Merge-Base..HEAD>
- Impact-Analyse vorhanden: ja / nein
- Impact-Basis: <Plan-Version / Commit>
- Impact aktuell: ja / nein / unklar
- Projekt-Profil übernommen aus Impact: <Kurzform>
```

## 0a) Staleness-Regel

Die Impact-Analyse gilt als **stale**, wenn seit ihrer Basis eine Änderung vorgenommen wurde, die eines dieser
Elemente betrifft:

- Semantic Change Set,
- API-/Event-/Command-/Query-Contract,
- Domain-Invariante,
- Persistenz / Migration,
- Security / Tenant,
- Async / Eventual Consistency,
- Transaktionsgrenze,
- relevante Read-/Write-Consumer.

Bei stale Impact zuerst die Differenz bestimmen. Nicht mit veralteten Risk-IDs so tun, als wäre der aktuelle
Plan vollständig analysiert.

---

# Schritt 1 — Upstream-Ergebnisse konsumieren, nicht nachbauen

Erstelle aus Task, finalem Plan und Impact-Analyse eine kompakte Arbeitsbasis:

```markdown
### Quality Input Summary

**Feature-Ziel:** ...

**Relevante Semantic Changes:**
- C1 ...
- C2 ...

**Relevante Invarianten:**
- INV-1 ...

**Top Impact Risks:**
- R-1 ...

**Offene Unknowns:**
- U-1 ...

**Betroffene Hauptpfade:**
- P1 ...
```

## Pflichtregel

Nicht erneut pauschal:

- alle Writer/Reader suchen,
- alle Lifecycle Listener inventarisieren,
- historische Tickets jeder Datei durchgehen,
- das komplette Security-/Migration-/Async-Risiko neu ableiten.

Diese Arbeit gehört zur Impact-Analyse. Quality öffnet einen Teil davon nur gezielt, wenn eine
Architekturentscheidung davon abhängt.

---

# Schritt 2 — Feature als Architekturproblem klassifizieren

Die Klassifikation dient **nicht** der Impact-Bestimmung, sondern der Auswahl relevanter Qualitätsfragen.
Mehrfachzuordnungen sind erlaubt.

## 2a) Feature-Charakter

- neues fachliches Capability,
- Erweiterung eines bestehenden Use Cases,
- neue fachliche Variante,
- neuer Workflow / Lebenszyklus,
- neue Integration,
- neues Daten-/Read-Modell,
- neue gemeinsame Abstraktion,
- neue UI-/Interaktionslogik,
- technische Plattform-/Infrastruktur-Erweiterung.

## 2b) Architekturtreiber

Extrahiere nur belegte Treiber:

| Driver | Quelle | Konsequenz für Design |
|---|---|---|
| fachliche Invariante | `INV-*` / AC | ... |
| hohes Impact-Risiko | `R-*` | ... |
| Security / Tenant | AC / Impact | ... |
| Rückwärtskompatibilität | Contract / Impact | ... |
| hohe Änderungswahrscheinlichkeit | Roadmap / bestehende Varianten | ... |
| Volumen / Latenz | NFR / Messdaten | ... |
| Audit / Compliance | Anforderung | ... |

**Keine hypothetischen NFRs erfinden.**

## 2c) Quality-Attribute-Scenarios nur bei echter Relevanz

Wenn Performance, Verfügbarkeit, Robustheit, Auditierbarkeit, Datenschutz oder ähnliche Qualitätsattribute
explizit gefordert oder durch ein `R-*` als Architekturtreiber belegt sind, formuliere sie als überprüfbares
Szenario statt als Schlagwort:

```markdown
### QA-Scenario QA1 — <Attribut>

- **Quelle/Stimulus:** Was passiert?
- **Kontext:** Unter welchen Bedingungen / welchem Volumen?
- **Betroffener Teil:** Welcher Use Case / welche Boundary?
- **Erwartete Reaktion:** Was muss das System tun?
- **Mess-/Nachweiskriterium:** Woran erkennt man, dass es genügt?
```

Beispielhaft ist „schnell“ kein Architecture Driver; „Liste mit 100k Datensätzen antwortet im vereinbarten
Lastprofil ohne vollständige Entity-Hydration“ kann einer sein, wenn diese Anforderung tatsächlich belegt ist.

---

# Schritt 3 — Architecture Decision Surface erstellen

Dies ist der Kerninput der Quality-Analyse.

Für jede **neue oder wesentlich veränderte Architekturentscheidung** eine Zeile erfassen:

```markdown
### Architecture Decision Surface

| D-ID | Entscheidung / Frage | Betroffene C/R/INV | Geplanter Ort | Warum eine echte Designentscheidung? |
|---|---|---|---|---|
| D1 | Wo lebt Regel X autoritativ? | C2, INV-1 | Domain ... | mehrere Consumer |
| D2 | Wie wird Provider Y isoliert? | C4, R-3 | Adapter ... | externer Contract |
```

Typische Decision Surfaces:

- **Responsibility:** Welche Klasse / Schicht besitzt eine Regel?
- **Boundary:** Wo endet Domain/Application und wo beginnt Infrastruktur/Provider?
- **Source of Truth:** Wo lebt ein fachliches Prädikat, Statusmodell oder Mapping autoritativ?
- **State Model:** Enum + Policy, State Machine, State Objects oder einfache Guards?
- **Variation:** `if/match`, Strategy, polymorphe Typen oder Datenkonfiguration?
- **Construction:** Konstruktor / Named Constructor / Factory / Builder?
- **Contract:** internes DTO, API DTO, Event Schema, Command/Query?
- **Consistency:** synchron, transaktional, eventual consistent?
- **Persistence Ownership:** Entity/Repository/Projection/Read Model?
- **Frontend State:** lokale UI-Logik, Hook/Reducer/Server-State?
- **Reuse:** bestehenden Service/Port erweitern oder neues Konzept?

## Regel

Wenn ein Planschritt **keine echte Designentscheidung** enthält, muss dafür auch kein künstlicher
Principle-/Pattern-Review erzeugt werden.

---

# Schritt 4 — Repository-Fit und bestehende „Golden Paths“ prüfen

Quality soll neue Features in die tatsächliche Architektur einpassen.

## 4a) Vergleichbare Use Cases auswählen

Suche gezielt 1–3 fachlich oder architektonisch vergleichbare Implementierungen.

Prüfe:

- Welche Layer werden verwendet?
- Wo lebt dort die Fachregel?
- Wie sehen Commands/Queries/Handler/DTOs aus?
- Wie werden Autorisierung, Persistenz, Events und Tests geschnitten?
- Welche Namen und Verzeichnisstrukturen bilden die Ubiquitous Language ab?

## 4b) Ähnlichkeit bewerten

Nicht blind kopieren.

| Vergleich | Bewertung |
|---|---|
| gleiche fachliche Verantwortung | starkes Architektur-Signal |
| gleiche technische Form, andere Fachsemantik | schwaches Signal |
| historischer Sonderfall / Legacy | nicht als Golden Path verwenden |
| neues Feature braucht bewusst andere Grenze | Abweichung begründen |

## 4c) Abweichungen sichtbar machen

```markdown
### Architecture-Fit

| D-ID | Bestehendes Projektmuster | Geplanter Ansatz | Abweichung? | Begründung |
|---|---|---|---|---|
| D1 | ... | ... | Nein/Ja | ... |
```

Eine bewusste Abweichung ist erlaubt. Eine **unbemerkte** Abweichung ist ein Quality-Risiko.

---

# Schritt 5 — Qualitätsprofile aktivieren

`global-design` und `testing-evidence` sind immer aktiv. Alle anderen nur durch Decision Surface,
Architekturtreiber oder konkrete Code-Signale.

| Profil | Aktivierungssignale | Fokus |
|---|---|---|
| `global-design` | immer | KISS, Klarheit, Kohäsion, Kopplung, explizite Verantwortungen |
| `domain-model` | neue/erweiterte Fachregel, Entity, VO, Berechnung | Invarianten, Sprache, Encapsulation, Information Expert |
| `application-use-case` | Command/Handler/Application Service | Use-Case-Grenze, Orchestrierung, Transaktion, Policy-Aufruf |
| `cqrs-boundary` | Read/Write-Flows | Command-/Query-Semantik, DTO-Grenzen, keine versteckte Mutation |
| `workflow-state` | Status/Lebenszyklus/Versionen | Transition Policy, State-Komplexität, Audit, Konkurrenz |
| `business-process-orchestration` | Events, E-Mail, Pendenzen, mehrere Rollen/Side Effects | Trigger-Ownership, Orchestrierung/Choreographie, Duplicate Safety, Audit, Failure Isolation |
| `authorization-model` | Rollen, Object-Level Authorization, Tenant | Policy-Ownership, Complete Mediation, Least Privilege, Read/Write-Symmetrie |
| `module-boundary` | neue Services/Module/shared Abstraktion | Abhängigkeitsrichtung, Public API, Coupling |
| `persistence-design` | neues/erweitertes Datenmodell | Aggregate-Grenze, Repository-Rolle, Constraints als zweite Verteidigung |
| `contract-design` | API/DTO/Event | Semantik, Nullability, Evolvierbarkeit, Fehlervertrag |
| `integration-boundary` | externer Provider/Datei/Queue | Adapter/ACL, Failure Model, Provider-Leak |
| `frontend-state` | neue komplexe UI | Server-/Client-Source-of-Truth, State-Schnitt, Error Mapping |
| `evolution` | mehrere Varianten / belegte nahe Änderungen | Change Amplification, OCP nur bei echter Achse |
| `testability-operability` | immer | isolierbare Regeln, Nachweise, Logs/Metriken/Audit bei Bedarf |
| `migration-rollout` | Schema-/Contract-Rollout | Expand/Contract, Deployment-Kopplung, Reversibilität |

Dokumentiere:

```markdown
### Aktivierte Qualitätsprofile

| Profil | Aktiviert durch D/C/R/INV | Betroffene Planschritte |
|---|---|---|
| ... | ... | ... |
```

---

# Schritt 6 — Design-Review entlang der aktivierten Profile

## 6.1 Simplicity / KISS / YAGNI

Prüfe:

- Ist dies die einfachste Struktur, die alle belegten Anforderungen, Invarianten und Risiken trägt?
- Gibt es Abstraktionen ohne heutigen Nutzer oder belegte nahe Änderungsachse?
- Wird ein Problem durch zusätzliche Schichten nur verschoben?
- Entsteht ein Mini-Framework für einen einzelnen Use Case?
- Ist die Anzahl neuer Konzepte proportional zur fachlichen Komplexität?

**Regel:** Komplexität muss durch einen benennbaren Driver oder Design Pressure bezahlt werden.

---

## 6.2 Responsibility / SRP / High Cohesion

Prüfe den **Änderungsgrund**, nicht die Dateigröße:

- Hat ein Artefakt eine klar benennbare Verantwortung?
- Vermischt ein Handler Orchestrierung, fachliche Berechnung, Mapping und Infrastruktur?
- Liegt die Regel bei dem Objekt/Service, das die Informationen und Invarianten besitzt?
- Werden zusammengehörige Regeln unnötig über Controller, Handler, Entity, Mapper und Frontend verteilt?
- Würden verschiedene Stakeholder dasselbe Artefakt aus unabhängigen Gründen ändern?

Hilfreiche Prinzipien:

- SRP,
- Information Expert,
- Tell, Don’t Ask,
- High Cohesion.

---

## 6.3 Boundaries / Dependency Direction / DIP

Prüfe:

- Hängt Domain-Code von Symfony, HTTP, Provider-DTOs oder Persistence-Details ab?
- Kennt Application-Code konkrete externe Provider, obwohl eine stabile fachliche Grenze existiert?
- Ist ein Interface eine echte Boundary/Role oder nur ein Interface vor einer einzelnen Klasse?
- Werden interne Domain-Modelle direkt als API-/Queue-/Provider-Contracts verwendet?
- Gibt es zyklische oder beidseitige Modulabhängigkeiten?
- Entsteht eine neue `shared`-Abstraktion, obwohl die Verantwortung einem konkreten Modul gehört?

**DIP nicht mechanisch anwenden.** Eine Abstraktion braucht eine stabile Grenze, nicht nur den Wunsch nach
„mehr Testbarkeit“.

---

## 6.4 Domain Model / Business Truth

Nutze die `INV-*` und Decision Tables aus Impact als Referenz.

Prüfe:

- Wo ist jede fachliche Regel autoritativ implementiert?
- Kann ein Objekt in einen Zustand gelangen, der `INV-*` verletzt?
- Sind fachliche Aktionen benannt (`submit()`, `approve()`, `copyAsDraft()`) statt beliebiger Setter?
- Werden Regeln über primitive Flags/Strings mehrfach nachgebaut?
- Ist Nullability fachlich erklärt?
- Braucht ein Konzept ein Value Object, weil es Einheit, Validierung oder Semantik trägt — oder wäre das nur Verpackung?
- Gibt es kanonische Prädikate, die Writer und Reader gemeinsam verwenden sollten?

### Rule-Ownership-Tabelle

Für zentrale Regeln:

| Regel / Konzept | Autoritativer Owner | Zulässige Consumer | Duplikate? | Entscheidung |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

Diese Tabelle ist wichtiger als syntaktisches DRY.

---

## 6.5 Application Layer / CQRS

Prüfe:

- Repräsentiert ein Command/Handler genau einen fachlich benennbaren Use Case?
- Orchestriert der Handler oder enthält er das eigentliche Domain-Modell?
- Ist eine Query wirklich side-effect-free?
- Sind Request/API DTO, Command und Domain-Modell getrennte Verträge, **wenn** ihre Semantik tatsächlich verschieden ist?
- Ist die Transaktionsgrenze um den atomaren Use Case klar?
- Werden Domain Events aus einem konsistenten Zustand erzeugt?
- Wird Businesslogik nicht in Mappern/Normalizer/Serializer versteckt?

Impact bestimmt, **welche** Read-/Write-Pfade betroffen sind. Quality bewertet, **wie gut ihre Grenzen geschnitten sind**.

---

## 6.6 Workflow / State Design

Nutze die Impact-Decision-Table und Statusvarianten.

Prüfe:

- Reichen explizite Transition-Methoden / Policy-Methoden?
- Oder unterscheiden sich Verhalten und erlaubte Aktionen pro Zustand so stark, dass State/State Machine echten Nutzen bringt?
- Sind Guards, Autorisierung und fachliche Vorbedingungen getrennt benennbar?
- Kann ein generischer Setter Transitionen umgehen?
- Ist Status nur Datenwert oder tatsächlich Verhaltensachse?
- Wird Audit/Versionierung mit State Management verwechselt?

**Bevorzugung:** bei wenigen einfachen Transitionen explizite Methoden/Policy vor vollständigem State-Pattern.

---

## 6.7 Persistence Design

Die konkrete Migrations-/Constraint-Risikoanalyse kommt aus Impact. Hier prüfen:

- Passt die Persistenzstruktur zur fachlichen Ownership?
- Ist ein Repository use-case-/aggregate-orientiert oder generischer Datenzugriffs-Sammelpunkt?
- Werden Domain-Invarianten zusätzlich dort durch Constraints abgesichert, wo die DB sie zuverlässig erzwingen kann?
- Zwingt das ORM zu einem Modell, das die fachliche Struktur unnötig verschlechtert?
- Ist ein separates Read Model bewusst oder nur duplizierte Persistenz?
- Führt Denormalisierung zu einer klar benannten Synchronisationsverantwortung?

---

## 6.8 Contract Design

Für API-, Event-, Command-/Query- und Integrationsverträge:

- Ist die Semantik des Contracts klar und stabil?
- Sind Pflichtfeld, optional, `null`, „nicht vorhanden“ und Default semantisch unterschieden?
- Werden interne Implementierungsdetails nach außen geleakt?
- Ist ein Event ein fachliches Ereignis oder nur ein technisches „EntityChanged“?
- Ist ein Command eine Absicht oder nur ein Datencontainer ohne Use-Case-Semantik?
- Ermöglicht die Form des Contracts die belegte Evolutionsrichtung ohne permanente Breaking Changes?

Backward-Compatibility-Risiken selbst bleiben `R-*`; hier wird die **Contract-Form** bewertet.

---

## 6.9 Integration Boundary / Failure Model

Bei externer Integration:

- Sind Provider-Modelle an der Boundary normalisiert?
- Ist der interne Port nach dem Bedarf der Anwendung geschnitten statt nach der Provider-API?
- Leakt Provider-Fehlersemantik tief in Application/Domain?
- Ist klar, welche Fehler retryable, permanent oder fachlich sind?
- Sind Sync/Async und Failure Handling für Aufrufer sichtbar genug?
- Entsteht ein God-Facade-Service, der mehrere unabhängige Use Cases bündelt?

Timeout/Retry/Idempotenz-Risiken aus Impact nicht duplizieren; prüfen, ob die Architektur sie **lokal beherrschbar** macht.

---

## 6.10 Frontend State / Server Truth

Prüfe:

- Ist klar, was Server-State und was rein lokaler UI-State ist?
- Wird autoritative Businesslogik im Frontend dupliziert?
- Gibt es mehrere konkurrierende Quellen für denselben Status?
- Ist komplexe lokale Zustandslogik noch kohärent oder braucht sie Hook/Reducer/State Machine?
- Sind Client-Mappings Teil des API-Contracts oder verstreute Ad-hoc-Transformationen?
- Entsteht ein generischer Frontend-Abstraction-Layer ohne mehrere reale Consumer?

---

## 6.11 Testability / Operability

Prüfe nicht nur „gibt es Tests?“, sondern ob das Design **gut nachweisbar** ist:

- Kann die zentrale Fachregel fokussiert getestet werden?
- Sind externe Effekte an einer Boundary isolierbar?
- Erfordert ein einfacher Domain-Test einen kompletten Framework-Boot?
- Sind Zeit, Zufall, IDs und externe Provider kontrollierbar, wenn relevant?
- Lassen sich wichtige Failure Modes gezielt auslösen?
- Gibt es für kritische Prozesse genug Korrelation/Audit/Logs, um Fehler später zu erklären?

Quality kann einen zusätzlichen Nachweis fordern, aber vorhandene `R→Test`-Einträge nicht kopieren.

---

## 6.12 Evolution / Change Amplification

Dieser Abschnitt ist für neue Features besonders wichtig.

Nur **belegte** Änderungsachsen betrachten, z.B. vorhandene Geschwistertypen, Roadmap, mehrere Provider oder
wiederkehrende fachliche Varianten.

Für jede belegte Achse ein Change Scenario formulieren:

```markdown
### Change Scenario E1 — neuen <Typ/Provider/Status> ergänzen

- Heute zu ändernde Stellen: ...
- Nach geplantem Design zu ändernde Stellen: ...
- Muss bestehender Code modifiziert oder nur ergänzt werden?
- Wo liegt die zentrale Auswahlentscheidung?
- Entsteht Shotgun Surgery?
- Wäre zusätzliche Abstraktion heute gerechtfertigt?
```

### Change-Amplification-Tabelle

| Scenario | erwartete Änderungsstellen | lokalisierte Regel? | Risiko | Konsequenz |
|---|---:|---|---|---|
| E1 | ... | ja/nein | ... | ... |

**OCP wird nur anhand solcher realen Szenarien bewertet**, nicht als abstraktes Ziel.

---

## 6.13 Complex Business Process Orchestration

Dieses Profil ist bei Business-Anwendungen mit mehreren Rollen, Pendenzen, Events, E-Mail-/Benachrichtigungs-
Side-Effects oder mehrstufigen Workflows besonders wichtig.

Prüfe den fachlichen Prozess als zusammenhängende Kette:

```text
User-/System-Aktion
→ Authorization / Object Access
→ Command / Use Case
→ atomare fachliche Mutation
→ Domain/Event Decision
→ Event / Async Message
→ Side Effects (E-Mail, Pendenz, Notification, Export, externe API)
→ Read-Sichtbarkeit / nächster Workflow-Schritt
→ Audit / Observability
```

Quality bewertet dabei nicht erneut den Impact jeder Station, sondern die **Ownership und Kopplung**:

- Wer besitzt den fachlichen Trigger für Event, E-Mail oder Pendenz?
- Ist der Side Effect Teil der atomaren Business-Transaktion oder bewusst eventual consistent?
- Ist Orchestrierung an einer klaren Use-Case-Grenze sichtbar oder entsteht versteckte Choreographie?
- Können Retry/Duplikate doppelte E-Mails, doppelte Pendenzen oder doppelte fachliche Aktionen erzeugen?
- Sind technische Events und fachliche Events sauber getrennt?
- Ist erkennbar, welche Rolle den Prozess auslösen, fortsetzen, sehen oder abbrechen darf?
- Bleibt die Berechtigungsprüfung auch bei indirekten/async Folgeaktionen vollständig?
- Gibt es eine autoritative Stelle für „wann entsteht/erlischt eine Pendenz“?
- Ist Audit fachlich ausreichend, um später zu erklären: wer hat was ausgelöst, welcher Folgeprozess lief,
  welche Nachricht wurde versendet und welcher Zustand resultierte?

Bei einem Prozess mit mehreren gekoppelten Side Effects eine **Process-Ownership-Tabelle** anlegen:

| Prozessschritt | fachlicher Owner | Trigger | sync/async | Failure Owner | Duplicate-Schutz | Audit-Signal |
|---|---|---|---|---|---|---|
| ... | ... | ... | ... | ... | ... | ... |

Ein `FULL`-Review darf nicht freigegeben werden, wenn für kritische Side Effects unklar ist, wer deren
Semantik und Fehlerbehandlung besitzt.


# Schritt 7 — Symmetry und Knowledge Ownership aus Quality-Sicht

Impact prüft Missing Counterparts funktional. Quality prüft die **Struktur hinter den Symmetrien**.

Beispiele:

- Create / Update teilen eine Regel: gemeinsame Domain Policy oder bewusst getrennt?
- List / Show verwenden dasselbe fachliche Label/Mapping: zentrale Quelle oder legitime View-spezifische Form?
- mehrere Typen verwenden dasselbe Prädikat: kanonische Methode oder duplizierte Primitive?
- Backend / Frontend validieren dieselbe Regel: Server autoritativ, Client nur UX?
- Import / UI / Copy schreiben dieselbe Property: gemeinsame Domain-Invariante oder drei unabhängige Pfade?

Ergebnis:

```markdown
### Knowledge Ownership Findings

| Konzept | heutige/geplante Stellen | autoritative Stelle | gewünschte Struktur | Q-Finding? |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |
```

---

# Schritt 8 — Design-Pattern-Fit aus Design Pressure ableiten

## 8.1 Suitability Gate

Für jeden ernsthaften Pattern-Kandidaten beantworten:

1. Welcher konkrete Design Pressure existiert?
2. Welche Repository-/Impact-Evidenz belegt ihn?
3. Ist er wiederkehrend oder einmalig?
4. Welche einfachere Lösung wurde geprüft?
5. Welche belegte Änderungsachse stabilisiert das Pattern?
6. Welche Komplexität / Indirektion / Testlast entstehen?
7. Gibt es im Projekt bereits einen Mechanismus dafür?
8. Welche Quality-Achse verbessert sich messbar oder nachvollziehbar?
9. Welche Quality-Achse wird schlechter?
10. Was wäre das Signal, das Pattern **nicht** einzuführen?

Ohne klare Antworten: **Pattern ablehnen**.

## 8.2 Business-App Pattern Map

| Design Pressure | Primäre Kandidaten | Erst einfachere Alternative prüfen | Warnsignal |
|---|---|---|---|
| mehrere echte Algorithmen derselben Rolle | Strategy | benannte Methode / kleiner `match` | nur ein oder zwei triviale Zweige |
| zustandsabhängiges Verhalten + komplexe Transitionen | State / State Machine | Transition Methods / Policy | Status ist nur Label/Guard |
| externe inkompatible Modelle | Adapter / Anti-Corruption Layer | lokaler Mapper | Adapter enthält ganzen Geschäftsprozess |
| stabile Schnittstelle, optionale kombinierbare Querschnittslogik | Decorator / Middleware | direkte Komposition | Reihenfolge/Fehlersemantik unklar |
| komplexe valide Konstruktion | Named Constructor / Factory / Builder | Konstruktor + VO | Builder erzeugt ungültige Zustände |
| fachliches Kopieren/Versionieren | explizite Copy Policy / Prototype | benannte `copyAs...()`-Methode | blinde Objektkopie |
| variable Verarbeitungspipeline | Chain of Responsibility | explizite Sequenz | kurze feste Reihenfolge |
| komplexes kohärentes Subsystem für viele Consumer | Facade | use-case-spezifischer Service | God Service |
| mehrere unabhängige Reaktionen auf fachliches Ereignis | Domain Event / Observer | direkter expliziter Aufruf | versteckte kritische Side Effects |
| stabile Algorithmusstruktur mit variablen Schritten | Template Method | Composition / Strategy | Vererbung nur für Code-Reuse |
| echte Teil-Ganzes-Struktur | Composite | Collection/Tree-Helper | flache Daten künstlich als Baum |
| zwei unabhängige stabile Variationsachsen | Bridge | Composition einfacher Rollen | unnötige Doppelhierarchie |
| Wiederherstellung eines vollständigen fachlichen Zustands | Memento/Snapshot | Version Entity / Audit getrennt | Audit wird mit Restore verwechselt |

### Bewusst seltene Patterns

`Singleton`, `Flyweight`, `Visitor`, eigener `Iterator`, zusätzlicher `Mediator` oder eigener `Command` neben
vorhandenem CQRS/MessageBus nur bei sehr konkretem nachgewiesenem Problem. Framework-Mechanismen nicht
parallel neu erfinden.

## 8.3 Pattern Decision Record

```markdown
### Pattern-Kandidat: <NAME>

- **D-ID / Design Pressure:** ...
- **Evidenz:** ...
- **Einfachste Alternative:** ...
- **Nutzen:** ...
- **Kosten:** ...
- **Belegte Änderungsachse:** ...
- **Projekt-Fit:** ...
- **Entscheidung:** verwenden / vorhandenes Pattern nutzen / ablehnen / weitere Evidenz nötig
- **Konkrete Planfolge:** ...
```

Auch **bewusst abgelehnte** ernsthafte Kandidaten dokumentieren, wenn die Entscheidung später wahrscheinlich
erneut diskutiert würde.

---

# Schritt 9 — Architecture Decision Log und ADR-Kandidaten

Nicht jede lokale Entscheidung braucht ein ADR. Wesentliche Entscheidungen aber sichtbar machen.

```markdown
### Architecture Decision Log

| D-ID | Entscheidung | Alternativen | gewählte Option | Hauptgrund | Trade-off | ADR nötig? |
|---|---|---|---|---|---|---|
| D1 | ... | ... | ... | ... | ... | ja/nein |
```

## ADR-Kandidat, wenn mindestens eines zutrifft

- langfristige modulübergreifende Architekturgrenze,
- neue projektweite Konvention,
- schwer reversibler Daten-/Integrationsentscheid,
- neuer Consistency-/Messaging-Ansatz,
- bewusste Abweichung von bestehender Architektur,
- Entscheidung wird voraussichtlich in mehreren Features wiederkehren.

Ein lokaler Service-Schnitt oder eine einzelne Strategy braucht normalerweise kein ADR.

---

# Schritt 10 — Quality Finding Register

Quality-Findings erhalten eigene IDs `Q-*`. `R-*` bleiben Eigentum der Impact-Analyse.

## 10.1 Finding-Typen

- `DESIGN_GAP`
- `ARCHITECTURE_DEVIATION`
- `RESPONSIBILITY`
- `COUPLING`
- `DUPLICATED_BUSINESS_KNOWLEDGE`
- `UNSUPPORTED_ABSTRACTION`
- `CHANGE_AMPLIFICATION`
- `CONTRACT_DESIGN`
- `TESTABILITY`
- `OPERABILITY`
- `POSITIVE_DECISION`

## 10.2 Schweregrad

| Stufe | Bedeutung |
|---|---|
| `BLOCKER` | Design verletzt fachliche/Security-/Integritäts-Gates oder macht den Plan fundamental untragfähig |
| `HIGH` | wesentliche Architektur-/Boundary-/State-/Evolution-Lücke vor Implementierung lösen |
| `MEDIUM` | relevante Wartbarkeits-, Kopplungs- oder Testbarkeitslücke |
| `LOW` | lokale Verbesserung mit begrenztem Änderungsrisiko |
| `INFO` | bestätigte gute Entscheidung, bewusster Trade-off oder sinnvoll abgelehnte Alternative |

## 10.3 Pflichtformat

```markdown
#### Q-04 · HIGH — <präziser Titel>

- **Typ:** COUPLING / ...
- **D-ID:** D2
- **Bezug zu Impact:** C3, R-2, INV-1 (falls relevant)
- **FACT:** ...
- **INFERENCE:** ...
- **Konkretes Qualitätsproblem:** ...
- **Warum es jetzt relevant ist:** ...
- **Einfachste Verbesserung:** ...
- **Alternativen / Trade-off:** ...
- **Erforderlicher Nachweis:** Test / Architekturtest / Code-Struktur / ADR / keiner
- **Confidence:** hoch / mittel / niedrig
```

Nicht zulässig:

- „SOLID beachten“
- „Factory erwägen“
- „Code sauber halten“
- „mehr abstrahieren“
- erneutes Abschreiben eines `R-*` ohne zusätzliche Design-Ursache.

## 10.4 Zentraler Register

```markdown
| Q-ID | Severity | Typ | D-ID | C/R/INV | Kurzproblem | Planänderung | Nachweis | Status |
|---|---|---|---|---|---|---|---|---|
```

---

# Schritt 11 — Review-Gegenstand reconciliieren

## Nur Plan-Modus

Erstelle **keinen komplett neuen Plan aus Stilpräferenz**. Ändere nur, was durch bestätigte `Q-*` oder
notwendige Entscheidungen ausgelöst wird.

Für jede Änderung am Plan dokumentieren:

```markdown
### Quality Plan Delta

| Δ-ID | Auslöser | alte Planung | neue Planung | semantischer Impact? |
|---|---|---|---|---|
| ΔQ1 | Q-03 | ... | ... | ja/nein |
```

Danach den Plan so aktualisieren, dass für wesentliche neue Artefakte klar ist:

- Verantwortung,
- Boundary / Layer,
- relevante Invarianten,
- Contract,
- Abhängigkeiten,
- Pattern-/No-Pattern-Entscheidung,
- Test-/Nachweisstrategie.

## Nur Branch-Modus

Statt Planänderung:

```markdown
### Erforderliche Code-Änderungen

| Q-ID | Datei/Symbol | konkrete Änderung | Test/Nachweis | Priorität |
|---|---|---|---|---|
```

Code↔Plan-Abweichungen sind nur dann Quality-Findings, wenn sie Designqualität, Anforderungen oder eine
bestätigte Entscheidung betreffen; triviale Implementierungsdetails nicht aufblasen.

---

# Schritt 12 — Impact-Recheck-Request bei semantischem Quality-Delta

Quality darf Impact **nicht selbst neu analysieren**.

Wenn der Quality-Review den Plan beziehungsweise die relevante Architektur semantisch verändert, liefere an
`SKILL.md`:

```yaml
impact_recheck_required: true
quality_delta:
  - ΔQ-...
reason:
  - neue/entfernte Semantic Changes
  - neue Boundary / Message / Event / Persistenz- oder Contract-Entscheidung
  - geänderte Transaction-/Async-Semantik
  - neue oder veränderte Business-Invariante
```

Kein Recheck ist nötig bei rein redaktionellen Planpräzisierungen, Namensverbesserungen oder anderen Änderungen,
die weder Verhalten noch Architektur-/Datenfluss verändern.

`SKILL.md` ruft bei `impact_recheck_required=true` den Sub-Skill `impact-analysis/SKILL.md` gegen den
reconciliierten Review-Gegenstand auf. Der aktualisierte Impact-Handoff wird anschließend wieder in den
Quality-Kontext übernommen. Falls dadurch neue wesentliche Architekturtreiber entstehen, kann `SKILL.md`
einen begrenzten Quality-Nachlauf auslösen.

Die Methodik implementiert **keine zweite Impact-Analyse** und dupliziert deren Regeln nicht.


# Schritt 13 — Adversarialer Gegencheck

Nach dem ersten Quality-Review bewusst versuchen, die eigenen Empfehlungen zu widerlegen.

Für jedes `BLOCKER`/`HIGH` und jede Pattern-/Abstraktionsempfehlung:

1. Gibt es bereits einen einfacheren etablierten Projektweg?
2. Ist die behauptete Änderungsachse wirklich belegt?
3. Ist die vermeintliche Duplikation tatsächlich dasselbe Fachwissen?
4. Kann die neue Abstraktion entfallen, ohne eine Invariante/Risk/Driver zu verschlechtern?
5. Erzeugt die Empfehlung neue Coupling-, Transaction- oder Consistency-Probleme?
6. Spiegelt das Interface nur die heutige Implementierung statt einer stabilen Rolle?
7. Ist das Problem bereits durch Framework/Container/ORM/MessageBus gelöst?
8. Belegt ein bestehender Test oder Golden Path das Gegenteil?
9. Ist ein `Q-*` in Wahrheit nur ein bereits bekanntes `R-*` und deshalb zu deduplizieren?

Ein Finding bleibt bestehen, wenn es diesen Gegencheck überlebt oder die Unsicherheit ausdrücklich als
`UNKNOWN`/niedrige Confidence dokumentiert bleibt.

---

# Schritt 14 — Completion Gate und Freigabe

Die Quality-Analyse ist erst abgeschlossen, wenn:

- [ ] Quality Snapshot dokumentiert und Impact-Freshness geprüft
- [ ] Upstream Semantic Changes / Invarianten / Risks / Unknowns übernommen
- [ ] echte Architecture Decision Surfaces identifiziert
- [ ] relevante Golden Paths / Projektkonventionen geprüft
- [ ] Qualitätsprofile evidenzbasiert aktiviert
- [ ] Rule Ownership für zentrale neue Fachregeln geklärt
- [ ] Verantwortungen, Boundaries und Dependency Direction geprüft
- [ ] belegte Evolution Scenarios / Change Amplification geprüft, falls relevant
- [ ] Pattern-Kandidaten haben Design Pressure + einfachere Alternative
- [ ] Architecture Decision Log vollständig genug
- [ ] jedes `BLOCKER/HIGH` adversarial gegengeprüft
- [ ] Quality Plan Delta dokumentiert
- [ ] erforderliches Delta-Impact durchgeführt
- [ ] Plan, Impact und Quality beschreiben denselben Stand
- [ ] alle verbleibenden Unknowns sichtbar

## Freigabeentscheidung

### `FREIGEGEBEN`

Nur wenn:

- keine offenen `BLOCKER`/`HIGH` Quality-Findings,
- kein stale Impact,
- kein unreconciled semantischer Quality-Delta,
- wesentliche Designentscheidungen evidenzbasiert sind,
- keine unbegründete Abstraktions-/Pattern-Komplexität bleibt.

### `FREIGEGEBEN MIT ÄNDERUNGEN`

Wenn:

- alle wesentlichen `Q-*` bereits im Plan/Code umgesetzt oder konkret eingeplant sind,
- Delta-Impact reconciled ist,
- nur dokumentierte `MEDIUM`/`LOW` oder nicht-blockierende Entscheidungen offen bleiben.

### `PLAN / DESIGN ÜBERARBEITEN`

Wenn:

- eine zentrale Architecture Decision ungeklärt ist,
- Verantwortungen oder Boundaries widersprüchlich sind,
- ein Mandatory Driver nur über Vermutungen behandelt wird,
- `BLOCKER/HIGH` offen sind,
- Pattern-/Abstraktionsstruktur nicht durch Design Pressure gerechtfertigt ist,
- der Quality-Delta noch nicht durch Impact reconciled wurde.

---

# Report-Template

```markdown
## Qualitätsreview

**Durchgeführt am:** <DATUM>
**Modus:** Plan / Branch
**Quality-Scope:** FULL / LITE / SKIP
**Review-Basis:** <Plan-Version / Commit>
**Impact-Basis:** <Plan-Version / Commit>
**Impact aktuell:** ja / nein
**Entscheidung:** FREIGEGEBEN / FREIGEGEBEN MIT ÄNDERUNGEN / PLAN-DESIGN ÜBERARBEITEN

### 1) Quality Input Summary

**Feature-Ziel:** ...
**Semantic Changes:** C1, C2, ...
**Invarianten:** INV-1, ...
**Top Risks:** R-1, ...
**Unknowns:** ...

### 2) Architecture Decision Surface

| D-ID | Entscheidung | C/R/INV | geplanter Ort | Design-Druck |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

### 3) Architecture-Fit

| D-ID | bestehender Golden Path | Plan | Abweichung | Begründung |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

### 4) Aktivierte Qualitätsprofile

| Profil | aktiviert durch | Planschritte |
|---|---|---|
| ... | ... | ... |

### 5) Rule / Knowledge Ownership

| Konzept | autoritative Stelle | Consumer | Entscheidung |
|---|---|---|---|
| ... | ... | ... | ... |

### 6) Evolution / Change Scenarios

| Scenario | Änderungsstellen | lokalisiert? | Konsequenz |
|---|---:|---|---|
| ... | ... | ... | ... |

### 7) Pattern Decisions

| Pattern | Design Pressure | einfachere Alternative | Entscheidung | Planfolge |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

### 8) Architecture Decision Log

| D-ID | Entscheidung | Alternativen | Option | Trade-off | ADR? |
|---|---|---|---|---|---|
| ... | ... | ... | ... | ... | ... |

### 9) Quality Finding Register

| Q-ID | Severity | Typ | D-ID | C/R/INV | Problem | Änderung | Status |
|---|---|---|---|---|---|---|---|
| ... | ... | ... | ... | ... | ... | ... | ... |

### 10) Bestätigte gute Entscheidungen

- INFO ...

### 11) Quality Plan Delta / erforderliche Code-Änderungen

| Δ-ID / Q-ID | Auslöser | Änderung | semantischer Impact? |
|---|---|---|---|
| ... | ... | ... | ... |

### 12) Impact-Recheck

- erforderlich: ja / nein
- Impact aktualisiert: ja / nein
- geänderte C/P/INV/R/Test-IDs: ...
- neue relevante Risiken: ...

### 13) Offene Entscheidungen / Unknowns

- ...
```

---

# Kompakte Aktivierungsmatrix für neue Business-Features

| Featuretyp | primäre Quality-Fragen | häufige Pattern-Hypothesen |
|---|---|---|
| neues CRUD mit echter Fachregel | Rule Ownership, Domain vs Handler, Contract, Tenant | meist kein GoF-Pattern |
| komplexe Berechnung | autoritative Regel, Variantenachse, Rundung, Testbarkeit | Strategy nur bei echten Varianten |
| Status-/Freigabeprozess | State Model, Transition Ownership, Audit, Change Scenario | Transition Policy; State nur bei Verhaltenskomplexität |
| externer Provider | Boundary, Provider-Leak, Failure Model, Contract | Adapter/ACL; Facade nur bei kohärentem Subsystem |
| Importpipeline | Stage Responsibilities, Error Model, Restartability | Chain/Strategy bei variabler Pipeline |
| Export/Reporting | Read Model Ownership, Formatvarianten, Memory/Performance | Strategy/Builder bei realer Komplexität |
| Kopieren/Versionieren | Copy Policy, Identity, Reset Rules, Invarianten | explizite Copy Policy; Prototype als Denkmodell |
| async Prozess | Boundary, Event Semantics, Handler Responsibility | Domain Event/Observer bewusst; keine versteckten Side Effects |
| mehrere fachliche Typen | Rule Ownership, Change Amplification, Exhaustiveness | Strategy/Polymorphie nur bei stabiler Rolle |
| komplexe UI | Server Truth, lokale State-Grenze, Mapping | Reducer/State Machine lokal bei echter Zustandskomplexität |
| neue gemeinsame Abstraktion | reale Consumer, stabile Rolle, Coupling, YAGNI | erst nach Rule of Three / belegter Shared Boundary |

---

# Gute vs. schlechte Quality-Analyse

## Gute Quality-Analyse

- konsumiert die Impact-Analyse statt sie zu duplizieren,
- beginnt bei Architecture Decisions und Design Pressure,
- referenziert `C-*`, `INV-*`, `R-*` statt parallele Wahrheiten zu erzeugen,
- bewertet Projekt-Fit anhand realer Golden Paths,
- lokalisiert fachliches Wissen,
- prüft belegte Change Scenarios statt abstrakt „OCP“ zu fordern,
- empfiehlt Patterns nur gegen einfachere Alternativen,
- dokumentiert Trade-offs und bewusste Pattern-Ablehnungen,
- erzeugt `Q-*` mit konkreter Evidenz und Planfolge,
- schickt semantische Quality-Planänderungen zurück durch Impact.

## Schlechte Quality-Analyse

- führt die komplette Impact-Analyse ein zweites Mal durch,
- listet SOLID/GoF unabhängig vom Feature auf,
- behandelt jedes Interface als DIP und jede Duplikation als DRY-Verstoß,
- schlägt Strategy/Factory/State ohne belegte Variationsachse vor,
- kopiert Legacy als „Projektstandard“, ohne die fachliche Ähnlichkeit zu prüfen,
- ersetzt einen verständlichen Plan durch ein Abstraktionsframework,
- erzeugt Findings wie „Tests hinzufügen“ oder „SOLID beachten“,
- verändert den Plan semantisch, ohne Impact/Risk/Test-Traceability zu aktualisieren.

---

# Merksatz

Nicht fragen:

> **Welche Coding Principles und Design Patterns können wir hier anwenden?**

Sondern:

> **Welche neuen Architekturentscheidungen führt dieses Feature ein, welcher reale Design-Druck liegt darauf,
> wie passt die Lösung in die bestehende Architektur, und ist jede zusätzliche Abstraktion ihren Preis wert?**
