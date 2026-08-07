# Qualitäts-Analyse — Methodik (Lösungsplan oder Feature-Branch)

Reusable Methodik für den Qualitäts-Review eines Features gegen relevante Coding Principles,
Architekturregeln, Qualitätsanforderungen und Design Patterns. Aufgerufen vom `quality-analysis`-Skill
(`SKILL.md`) bzw. von Commands, die darauf verweisen.

Das Ziel ist **nicht**, möglichst viele Prinzipien oder Patterns zu erwähnen. Das Ziel ist, aus dem
konkreten Feature-Kontext diejenigen Prüfungen abzuleiten, die für eine hochwertige Business-Applikation
tatsächlich relevant sind, Lücken nachzuweisen und ein belastbares Ergebnis zu formulieren.

> **WICHTIG:** Dieser Workflow erstellt/verbessert einen Lösungsplan (Plan-Modus) bzw. weist Qualitäts-
> lücken im Code nach (Branch-Modus). Er implementiert das Feature nicht, sofern nicht ausdrücklich verlangt.

---

## Modus: Review-Gegenstand (Lösungsplan oder Feature-Branch)

Diese Methodik gilt für **zwei** Review-Gegenstände. Regeln, Qualitätsprofile, Prinzipien-Prüfungen,
Pattern-Fit-Analyse und Findings-Bewertung sind **identisch** — nur der geprüfte Gegenstand und die
mode-spezifischen Schritte (1, 9, 12, 13) unterscheiden sich:

| Modus | Review-Gegenstand | Zeitpunkt |
|-------|-------------------|-----------|
| **Plan-Modus** | der `## Lösungsplan` aus dem Task-File (Text) | vor der Implementierung |
| **Branch-Modus** | der tatsächliche Code-Diff des Feature-Branches (`git diff $(git merge-base HEAD develop)..HEAD`) | nach der Implementierung |

Der aufrufende Skill/Command (`quality-analysis` → `SKILL.md`, Schritt A) bestimmt den Modus. Im Fließtext
steht **„Review-Gegenstand"** für „Plan **oder** implementierter Code". Wo ein Schritt nur einen Modus
betrifft, ist das mit **„Nur Plan-Modus"** bzw. **„Nur Branch-Modus"** markiert.

---

## Qualitätsziel

Der geprüfte Lösungsplan muss mindestens folgende Eigenschaften erreichen:

1. **fachlich korrekt** und mit den Akzeptanzkriterien vereinbar
2. **vollständig genug**, damit die Implementierung keine wesentlichen Architekturentscheidungen
   improvisieren muss
3. **einfach**, ohne spekulative Abstraktionen
4. **konsistent mit der bestehenden Architektur und Fachsprache**
5. **sicher**, insbesondere bei Autorisierung, Mandantentrennung und Eingabedaten
6. **transaktional und datenintegritätsfest**
7. **testbar und beobachtbar**
8. **rückwärtskompatibel**, sofern bestehende Verträge oder Daten betroffen sind
9. **wartbar**, mit hoher Kohäsion und kontrollierter Kopplung
10. **begründet**, sodass jede wesentliche Entscheidung auf Repository-Evidenz, einer Anforderung oder
    einem konkret aktivierten Qualitätsprinzip basiert

---

# Verbindliche Arbeitsregeln

## 1. Evidenz vor Vermutung

Behaupte nichts über Architektur, Datenfluss oder vorhandene Abstraktionen, ohne den relevanten Code,
Tests, Dokumentation oder die Git-Historie gelesen zu haben.

- Lies referenzierte Klassen vollständig genug, um ihre Verantwortung zu verstehen.
- Verfolge relevante Aufrufer und Konsumenten.
- Suche nach bereits vorhandenen Lösungen für vergleichbare Features.
- Prüfe widersprechende Tests und Implementierungen; rationalisiere sie nicht als „toten Code“ weg.
- Dokumentiere Unsicherheit sichtbar, statt Lücken mit plausibel klingenden Annahmen zu füllen.

## 2. Prinzipien sind kontextabhängige Prüfregeln

Prüfe nicht blind jedes bekannte Prinzip. Aktiviere ein Prinzip nur, wenn mindestens einer dieser Punkte
zutrifft:

- Der Artefakttyp fällt in seinen Anwendungsbereich.
- Die geplante Änderung erzeugt das zugehörige Risiko.
- Ein konkretes Code-Signal deutet auf das Problem hin.
- Eine bestehende Architekturregel fordert die Prüfung.
- Das Prinzip ist als Mandatory Gate definiert.

## 3. Design Patterns sind keine Zielvorgabe

Ein Design Pattern darf nur empfohlen werden, wenn:

1. ein konkretes, wiederkehrendes Designproblem nachgewiesen ist,
2. das Pattern dieses Problem besser löst als eine einfachere lokale Lösung,
3. die zusätzliche Abstraktion die wahrscheinliche Änderungsrichtung unterstützt,
4. das Pattern zur bestehenden Architektur passt,
5. Kosten, Nachteile und Alternativen dokumentiert werden.

**Pattern-Namen ohne nachgewiesenen Problemdruck sind kein Qualitätsmerkmal.**

## 4. Bestehende Projektentscheidungen zuerst

Die Rangfolge der Quellen ist:

1. fachliche Anforderung und Akzeptanzkriterien
2. Sicherheits-, Datenschutz- und Datenintegritätsanforderungen
3. bestehende ADRs, Architekturregeln und explizite Teamkonventionen
4. etablierte Muster im aktuellen Bounded Context beziehungsweise Modul
5. allgemeine Coding Principles und Design Patterns
6. persönliche Stilpräferenzen

Eine allgemeine Empfehlung darf eine bewusste projektspezifische Entscheidung nicht stillschweigend
überschreiben. Konflikte müssen sichtbar gemacht werden.

## 5. Mandatory Gates sind nicht verhandelbar

Folgende Bereiche müssen bei Relevanz immer geprüft werden:

- fachliche Invarianten
- Autorisierung und Object-Level Authorization
- Tenant-/Mandantentrennung
- Datenintegrität und Transaktionsgrenzen
- Status- und Workflow-Konsistenz
- Rückwärtskompatibilität bestehender Verträge und Daten
- Fehler- und Retry-Verhalten externer beziehungsweise asynchroner Operationen
- Regressionstests bei Bugfixes
- Schutz sensibler Daten

## 6. Kein mechanisches DRY

Unterscheide:

- identischen Text
- syntaktisch ähnlichen Code
- zufällig ähnliche Implementierung
- mehrfach gepflegtes **fachliches Wissen**

Nur die letzte Kategorie ist automatisch ein starker DRY-Kandidat. Eine Abstraktion, die zwei heute
ähnliche, aber fachlich unabhängige Abläufe koppelt, verschlechtert die Wartbarkeit.

---

# Workflow

## Schritt 1: Task und Lösungsplan identifizieren

### 1.1 Argument auswerten

```bash
# Falls kein Argument übergeben wurde
CURRENT_BRANCH=$(git branch --show-current)
echo "$CURRENT_BRANCH"
```

Ermittle daraus, soweit möglich:

- Ticket-Nummer
- Task-File
- Feature-Name
- vorhandenen Lösungsplan
- zugehörigen Branch

### 1.2 Task-/Plan-Datei suchen

