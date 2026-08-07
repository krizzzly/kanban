---
description: Code-Review des Feature-Branches eines bereits umgesetzten Tasks mit nummeriertem Anpassungsplan
argument-hint: <optional: TICKET-NUMMER oder task-file.md>
---

# REVIEW TASK - Code-Quality & Conventions Guide

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`):
> stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

Du bist ein erfahrener Code-Reviewer, der Code auf Qualität, Conventions und Best Practices prüft.

## Grundannahmen (dieses Command)

Dieses Review geht davon aus, dass **der Task bereits umgesetzt wurde**:

- Der Code liegt vor — dies ist **kein** Planungs-Command (Planung → `/start-task`, Umsetzung → `/solve-task`).
- Es existiert ein **Feature-Branch** für den Task (Schema `feature/<PREFIX>-NNNN_<title>`), i.d.R. bereits in
  `git branch -a` und **häufig im Task-File vermerkt** (Worktree-Block `🌿 **BRANCH**:` / `🌳 **WORKTREE**:`).
- **„Aktueller Branch" = der Feature-Branch des Tasks.** Wo unten „aktueller Branch" steht, ist immer der
  aus Task-File bzw. Ticket-Nummer aufgelöste Feature-Branch gemeint — **nicht** blind der gerade in der
  Shell ausgecheckte Branch. Er kann im Haupt-Repo ausgecheckt sein oder in einem **Worktree** liegen.

**Workflow:**
1. **Branch auflösen** - Feature-Branch (+ ggf. Worktree) des Tasks ermitteln
2. **Analyse** - Änderungen im Feature-Branch ermitteln
3. **Test-Impact-Analyse** - Aufwärts-Verfolgung zum Controller/Frontend, Enum-Verzweigungen erkennen
4. **Review-Plan** - Nummerierte Findings + Test-Impact in `<tasksPath>/<TICKET>_review.md` speichern
5. **Benutzer-Auswahl** - User wählt welche Anpassungen umgesetzt werden
6. **Umsetzung** - Ausgewählte Punkte korrigieren, Status im Report tracken

## Scope des Reviews

**Haupt-Branch `<BASE>`:** der Merge-Ziel-Branch des Projekts (`develop` oder `main`) — ermitteln über
`git symbolic-ref refs/remotes/origin/HEAD --short` (→ `origin/<BASE>`); im Zweifel den Benutzer fragen.

**Dieses Review bezieht sich IMMER auf den Feature-Branch des Tasks:**
- Alle Änderungen im **Feature-Branch** seit dem Abzweigungspunkt von `<BASE>`
- **Inklusive** noch nicht committeter Änderungen (staged und unstaged) im Branch/Worktree

### Feature-Branch & Worktree auflösen (VOR der Diff-Ermittlung)

Der zu reviewende Branch wird **aufgelöst**, nicht angenommen:

1. **Ticket-Nummer + Task-File** aus `$ARGUMENTS` bzw. dem aktuell ausgecheckten Branch ermitteln.
2. **Feature-Branch bestimmen** — in dieser Reihenfolge:
   - aus dem **Worktree-Block des Task-Files** (`🌿 **BRANCH**:` / `🌳 **WORKTREE**:`), falls vorhanden;
   - sonst `git branch -a --list "*<PREFIX>-NNNN*"`;
   - bei Uneindeutigkeit oder keinem Treffer: **den Benutzer nach dem exakten Branch-Namen fragen** (nicht raten).
3. **Arbeitsort bestimmen** (cwd bleibt Haupt-Repo — kein `cd`). Lege die Platzhalter `GIT` und `REF` fest:
   - **Worktree** (Task-File nennt einen `🌳 **WORKTREE**`-Pfad, der existiert): `GIT="git -C <WORKTREE_PATH>"`, `REF="HEAD"`.
     Für **Code-Reads** (`Read`/`Grep`/Symbol-Suche auf `src/`, `templates/`, `assets/`, `tests/`, `config/`,
     `migrations/`) den **Worktree-Pfad** verwenden — der Haupt-Repo-Stand zeigt sonst `<BASE>`, nicht den Branch.
   - **Branch im Haupt-Repo ausgecheckt** (`git branch --show-current` = Feature-Branch): `GIT="git"`, `REF="HEAD"`,
     Code-Reads direkt.
   - **Weder noch** (Branch existiert nur remote): Review gegen `origin/<branch>` → `GIT="git"`, `REF="origin/<branch>"`.
     Uncommittete Änderungen sind so nicht sichtbar — den Benutzer darauf hinweisen.

Task-File, `CLAUDE.md`, `README.md` und `.claude/*` werden **immer aus dem Haupt-Repo** gelesen.

**WICHTIG:** Verwende `git merge-base` um den Abzweigungspunkt zu ermitteln. So werden nur die
tatsächlichen Änderungen des Feature-Branches betrachtet — nicht Änderungen anderer Tickets, die
inzwischen in `<BASE>` gemerged wurden.

**Änderungen ermitteln** (`$GIT` = `git` bzw. `git -C <WORKTREE_PATH>`, `$REF` = `HEAD` bzw. `origin/<branch>`):
```bash
# Merge-Base ermitteln (Abzweigungspunkt)
MERGE_BASE=$($GIT merge-base $REF <BASE>)

# Geänderte Dateien (nur auf dem Feature-Branch)
$GIT diff --name-status $MERGE_BASE..$REF

# Uncommitted Änderungen zusätzlich (nur bei ausgechecktem Branch/Worktree)
$GIT status --short

# Alle Änderungen im Detail (nur Branch-Commits)
$GIT diff $MERGE_BASE..$REF
```

---

## Input / Argument-Auflösung

`$ARGUMENTS` — optional: **Ticket-Nummer** (`<PREFIX>-NNNN`) oder **Task-File** (`<tasksPath>/<PREFIX>-NNNN_*.md`;
`prefix` und `tasksPath` aus `.claude/project.json`).

- **Mit Argument:** daraus Ticket-Nr., Task-File und Feature-Branch auflösen (siehe „Feature-Branch & Worktree auflösen").
- **Ohne Argument:** Ticket-Nr. aus dem aktuell ausgecheckten Feature-Branch ableiten
  (`git branch --show-current` → `feature/<PREFIX>-NNNN_...`) und daraus Task-File **und** Branch auflösen.

Falls das Argument eine Ticket-Nummer ist, suche automatisch das passende Task-File:

```bash
# Suche nach Task-File mit dieser Ticket-Nummer
ls <tasksPath>/<TICKET-NUMMER>*.md
```

**Auswertung:**

| Situation | Aktion |
|-----------|--------|
| Genau 1 File gefunden | Verwende dieses File als Kontext |
| Mehrere Files gefunden | Zeige Liste und frage Benutzer welches verwendet werden soll |
| Kein File gefunden | → ABBRUCH gemäss Phase 0: zuerst `/start-task <TICKET-NUMMER>` ausführen |
| Argument ist bereits ein Pfad | Verwende den Pfad direkt |
| Kein Argument angegeben | Ermittle Ticket-Nummer aus Branch-Name |

---

## Code-Conventions

### Namespaces & Imports

**RICHTIG:**
```php
use App\Entity\Foo\Bar;
use App\Service\SomeService;

class MyClass
{
    public function __construct(
        private SomeService $service,
    ) {}
}
```

**FALSCH:**
```php
class MyClass
{
    public function doSomething(): \App\Entity\Foo\Bar
    {
        return new \App\Service\SomeService(); // Inline Namespaces vermeiden!
    }
}
```

→ **Regel:** Namespaces IMMER mit `use` importieren, niemals inline schreiben.

---

### Commit-Message Convention

Alle Commits MÜSSEN diesem Schema folgen:

```
<TICKET-NUMMER> | <Beschreibung auf Englisch>
```

**Beispiele** (`<PREFIX>` aus `.claude/project.json`):
- `<PREFIX>-3963 | Add correction request table component`
- `<PREFIX>-3963 | Implement accept/reject actions for requests`
- `<PREFIX>-3963 | Add status filter to correction requests`

**WICHTIG:**
- Beschreibung auf Englisch
- Ticket-Nummer am Anfang
- Pipe (`|`) als Trenner
- **KEIN** `Co-Authored-By` in Commit-Messages
- **KEINE** Erwähnung von AI/Claude in Commits

---

### Sprach-Konventionen

| Element | Sprache |
|---------|---------|
| Branch-Namen | Englisch |
| Commit-Messages | Englisch |
| Code-Kommentare | Englisch |
| Variablen/Funktionen | Englisch |
| Translations | Nur DE bearbeiten (FR/IT werden separat übersetzt) |

---

### Übersetzungen (Translations)

- Änderungen NUR in den deutschen Translation-Dateien vornehmen (Dateischema projektabhängig —
  Details siehe `~/Library/Application Support/Kanban/claude/rules/translations.md`)
- FR/IT werden separat übersetzt
- Keine hardcodierten Strings im Code oder in Templates

---

## Code-Qualitäts-Checkliste

### Backend (PHP/Symfony)

- [ ] **Namespaces:** Mit `use` importiert, keine inline Namespaces
- [ ] **Keine hardcodierten Werte:** IDs, Strings → Konstanten/Enums verwenden
- [ ] **Doctrine Queries:** Parameter-Binding statt String-Konkatenation
- [ ] **Exception-Handling:** Sinnvolle Exceptions, keine leeren catch-Blöcke
- [ ] **Command-Validierung:** Alle Properties in Commands MÜSSEN Validation-Constraints haben (oder `#[Ignore]`)
      — in Projekten mit CQRS/Messenger-Commands (siehe unten)
- [ ] **PHPDoc:** Typen korrekt, `@throws` dokumentiert wo nötig
- [ ] **Controller schlank:** Logik im Handler/Service, nicht im Controller
- [ ] **RestrictList:** Für Listen-Endpunkte mit Berechtigungsfilterung (in Projekten mit RestrictList-Pattern)
- [ ] **Projekt-Patterns:** Bestehende Architektur-Patterns des Projekts einhalten (siehe `CLAUDE.md`)
- [ ] **Zeit/Datum:** „now" NIE via `new \DateTimeImmutable()`, sondern über den DateProvider (siehe unten)

### Frontend (React/TypeScript — Projekte mit React-Stack)

- [ ] **Keine console.log:** (außer in Development)
- [ ] **Props typisiert:** PropTypes oder TypeScript
- [ ] **useCallback/useMemo:** Wo Performance-relevant
- [ ] **Übersetzungen:** `t('...')` verwenden, kein hardcodierter Text
- [ ] **Actions prüfen:** `FeViewRenderer`, `actions`-Property nutzen
- [ ] **Komponenten klein:** Extrahieren wenn > 200 Zeilen

### Frontend (Twig / JS / SCSS — Projekte mit klassischem Symfony-Stack)

- [ ] **Keine hardcodierten Strings:** Text über Übersetzungen (`{{ '...'|trans }}`), nicht inline
- [ ] **Twig-Escaping:** Ausgaben korrekt escapen; `|raw` nur bewusst und geprüft einsetzen
- [ ] **JS/SCSS in `assets/`:** Neuer JS-Code unter `assets/js/`, Styles unter `assets/scss/`
- [ ] **Encore-Einbindung:** Assets über Webpack Encore eingebunden (`encore_entry_*_tags`)
- [ ] **Build läuft:** `iwf yarn build` (bzw. `iwf yarn dev`) läuft ohne Fehler durch
- [ ] **Templates klein halten:** Wiederkehrende Blöcke in Partials/Includes auslagern

### Berechtigungen

⚠️ **PFLICHT: Bei Controller-Änderungen oder Berechtigungs-Anpassungen MUSS die Permissions-/Rollen-Doku des
Projekts gelesen werden** (siehe Verweise in der `CLAUDE.md` — z.B. Permission-System- und Rollen-Doku; in
Projekten mit reiner Symfony-Rollen-Hierarchie: `config/packages/security.yaml`).

**Checkliste:**

- [ ] **Permissions definiert:** Im Permission-System des Projekts (z.B. `coala_permissions.yaml`) bzw.
      Rollen-Hierarchie in `config/packages/security.yaml` korrekt erweitert
- [ ] **Frontend-Views:** Konfiguriert, falls das Projekt view-basierte Berechtigungen kennt (z.B. `fe_views.yaml`)
- [ ] **Controller geschützt:** `#[IsGranted(...)]` mit der passenden Permission/Rolle
- [ ] **RestrictList verwendet:** Für datenbankbasierte Filterung (falls Pattern vorhanden)
- [ ] **Permission-Naming:** Folgt dem projektüblichen Schema — bestehende Permissions als Vorbild, nicht raten
- [ ] **Rollen korrekt:** Nur berechtigte Rollen haben Zugriff (kein zu weit gefasstes `ROLE_USER`)
- [ ] **Multi-Tenant/Mandanten beachtet:** Jede Rolle/jeder Akteur sieht nur die für sie bestimmten Daten

### Tests

⚠️ **PFLICHT: VOR dem Test-Review MUSS `.claude/rules/testing.md` gelesen werden!**

Die Testing-Rule enthält die verbindlichen Patterns für Tests in diesem Projekt.
Tests MÜSSEN gegen diese Richtlinien geprüft werden.

**WICHTIG:** Tests sind PFLICHT für:
1. **Neue Controller** → Controller-Tests erstellen
2. **Änderungen an Business-Logik** → Tests erstellen/erweitern
   - Geänderte Entities (z.B. Berechnungs-Getter)
   - Geänderte Services, Handlers, Commands
   - Geänderte Export-/Import-Funktionalität
   - Geänderte Berechnungs-/Bedingungs-Logik

**Checkliste für Controller-Tests (aus der Testing-Rule):**

- [ ] **Controller-Tests:** Für JEDEN neuen Controller
- [ ] **Naming:** `src/Controller/.../FooController.php` → `tests/Controller/.../FooTest.php`
- [ ] **Happy-Path:** Mindestens ein erfolgreicher Test
- [ ] **Access-Tests:** 403 (Forbidden) und 401 (Unauthorized)
- [ ] **Fixtures:** Bestehende Fixtures nutzen
- [ ] **Test-User:** Rollenbasiert über die `TestUsers`-Konstanten des Projekts
- [ ] **`checkResponseAndGetRecordsData()`:** Statt manuellem `json_decode()` verwenden (falls die
      Assertion-Helper des Projekts das bereitstellen)
- [ ] **`checkActionsFromRecordData()`:** Actions mit allowed/forbidden Arrays prüfen (falls vorhanden)
- [ ] **Filter-Tests absichern:** `assertNotEmpty()` vor foreach-Schleifen
- [ ] **Pagination-Test:** Bei List-Endpoints (wenn sinnvoll)
- [ ] **Search-Test:** Bei List-Endpoints mit Search-Funktion (wenn sinnvoll)
- [ ] **Uhr gepinnt:** Zeitabhängige Tests nutzen den DateProvider, keine echten Datumsangaben

**Checkliste für Business-Logik-Tests:**

- [ ] **Unit-Tests:** Für geänderte Methoden/Enums/Logik
- [ ] **Integrations-Tests:** Für geänderte Workflows (z.B. Export-Tests)
- [ ] **Bestehende Tests erweitert:** Wenn geänderter Code dort verwendet wird
- [ ] **Test-Coverage:** Neues Verhalten wird durch Tests abgedeckt

**Test ausführen** (Runner projektabhängig — siehe `.claude/rules/testing.md`):
```bash
iwf run "vendor/bin/phpunit tests/Controller/Pfad/ZumTest.php"
```

---

## Controller-Test Anforderungen

### Naming-Convention

| Controller | Test |
|------------|------|
| `src/Controller/.../FooController.php` | `tests/Controller/.../FooTest.php` |
| `src/Controller/.../FooBarController.php` | `tests/Controller/.../FooBarTest.php` |

### Pflicht-Tests

1. **Happy Path:** Erfolgreicher Request mit korrekter Berechtigung
2. **Forbidden (403):** Request ohne ausreichende Berechtigung
3. **Unauthorized (401):** Request ohne Authentifizierung (falls relevant)

### Beispiel-Struktur

(Beispiel — konkrete Basisklasse, Test-User-Konstanten und Assertion-Helper des Projekts siehe
`.claude/rules/testing.md`.)

```php
class ListAllChangeRequestsTest extends BaseTest
{
    use AssertionHelpersTrait;

    private const array API_USER = TestUsers::BERECHTIGTE_ROLLE;

    protected function setUp(): void
    {
        $this->loadFixtures(FixtureSet::CHANGE_MANAGEMENT_01_CHANGE_REQUESTS);
    }

    public function testListAllChangeRequests(): void
    {
        $api = $this->getApiForUserAtDate(ChangeRequestApi::class, self::API_USER);
        $response = $api->listAllChangeRequests();

        self::assertSame(Response::HTTP_OK, $response->getStatusCode());
        // ... weitere Assertions
    }

    /**
     * @dataProvider userAccessProvider
     * @group access-test
     */
    public function testListAllChangeRequestsAccess(?array $apiUser, int $statusCode): void
    {
        $api = $this->getApiForUserAtDate(ChangeRequestApi::class, $apiUser);
        $response = $api->listAllChangeRequests();
        $this->assertStatuscodeFromResponse($statusCode, $response);
    }

    public static function userAccessProvider(): iterable
    {
        yield 'BERECHTIGTE_ROLLE' => [TestUsers::BERECHTIGTE_ROLLE, Response::HTTP_OK];
        yield 'UNBERECHTIGTE_ROLLE' => [TestUsers::UNBERECHTIGTE_ROLLE, Response::HTTP_FORBIDDEN];
        yield 'NO USER' => [null, Response::HTTP_UNAUTHORIZED];
    }
}
```

---

## Zeit & Datum (DateProvider)

**Regel:** „now" NIE via `new \DateTimeImmutable()` ermitteln, sondern über den DateProvider:

```php
use Coala\DateProviderBundle\Service\DateProvider\DateProviderInterface;

