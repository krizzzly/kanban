---
name: solve-task
description: Setze einen vorbereiteten JIRA-Task um (überspringt Analyse/Planung)
argument-hint: <TICKET-NUMMER oder task-file.md> [--no-worktree]
disable-model-invocation: true
---

# SOLVE TASK - Umsetzungs-Arbeitsanweisung

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`):
> stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

Du bist ein erfahrener Software-Entwickler, der einen **bereits geplanten** JIRA-Task umsetzt.

## Argument-Auflösung

**Input:** $ARGUMENTS

**Schritt 0: Task-File ermitteln**

Falls das Argument eine Ticket-Nummer ist (Schema `<PREFIX>-NNNN`, `prefix` aus `.claude/project.json`),
suche automatisch das passende Task-File im Task-Ordner (`tasksPath` aus `.claude/project.json`):

```bash
# Suche nach Task-File mit dieser Ticket-Nummer
ls <tasksPath>/<TICKET-NUMMER>*.md
```

**Auswertung:**

| Situation | Aktion |
|-----------|--------|
| Genau 1 File gefunden | Verwende dieses File |
| Mehrere Files gefunden | Zeige Liste und frage Benutzer welches verwendet werden soll |
| Kein File gefunden | Hinweis: `/get-task <TICKET-NUMMER>` verwenden um Task zu laden |
| Argument ist bereits ein Pfad | Verwende den Pfad direkt |

**Ermitteltes Task-File:** `<TASK_FILE>` (wird im weiteren Workflow verwendet)

---

## Dein Task-File

Lies und analysiere: `<TASK_FILE>`

**WICHTIG:** Dieses Command erfordert gründliches Nachdenken. Füge `ULTRATHINK` am Ende deiner Überlegungen hinzu,
um maximale Analyse-Tiefe zu gewährleisten.

## Worktree-Verhalten (Default: AN)

- **Standard:** Falls das Task-File noch keinen Worktree-Block hat, wird in Phase 0a automatisch einer angelegt
  und der Block ins Task-File eingefügt (nur Worktree, **kein** Docker-Stack).
- **Opt-out:** Wenn `$ARGUMENTS` das Flag `--no-worktree` enthält, KEIN Worktree anlegen — Feature-Branch wird
  im Haupt-Repo erzeugt (altes Default-Verhalten). Das Flag wird beim Task-File-Lookup ignoriert.

> Vollständige Befehls-/Flag-Referenz zu `iwf worktree`: `~/Library/Application Support/Kanban/claude/rules/worktree.md` (bzw. `iwf worktree --help`).

---

## Jira-Status und Zuweisung (macht Kanban)

Wird dieses Skill **aus Kanban** abgesetzt (Karten-Kontextmenü oder Detail-Header), zieht die App das
JIRA-Ticket dabei nach: Status auf **„In Arbeit"** und **dir zugewiesen**. Geschrieben wird nur, was
fehlt; das Ergebnis steht in Kanbans Toolbar. Du musst dafür nichts tun — und sollst es auch nicht:
für Transition und Zuweisung gibt es hier kein Werkzeug.

Läuft das Skill **ausserhalb** von Kanban, bleibt das aus. Dann gehören Status und Zuweisung von Hand
in JIRA gesetzt — der Status im Task-File (`🟡 In Arbeit`) sagt JIRA nichts.


---

## Voraussetzungen

Dieses Command setzt voraus, dass das Task-File bereits folgende Abschnitte enthält:

- `## Analyse` - Fachliche und technische Analyse
- `## Lösungsplan` - Strukturierter Plan mit konkreten Schritten

> Falls diese fehlen, verwende stattdessen `start-task` für den vollständigen Workflow!

---

## Workflow - Führe diese Schritte der Reihe nach aus:

### Phase 0a: Worktree-Routing (IMMER ALLERERST!)

**Grundprinzip:** Claude wird IM HAUPT-REPO gestartet und BLEIBT dort als Working-Directory
(`repoDir` aus `.claude/project.json`). Wenn das Task-File einen Worktree-Block enthält, werden ALLE
Code-Operationen und Git-Befehle für den Feature-Branch in den Worktree-Pfad **geroutet** — ohne `cd`.
Lesen aus Haupt-Repo (Task-File, CLAUDE.md, `.claude/`, Docs), Schreiben/Git ins Worktree.

**Schritt 0a-1: Worktree-Block im Task-File suchen**