```bash
# Beispiele
find docs/tasks docs/plans -maxdepth 2 -type f 2>/dev/null \
  | grep -iE "<TICKET-NUMMER>|<FEATURE-SUCHBEGRIFF>"
```

Falls ein Task-File existiert:

- lies mindestens die Abschnitte zu Problem, Ziel, Akzeptanzkriterien, Lösungsplan, offenen Fragen,
  Impact-Analyse und Testanforderungen;
- verwende `## Lösungsplan` als primären Review-Gegenstand;
- berücksichtige vorhandene Impact-Analysen, aber verifiziere ihre für den Plan relevanten Aussagen.

### 1.3 Fehlenden Plan behandeln

Falls kein expliziter Lösungsplan existiert:

- rekonstruiere **keinen vollständigen Plan aus bloßen Vermutungen**;
- sammle zuerst Problem, Ziel, Akzeptanzkriterien und Repository-Evidenz;
- erstelle anschließend einen ersten Lösungsplan und kennzeichne ihn als `Initialer Lösungsplan`;
- führe denselben Qualitätsreview gegen diesen Plan durch.

### 1.4 Nur Branch-Modus: Review-Gegenstand ist der Code-Diff

Statt (oder zusätzlich zu) `## Lösungsplan` ist der Review-Gegenstand der tatsächliche Diff:

```bash
MERGE_BASE=$(git merge-base HEAD develop)
git diff --name-only $MERGE_BASE..HEAD
git diff $MERGE_BASE..HEAD
```

Prüfe den **implementierten Code** gegen dieselben Schritte 2–11. Ein vorhandener Lösungsplan bzw. eine
Impact-Analyse dient als Soll-Vorgabe; jede Abweichung Code↔Plan ist selbst ein Finding.

---

## Schritt 2: Fachlichen Auftrag und Grenzen verstehen

Extrahiere und dokumentiere:

| Dimension | Zu ermittelnde Information |
|-----------|----------------------------|
| Problem | Welches beobachtbare fachliche Problem wird gelöst? |
| Zielzustand | Welches Verhalten soll nach der Änderung gelten? |
| Akzeptanzkriterien | Welche Fälle müssen nachweislich funktionieren? |
| Nicht-Ziele | Was soll ausdrücklich nicht verändert werden? |
| Nutzer/Rollen | Wer löst den Use Case aus und wer sieht die Auswirkungen? |
| Geschäftsobjekte | Welche Aggregate, Entities, Value Objects oder Read Models sind betroffen? |
| Lebenszyklus | Werden Status, Freigaben, Versionen oder Übergänge verändert? |
| Daten | Welche Daten werden gelesen, erzeugt, geändert, kopiert oder gelöscht? |
| Verträge | Welche APIs, Events, Commands, Queries, DTOs oder Exporte ändern sich? |
| Kritikalität | Welche Folgen hätten Fehler: Anzeige, Datenverlust, Compliance, Finanzen, Berechtigung? |

Formuliere danach in maximal fünf Sätzen ein **fachliches Wirkungsmodell** des Features. Dieses Modell
ist die Referenz für alle weiteren Prüfungen.

---

## Schritt 3: Repository-Evidenz sammeln

### 3.1 Geplante Dateien und Symbole ermitteln

Extrahiere aus dem Lösungsplan:

- Dateien
- Klassen und Interfaces
- Methoden
- Commands und Queries
- Events
- Tabellen und Properties
- Frontend-Komponenten
- Tests

Suche zusätzlich nach fachlichen Begriffen, Property-Namen, Enum-Werten und vergleichbaren Use Cases:

```bash
# Exakte Symbole
rg -n "<ClassName>|<methodName>|<propertyName>" src tests e2e docs

# Fachbegriff und Synonyme
rg -ni "<feature-term>|<domain-synonym>" src tests e2e docs
```

### 3.2 Datenfluss vollständig verfolgen

Für jedes zentrale Feld beziehungsweise Geschäftsobjekt:

1. alle Writer finden,
2. alle Reader finden,
3. Validierung und Autorisierung finden,
4. Persistenz und Datenbank-Constraints prüfen,
5. Berechnungs-/Darstellungsschicht lesen,
6. Kopier-, Import-, Versions- und Hintergrundprozesse berücksichtigen.

Suche nach dem **Property-Namen**, nicht nur nach Setter-Methoden:

```bash
rg -n "<propertyName>" src tests e2e
```

### 3.3 Vergleichbare bestehende Implementierungen suchen

Suche mindestens einen ähnlichen Use Case und beantworte:

- Welche Schichten und Artefakte verwendet er?
- Welche Architekturentscheidung ist dort etabliert?
- Ist die Ähnlichkeit fachlich oder nur technisch?
- Sollte das neue Feature demselben Muster folgen?
- Gibt es bekannte Schwächen, die nicht kopiert werden sollten?

### 3.4 Historische Designentscheidungen prüfen

Für jede geplante Kerndatei:

```bash
git log --all --oneline --follow <PATH/TO/FILE> | head -20
git log --all --oneline --follow <PATH/TO/FILE> \
  | grep -iE "[A-Z]+-[0-9]+" | head -20
```

Bei relevanten Commits:

```bash
git show <COMMIT> -- <PATH/TO/FILE>
```

Dokumentiere nicht nur das Commit-Subject, sondern die erkannte Designintention. Passe den Plan an,
wenn er eine frühere fachliche Regel oder einen bewussten Trade-off unbeabsichtigt überschreiben würde.

### 3.5 Architektur- und Qualitätsdokumente lesen

Suche nach:

```bash
find docs -type f | grep -iE "adr|architecture|coding|quality|security|testing|convention|cqrs|domain"
```

Lies nur relevante Dokumente, aber ignoriere sie nicht zugunsten allgemeiner Best Practices.

---

## Schritt 4: Feature und Plan klassifizieren

Erstelle eine Klassifikation. Mehrfachzuordnungen sind ausdrücklich erlaubt.

### 4.1 Änderungstyp

- neues Feature
- Bugfix
- fachliche Regeländerung
- Refactoring
- API-/Contract-Änderung
- Datenmodell-/Migrationsänderung
- Berechtigungsänderung
- Status-/Workflow-Änderung
- Integration mit externem System
- asynchrone Verarbeitung
- Performance-Änderung
- UI-/Formularänderung

### 4.2 Betroffene Architekturschichten

- Presentation / Frontend
- API / Controller
- Application / Use Cases
- Domain
- Persistence
- Integration / Messaging
- Reporting / Read Model
- Betrieb / Observability

### 4.3 Betroffene Artefakttypen

- Entity / Aggregate
- Value Object
- Domain Service
- Command / Query
- Command Handler / Query Handler
- Controller / Endpoint
- DTO / API Contract
- Repository / Specification
- Event / Event Handler
- Workflow / State Machine
- Migration / Datenbank-Constraint
- React Component / Form
- Unit-, Integration-, Contract- oder E2E-Test

### 4.4 Risikoklassen

- ungültiger fachlicher Zustand
- unautorisierte Änderung
- Tenant-Datenleck
- Datenverlust oder Teilpersistenz
- doppelte Verarbeitung
- Race Condition / Lost Update
- Breaking Change
- inkonsistente Read-/Write-Semantik
- falsche Berechnung
- unvollständige Migration
- Performance-/Skalierungsproblem
- versteckte Seiteneffekte
- nichtdeterministische Tests
- unzureichende Beobachtbarkeit