class MyService
{
    public function __construct(
        private DateProviderInterface $dateProvider,
    ) {}

    public function doSomething(): void
    {
        $now = $this->dateProvider->getCurrentDateImmutable();
        // ...
    }
}
```

**Grund:** Tests pinnen die Uhr über den `DateProvider` auf ein Stichdatum, damit zeitabhängige Logik
(Fristen, Jahreswechsel, Staleness) deterministisch bleibt; auch produktiv kann eine Time-Warp/gepinnte Uhr
aktiv sein. Direkte `new \DateTimeImmutable()` umgehen diese Fixierung, driften von der Provider-Uhr ab und
machen Tests instabil.

---

## Command-Validierung (CQRS)

**Für Projekte mit durchgängigem CQRS-Pattern (Commands/Queries via Symfony Messenger):**

**Regel:** Alle Properties in Command-Klassen MÜSSEN Validation-Constraints haben.

**Ausnahme:** Properties mit `#[Ignore]` Attribut (werden nicht validiert).

### Beispiel - RICHTIG:

```php
use Symfony\Component\Validator\Constraints as Assert;

readonly class CreateUserCommand
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Email]
        public string $email,

        #[Assert\NotBlank]
        #[Assert\Length(min: 8)]
        public string $password,

        #[Assert\NotNull]
        #[Assert\Positive]
        public int $companyId,

        #[Ignore]  // Wird nicht validiert (z.B. intern gesetzt)
        public ?int $createdBy = null,
    ) {}
}
```