Lies die ersten ~15 Zeilen des Task-Files und prüfe ob ein Block der Form

```markdown
> 🌳 **WORKTREE**: `<worktreePrefix>/<TICKET-NUMMER>`\
> 🌿 **BRANCH**: `feature/<TICKET-NUMMER>_<title>`\
```

existiert (die Metadaten-Zeilen enden auf `\` = harter Zeilenumbruch; `worktreePrefix` aus
`.claude/project.json`). Falls ja, extrahiere `WORKTREE_PATH` und `BRANCH`.

**Schritt 0a-2: Worktree validieren** (nur wenn Block vorhanden)

```bash
pwd                                                  # sollte = repoDir (aus .claude/project.json) sein
git worktree list                                    # bestätigen, dass WORKTREE_PATH ein gültiger Worktree ist
git -C <WORKTREE_PATH> branch --show-current         # sollte = BRANCH sein
```

**Fallunterscheidung:**

| Situation                                                                  | Aktion                                                                                                  |
|----------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| Kein Worktree-Block im Task-File, KEIN `--no-worktree` im Input             | **Default:** Worktree per `iwf worktree create` anlegen, Block ins Task-File schreiben, dann WORKTREE-ROUTING aktivieren (siehe Schritt 0a-3). Weiter mit Phase 0b. |
| Kein Worktree-Block im Task-File, `--no-worktree` im Input                  | Standard-Workflow im Haupt-Repo (Opt-out). Weiter mit Phase 0b.                                          |
| Block vorhanden, Worktree gültig, Branch dort aktiv                         | **WORKTREE-ROUTING aktivieren** (siehe Schritt 0a-3). Weiter mit Phase 0b.                              |
| Block vorhanden, Worktree-Pfad existiert nicht (mehr), KEIN `--no-worktree` | Benutzer informieren: Worktree wurde entfernt. Block aus Task-File löschen, dann erneut Default-Worktree anlegen (`iwf worktree create`), Block schreiben, Routing aktivieren. |
| Block vorhanden, Worktree-Pfad existiert nicht (mehr), `--no-worktree`      | Block aus Task-File löschen, im Haupt-Repo weiter.                                                       |
| Block vorhanden, Worktree-Pfad existiert aber Branch dort ist anders        | Inkonsistent — Benutzer fragen, was korrekt ist. NICHT raten.                                            |

**Worktree-Default-Anlage (wenn obenstehende Default-Spalte greift):**

1. Branch-Suffix aus dem Task-File-Namen ableiten (englischer Titel ohne `<PREFIX>-NNNN_` und `.md`; bzw. ohne Suffix).
2. `iwf worktree create NNNN <suffix>` ausführen (NNNN = nackte Ticket-Nummer, nicht `<PREFIX>-NNNN`).
   (Flag-/Befehls-Referenz: `~/Library/Application Support/Kanban/claude/rules/worktree.md` bzw. `iwf worktree --help`.)
3. Worktree-Block direkt unter die H1 des Task-Files einfügen (Format identisch zu `create-worktree`).
4. WORKTREE-ROUTING für den Rest der Session aktivieren.

**Schritt 0a-3: Worktree-Routing-Regeln** (für die restliche Session)

Wenn der Worktree aktiv ist, gelten ab hier folgende Regeln:

**Code-Dateien (Edit/Write/Read von Source):**

- Pfade IMMER absolut mit Worktree-Prefix verwenden, z.B.
  `<WORKTREE_PATH>/src/Controller/Foo.php`.
- Betroffen sind: `src/`, `assets/`, `templates/`, `tests/`, `config/`, `migrations/`, `translations/`,
  `composer.json`, `composer.lock` — und generell alle versionierten Code-Files des Projekts.

**Read-Only-Quellen (Lesen aus dem Haupt-Repo):**

- Task-File (im Task-Ordner, `tasksPath` aus `.claude/project.json`)
- CLAUDE.md, README.md und alle darin referenzierte Doku
- der Agent-Ordner des Repos (`.claude/` bzw. `.codex/`): Skills, Rules, Settings
- Alle Dokumentation und Memory-Files

**Git-Befehle:**

- IMMER mit `git -C <WORKTREE_PATH> ...`. Beispiele:
  - `git -C <WORKTREE_PATH> status`
  - `git -C <WORKTREE_PATH> add src/Foo.php`
  - `git -C <WORKTREE_PATH> commit -m "<TICKET-NUMMER> | ..."`
  - `git -C <WORKTREE_PATH> diff`
- Recherche-Befehle (`git log --all --grep=...`) können auch im Haupt-Repo laufen — Git teilt die History.

**Tests / PHPStan / iwf / Docker (WICHTIG — Container-Pfad-Problem):**

- Die Container des **Haupt-Stacks** sehen NUR den Haupt-Repo-Pfad. Sie sehen den Worktree-Code NICHT.
- → `iwf run phpstan` bzw. Container-basierte PHPUnit-Aufrufe gegen den Haupt-Stack würden den
  **Haupt-Repo-Stand** testen, nicht die Worktree-Änderungen.
- Bevor du Container-basierte Tests laufen lässt: dem Benutzer melden:
  ```
  ⚠️ Tests/PHPStan laufen im Docker-Container des Haupt-Stacks und sehen NUR den Haupt-Repo-Stand.
  Worktree-Änderungen werden NICHT getestet, bis der Branch im Haupt-Repo ausgecheckt ist.
  Optionen:
  1) Tests im Worktree-eigenen Stack laufen lassen (falls vorhanden): cd <WORKTREE_PATH> && iwf run ...
  2) Tests jetzt OHNE Docker laufen (cd <WORKTREE_PATH>; vendor/bin/phpunit ...)
  3) Branch im Haupt-Repo auschecken (Worktree wird dadurch blockiert/entfernt) und dann Tests
  4) Tests überspringen — Validation später durch User
  ```
- Default: Option 4 — Validation überlassen wir dem User.

---

### Phase 0b: Already-Solved-Check (IMMER ZUERST!)

**Haupt-Branch `<BASE>`:** der Merge-Ziel-Branch des Projekts (`develop` oder `main`) — ermitteln über
`git symbolic-ref refs/remotes/origin/HEAD --short` (→ `origin/<BASE>`); im Zweifel den Benutzer fragen.

**Schritt 0: Prüfe ob der Task bereits gelöst wurde**

1. Extrahiere die Ticket-Nummer aus dem Dateinamen (z.B. `<PREFIX>-3963` aus `<PREFIX>-3963_some_title.md`)
2. Durchsuche die Git-Historie nach Commits mit dieser Ticket-Nummer:
   ```bash
   git log --oneline --all --grep="<TICKET-NUMMER>"
   ```
3. Prüfe auch ob ein Feature-Branch existiert und bereits gemerged wurde:
   ```bash
   git branch -a | grep -i "<TICKET-NUMMER>"
   git log --oneline <BASE> --grep="<TICKET-NUMMER>"
   ```

**Auswertung:**

| Situation                                 | Aktion                                 |
|-------------------------------------------|----------------------------------------|
| Commits mit Ticket-Nr in `<BASE>` gefunden | Task ist abgeschlossen und gemerged    |
| Feature-Branch existiert mit Commits      | Task ist in Arbeit                     |
| Keine Commits/Branches gefunden           | Task ist neu → weiter mit Phase 1      |

**Bei bereits gelöstem/bearbeitetem Task:**

- Zeige dem Benutzer die gefundenen Commits an
- Zeige den Branch-Status an
- Falls Task in Arbeit: Frage ob fortgesetzt werden soll
- Aktualisiere den Status im Task-File entsprechend:
    - `🟢 Abgeschlossen` - wenn in `<BASE>` gemerged
    - `🟡 In Arbeit` - wenn Feature-Branch existiert aber nicht gemerged

**Status-Meldungen:**

```
🟢 TASK BEREITS ABGESCHLOSSEN
Ticket: <TICKET-NUMMER>
Status: Gemerged in <BASE>
Gefundene Commits: <Liste>
```

ODER

```
🟡 TASK IN ARBEIT
Ticket: <TICKET-NUMMER>
Branch: feature/<branch-name>
Status: Nicht gemerged