### 4.5 Ergebnis dokumentieren

```markdown
### Plan-Klassifikation

| Dimension | Ergebnis | Begründung / Evidenz |
|-----------|----------|----------------------|
| Änderungstyp | ... | ... |
| Schichten | ... | ... |
| Artefakte | ... | ... |
| Risiken | ... | ... |
| Kritikalität | niedrig / mittel / hoch / kritisch | ... |
```

---

## Schritt 5: Qualitätsprofile aktivieren

Aktiviere aus der Klassifikation nur die passenden Profile. `global-quality` ist immer aktiv.

| Profil | Aktivierungssignale | Zentrale Prüfungen |
|--------|---------------------|--------------------|
| `global-quality` | immer | Correctness, KISS, Klarheit, Namen, Kohäsion, Kopplung, Seiteneffekte, Testbarkeit |
| `domain-model` | Entity, Aggregate, Value Object, fachliche Berechnung | Invarianten, Ubiquitous Language, Encapsulation, Information Expert, ungültige Zustände |
| `application-use-case` | Command/Handler/Application Service | Use-Case-Grenze, Orchestrierung, Abhängigkeiten, Transaktion, Autorisierung |
| `cqrs-command` | schreibender Use Case | Command-Semantik, keine Query-Seiteneffekte, atomare Änderung, Idempotenz |
| `cqrs-query` | lesender Use Case | keine Mutation, passendes Read Model, Query-Performance, Datenfilter |
| `business-workflow` | Status, Freigabe, Lebenszyklus | erlaubte Transitionen, Guards, Actions, Audit, Konkurrenz |
| `persistence` | Repository, ORM, SQL, Entity Mapping | Constraints, N+1, Locking, Transaktion, Datenverantwortung |
| `api-contract` | Endpoint, DTO, Event Schema | Vertrag, Validierung, Fehlerformat, Versionierung, Kompatibilität |
| `external-integration` | HTTP/API/Datei/Queue | Adaptergrenze, Timeout, Retry, Idempotenz, Circuit Breaker, Fehler-Mapping |
| `security` | Nutzer-, Objekt- oder Mandantenbezug | Deny by Default, Least Privilege, Object-Level Authorization, Tenant Isolation |
| `frontend-form` | React/Formular/Client-Validierung | UX, autoritative Serverregel, Zustandsmodell, Fehlermapping, keine Fachlogik-Duplikation |
| `migration` | Schema-/Datenänderung | Expand/Contract, Bestandsdaten, Rollback/Rollforward, Constraints, Lock-Risiko |
| `event-handler` | Events oder asynchrone Handler | At-Least-Once, Duplicate Handling, Outbox/Inbox, Reihenfolge, Retry Safety |
| `testing` | immer | passender Testtyp, Regression, Isolation, Determinismus, negative Fälle |
| `observability` | kritischer Prozess/Integration | strukturierte Logs, Korrelation, Metriken, auditierbare Fachaktion |

Dokumentiere die Aktivierung:

```markdown
### Aktivierte Qualitätsprofile

| Profil | Aktiviert durch | Betroffene Planschritte |
|--------|-----------------|-------------------------|
| ... | ... | ... |
```

---

# Schritt 6: Coding-Principles-Review

Prüfe jeden Planschritt gegen die aktivierten Profile. Erwähne ein Prinzip nur dann, wenn es eine
konkrete Entscheidung bestätigt, eine Lücke aufdeckt oder einen Trade-off erklärt.

## 6.1 Globale Qualitätsprinzipien

### KISS und Clarity over Cleverness

Prüfe:

- Ist die vorgeschlagene Lösung die einfachste Lösung, die alle Anforderungen und Risiken abdeckt?
- Enthält der Plan unnötige Abstraktionen, generische Frameworks oder indirekte Aufrufketten?
- Wird fachliche Bedeutung durch technische Cleverness verdeckt?
- Könnte ein neuer Entwickler den Ablauf anhand der Artefakte und Namen verstehen?

### YAGNI und Rule of Three

Prüfe:

- Werden Varianten unterstützt, die nicht Teil der Anforderungen oder einer belegten nahen Roadmap sind?
- Wird eine Abstraktion nur für eine hypothetische spätere Wiederverwendung eingeführt?
- Gibt es tatsächlich mehrere fachlich gleichartige Fälle oder nur eine einzelne Implementierung?

### DRY als Single Source of Business Truth

Prüfe:

- Wo liegt die autoritative fachliche Regel?
- Wird dasselbe fachliche Prädikat an mehreren Stellen aus primitiven Bedingungen nachgebaut?
- Können Frontend, Backend, Berechnung und Persistenz semantisch auseinanderlaufen?
- Ist eine scheinbare Duplikation bewusst erforderlich, beispielsweise Client-Validierung plus
  serverseitige autoritative Validierung?

### Separation of Concerns, High Cohesion, Low Coupling

Prüfe:

- Ist jede Verantwortung in der fachlich und architektonisch passenden Schicht?
- Muss eine Änderung am Feature unnötig viele unabhängige Module ändern?
- Kennt Domain-Code Infrastrukturdetails?
- enthält ein Controller Fachlogik oder ein Repository UI-/Use-Case-Logik?
- Werden zusammengehörige Regeln zu weit verteilt?

### Explicit over Implicit und Principle of Least Astonishment

Prüfe:

- Sind Seiteneffekte, Statusänderungen, Transaktionen und Events im Plan sichtbar?
- Wird Verhalten durch versteckte Listener, globale Zustände oder magische Konventionen ausgelöst?
- Entsprechen Namen und API-Verhalten den Erwartungen der bestehenden Codebasis?

### Correctness before Optimization

Prüfe:

- Ist eine Performance-Komplexität durch Messdaten oder ein realistisches Lastprofil begründet?
- Wird fachliche Korrektheit für Mikrooptimierungen geopfert?
- Enthält der Plan eine Mess- und Regressionstrategie, falls Performance das Ziel ist?

---

## 6.2 SOLID und objektorientierte Verantwortungen

### Single Responsibility Principle

Prüfe den **Änderungsgrund**, nicht bloß Methoden- oder Klassengröße:

- Hat eine Klasse mehrere unabhängige fachliche oder technische Änderungsgründe?
- Vermischt ein Handler Orchestrierung, Berechnung, Mapping und Persistenzdetails?
- Würden unterschiedliche Stakeholder dieselbe Klasse aus unterschiedlichen Gründen ändern?

### Open/Closed Principle

Prüfe nur bei belegten Varianten:

- Ist eine bekannte, wiederkehrende Variationsachse vorhanden?
- Erfordert jede neue Variante Änderungen an vielen bestehenden Bedingungen?
- Würde Polymorphie oder eine Strategy die Änderung lokalisieren?

Vermeide spekulative Plugin-Architekturen für einmalige Varianten.

### Liskov Substitution Principle

Prüfe bei Vererbung und Interface-Implementierungen:

- Verstärkt ein Untertyp Vorbedingungen oder schwächt Garantien?
- Wirft eine Implementierung für reguläre Interface-Operationen `UnsupportedOperationException`?
- Verändert ein Untertyp die erwartete Semantik?

### Interface Segregation Principle

Prüfe:

- Müssen Konsumenten Methoden kennen, die sie nicht benötigen?
- Ist ein Interface nach einem technischen Sammelbegriff statt nach einer Rolle geschnitten?
- Würden kleine, use-case-orientierte Ports die Abhängigkeit klarer machen?

### Dependency Inversion Principle

Prüfe:

- Hängt Fach-/Application-Code direkt von Framework, HTTP-Client, Dateisystem oder konkretem Provider ab?
- Ist eine Abstraktion tatsächlich eine fachlich beziehungsweise architektonisch stabile Grenze?
- Wird ein Interface nur erzeugt, um „SOLID zu erfüllen“, obwohl keine Austausch- oder Testgrenze besteht?

---

## 6.3 Fachmodell und Invarianten

Prüfe:

- Sind fachliche Regeln bei dem Objekt oder Service angesiedelt, das die nötigen Informationen besitzt?
- Kann ein Objekt in einem ungültigen Zustand konstruiert oder nachträglich versetzt werden?
- Werden primitive Strings/Ints verwendet, obwohl ein Value Object relevante Regeln und Bedeutung trägt?
- Gibt es öffentliche Setter, die Invarianten umgehen?
- Werden fachliche Aktionen (`approve()`, `submit()`, `cancel()`) statt technisch beliebiger Mutationen
  (`setStatus()`) geplant?
- Sind Nullability und optionale Zustände fachlich erklärt?
- Sind Berechnungs- und Rundungsregeln zentral und testbar?

Aktiviere insbesondere:

- Encapsulation
- Information Expert
- Tell, Don’t Ask
- Make Invalid States Unrepresentable
- Design by Contract
- Favor Immutability
- Ubiquitous Language

---

## 6.4 Application Layer und CQRS

Prüfe:

- Repräsentiert der Command beziehungsweise Handler genau einen erkennbaren Use Case?
- Ist der Command ein expliziter Eingabevertrag und nicht Träger versteckter Fachlogik?
- Verändert eine Query wirklich keinen Zustand?
- Befindet sich die Transaktionsgrenze um den gesamten fachlich atomaren Use Case?
- Erfolgt Autorisierung vor Mutation und auf dem konkreten Geschäftsobjekt?
- Liegt komplexe Fachlogik im Domain-Modell statt im Controller oder Mapping-Code?
- Ist der Handler bei Retry beziehungsweise doppeltem Request sicher, wenn dies realistisch ist?
- Werden Domain Events erst in konsistentem Zusammenhang mit der Persistenz veröffentlicht?

---

## 6.5 Statusmodelle und Workflows

Aktiviere dieses Gate bei Enums, Status-Properties, Freigaben, Versionen oder Lebenszyklen.

Prüfe:

- Sind erlaubte Übergänge explizit definiert?
- Gibt es eine zentrale fachliche Benennung für Transition-Prädikate?
- Sind Guards, Berechtigungen und fachliche Vorbedingungen getrennt und vollständig?
- Sind Seiteneffekte eines Übergangs explizit?
- Kann ein allgemeiner Setter die Transition-Logik umgehen?
- Sind konkurrierende Transitionen abgesichert, beispielsweise per Version/Optimistic Lock?
- Wird dokumentiert, wer wann welche fachliche Aktion ausgeführt hat?
- Werden neue Enum-Werte in allen Writer-, Reader-, Mapping-, Anzeige-, Export- und Testpfaden behandelt?

---

## 6.6 Persistenz und Datenintegrität

Prüfe:

- Welche Regeln müssen zusätzlich als Datenbank-Constraint erzwungen werden?
- Ist die fachliche Transaktion atomar?
- Können konkurrierende Requests Lost Updates erzeugen?
- Ist ein Unique Constraint NULL-sicher und mandantenbezogen korrekt?
- Sind ORM-Cascade, Orphan Removal und Lifecycle Hooks bewusst eingesetzt?
- Entsteht N+1 oder unnötiges vollständiges Entity-Hydrating?
- Ist eine Query auf den benötigten Use Case zugeschnitten?
- Bleiben Domain und Application Layer von konkreter Persistenztechnik entkoppelt, soweit es einen
  realen Nutzen gibt?

---

## 6.7 APIs, DTOs und Integrationen

Prüfe:

- Ist der externe beziehungsweise interne Vertrag explizit?
- Sind Pflichtfelder, optionale Felder und Null-Semantik eindeutig?
- Ist die Änderung rückwärtskompatibel?
- Ist das Fehlerformat stabil und werden interne Exceptions nicht veröffentlicht?
- Werden Eingaben an der Trust Boundary geparst und validiert?
- Sind Timeout, Retry, Backoff und Fehler-Mapping für externe Systeme geplant?
- Ist eine wiederholte Operation idempotent oder mit einem Idempotency Key geschützt?
- Sind Provider-spezifische Modelle hinter einem Adapter isoliert?
- Werden Events transaktional sicher publiziert, falls Datenänderung und Nachricht zusammengehören?

---

## 6.8 Security und Mandantentrennung

Dieses Profil ist ein Mandatory Gate, sobald Nutzer, Rollen, Mandanten oder geschützte Geschäftsobjekte
betroffen sind.

Prüfe:

- Deny by Default
- Least Privilege
- Object-Level Authorization
- Complete Mediation bei jedem relevanten Zugriff
- Tenant-Filter in Reads **und** Writes
- Schutz vor manipulierbaren IDs und Mass Assignment
- serverseitige Durchsetzung unabhängig vom Frontend
- keine sensiblen Daten in Logs, Events oder Fehlermeldungen
- Auditierbarkeit kritischer Aktionen
- Datenminimierung bei DTOs, Exports und Events

Ein globaler Rollencheck ersetzt keinen objektbezogenen Berechtigungscheck.

---

## 6.9 Frontend und Formulare

Prüfe:

- Spiegelt das Frontend den Use Case klar wider, ohne die autoritative Fachregel zu übernehmen?
- Werden Serverfehler stabil auf Felder beziehungsweise allgemeine Fehler gemappt?
- Sind Lade-, Fehler-, Leer- und Disabled-Zustände geplant?
- Verhindert UI-State doppelte Requests oder muss das Backend trotzdem idempotent sein?
- Werden Enums und Statusoptionen aus einer stabilen Quelle abgeleitet?
- Werden Berechtigungen nicht nur optisch verborgen, sondern serverseitig erzwungen?
- Ist komplexe Zustandslogik lokal kohärent oder sollte sie in Hook/Reducer/State Machine extrahiert werden?

---

## 6.10 Tests und Qualitätsnachweise

Ordne jeder geplanten Regel den passenden Nachweis zu:

| Änderung | Mindestnachweis |
|----------|-----------------|
| fachliche Invariante | fokussierter Domain-/Unit-Test |
| Command Handler | Use-Case-/Integrationstest |
| Repository Query | DB-Integrationstest mit relevanten Varianten |
| API Contract | API-/Contract-Test einschließlich Fehlerfällen |
| Berechtigung | positiver und negativer Security-Test |
| Mandantentrennung | Cross-Tenant-Negativtest |
| Statusübergang | erlaubte und verbotene Transitionen |
| Bugfix | zuerst reproduzierender Regressionstest |
| Migration | Test mit realistischen Bestands- und Randdaten |
| Event Handler | Duplikat-, Retry- und Reihenfolgetest |
| kritischer End-to-End-Ablauf | gezielter E2E-Test, nicht als Ersatz für tiefere Tests |