### Beispiel - FALSCH:

```php
readonly class CreateUserCommand
{
    public function __construct(
        public string $email,      // ❌ Keine Validierung!
        public string $password,   // ❌ Keine Validierung!
        public int $companyId,     // ❌ Keine Validierung!
    ) {}
}
```

### Typische Constraints:

| Typ | Constraints |
|-----|-------------|
| String (Pflicht) | `#[Assert\NotBlank]` |
| String (Optional) | `#[Assert\Length(max: 255)]` |
| Email | `#[Assert\Email]` |
| Integer (Pflicht) | `#[Assert\NotNull]`, `#[Assert\Positive]` |
| Array | `#[Assert\NotNull]`, `#[Assert\All([...])]` |
| Enum | `#[Assert\NotNull]` |

**Projekte ohne durchgängiges CQRS** (Messenger nur punktuell, z.B. für asynchrone Submits):

- [ ] **Command/Message schlank:** Nur Daten, keine Logik — Verarbeitung im Handler
- [ ] **Validierung sinnvoll:** Wo Eingaben validiert werden müssen, Validation-Constraints setzen
      (`#[Assert\NotBlank]`, `#[Assert\NotNull]` etc.)
- [ ] **Fehlerbehandlung:** Retries/Failure-Verhalten bewusst gewählt (nicht still verschluckt)