Möchtest du die Arbeit an diesem Task fortsetzen?
```

---

### Phase 1: Vollständigkeits-Check

**Schritt 1: Task-File prüfen**

Prüfe ob folgende Pflicht-Abschnitte vorhanden und ausgefüllt sind:

- [ ] `### Status` - Status-Abschnitt vorhanden
- [ ] `## Analyse` - Fachliche und technische Analyse
- [ ] `## Lösungsplan` - Strukturierter Plan mit konkreten Schritten

**Bei fehlenden Abschnitten:**

```
⚠️ TASK-FILE UNVOLLSTÄNDIG

Fehlende Abschnitte:
- [ ] Analyse
- [ ] Lösungsplan

→ Verwende `/start-task <TICKET-NUMMER>` für den vollständigen Workflow mit Analyse und Planung.
```

**Stoppe und informiere den Benutzer!** Fahre NUR fort wenn alle Pflicht-Abschnitte vorhanden sind.

**Schritt 2: Feature-Branch sicherstellen**

- **Falls Worktree-Routing in Phase 0a aktiviert wurde** (Default-Pfad oder bestehender Worktree): Der
  Feature-Branch ist im Worktree bereits aktiv. Im Haupt-Repo bleibt `<BASE>` (oder ein anderer Branch)
  ausgecheckt — das ist gewollt. KEIN `git checkout` im Haupt-Repo. Nur Status auf `🟡 In Arbeit`
  aktualisieren und weiter.