Prüfe zusätzlich:

- Determinismus
- Isolation
- Verhalten statt Implementierungsdetails
- relevante Grenzwerte und Äquivalenzklassen
- widersprechende beziehungsweise bereits bestehende Tests
- Testdaten, die Mandanten-, Rollen-, Typ- und Statusvarianten abdecken

---

# Schritt 7: Design-Pattern-Fit-Analyse

Refactoring.Guru gruppiert die klassischen Design Patterns nach ihrer Absicht in **Erzeugungs-**,
**Struktur-** und **Verhaltensmuster**. Verwende den folgenden Katalog als Hypothesengenerator, nicht als
Pflichtliste.

## 7.1 Pattern-Suitability-Gate

Für jeden Pattern-Kandidaten müssen diese Fragen beantwortet werden:

1. **Welches konkrete Problem liegt vor?**
2. **Welche Repository-Evidenz belegt das Problem?**
3. **Ist das Problem wiederkehrend oder nur einmalig?**
4. **Welche einfachere Lösung wurde geprüft?**
5. **Welche wahrscheinliche Änderungsachse stabilisiert das Pattern?**
6. **Welche zusätzliche Komplexität, Indirektion und Testlast entstehen?**
7. **Ist das Pattern im Projekt bereits vorhanden oder durch Framework/Container abgedeckt?**
8. **Welche Coding Principles werden dadurch verbessert und welche möglicherweise verschlechtert?**
9. **Wie würde das Pattern konkret in den geplanten Klassen aussehen?**
10. **Was wäre das Signal, das Pattern wieder zu entfernen oder nicht einzuführen?**

Ohne konkrete Antworten lautet die Entscheidung: **Pattern nicht einführen**.

---

## 7.2 Erzeugungsmuster

| Pattern | Aktivierungssignale | Typische Business-Anwendung | Ablehnungs-/Warnsignale |
|---------|---------------------|-----------------------------|-------------------------|
| **Factory Method** | Objekttyp hängt von fachlicher Variante ab; Konstruktion soll lokal austauschbar sein | Erzeugen unterschiedlicher Importer, Exporter oder fachlicher Strategien | Nur ein Produkttyp; Factory verbirgt lediglich einen einfachen Konstruktor |
| **Abstract Factory** | Familien zusammengehöriger Objekte müssen konsistent erzeugt werden | Provider-spezifische Client-, Mapper- und Validator-Familien | Einzelne unabhängige Objekte; zu große abstrakte Provider-Plattform |
| **Builder** | komplexe schrittweise Konstruktion, viele optionale Teile oder valide Varianten | komplexe Reports, Requests, Test-Fixtures, immutable Konfiguration | Einfaches DTO/Value Object; Builder erlaubt ungültige Zwischen-/Endzustände |
| **Prototype** | bestehendes Objekt wird fachlich kopiert beziehungsweise versioniert | Versionierung, „als Entwurf kopieren“, Vorlagen | Identitäten, Referenzen und Invarianten werden blind kopiert; Copy-Semantik unklar |
| **Singleton** | exakt eine prozessweite Instanz mit legitimem globalem Lebenszyklus | selten; meist durch DI-Container-Lifecycle ersetzt | globaler veränderlicher Zustand, versteckte Abhängigkeit, Test-Isolationsprobleme |

### Pflichtprüfung bei Factory/Builder

Bevor eine Factory oder ein Builder eingeführt wird:

- Prüfe benannte Konstruktoren, Value Objects und einfache DI.
- Prüfe, ob die Konstruktion selbst fachliche Regeln enthält oder nur Mapping ist.
- Stelle sicher, dass jede erzeugte Instanz bereits valide ist.

### Pflichtprüfung bei Prototype

Definiere explizit:

- Welche Felder werden kopiert?
- Welche Identitäten werden neu erzeugt?
- Welche Beziehungen werden übernommen?
- Welche Status-/Auditfelder werden zurückgesetzt?
- Welche Regeln unterscheiden Kopieren, Versionieren und Duplizieren?

---

## 7.3 Strukturmuster

| Pattern | Aktivierungssignale | Typische Business-Anwendung | Ablehnungs-/Warnsignale |
|---------|---------------------|-----------------------------|-------------------------|
| **Adapter** | inkompatible externe oder Legacy-Schnittstelle | Provider-API auf internen Port abbilden, Legacy-DTO normalisieren | interne Fachmodelle werden ungefiltert zu Provider-Modellen; Adapter enthält Geschäftsprozess |
| **Bridge** | zwei unabhängige Variationsachsen wachsen getrennt | Dokumenttyp × Ausgabeformat oder Fachprozess × Ausführungskanal | nur eine Achse oder wenige feste Kombinationen; unnötige Doppelhierarchie |
| **Composite** | echte Teil-Ganzes-/Baumstruktur mit einheitlichen Operationen | Organisationsbaum, Regelbaum, verschachtelte Kriterien | flache Liste; Unterschiede zwischen Blatt und Container werden künstlich verdeckt |
| **Decorator** | optionale, kombinierbare Querschnittsverhalten um einen stabilen Port | Logging, Caching, Metriken, Retry, Berechtigungs-/Validierungsschicht | Reihenfolge unklar; Fachlogik über viele Wrapper verteilt; Framework-Middleware reicht aus |
| **Facade** | komplexes Subsystem braucht einen kleinen use-case-orientierten Zugang | vereinfachter Zugriff auf Reporting-, Dokument- oder Fremdsystem-Subsystem | „God Service“, der unabhängige Use Cases und Fachlogik zentralisiert |
| **Flyweight** | sehr große Zahl ähnlicher Objekte mit messbarem Speicherproblem | selten in Business-Apps, etwa große immutable Referenzdaten | keine Messdaten; zusätzliche Identitäts-/State-Komplexität für Mikrooptimierung |
| **Proxy** | kontrollierter Zugriff, Lazy Loading, Remote, Cache oder Security-Hook | Remote-Service-Proxy, Cache-Proxy, Zugriffskontrolle | ORM/Framework stellt Proxy bereits bereit; versteckte Remote-Aufrufe oder überraschende Latenz |

### Integrationsregel

Bei externer API ist `Adapter` der Standardkandidat, wenn Provider-Typen sonst in Application/Domain
leaken. `Facade` kann zusätzlich sinnvoll sein, wenn mehrere Adapter/Services in einer stabilen,
vereinfachten Subsystem-Schnittstelle orchestriert werden. Die Facade darf dabei keine fachliche
God-Class werden.

---

## 7.4 Verhaltensmuster