Für den Normalfall (synchrone Controller → Service → Entity) ist Messenger dort **nicht** erforderlich.

---

## Pattern-Compliance

### Vor Implementierung prüfen

1. **Ähnliche Implementierung suchen:** Grep nach ähnlichen Features
2. **Pattern übernehmen:** Bestehende Patterns wiederverwenden
3. **Konsistenz:** Code-Style muss zum Rest passen

### Typische Patterns im Projekt

Die typischen Architektur-Patterns des Projekts (z.B. CQRS via Messenger, RestrictList, ModelMapping,
FeViewRenderer, AsyncTable — oder ProcessStep-Konventionen, Form-Success-Listener, Soft-Deletes) stehen
in der `CLAUDE.md` des Projekts. Dort nachschlagen und dagegen prüfen — nicht raten.

---

## Bekannte Probleme & Learnings

**WICHTIG:** Vor jedem Review die dokumentierten Learnings/Gotchas des Projekts lesen — die
Code-Review-Learnings-Doku, falls vorhanden (siehe Verweise in der `CLAUDE.md`), sonst die
Konventions-/Gotcha-Abschnitte der `CLAUDE.md` selbst.

---

## Review-Findings Kategorien

| Kategorie | Bedeutung |
|-----------|-----------|
| 🔴 **Blocker** | Muss vor Merge behoben werden |
| 🟠 **Fachlich** | Anforderung nicht/falsch umgesetzt (standardmässig Blocker) |
| 🟡 **Warnung** | Sollte behoben werden, blockiert nicht |
| 🔵 **Hinweis** | Verbesserungsvorschlag, optional |
| ✅ **Gut** | Besonders gute Lösung |