- **Nur falls `--no-worktree` gesetzt ist** (Arbeit komplett im Haupt-Repo):
  - Prüfe ob bereits ein passender Branch existiert
  - Falls nein, erstelle Branch nach Schema: `feature/<TicketNummer>_<TicketTitelKurz>`
  - Wechsle auf den Feature-Branch
  - Aktualisiere Status auf `🟡 In Arbeit`

---

### Phase 2: Umsetzung

**Schritt 3: Relevante Dokumentation lesen**

- Lies die `CLAUDE.md` im Projekt-Root und alle darin referenzierten Dokumente (falls noch nicht gelesen)
- Lies den `## Lösungsplan` im Task-File sorgfältig

**Schritt 4: Task implementieren**

- Arbeite den Lösungsplan systematisch ab
- Nutze die TODO-Liste um den Fortschritt zu tracken
- **NIEMALS committen!** Der Benutzer committed selbst. Änderungen bleiben unstaged.

**Schritt 5: Tests erstellen (PFLICHT!)**

**WICHTIG:** Code-Änderungen ohne Tests sind unvollständig!

**Test-Pflicht gilt für:**

1. **Neue Controller** → Controller-Test MUSS erstellt werden
2. **Änderungen an Business-Logik** → Tests MÜSSEN erstellt/erweitert werden
   - Geänderte Entities (z.B. Berechnungs-Getter)
   - Geänderte Services, Handlers, Commands
   - Geänderte Export-/Import-Funktionalität
   - Geänderte Berechnungs-/Bedingungs-Logik

**Faustregel:**
> "Wenn du eine Methode änderst, die in Tests verwendet wird, erweitere diese Tests um das neue Verhalten zu prüfen."

**Dokumentation:**

- Testing-Konventionen (verbindlich): `.claude/rules/testing.md` — Test-Struktur, Fixtures, Runner, Best Practices
- Permissions-/Rollen-Doku des Projekts (siehe Verweise in der `CLAUDE.md`) — für Access-Tests

**Naming-Convention für Controller-Tests:**

| Controller                             | Test                                   |
|----------------------------------------|----------------------------------------|
| `src/Controller/.../FooController.php` | `tests/Controller/.../FooTest.php`     |

**Test-Anforderungen (Controller-Tests):**

- Mindestens ein Test für den "Happy Path" (erfolgreicher Request, `Response::HTTP_OK`)
- Test für fehlende Berechtigung (403 Forbidden)
- Test für nicht authentifiziert (401 Unauthorized) falls relevant

**Test-Anforderungen (Business-Logik):**

- Unit-Tests für geänderte Methoden/Logik
- Integrations-Tests für geänderte Workflows (z.B. Export-Tests)
- Bestehende Tests erweitern, wenn geänderter Code dort verwendet wird

**Fixture-Tampering zur Laufzeit:**

Falls die bestehenden Fixtures nicht ausreichen, um eine Änderung zu testen, ist es erlaubt, Fixtures
**zur Laufzeit im Test anzupassen**:

```php
// Beispiel: Entity-Zustand für Test anpassen
$project = $this->loadFixture(LoadProjects::class, 'project_in_review');
$project->setStatus(ProjectStatus::FINISHED);
$this->em->flush();

// Jetzt Test mit angepasstem Zustand durchführen
```

Dies ist oft einfacher als neue Fixture-Dateien zu erstellen und vermeidet Fixture-Bloat.