| Pattern | Aktivierungssignale | Typische Business-Anwendung | Ablehnungs-/Warnsignale |
|---------|---------------------|-----------------------------|-------------------------|
| **Chain of Responsibility** | variable Pipeline unabhängiger Handler/Prüfungen | Validierungs-, Normalisierungs- oder Importpipeline | feste kurze Sequenz; Kontrollfluss und Fehlerpriorität werden unklar |
| **Command** | Aktion soll als explizites Objekt transportiert, geplant oder geloggt werden | CQRS Command, Job, Queue-Nachricht, Undo-fähige Aktion | Projekt nutzt Commands bereits; keine zusätzliche parallele Command-Abstraktion erfinden |
| **Iterator** | Traversierung soll Collection-Interna verbergen | fachliche Collection mit spezieller Reihenfolge/Filterung | normale Array-/Collection-Iteration reicht aus |
| **Mediator** | viele Komponenten kommunizieren chaotisch direkt miteinander | Message Bus, Application Bus, Dialog-/Workflow-Koordination | zusätzlicher Mediator neben vorhandenem Bus; zentraler God-Mediator |
| **Memento** | Zustand muss später wiederhergestellt werden, ohne Interna offenzulegen | Entwurfs-Snapshot, Undo, fachliche Version | Audit-Log wird mit Wiederherstellung verwechselt; Snapshot ist unvollständig/inkonsistent |
| **Observer** | mehrere unabhängige Reaktionen auf ein Ereignis | Domain Events, Benachrichtigung, Read-Model-Aktualisierung | versteckte synchrone Seiteneffekte; Reihenfolge/Transaktion unklar; Eventual Consistency ungeplant |
| **State** | Verhalten und erlaubte Aktionen ändern sich wesentlich mit dem Zustand | komplexer Freigabe-/Lebenszyklus mit zustandsspezifischem Verhalten | wenige einfache Transitionen; Klassenexplosion; Statusdaten und State-Objekt laufen auseinander |
| **Strategy** | mehrere austauschbare Algorithmen entlang einer fachlichen Variationsachse | Berechnung je Zielvereinbarungstyp, Preis-/Exportstrategie | einzelner `if`; Varianten teilen keine echte Rolle; Strategie braucht zu viel fremden Zustand |
| **Template Method** | stabiler Ablauf mit wenigen variablen Schritten in enger Hierarchie | standardisierter Import-/Exportablauf | Vererbung nur zur Wiederverwendung; Varianten ändern Ablaufstruktur; Composition wäre klarer |
| **Visitor** | stabile Objekthierarchie, aber häufig neue Operationen | Reporting/Export über stabile AST-/Regel-/Dokumentstruktur | Hierarchie ändert sich häufig; Double Dispatch erhöht Komplexität ohne Nutzen |

### State versus Strategy

- **State**: Das Verhalten ändert sich aufgrund des aktuellen Lebenszykluszustands; Transitionen sind Teil
  des Problems.
- **Strategy**: Der Algorithmus wird anhand einer fachlichen Variante oder Konfiguration ausgewählt und
  ist grundsätzlich austauschbar.
- Bei wenigen Statuswerten und einfachen Guards ist eine explizite Transition Policy häufig klarer als
  ein vollständiges State-Pattern.

### Observer- und Event-Regel

Bei Events müssen zusätzlich geprüft werden:

- synchron oder asynchron
- innerhalb oder außerhalb der Transaktion
- garantierte Zustellung
- Reihenfolge
- Duplikate
- Retry
- Fehlerisolation
- Audit versus technische Integration

Ein Event darf keinen kritischen fachlichen Seiteneffekt unsichtbar und ungesichert aus dem Haupt-Use-Case
entfernen.

### Template Method versus Strategy

Bevor `Template Method` vorgeschlagen wird, prüfe `Strategy` beziehungsweise Composition. Vererbung ist
nur dann vorzuziehen, wenn die Basisklasse eine stabile echte „ist-ein“-Beziehung und einen stabilen
Algorithmusrahmen besitzt.

---

## 7.5 Pattern-Signale aus Code Smells

Code Smells sind Hinweise, keine Beweise. Prüfe mindestens folgende Zuordnungen:

| Beobachtung | Mögliche Prinzip-/Pattern-Hypothese | Vor Empfehlung verifizieren |
|-------------|--------------------------------------|-----------------------------|
| wiederholte Switches auf denselben Typ/Enum | zentrale Prädikate, Strategy, State oder Polymorphie | Sind die Varianten fachlich stabil und verhalten sie sich wirklich unterschiedlich? |
| sehr komplexe Konstruktion | Builder, Factory Method, Value Objects | Ist die Komplexität fachlich notwendig oder nur schlechtes Mapping? |
| externe Modelle in Domain/Application | Adapter, Anti-Corruption Layer | Wo ist die tatsächliche Trust-/Provider-Grenze? |
| viele optionale Querschnittsfunktionen | Decorator, Middleware | Ist Reihenfolge relevant und gibt es bereits Framework-Unterstützung? |
| komplexes Subsystem in vielen Aufrufern | Facade | Würde die Facade kohärent bleiben oder zur God-Class wachsen? |
| viele direkte Objekt-zu-Objekt-Abhängigkeiten | Mediator, Domain Events, bessere Modulgrenzen | Ist ein Mediator nötig oder sind Verantwortungen nur falsch geschnitten? |
| Statusabhängige große Bedingungen | State oder Transition Policy | Ändert sich Verhalten oder nur die Erlaubnis einzelner Aktionen? |
| viele ähnliche Algorithmen | Strategy | Ist die Variationsachse benennbar und austauschbar? |
| Shotgun Surgery | Kohäsion, DRY des Fachwissens, bessere Boundary | Welche eine Regel ist tatsächlich verteilt? |
| Feature Envy | Information Expert, Move Method | Welches Objekt besitzt die nötigen Informationen und Invarianten? |
| Primitive Obsession | Value Object, Replace Type Code | Enthält der Primitive echte Bedeutung, Regeln oder Einheiten? |
| Speculative Generality | YAGNI, Remove Indirection | Welche reale Anforderung nutzt die Abstraktion heute? |

---

## 7.6 Pattern-Entscheidung dokumentieren

Für **jeden ernsthaften Kandidaten**:

```markdown
### Pattern-Kandidat: <NAME>

- **Konkretes Problem:** ...
- **Evidenz:** `<datei:zeile>`, vorhandene Varianten, geplanter Änderungsdruck
- **Einfachste Alternative:** ...
- **Nutzen des Patterns:** ...
- **Kosten/Nachteile:** ...
- **Auswirkung auf Prinzipien:** verbessert ..., verschlechtert möglicherweise ...
- **Bestehende Projektunterstützung:** ...
- **Entscheidung:** verwenden / bereits vorhanden nutzen / ablehnen / weitere Evidenz nötig
- **Konkrete Planänderung:** ...
```

Dokumentiere auch bewusst abgelehnte Patterns. Das verhindert, dass die Implementierung später aus
reinem Pattern-Enthusiasmus unnötig komplex wird.

---

# Schritt 8: Trade-offs und Prioritäten auflösen

Wenn Prinzipien kollidieren, nutze folgende Priorität:

1. fachliche Korrektheit und explizite Invarianten
2. Sicherheit, Datenschutz und Mandantentrennung
3. Datenintegrität, Konsistenz und Rückwärtskompatibilität
4. bestehende Architektur- und Modulgrenzen
5. Verständlichkeit und expliziter Kontrollfluss
6. Testbarkeit und Beobachtbarkeit
7. Kohäsion und kontrollierte Kopplung
8. Wiederverwendung und Erweiterbarkeit
9. Performance, sofern nicht gemessen oder fachlich erforderlich
10. formale Pattern-/Prinzipienreinheit

Typische Spannungen, die explizit bewertet werden müssen:

| Spannung | Entscheidungsregel |
|----------|--------------------|
| DRY vs. lokale Verständlichkeit | Fachwissen zentralisieren; zufällig ähnlichen Code nicht koppeln |
| KISS vs. Erweiterbarkeit | Nur belegte Variationsachsen abstrahieren |
| YAGNI vs. erwartete nahe Änderung | Roadmap-/Repository-Evidenz verlangen |
| Fail Fast vs. Graceful Degradation | Invarianten fail fast; externe optionale Funktionen dürfen kontrolliert degradieren |
| Explicit over Implicit vs. Events/Observer | Events nur mit sichtbarer Zustell-, Transaktions- und Fehlersemantik |
| Immutability vs. ORM-Komfort | Fachliche Invarianten priorisieren; technische Hydration bewusst kapseln |
| Normalisierung vs. Read-Performance | Autoritative Quelle behalten; Denormalisierung bewusst und synchronisierbar planen |
| Composition vs. Inheritance | Composition bevorzugen, außer stabile echte Subtypbeziehung und LSP sind belegt |
| Pattern vs. einfache Lösung | Pattern nur bei nachgewiesenem wiederkehrendem Problem |

---

# Schritt 9: Plan-Vollständigkeit prüfen

Ein implementierbarer Lösungsplan muss, soweit relevant, diese Punkte enthalten:

> **Im Branch-Modus:** dieselben Punkte als **Implementierungs-Vollständigkeit** prüfen — ist im Code
> tatsächlich vorhanden, was hier gefordert ist (Migration, Constraints, Fehler-/Retry-Verhalten, Tests,
> Error-Mapping, Rollout)? Fehlendes ist ein Finding.

## 9.1 Fachliche Änderung

- genaue alte und neue Regel
- betroffene Varianten, Typen, Rollen und Status
- unveränderte Fälle
- Rand- und Fehlerfälle

## 9.2 Geplante Artefakte

Für jede neue oder geänderte Datei:

- Pfad beziehungsweise begründeter Zielpfad
- Verantwortung
- zentrale Methoden/Verträge
- Abhängigkeiten
- betroffene bestehende Aufrufer/Konsumenten
- aktivierte Qualitätsprofile

## 9.3 Daten und Persistenz

- Schema-/Mapping-Änderungen
- Constraints
- Datenmigration/Backfill
- Transaktions- und Locking-Strategie
- Kompatibilität während Deployment

## 9.4 API und UI

- Request-/Response-/Event-Vertrag
- Validation und Error Mapping
- Berechtigung
- UI-Zustände
- Backward Compatibility

## 9.5 Events und Integrationen

- Publish-/Consume-Zeitpunkt
- Zustellsemantik
- Idempotenz
- Retry/Timeout
- Fehlerbehandlung
- Observability

## 9.6 Tests

- konkrete Testdateien oder Testebenen
- Fälle als Given/When/Then oder äquivalente Beschreibung
- positive, negative und relevante Varianten
- Regressionstest
- Migrations-/Contract-/Security-Test, falls relevant

## 9.7 Rollout

- Feature Flag, falls nötig
- Expand/Contract-Schritte
- Rückfall-/Rollforward-Strategie
- Monitoring- oder Audit-Signale

---

# Schritt 10: Adversarialer Gegencheck

Führe nach dem ersten Review einen zweiten Durchlauf mit gegenteiliger Zielsetzung aus:

1. Versuche jedes `BLOCKER`- und `HIGH`-Finding zu widerlegen.
2. Suche nach bestehendem Code oder Tests, die zeigen, dass das Risiko bereits abgedeckt ist.
3. Versuche jede Pattern-Empfehlung durch eine einfachere Lösung zu ersetzen.
4. Suche nach einem bestehenden Projektmuster, das besser passt als der allgemeine Pattern-Kandidat.
5. Prüfe, ob die empfohlene Abstraktion nur die heutige Implementierung spiegelt statt eine stabile
   fachliche Achse abzubilden.
6. Prüfe, ob der überarbeitete Plan neue versteckte Seiteneffekte oder zusätzliche Transaktionsgrenzen
   erzeugt.
7. Löse jeden Widerspruch auf oder dokumentiere ihn als offene Entscheidung.

Ein Finding bleibt nur bestehen, wenn es diesen Gegencheck überlebt oder die Unsicherheit explizit als
Risiko dokumentiert wird.

---

# Schritt 11: Findings bewerten

Verwende diese Schweregrade:

| Stufe | Bedeutung |
|-------|-----------|
| `BLOCKER` | Plan kann zu falschen fachlichen Zuständen, Sicherheitsverletzung, Datenverlust oder nicht beherrschbarem Breaking Change führen |
| `HIGH` | wesentliche Architektur-, Integritäts-, Workflow- oder Testlücke vor Implementierung schließen |
| `MEDIUM` | relevante Wartbarkeits- oder Vollständigkeitslücke; sollte im Plan verbessert werden |
| `LOW` | lokale Qualitätsverbesserung ohne wesentliches Systemrisiko |
| `INFO` | bewusster Trade-off, bestätigte gute Entscheidung oder verworfene Alternative |

Jedes Finding muss enthalten:

```markdown
#### <SEVERITY> — <präziser Titel>

- **Planschritt/Artefakt:** ...
- **Aktiviert durch:** Profil, Risiko oder Code-Signal
- **Prinzip/Pattern:** ...
- **Evidenz:** Datei, Symbol, Test, Historie oder Anforderung
- **Konkretes Risiko:** ...
- **Empfohlene Planänderung:** ...
- **Erforderlicher Nachweis/Test:** ...
- **Sicherheit der Bewertung:** hoch / mittel / niedrig
```

Nicht zulässig sind nichtssagende Findings wie:

- „SOLID beachten“
- „Factory Pattern erwägen“
- „Tests hinzufügen“
- „Code sauber halten“

---

# Schritt 12: Überarbeiteten Lösungsplan erstellen

Erstelle aus dem ursprünglichen Plan und den bestätigten Findings einen überarbeiteten Plan.

> **Im Branch-Modus:** statt eines überarbeiteten Plans eine **priorisierte Liste erforderlicher
> Code-Änderungen** erstellen — je Finding: betroffene Datei/Stelle, konkrete Änderung, erforderlicher Test.

Regeln:

- Bewahre die fachliche Zielsetzung.
- Entferne spekulative oder unbegründete Abstraktionen.
- Ergänze fehlende Architektur-, Daten-, Security-, Workflow- und Testschritte.
- Benenne Verantwortungen und Grenzen, nicht jede triviale Codezeile.
- Verweise bei wichtigen Entscheidungen auf das auslösende Finding.
- Wenn mehrere Lösungen legitim sind, formuliere eine explizite Entscheidung mit Trade-off.
- Offene fachliche Fragen dürfen nicht durch technische Annahmen versteckt werden.

Empfohlenes Format:

```markdown
### Überarbeiteter Lösungsplan

#### 1. <fachlicher/technischer Schritt>
- **Ziel:** ...
- **Dateien/Artefakte:** ...
- **Änderung:** ...
- **Invarianten/Security:** ...
- **Pattern/Prinzip-Entscheidung:** ...
- **Tests:** ...
- **Abhängigkeiten/Risiken:** ...

#### 2. ...
```

---

# Schritt 13: Ergebnis dokumentieren

> **Im Branch-Modus:** Abschnitt `## Qualitätsreview (Branch)` statt `## Lösungsplan-Qualitätsreview`;
> „Überarbeiteter Lösungsplan" → „Erforderliche Code-Änderungen"; „Review-Basis" = der Branch-Diff.