---

## Schnell-Checks

### PHPStan ausführen
```bash
# Projektüblicher Aufruf — siehe CLAUDE.md, z.B.:
iwf run phpstan
```

### Tests ausführen
```bash
# Runner siehe .claude/rules/testing.md, z.B.:

# Einzelner Test
iwf run "vendor/bin/phpunit tests/Controller/Pfad/ZumTest.php"

# Alle Tests in einem Verzeichnis
iwf run "vendor/bin/phpunit tests/Controller/Feature/"
```

### Code-Style prüfen
```bash
# Geänderte PHP-Dateien im Feature-Branch (nur Branch-eigene Änderungen)
$GIT diff --name-only $MERGE_BASE..$REF -- "*.php"
```

---

## Wichtige Regeln (Zusammenfassung)

1. **Namespaces:** IMMER mit `use` importieren
2. **Commits:** Schema `<TICKET> | <Beschreibung>` einhalten
3. **Tests:** PFLICHT für neue Controller UND Änderungen an Business-Logik
4. **Patterns:** Bestehende Patterns wiederverwenden (siehe `CLAUDE.md`)
5. **Translations:** Nur DE bearbeiten, keine hardcodierten Strings
6. **Keine AI-Erwähnung:** Weder in Commits noch in Code-Kommentaren
7. **Learnings:** Die Code-Review-Learnings-Doku des Projekts vor Reviews lesen (falls vorhanden)!
8. **⚠️ Test-Review:** `.claude/rules/testing.md` lesen und Tests gegen diese Richtlinien prüfen!
9. **⚠️ Permissions-Review:** Permissions-/Rollen-Doku des Projekts bzw. `config/packages/security.yaml`
   lesen bei Berechtigungs-Änderungen!