**Test ausführen:**

Der konkrete Runner ist projektabhängig (siehe `.claude/rules/testing.md` bzw. `CLAUDE.md`), z.B.:

```bash
# Controller-Tests
iwf run "vendor/bin/phpunit tests/Controller/Pfad/ZumTest.php"

# Unit-Tests
iwf run "vendor/bin/phpunit tests/Model/Enum/FooTest.php"

# Einzelne Test-Methode
iwf run "vendor/bin/phpunit --filter testHappyPath"

# Alle Tests in einem Verzeichnis
iwf run "vendor/bin/phpunit tests/Controller/Feature/"
```

---

### Phase 3: Qualitätssicherung

**Schritt 6: Tests und PHPStan ausführen**

```bash
# PHPStan (projektüblicher Aufruf — siehe CLAUDE.md)
iwf run phpstan

# Controller-Tests (Runner siehe .claude/rules/testing.md)
iwf run "vendor/bin/phpunit tests/Controller/Pfad/ZumTest.php"
```

**Bei Fehlern:** Behebe sie bevor du fortfährst!

---

### Phase 4: Abschluss

**Schritt 7: Dokumentation finalisieren**

> **Warum `### Für Kunde` der wichtigste Absatz des Task-Files ist:** genau dieser Unterabschnitt wird
> ins Jira-Feld „Lösung" übernommen (Kanban belegt den Editor damit vor). Das Task-File selbst wird
> **nicht mitcommittet** — nach dem Merge und dem Aufräumen des Worktrees ist das Jira-Feld die
> **einzige** Stelle, an der noch steht, was entschieden, abgewichen und angenommen wurde. Was hier
> fehlt, ist dauerhaft weg.

Ergänze/aktualisiere im Task-File den Abschnitt:

```markdown
## JIRA Lösungsfeld

### Für Test-Ingenieur

**Manuelle Testanleitung:**

- Rolle: [Welche Benutzerrolle für den Test erforderlich ist]
- URL/Seite: [Exakte URL oder Menüpfad zur Funktion]
- Vorbedingungen: [z.B. Testdaten, Feature-Flags, etc.]

**Testschritte:**

1. [Schritt-für-Schritt Anleitung]
2. [Was zu prüfen ist]
3. [Erwartetes Ergebnis]

**Geänderte Dateien:**

- Backend: [Liste der geänderten/neuen PHP-Dateien]
- Frontend: [Liste der geänderten/neuen Frontend-Dateien]
- Config: [Geänderte Konfigurationsdateien]
- Tests: [Neu erstellte Tests]

### Für Kunde

[Verständliche Beschreibung: Welches Problem wurde gelöst? Was ist neu?]

**Entscheidungen, Abweichungen, Annahmen:**

- **Entscheidung:** [Was entschieden wurde — warum, welche Alternative verworfen]
- **Abweichung von AK „[Kriterium]":** [Was anders umgesetzt ist als gefordert — warum]
- **Annahme:** [Was angenommen wurde, weil Ticket/AK es nicht sagen — woraus abgeleitet; was zu tun ist, falls sie falsch ist]
- **Bewusst nicht umgesetzt:** [Was ausgelassen wurde — warum, ggf. Folge-Ticket]
- **Wichtig zu wissen:** [Nebenwirkung, Migration, Konfigurationsschritt, Grenze der Lösung]
```

**Der Block „Entscheidungen, Abweichungen, Annahmen" ist PFLICHT** — er ist der Grund, warum es das
Jira-Feld gibt (siehe Kasten oben). Regeln dafür:

- **Quellen zusammentragen:** `## Entscheidungen` im Task-File, alles was während der Umsetzung mit dem
  Benutzer besprochen wurde, jede Stelle wo du vom Lösungsplan oder von den Akzeptanzkriterien
  abgewichen bist, und jede Lücke im Ticket, die du selbst gefüllt hast.
- **Jede Abweichung von den AK muss dastehen** — mit dem betroffenen Kriterium und der Begründung.
  Ein Reviewer, der die AK gegen die Umsetzung hält, darf nicht überrascht werden.
- **Verständlich, nicht technisch:** „Warum" statt Klassennamen; Code-Mechanik steht im Code, die
  Begründung nirgends.
- **Nichts weglassen, weil es „nur eine Kleinigkeit" ist.** Wenn du beim Schreiben zögerst, ob es
  reingehört: es gehört rein.