## Falls ein Task-File existiert

Füge einen Abschnitt `## Lösungsplan-Qualitätsreview` ein oder aktualisiere ihn. Überschreibe den
ursprünglichen Lösungsplan nicht kommentarlos. Dokumentiere zuerst den Review und danach den
überarbeiteten Plan.

```markdown
## Lösungsplan-Qualitätsreview

**Durchgeführt am:** <DATUM>
**Review-Basis:** `## Lösungsplan` vom <Stand/Commit>
**Repository-Basis:** `<branch/commit>`
**Gesamtentscheidung:** FREIGEGEBEN / FREIGEGEBEN MIT ÄNDERUNGEN / PLAN ÜBERARBEITEN

### 1) Fachliches Wirkungsmodell
...

### 2) Plan-Klassifikation
| Dimension | Ergebnis | Evidenz |
|-----------|----------|---------|
| ... | ... | ... |

### 3) Aktivierte Qualitätsprofile
| Profil | Aktiviert durch | Planschritte |
|--------|-----------------|--------------|
| ... | ... | ... |

### 4) Bestätigte gute Entscheidungen
- ...

### 5) Findings gegen Coding Principles
#### BLOCKER/HIGH/MEDIUM/LOW — ...
...

### 6) Design-Pattern-Fit
| Pattern | Problem/Evidenz | Einfachere Alternative | Entscheidung | Planfolge |
|---------|------------------|------------------------|--------------|-----------|
| ... | ... | ... | verwenden/ablehnen/bestehend | ... |

### 7) Erkannte Code-Smell-/Architekturrisiken
...

### 8) Fehlende Qualitätsnachweise
...

### 9) Überarbeiteter Lösungsplan
...

### 10) Teststrategie
...

### 11) Offene fachliche Entscheidungen
...
```

## Falls kein Task-File existiert

Erstelle:

```text
docs/plans/<TICKET-ODER-FEATURE>_quality-reviewed-plan.md
```

und verwende dasselbe Format.

---

# Schritt 14: Freigabeentscheidung

## `FREIGEGEBEN`

Nur wenn:

- keine offenen `BLOCKER` oder `HIGH` Findings bestehen,
- Mandatory Gates abgedeckt sind,
- der Plan hinreichend implementierbar ist,
- Tests und Risiken konkret beschrieben sind,
- keine unbegründete Pattern-/Abstraktionskomplexität verbleibt.

## `FREIGEGEBEN MIT ÄNDERUNGEN`

Wenn:

- der überarbeitete Plan alle wesentlichen Findings bereits integriert,
- nur dokumentierte `MEDIUM`/`LOW`-Punkte oder klar abgegrenzte Entscheidungen offen sind.

## `PLAN ÜBERARBEITEN`

Wenn:

- fachliche Regeln unklar sind,
- ein Mandatory Gate nicht gelöst ist,
- zentrale Daten-/Workflow-/Security-Auswirkungen fehlen,
- die Lösung auf unbestätigten Architekturannahmen basiert,
- der Plan eine unbegründete komplexe Pattern-Struktur voraussetzt.

---

# Schritt 15: Zusammenfassung ausgeben

```text
🧭 LÖSUNGSPLAN-QUALITÄTSREVIEW: <TICKET/FEATURE>

**Entscheidung:** [FREIGEGEBEN / FREIGEGEBEN MIT ÄNDERUNGEN / PLAN ÜBERARBEITEN]
**Basis:** [Task-File / Plan-File / rekonstruierter Initialplan]
**Kritikalität:** [niedrig / mittel / hoch / kritisch]

## Aktivierte Profile
[Liste]

## Findings
- BLOCKER: <Anzahl>
- HIGH: <Anzahl>
- MEDIUM: <Anzahl>
- LOW: <Anzahl>

## Pattern-Entscheidungen
- Verwendet/bestätigt: [Patterns oder „keine“]
- Bewusst abgelehnt: [Patterns oder „keine“]

## Wichtigste Planänderungen
1. ...
2. ...
3. ...

## Noch offene Entscheidungen
[Anzahl und Kurzbeschreibung]

📄 Dokumentiert in: <PFAD> → ## Lösungsplan-Qualitätsreview
```

---

# Kompakte Aktivierungsmatrix für Business-Applikationen

Nutze diese Matrix als erste Auswahlhilfe. Sie ersetzt nicht die Evidenzanalyse.

| Anwendungsfall | Mandatory-Prüfungen | Häufige Pattern-Kandidaten |
|----------------|----------------------|----------------------------|
| neues CRUD-Feature | Validierung, Autorisierung, Tenant, Datenintegrität, API/UI-Vertrag | meist keine; eventuell Factory/Builder bei komplexer Erzeugung |
| komplexe fachliche Berechnung | zentrale Regel, Rundung, Typvarianten, Grenzwerte, Testmatrix | Strategy; selten Template Method |
| Status-/Freigabeprozess | Transitionen, Guards, Audit, Locking, negative Tests | State oder explizite Transition Policy; Command; Observer nur bewusst |
| externer Provider | Trust Boundary, Mapping, Timeout, Retry, Idempotenz, Fehlervertrag | Adapter, Facade, Proxy, Decorator |
| Importpipeline | Parsing, Validierung, Teilfehler, Transaktion, Wiederaufnahme | Chain of Responsibility, Strategy, Adapter, Template Method |
| Export/Reporting | Read Model, Berechtigungen, Formatvarianten, Performance | Strategy, Builder, Visitor, Facade |
| Kopieren/Versionieren | Identitäten, Referenzen, Statusreset, Audit, Invarianten | Prototype; Memento nur für Wiederherstellung |
| asynchroner Prozess | Outbox/Inbox, At-Least-Once, Duplikate, Retry, Reihenfolge | Command, Observer, Chain of Responsibility |
| mehrere fachliche Typen | kanonisches Prädikat, Symmetrie Writer/Reader, Exhaustiveness | Strategy, State oder Polymorphie |
| komplexe UI-Zustände | Serverautorität, Fehler-/Loading-Zustände, Race/Doppelrequest | State/Reducer lokal; Command-Semantik für Aktionen |
| Datenmigration | Bestandsdaten, Expand/Contract, Constraints, Rollforward | Patterns zweitrangig; Adapter bei altem/neuem Schema |
| Querschnittsfunktion | explizite Reihenfolge, Fehlerverhalten, Transparenz | Decorator, Proxy oder Middleware |

---

# Referenz: Design-Pattern-Katalog

Die Pattern-Fit-Analyse orientiert sich am klassischen Katalog von Refactoring.Guru:

- Design Patterns: <https://refactoring.guru/design-patterns>
- Pattern-Katalog: <https://refactoring.guru/design-patterns/catalog>
- Klassifikation: <https://refactoring.guru/design-patterns/classification>
- Code-Smell-/Refactoring-Katalog: <https://refactoring.guru/refactoring/catalog>

Die dort beschriebenen Patterns sind allgemeine Lösungsmodelle und müssen an die konkrete Codebasis,
Programmiersprache, Framework-Konventionen und fachlichen Anforderungen angepasst werden.

---

## Starte jetzt

Beginne mit **Schritt 1: Task und Lösungsplan identifizieren**. Implementiere noch keinen Code.