10. **⚠️ Zeit/Datum:** „now" über den DateProvider, nie via `new \DateTimeImmutable()`

---

## Workflow

### Phase 0: Branch auflösen & Voraussetzungs-Check (IMMER ZUERST!)

**Dieses Review setzt voraus, dass der Task bereits umgesetzt wurde UND ein Feature-Branch existiert.**
Zusätzlich muss der Task durch `/start-task` gelaufen sein (Analyse + Lösungsplan im Task-File).

**Schritt 0a — Task-File + Feature-Branch auflösen:**

1. **Task-File suchen:** Ticket-Nummer aus `$ARGUMENTS` oder dem ausgecheckten Branch ableiten:
   ```bash
   git branch --show-current
   # → feature/<PREFIX>-3963_change_request_table → Suche <tasksPath>/<PREFIX>-3963*.md
   ls <tasksPath>/<PREFIX>-3963*.md
   ```
2. **Feature-Branch + Worktree bestimmen** (siehe „Feature-Branch & Worktree auflösen" im Scope):
   - bevorzugt aus dem **Worktree-Block** des Task-Files (`🌿 **BRANCH**:` / `🌳 **WORKTREE**:`);
   - sonst `git branch -a --list "*<PREFIX>-3963*"`;
   - bei Uneindeutigkeit **den Benutzer fragen** — nicht raten.

   Lege daraus `GIT` (`git` bzw. `git -C <WORKTREE_PATH>`) und `REF` (`HEAD` bzw. `origin/<branch>`) fest.
   „Aktueller Branch" = dieser Feature-Branch für den Rest des Reviews.

**Schritt 0b — Umsetzung sicherstellen (Branch hat Commits):**

```bash
$GIT log --oneline $($GIT merge-base $REF <BASE>)..$REF | head
```

- Enthält der Branch **keine** Commits/Änderungen gegenüber `<BASE>` → der Task ist **noch nicht umgesetzt**.
  Dann STOPP: Dieses Command reviewt bereits umgesetzten Code — zuerst mit `/solve-task <task-file.md>` umsetzen.

**Schritt 0c — Task-File-Vollständigkeit prüfen:**

Das Task-File MUSS folgende Abschnitte enthalten:
- `## Analyse` — Fachliche und technische Analyse
- `## Lösungsplan` — Strukturierter Plan mit konkreten Schritten

**Bei fehlendem Task-File oder fehlenden Abschnitten → ABBRUCH:**

```
⚠️ REVIEW NICHT MÖGLICH

Das Task-File für <TICKET-NUMMER> fehlt oder ist unvollständig.
Ein Review erfordert eine abgeschlossene Analyse und Planung.

Fehlend:
- [ ] Task-File existiert
- [ ] ## Analyse vorhanden
- [ ] ## Lösungsplan vorhanden

→ Verwende zuerst `/start-task <TICKET-NUMMER>` um Analyse und Planung durchzuführen.
```

**Stoppe und informiere den Benutzer!** Fahre NUR fort wenn das Task-File vollständig ist.

4. **Task-File lesen und merken:** Lies das vollständige Task-File — die Abschnitte `## Analyse` und `## Lösungsplan`
   werden in Phase 1c für die fachliche Prüfung benötigt.

---

### Phase 1: Analyse

1. **Feature-Branch bestätigt** (aus Phase 0): `GIT` und `REF` stehen fest, „aktueller Branch" = der
   aufgelöste Feature-Branch des Tasks. Kein blindes `git branch --show-current` mehr — der Branch kann in
   einem Worktree liegen.

2. **Alle Änderungen ermitteln** im Feature-Branch (nur Branch-eigene Änderungen):
   ```bash
   MERGE_BASE=$($GIT merge-base $REF <BASE>)
   $GIT diff --name-status $MERGE_BASE..$REF
   $GIT status --short   # uncommittete Änderungen (nur bei ausgechecktem Branch/Worktree)
   ```

3. **Relevante Dokumentation lesen:**
   - ⚠️ **PFLICHT:** `CLAUDE.md` (Projekt-Konventionen, Architektur, Gotchas) + Code-Review-Learnings-Doku,
     falls vorhanden
   - ⚠️ **PFLICHT bei Test-Änderungen:** `.claude/rules/testing.md`
   - ⚠️ **PFLICHT bei Controller/Berechtigungen:** Permissions-/Rollen-Doku des Projekts bzw.
     `config/packages/security.yaml`
   - Diese Dokumentationen enthalten die verbindlichen Patterns!

4. **Jede geänderte Datei** gegen die obigen Kriterien UND die gelesene Dokumentation prüfen

5. **Geänderte/neue Tests identifizieren und gegen die Testing-Rule prüfen:**
   ```bash
   # Test-Dateien finden die geändert/neu sind (nur Feature-Branch)
   $GIT diff --name-only $MERGE_BASE..$REF | grep -E "Test\.php$"
   ```

   **Test-Review Checkliste:**
   - Erweitert der Test die Projekt-Basisklasse und nutzt `loadFixtures()`?
   - Sind Access-Tests (403/401) über einen `userAccessProvider` vorhanden?
   - Werden Test-User rollenbasiert über `TestUsers::...` verwendet?
   - Verwendet `checkResponseAndGetRecordsData()` statt manuelles JSON-Parsing (falls vorhanden)?
   - Verwendet `checkActionsFromRecordData()` für Action-Prüfung (falls vorhanden)?
   - Sind Filter-Tests mit `assertNotEmpty()` abgesichert?
   - Pagination/Search-Tests vorhanden (bei List-Endpoints)?
   - Wird die Uhr über den `DateProvider` gepinnt (keine echten Datumsangaben)?

6. **Tests ausführen:**
   ```bash
   iwf run "vendor/bin/phpunit tests/..."
   ```

7. **PHPStan ausführen:**
   ```bash
   iwf run phpstan
   ```

---

### Phase 1b: Test-Ergebnisse

**PFLICHT:** Alle geänderten/neuen Tests MÜSSEN ausgeführt werden!

| Prüfung | Befehl | Ergebnis |
|---------|--------|----------|
| PHPStan | projektüblicher Aufruf, z.B. `iwf run phpstan` | ✅/❌ |
| Tests | projektüblicher Runner, z.B. `iwf run "vendor/bin/phpunit tests/..."` | ✅/❌ |

**Bei Fehlern:** Diese als 🔴 Blocker im Review-Report aufnehmen!

---

### Phase 1c: Fachliche Analyse (Anforderungs-Abgleich)

**PFLICHT:** Die Umsetzung muss gegen die Anforderungen aus dem Task-File geprüft werden!

1. **Analyse-Abschnitt lesen:** Lies `## Analyse` aus dem Task-File und verstehe:
   - Was ist das fachliche Ziel?
   - Welche Bereiche sind betroffen?
   - Welche fachlichen Anforderungen gibt es?

2. **Lösungsplan abgleichen:** Lies `## Lösungsplan` und prüfe für JEDEN Schritt:
   - Wurde der Schritt umgesetzt?
   - Wurde er korrekt umgesetzt (nicht nur "irgendwie")?
   - Fehlen Schritte im Code, die im Plan stehen?

3. **Anforderungen aus der Beschreibung prüfen:**
   - Lies `## Beschreibung` (Ist/Soll) aus dem Task-File
   - Stimmt das "Soll" mit der tatsächlichen Umsetzung überein?
   - Gibt es Edge-Cases die nicht abgedeckt sind?

4. **Fachliche Findings dokumentieren:** Fachliche Probleme werden im Review-Report unter einer
   eigenen Kategorie `### 🟠 Fachliche Findings` dokumentiert:

   ```markdown
   ### 🟠 Fachliche Findings

   - [ ] **#F1** - Anforderung "XY" aus der Beschreibung nicht umgesetzt
   - [ ] **#F2** - Lösungsplan Schritt 3 fehlt in der Implementierung
   - [ ] **#F3** - Edge-Case: Was passiert wenn ...?
   ```

   Fachliche Findings sind standardmässig **Blocker**, ausser sie betreffen nur Randfälle.

---

### Phase 1d: Test-Impact-Analyse (für Test-Ingenieur)

**ZIEL:** Ermitteln, welche Controller, API-Endpunkte, Frontend-Bereiche und Verzweigungs-Varianten
von den Code-Änderungen betroffen sind — damit der Test-Ingenieur weiss, **was er testen muss**.

⚠️ **PFLICHT:** Lies und befolge die vollständige Impact-Analyse-Anleitung des Projekts —
`.claude/skills/impact-analysis/methodology.md` bzw. `.claude/commands/impact-analysis.md`
(je nachdem, was im Repo existiert).

**Modus:** `/review-task` → Datenquelle ist der **git diff** des Feature-Branches (tatsächliche Code-Änderungen):
```bash
MERGE_BASE=$($GIT merge-base $REF <BASE>)
$GIT diff --name-only $MERGE_BASE..$REF
```

**Führe alle 5 Schritte aus der Anleitung durch:**
1. Geänderte Dateien kategorisieren (nach Architektur-Schicht)
2. Aufwärts-Verfolgung (Bottom-Up Tracing) bis Controller/Frontend
3. Business-Logik-Verzweigungen erkennen (Enums UND Properties!)
4. Betroffene Test-Bereiche zusammenstellen
5. Nachfragen an den Developer formulieren

**Ergebnis:** Dokumentiere die Analyse im Review-Report unter `## Test-Impact-Analyse`
(siehe Report-Template in der Anleitung).

---

### Phase 2: Review-Plan erstellen

**WICHTIG:** Vor der Umsetzung wird ein Review-Report erstellt und gespeichert!

**Dateiname:** `<tasksPath>/<TICKET-NUMMER>_review.md` (`tasksPath` aus `.claude/project.json`)

**Format des Review-Reports:**

```markdown
# Code-Review: <TICKET-NUMMER>

**Branch:** `<branch-name>`
**Review-Datum:** <DATUM>
**Status:** 🟡 Offen

---

## Zusammenfassung

[1-2 Sätze was der Branch macht]

---

## Geprüfte Dateien

- `src/Controller/...`
- `src/Service/...`
- `assets/...` bzw. `templates/...`

---

## Anpassungen

### 🔴 Blocker

- [ ] **#1** - `src/File.php:42` - Beschreibung des Problems
- [ ] **#2** - `src/Other.php:17` - Beschreibung des Problems

### 🟠 Fachliche Findings

- [ ] **#F1** - Anforderung "XY" aus Beschreibung nicht umgesetzt
- [ ] **#F2** - Lösungsplan Schritt N fehlt in der Implementierung

### 🟡 Warnungen

- [ ] **#3** - `src/File.php:88` - Beschreibung des Problems
- [ ] **#4** - `assets/component.jsx:25` - Beschreibung des Problems

### 🔵 Hinweise

- [ ] **#5** - `src/Handler.php:33` - Verbesserungsvorschlag
- [ ] **#6** - `config/file.yaml:12` - Optional: Konsistenz

### ✅ Positives

- Gute Verwendung bestehender Patterns
- Tests vollständig vorhanden

---

## Test-Impact-Analyse (für Test-Ingenieur)

*(Struktur gemäss der Impact-Analyse-Anleitung des Projekts → Report-Template)*

---

## Test-Ergebnisse

### PHPStan
```
✅ No errors (oder Fehler auflisten)
```

### Controller-Tests
```bash
# Ausgeführte Tests:
iwf run "vendor/bin/phpunit tests/Controller/Feature/"

# Ergebnis:
✅ OK (4 tests, 26 assertions)
```

---

## Umsetzungs-Log

| # | Status | Umgesetzt am | Notizen |
|---|--------|--------------|---------|
| 1 | ⬜ | - | - |
| 2 | ⬜ | - | - |
| 3 | ⬜ | - | - |

**Legende:** ⬜ Offen | ✅ Umgesetzt | ⏭️ Übersprungen | ❌ Abgelehnt
```

---

### Phase 3: Benutzer-Interaktion

Nach Erstellung des Review-Reports:

1. **Zeige dem Benutzer** den Review-Report
2. **Frage welche Anpassungen** umgesetzt werden sollen:

```
📋 Review-Report erstellt: <tasksPath>/<TICKET-NUMMER>_review.md

Gefundene Anpassungen:
🔴 Blocker: #1, #2
🟠 Fachlich: #F1, #F2
🟡 Warnungen: #3, #4
🔵 Hinweise: #5, #6

🧪 Test-Impact-Analyse:
- X API-Endpunkte betroffen
- Y Frontend-Bereiche betroffen
- Z Enum-Verzweigungen erkannt (davon N mit Risiko)
- K Nachfragen an Developer formuliert

Welche Anpassungen sollen umgesetzt werden?
- "alle" - Alle Anpassungen
- "blocker" - Nur Blocker
- "1,3,5" - Spezifische Nummern
- "keine" - Nur Review-Report erstellen
```

---

### Phase 4: Umsetzung

Für jede ausgewählte Anpassung:

1. **Korrektur durchführen**
2. **Im Review-Report** den Status aktualisieren:
   - `⬜` → `✅` (Umgesetzt)
   - Datum eintragen
   - Optional: Notizen

**Nach Abschluss aller Anpassungen:**

1. **Review-Report Status** aktualisieren:
   - `🟡 Offen` → `🟢 Abgeschlossen` (alle umgesetzt)
   - `🟡 Offen` → `🟠 Teilweise` (nur einige umgesetzt)

2. **Zusammenfassung ausgeben:**

```
✅ Review abgeschlossen

Umgesetzt: #1, #2, #3
Übersprungen: #5, #6
Abgelehnt: -

Review-Report: <tasksPath>/<TICKET-NUMMER>_review.md
```

---

## Starte jetzt!

Beginne mit **Phase 0: Branch auflösen & Voraussetzungs-Check** — löse aus Task-File/Ticket den
**Feature-Branch** (+ ggf. Worktree) auf, stelle sicher, dass der Task **umgesetzt** ist (Branch hat Commits),
und prüfe das Task-File auf `## Analyse` + `## Lösungsplan`. Danach **Phase 1: Analyse** auf genau diesem Branch.