- **Gibt es wirklich nichts:** genau eine Zeile schreiben — „Keine Abweichungen von den
  Akzeptanzkriterien, keine offenen Annahmen." Den Block weglassen ist nicht erlaubt: dann bleibt
  unklar, ob nichts war oder ob es vergessen wurde.

**Schritt 7b: `## Lösung` ins Task-File schreiben (PFLICHT)**

Commit-Message **und** Test-URL werden nicht nur am Schluss ausgegeben (Schritt 9), sondern **zusätzlich
dauerhaft ins Task-File** geschrieben — sonst gehen sie nach der Session verloren. Ergänze/aktualisiere direkt
nach `## JIRA Lösungsfeld` den Abschnitt `## Lösung`:

```markdown
## Lösung

**Commit-Message:** `<TICKET-NUMMER> | <Beschreibung auf Englisch>`

**Test-URL (Ergebnis ansehen):** `https://<Worktree-Stack-Host>/<konkreter-Pfad-zum-Ergebnis>`
— <1 Satz: warum hier / ggf. konkreter Beispiel-Datensatz>
```

(Worktree-Stack-Host aus dem Worktree-Block des Task-Files; ohne Worktree die Haupt-Stack-URL
`https://<repo-ordnername>.<stackDomain>` — Repo-Ordnername = letzter Pfadbestandteil von `repoDir`,
`stackDomain` aus `.claude/project.json`.)

Dieser Abschnitt ist die Single Source of Truth: erst hier ins Task-File schreiben, dann inhaltlich identisch
in die Abschluss-Zusammenfassung (Schritt 9, Blöcke „## Commit-Message" und „## 🔗 Ergebnis ansehen") übernehmen.

**Schritt 8: Abschluss-Checkliste abhaken**

Stelle sicher, dass im Task-File die Abschluss-Checkliste vorhanden ist und hake alle erledigten Punkte ab:

```markdown
## Abschluss-Checkliste

- [x] Already-Solved-Check durchgeführt
- [x] Feature-Branch erstellt und aktiv
- [x] Lösung vollständig implementiert
- [x] Tests erstellt (Controller-Tests für jeden neuen Controller, Tests für geänderte Business-Logik)
- [x] Tests/PHPStan ausgeführt und bestanden
- [x] JIRA Lösungsfeld ausgefüllt (beide Abschnitte; „Für Kunde" inkl. Entscheidungen, Abweichungen von den AK und Annahmen)
- [x] `## Lösung` ins Task-File geschrieben (Commit-Message + Test-URL)
- [ ] Änderungen committed (vom Benutzer, mit korrekter Commit-Message, OHNE Co-Authored-By)
- [x] Abschluss-Zusammenfassung dem Benutzer ausgegeben
```

**Schritt 9: Abschluss-Zusammenfassung ausgeben (PFLICHT!)**

```
✅ TASK ERFOLGREICH ABGESCHLOSSEN

## Zusammenfassung
[1-2 Sätze was gemacht wurde]

## Manuelle Verifikation
- **Rolle:** [Benutzerrolle]
- **Seite:** [Menüpfad / URL]
- **Was prüfen:** [Kurze Beschreibung]

## 🔗 Ergebnis ansehen (Worktree)
- **URL:** https://<Worktree-Stack-Host>/<konkreter-Pfad-zum-Ergebnis>
- **Warum hier:** [1 Satz: an dieser Stelle ist die Änderung am besten sichtbar]
- [ggf.] **Beispiel-Datensatz:** [Name/Nr eines Datensatzes/einer Entität, die das Feature tatsächlich zeigt]

## Erstellte Tests
- [Liste der Controller-Tests]
- [Wie ausführen: projektüblicher Runner, z.B. iwf run "vendor/bin/phpunit tests/..."]

## Commit-Message
```
<TICKET-NUMMER> | <Beschreibung auf Englisch>
```

## Nächste Schritte
- [ ] Code Review
- [ ] Merge in <BASE>
- [ ] QA-Test auf Testumgebung
```

**PFLICHT — Commit-Message:** Am Schluss der Abschluss-Zusammenfassung IMMER die vorgeschlagene Commit-Message
als eigenen, kopierbaren Block ausgeben (Schema `<TICKET-NUMMER> | <Beschreibung auf Englisch>`, siehe
„Commit-Message Convention" unten) — auch wenn nicht committet wird. Der Benutzer committet selbst; dieselbe
Message steht zusätzlich dauerhaft im Task-File unter `## Lösung` (Schritt 7b).

**PFLICHT — „Ergebnis ansehen"-URL:** Am Schluss IMMER eine konkrete, klickbare **Worktree-URL** ausgeben, unter
der der Benutzer das Task-Ergebnis am besten sieht — und dieselbe URL zusätzlich ins Task-File unter `## Lösung`
schreiben (Schritt 7b). So leitest du sie ab:

1. **Basis-URL:** aus dem Worktree-Block des Task-Files (Worktree-Stack-Host). Falls kein Worktree
   (`--no-worktree`), die Haupt-Stack-URL `https://<stackDomain>` verwenden (`stackDomain` aus
   `.claude/project.json`).
2. **Stack läuft?** Kurz prüfen (`docker ps` — laufen die Container des Worktree-Stacks?). Falls nicht:
   Start-Hinweis dazuschreiben (`cd <WORKTREE_PATH> && iwf stack start`), URL trotzdem zeigen.
3. **Zielseite wählen:** die Seite/Route, auf der die Änderung direkt sichtbar/auslösbar ist
   (z.B. die Detail-Seite, der Report-Download-Button, die Liste, das Formular). Bei reinen API/Export-Änderungen
   die Seite zeigen, von der aus der Export/die Aktion ausgelöst wird.
4. **Auf einen passenden Datensatz verlinken (wenn sinnvoll):** Wo das Feature nur bei bestimmten Daten sichtbar
   ist, einen **konkreten** Beispiel-Datensatz aus der Worktree-DB ermitteln und direkt verlinken — z.B. per
   `bin/console dbal:run-sql '<einzeilige Query>'` (im Stack via `iwf run "..."`) die ID/Nr eines Datensatzes
   finden, der die Bedingung erfüllt, und die Detail-/Report-URL daraus bauen. Findet sich kein Datensatz: den
   Menüpfad + die nötige Vorbedingung beschreiben (was angelegt werden muss, damit es sichtbar wird).
5. **Routen nicht raten** — aus dem Routing des Projekts ableiten (Symfony: `config/routes*`,
   `#[Route]`-Attribute an den Controllern; React-Frontend: Router bzw. Route-Translations).

Aktualisiere den Status im Task-File auf `🟢 Abgeschlossen`.

---

## Commit-Message Convention

Alle Commits MÜSSEN diesem Schema folgen:

```
<TICKET-NUMMER> | <Beschreibung auf Englisch>
```

**Beispiele** (`<PREFIX>` aus `.claude/project.json`):

- `<PREFIX>-3963 | Add correction request table component`
- `<PREFIX>-3963 | Implement accept/reject actions for requests`

---

## Wichtige Regeln

1. **Already-Solved-Check**: IMMER zuerst prüfen ob Task schon bearbeitet wurde
2. **Worktree-Default**: Worktree wird automatisch angelegt, sofern noch keiner existiert und `--no-worktree` nicht im Input ist
3. **Vollständigkeits-Check**: Nur fortfahren wenn Analyse und Lösungsplan vorhanden sind
4. **Tests**: PFLICHT für jeden neuen Controller (Controller-Test) und für Änderungen an Business-Logik
5. **Nachfragen**: Bei Unklarheiten IMMER fragen, niemals raten
6. **Sprache**: Branch-Namen, Commit-Messages und Code-Kommentare auf Englisch
7. **Commits**: Aussagekräftige Messages mit Ticket-Nummer (Schema beachten!)
8. **Keine AI-Erwähnung**: Weder in Commits noch in Code-Kommentaren
9. **ULTRATHINK**: Dieses Command erfordert gründliche Analyse - nutze erweiterte Denkzeit
10. **NIE PUSHEN**: Unter keinen Umständen selbst pushen oder danach fragen - das macht der Benutzer selbst
11. **Verifikations-URL (PFLICHT)**: Jedes Lösen MUSS am Ende mit einer konkreten, klickbaren App-URL abschliessen,
    unter der der Benutzer selbst einsehen/überprüfen kann, dass der Task erfolgreich umgesetzt wurde. Die
    Abschluss-Zusammenfassung gilt OHNE diese URL als unvollständig — niemals ohne sie abschliessen. Ableitung und
    Format siehe Phase 4, Schritt 9 (Block „🔗 Ergebnis ansehen" + „PFLICHT — „Ergebnis ansehen"-URL").
12. **Aktuelles Datum/Zeit immer über den DateProvider (PFLICHT)**: NIEMALS `new \DateTimeImmutable()`,
    `new \DateTime()`, `time()` o.ä. für „jetzt" verwenden. IMMER den Projekt-Provider
    `Coala\DateProviderBundle\Service\DateProvider\DateProviderInterface` injizieren und
    `->getCurrentDateImmutable()` (bzw. `->getCurrentDate()` für mutable) aufrufen. **Warum:** Die Projekte
    pinnen bzw. warpen die Uhr über den Provider (Tests setzen ein Stichdatum; auch produktiv kann eine
    Time-Warp/gepinnte Uhr aktiv sein) — Gedmo-Timestamps und die Geschäftslogik laufen über den Provider.
    Ein direktes `new \DateTimeImmutable()` liefert Echtzeit und driftet von der Provider-Uhr ab → subtile
    Bugs (z.B. Staleness/Retention oder Jahreswechsel-Logik vergleicht eine ge-warpte `createdAt` gegen ein
    Echtzeit-`now`). **Schichtung:** „now" nur in der Service-/Handler-Schicht aus dem Provider holen und als
    `$now`-Parameter in Entities/Repositories durchreichen (keine Clock-Zugriffe in Entity- oder Query-Schicht).
    **In Tests:** die Provider-Uhr via `self::getService(DateProviderInterface::class)` lesen und Seed-Zeiten
    relativ dazu setzen (`->getCurrentDateImmutable()->modify('-13 hours')`), damit Seed-Zeit und geprüfte „now"
    dieselbe (gepinnte/ge-warpte) Uhr verwenden.
13. **KEINE Ticket-Nummern in Code-Kommentaren (MUST NOT)**: Inline-Kommentare und PHPDoc/Docblocks dürfen
    **NIEMALS** eine Ticket-Nummer enthalten (`<PREFIX>-NNNN`, inkl. `.a`/`.b`-Suffixe). Das „Warum" gehört in
    den Kommentar selbst; die Ticket-Historie gehört ins Task-File und in die Commit-Message — nicht in den
    Quellcode. (Einzige Ausnahme: die `getDescription()`-Zeile einer Doctrine-Migration führt die Ticket-Nr.
    wie gehabt als Identifikations-Label.) Gilt zusätzlich zur AI-Erwähnungs-Regel (#8).
14. **Kommentare beschreiben Zustand, nicht Änderung (MUST)**: Ein Kommentar erklärt **immer den aktuellen
    Zustand** — was der Code IST und TUT —, **nie eine Änderung/Historie** relativ zu einem früheren Stand.
    Vermeide Formulierungen wie „the **existing** X", „the **former** Y", „**replaces** Z", „**no longer** …",
    „**now** … instead", „**Mirrors** …": sie veralten und werden verwirrend, sobald der referenzierte frühere
    Zustand verschwunden ist (der Leser sieht nur noch den aktuellen Code). Schreibe stattdessen, was die
    Sache standalone ist/tut. (Ausnahme: Doctrine-Migrations-Docblocks dürfen die Schema-Transition
    beschreiben — eine Migration *ist* ein Änderungs-Skript.)
15. **Lösung ins Task-File (PFLICHT)**: Commit-Message **und** Test-URL („Ergebnis ansehen") gehören nicht nur
    in die Abschluss-Zusammenfassung, sondern zusätzlich **dauerhaft ins Task-File** unter den Abschnitt
    `## Lösung` (Phase 4, Schritt 7b). Nur konsolen-ausgegeben zählt als unvollständig — nach der Session wäre
    beides sonst weg.

---

## Weitere Infos

- Importiere Namespaces prinzipiell mit "use", schreibe Namespaces niemals direkt in den Code
- Beachte bei deinem Code die Code-Review-Learnings des Projekts (falls vorhanden — siehe Verweise in der `CLAUDE.md`)
- Übersetzungen werden nur in den deutschen Translation-Dateien gepflegt — keine hardcodierten Strings im
  Code/Template. Details: `~/Library/Application Support/Kanban/claude/rules/translations.md`

---

## Starte jetzt!

Beginne jetzt mit Phase 0a: Worktree-Routing, danach Phase 0b: Already-Solved-Check.
