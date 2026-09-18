---
name: start-task
description: Analysiere und plane einen JIRA-Task aus einem Markdown-File
argument-hint: <TICKET-NUMMER oder task-file.md> [--no-worktree]
disable-model-invocation: true
---

# START TASK - Analyse & Planungs-Arbeitsanweisung

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `dockerStack`, `stackDomain`,
> `gitlabProjectPath`): stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen
> Projektwert brauchst — nie raten. `dockerStack: false` heisst: kein Docker-Stack — dann gibt es weder
> `stackDomain` noch `iwf`, und Befehle laufen direkt im Worktree.

Du bist ein erfahrener Software-Entwickler, der JIRA-Tasks systematisch analysiert und einen Lösungsplan erstellt.

**WICHTIG:** Dieses Command führt NUR Analyse und Planung durch. Die Umsetzung erfolgt separat mit `solve-task`.

Platzhalter in spitzen Klammern (`<PREFIX>`, `<tasksPath>`, `<worktreePrefix>`, `<stackDomain>`) stehen im
Folgenden für die entsprechenden Werte aus `.claude/project.json`.

## Argument-Auflösung

**Input:** $ARGUMENTS

**Schritt 0: Task-File ermitteln**

Falls das Argument eine Ticket-Nummer ist (z.B. `<PREFIX>-1234`), suche automatisch das passende Task-File:

```bash
# Suche nach Task-File mit dieser Ticket-Nummer (tasksPath aus .claude/project.json)
ls <tasksPath>/<TICKET-NUMMER>*.md
```

**Auswertung:**

| Situation | Aktion |
|-----------|--------|
| Genau 1 File gefunden | Verwende dieses File |
| Mehrere Files gefunden | Zeige Liste und frage Benutzer welches verwendet werden soll |
| Kein File gefunden | **Zuerst automatisch `get-task` ausführen** (siehe Fallback unten), dann mit dem neuen File fortfahren |
| Argument ist bereits ein Pfad | Verwende den Pfad direkt |

**Fallback: Kein Task-File vorhanden → automatisch `get-task` ausführen**

NICHT abbrechen und NICHT den Benutzer auf `get-task` verweisen, sondern den kompletten
`get-task`-Workflow selbst ausführen (Anweisungen in [get-task](get-task.md)):

1. JIRA-Ticket via MCP-Tool laden, Task-File im Task-Ordner (`tasksPath`) erstellen und
   Ticket-Zusammenfassung zeigen
2. Task-File-Namen normalisieren und Worktree anlegen (get-task-Default). Ein `--no-worktree`-Flag
   aus dem `start-task`-Input gilt dabei auch für den get-task-Schritt.
3. Danach normal mit diesem Workflow fortfahren — das neu erstellte Task-File ist der Input;
   der von get-task angelegte Worktree wird in Phase 0 über den Worktree-Block erkannt und geroutet.

Schlägt das Laden fehl (z.B. MCP-Tool nicht erreichbar), die Fehlermeldung aus get-task ausgeben
und ABBRECHEN — ohne Task-File kein `start-task`.

**Ermitteltes Task-File:** `<TASK_FILE>` (wird im weiteren Workflow verwendet)

---

## Dein Task-File

Lies und analysiere: `<TASK_FILE>`

**WICHTIG:** Dieses Command erfordert gründliches Nachdenken. Füge `ULTRATHINK` am Ende deiner Überlegungen hinzu, um
maximale Analyse-Tiefe zu gewährleisten.

## Worktree-Verhalten (Default: AN)

- **Standard:** Falls das Task-File noch keinen Worktree-Block hat, wird in Phase 0 automatisch einer angelegt
  und der Block ins Task-File eingefügt (nur Worktree, **kein** Docker-Stack wird gestartet).
- **Opt-out:** Wenn `$ARGUMENTS` das Flag `--no-worktree` enthält, KEIN Worktree anlegen — Analyse läuft im
  Haupt-Repo (altes Default-Verhalten). Das Flag wird beim Task-File-Lookup ignoriert.
- **Wie angelegt wird, entscheidet `dockerStack`:** `true` (oder fehlend) → `iwf worktree create`;
  `false` → `git worktree add` mit ermitteltem Basis-Branch.

> Vollständige Befehls-/Flag-Referenz zu beiden Wegen:
> `~/Library/Application Support/Kanban/claude/rules/worktree.md`.

---

## Workflow - Führe diese Schritte der Reihe nach aus:

### Phase 0: Worktree-Routing, Develop-Stand & Already-Solved-Check (IMMER ZUERST!)

**Schritt 0a-Pre: Worktree-Block im Task-File suchen**

Lies die ersten ~15 Zeilen des Task-Files und suche nach einem Block der Form:

```markdown
> 🌳 **WORKTREE**: `<worktreePrefix>/<PREFIX>-XXXX`\
> 🌿 **BRANCH**: `feature/<PREFIX>-XXXX_<title>`\
```

**Grundprinzip:** Claude bleibt im Haupt-Repo (Working-Directory wird NICHT gewechselt). Wenn ein
Worktree-Block existiert, werden Code-Reads und Git-Befehle für die Analyse in den Worktree-Pfad geroutet.
Task-File, CLAUDE.md, `.claude/`, Docs werden weiterhin aus dem Haupt-Repo gelesen.

**Fallunterscheidung:**

| Befund                                                              | Aktion                                                                                                                                                                            |
|---------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Worktree-Block vorhanden UND Pfad existiert UND Worktree gültig      | **WORKTREE-ROUTING aktivieren**: Code-Inspektion (`Read`, `Grep`, Symbol-Lookups) auf Worktree-Pfad. Git-Befehle mit `git -C <WORKTREE_PATH>`. Schritt 0a (Develop-Pull) entfällt. |
| Worktree-Block vorhanden, Pfad nicht (mehr) gültig                   | Benutzer informieren — Worktree wurde entfernt. Worktree-Block aus Task-File löschen. Weiter mit **Schritt 0a-Worktree** (Default: neu anlegen, ausser `--no-worktree`).            |
| Kein Worktree-Block vorhanden, KEIN `--no-worktree` im Input         | **Default-Pfad:** Direkt mit **Schritt 0a-Worktree** Worktree anlegen, dann Routing aktivieren.                                                                                    |
| Kein Worktree-Block vorhanden, `--no-worktree` im Input              | Worktree-Erstellung überspringen. Normal weiter mit Schritt 0a (Haupt-Repo, `develop` auschecken).                                                                                 |

**Schritt 0a-Worktree: Worktree per Default anlegen** (nur wenn kein Worktree-Block existiert und `--no-worktree` NICHT gesetzt)

0. **Falls die Datei nur `<PREFIX>-NNNN.md` heisst (kein englischer Titel): zuerst normalisieren** —
   englischen `snake_case`-Kurztitel generieren und nach `<tasksPath>/<PREFIX>-NNNN_<english_title>.md` umbenennen
   (= Phase 1, Schritt 2 vorgezogen). Der Worktree-Branch wird aus diesem Namen abgeleitet, **niemals ohne Suffix**.
1. Branch-Suffix = der `<english_title>`-Teil des (normalisierten) Dateinamens (immer gesetzt).
2. Worktree anlegen — **`dockerStack` aus `.claude/project.json` entscheidet, wie:**

   **`dockerStack: true` (oder fehlend):** `iwf worktree create NNNN <english_title>` ausführen
   (NNNN = nackte Ticket-Nummer, nicht `<PREFIX>-NNNN`).

   **`dockerStack: false`:** reiner Git-Worktree, Basis-Branch ermitteln statt annehmen:
   ```bash
   R=<repoDir>
   BASE=$(git -C "$R" symbolic-ref --quiet --short refs/remotes/origin/HEAD)
   if [ -z "$BASE" ]; then
     for kandidat in origin/develop origin/main develop main; do
       git -C "$R" rev-parse --verify --quiet "$kandidat" >/dev/null && { BASE="$kandidat"; break; }
     done
   fi
   [ -z "$BASE" ] && BASE=HEAD
   git -C "$R" worktree add <worktreePrefix>/<PREFIX>-NNNN \
       -b feature/<PREFIX>-NNNN_<english_title> --no-track "$BASE"
   ```
   (Befehls-/Flag-Referenz: `~/Library/Application Support/Kanban/claude/rules/worktree.md`.)
3. Nach erfolgreichem Lauf den Worktree-Block direkt unter die H1 des Task-Files einfügen
   (Format identisch zu `create-worktree` — die `🐳 **STACK**`-Zeile nur bei `dockerStack: true`).
4. WORKTREE-ROUTING für den Rest der Session aktivieren.
5. Schritt 0a (Develop-Pull im Haupt-Repo) entfällt — der Worktree wurde frisch vom Basis-Branch erstellt
   (mit Stack: `origin/develop`; ohne Stack: der oben ermittelte `$BASE`).

**Bei aktivem Worktree-Routing** beachte für alle Phasen:

- `Read`/`Grep`/Symbol-Suche auf Source-Files (`src/`, `assets/`, `tests/`, `templates/`, `config/`,
  `migrations/` etc.) IMMER mit absolutem Worktree-Pfad (`<worktreePrefix>/<PREFIX>-XXXX/...`).
- `Read` von Task-File, CLAUDE.md, Docs, `.claude/*`: Haupt-Repo-Pfad — die Worktree-Stände sind
  oft veraltet/nicht vorhanden.
- Git-Inspektion (Commits, Branches): `git -C <WORKTREE_PATH> log/diff/status`.
- Recherche im Codebase: Wenn der Worktree-Branch sich kaum von develop unterscheidet, ist Read im
  Haupt-Repo OK — sonst kann sich der Code unterscheiden und Analyse läuft auf veraltetem Stand.

---

**Schritt 0a: In develop wechseln** (nur ohne aktiven Worktree UND mit `--no-worktree`)

**PFLICHT (nur wenn explizit ohne Worktree gearbeitet wird):** Wechsle IMMER zuerst in den `develop`-Branch,
um sicherzustellen, dass du den aktuellen Stand des Projekts analysierst:

```bash
git checkout develop && git pull
```

**Schritt 0b: Prüfe ob der Task bereits gelöst wurde**

1. Extrahiere die Ticket-Nummer aus dem Dateinamen (z.B. `<PREFIX>-3963` aus `<PREFIX>-3963_some_title.md`)
2. Durchsuche die Git-Historie nach Commits mit dieser Ticket-Nummer:
   ```bash
   git log --oneline --all --grep="<TICKET-NUMMER>"
   ```
3. Prüfe auch ob ein Feature-Branch existiert und bereits gemerged wurde:
   ```bash
   git branch -a | grep -i "<TICKET-NUMMER>"
   git log --oneline develop --grep="<TICKET-NUMMER>"
   ```

**Auswertung:**

| Situation                                 | Aktion                              |
|-------------------------------------------|-------------------------------------|
| Commits mit Ticket-Nr in develop gefunden | Task ist abgeschlossen und gemerged |
| Feature-Branch existiert mit Commits      | Task ist in Arbeit                  |
| Keine Commits/Branches gefunden           | Task ist neu → weiter mit Phase 1   |

**Bei bereits gelöstem/bearbeitetem Task:**

- Zeige dem Benutzer die gefundenen Commits an (mit `git log --oneline --all --grep="<TICKET>"`)
- Zeige den Branch-Status an
- **Führe trotzdem Phase 2 (Analyse) durch** und dokumentiere im Task-File
- Aktualisiere den Status im Task-File entsprechend:
    - `🟢 Abgeschlossen` - wenn in develop gemerged
    - `🟡 In Arbeit` - wenn Feature-Branch existiert aber nicht gemerged

**Melde den Status:**

```
🟢 TASK BEREITS ABGESCHLOSSEN

Ticket: <TICKET-NUMMER>
Status: Gemerged in develop

Gefundene Commits:
<Liste der Commits>
```

ODER

```
🟡 TASK IN ARBEIT

Ticket: <TICKET-NUMMER>
Branch: feature/<branch-name>
Status: Nicht gemerged

Gefundene Commits:
<Liste der Commits>

Möchtest du die Arbeit an diesem Task fortsetzen?
```

- **Immer:** Phase 2 (Analyse) durchführen und Status im Task-File dokumentieren
- Falls Task in Arbeit: Frage ob fortgesetzt werden soll
- Falls neu: Weiter mit allen Phasen

---

### Phase 1: Vorbereitung

**Schritt 1: Dokumentation lesen**

- Lies die `CLAUDE.md` im Projekt-Root (falls vorhanden) und alle darin referenzierten Dokumente
- Lies das Task-File vollständig und verstehe den Kontext

**Schritt 2: Task-File normalisieren**

- Extrahiere aus Zeile 1: `<TicketNummer>` und `<Deutsche Beschreibung>`
- Erstelle daraus einen kurzen englischen Titel: `<TicketTitelKurz>` (snake_case, lowercase)
- Benenne das File um nach Schema: `<TicketNummer>_<TicketTitelKurz>.md`
- Beispiel: `PROJ-123_implement_user_authentication.md`
- **Branch-Namen nachziehen (PFLICHT, schliesst die „namenloser Branch“-Lücke):** Wenn bereits ein Worktree
  existiert (Worktree-Block vorhanden) und dessen Branch noch **suffixlos** heisst (`feature/<PREFIX>-NNNN`,
  weil `get-task` ihn vor der Normalisierung erstellt hat), den Branch jetzt auf
  `feature/<PREFIX>-NNNN_<TicketTitelKurz>` umbenennen — **lokal und remote**:
  ```bash
  # lokal (im Worktree)
  git -C <WORKTREE_PATH> branch -m feature/<PREFIX>-NNNN_<TicketTitelKurz>
  # nur falls der alte Branch schon gepusht war (sonst entfällt der Remote-Teil):
  git -C <WORKTREE_PATH> push -u origin feature/<PREFIX>-NNNN_<TicketTitelKurz>
  git -C <WORKTREE_PATH> push origin --delete feature/<PREFIX>-NNNN
  ```
  Danach die `🌿 **BRANCH**:`-Zeile im Worktree-Block des Task-Files entsprechend aktualisieren. (Worktree-Pfad
  und — falls es einen gibt — Stack-Name bleiben unverändert: sie hängen an der Ticket-Nummer, nicht am
  Branch-Suffix.)
- Füge direkt unter der Überschrift einen Status-Abschnitt hinzu (falls nicht vorhanden):
  ```markdown
  ### Status
  🔴 Offen
  ```

**Schritt 3: Feature-Branch / Worktree sicherstellen**

- **Falls Worktree-Routing in Phase 0 aktiviert wurde** (Default-Pfad oder bestehender Worktree): Der
  Feature-Branch ist im Worktree bereits angelegt und aktiv. Im Haupt-Repo bleibt `develop` ausgecheckt —
  das ist gewollt. KEIN `git checkout` im Haupt-Repo.
- **Nur falls `--no-worktree` gesetzt ist** (Arbeit komplett im Haupt-Repo):
  - Prüfe ob bereits ein passender Branch existiert
  - Falls nein, erstelle Branch nach Schema: `feature/<TicketNummer>_<TicketTitelKurz>`
  - Beispiel: `feature/<PREFIX>-123_implement_user_authentication`
  - Wechsle auf den Feature-Branch

---

### Phase 2: Analyse & Planung

**Schritt 4: Fachliche Analyse dokumentieren**

- Analysiere den Task und dokumentiere im Task-File unter `## Analyse`:
  ```markdown
  ## Analyse

  **Art der Änderung:** [z.B. Feature, Bugfix, Refactoring, UI-Anpassung]

  **Betroffene Bereiche:**
  - [z.B. Frontend: Seite/Komponente XY]
  - [z.B. Backend: API-Endpunkt XY]
  - [z.B. Datenbank: Neue Tabelle/Spalte]

  **Fachliche Einordnung:**
  [Kurze Beschreibung was fachlich/funktional erreicht werden soll und warum]

  **Technische Einordnung:**
  [Welche Technologien/Patterns sind betroffen, geschätzte Komplexität]
  ```

- **Berechtigungs-Tests prüfen:** Falls der Task Berechtigungen ändert (Rollen bzw. die
  Permission-Konfiguration des Projekts — wo die liegt, sagt die `CLAUDE.md`/Projekt-Doku),
  suche nach bestehenden Tests, die diese Zugriffe testen (`userAccessProvider`, `HTTP_FORBIDDEN`,
  `HTTP_OK`, `HTTP_UNAUTHORIZED`).
  Durchsuche dazu `tests/Controller/` nach dem betroffenen Controller-Test und prüfe den `userAccessProvider()`.
  Die geänderten Rollen müssen im Lösungsplan als Test-Anpassung aufgeführt werden.
  ```bash
  # Beispiel: Suche nach Tests für einen bestimmten Controller
  grep -r "<ControllerName>" tests/Controller/ --include="*.php" -l
  ```

- **Datenmigration prüfen:** Falls der Task bestehende Daten ändern, korrigieren oder transformieren muss,
  prüfe die projektüblichen Migrationswege (siehe `CLAUDE.md`/Projekt-Doku) und entscheide:
    - **Doctrine Migration** (`migrations/`) — bei Schema-Änderungen oder einfachen SQL-Updates.
    - **Projektspezifischer Migrations-Mechanismus** — bei komplexen Datenmigrationen, die DI-Zugriff
      (Repositories, Logger, Services) oder Command-Ausführung benötigen. Welcher Mechanismus das im
      Projekt ist, steht in der Projekt-Doku — nicht raten.
      Dokumentiere die Entscheidung und Begründung im Analyse-Abschnitt.

**Schritt 5: Verständnis sicherstellen**

- Falls du etwas am Task nicht verstehst: **Frage SOFORT nach** bevor du fortfährst
- Kläre Unklarheiten, bevor du mit der Planung beginnst

**Schritt 6: Plan erstellen und dokumentieren**

- Erstelle einen strukturierten Lösungsplan mit konkreten Schritten
- Dokumentiere den Plan im Task-File unter einem neuen Abschnitt `## Lösungsplan`
- Der Plan sollte so detailliert sein, dass die Umsetzung klar ist

**Beispiel für einen Lösungsplan:**

```markdown
## Lösungsplan

### Backend

1. Neuen Controller erstellen: `src/Controller/.../FooController.php`
2. Query/Command erstellen für ...
3. Handler implementieren mit ...

### Frontend

4. Komponente/Template erstellen bzw. anpassen (z.B. `assets/pages/.../FooComponent.tsx`
   oder `templates/.../foo.html.twig`)
5. API-Integration / JS+SCSS ergänzen

### Tests

6. Controller-Test erstellen: `tests/Controller/.../FooTest.php`
7. Unit-Tests für geänderte Business-Logik (z.B. Entity-Methoden, Enums)
8. Bestehende Tests erweitern, falls geänderter Code dort verwendet wird

### Config

9. Berechtigungen/Rollen gemäss Projekt-Konvention prüfen/anpassen
10. Weitere Projekt-Konfiguration (Views, Formular-/Step-Config, …) gemäss Projekt-Doku anpassen
```

**WICHTIG bei der Planung:**

- **Tests sind PFLICHT** - nicht nur für neue Controller, sondern für ALLE Business-Logik-Änderungen
- Plane Tests für: geänderte Entities, Services, Handlers, Export/Import-Logik, Berechnungen
- Wenn du eine Methode änderst, die in Tests verwendet wird, plane die Test-Erweiterung ein

**Schritt 6b: Impact-Analyse (Nebeneffekte & Verzweigungen erkennen)**

Wenn nicht explizit erwähnt ist, dass keine Impact-Analyse benötigt wird, gilt Folgendes:
⚠️ **PFLICHT:** Lies und befolge die Anleitung in
[impact-analysis methodology](../impact-analysis/methodology.md)

**Modus:** `start-task` → Datenquelle ist der **Lösungsplan** (geplante Datei-Änderungen).
Ermittle aus dem Plan, welche Dateien/Klassen/Methoden geändert werden sollen, und nutze diese
als Ausgangspunkt.

**Führe alle 6 Schritte aus der Anleitung durch:**

0. **Historische Ticket-Verfolgung (PFLICHT, vor allem anderen):** Für jede geplant zu ändernde
   Datei `git log --all --oneline --follow <FILE> | grep -iE "<PREFIX>-[0-9]+"` ausführen und die
   Treffer chronologisch rückwärts inspizieren. Pro Ticket-Commit kurz `git show <sha> -- <FILE>`
   öffnen, die fachliche Designintention erfassen und in der Impact-Analyse tabellarisch festhalten.
   **Wenn ein altes Ticket eine Heuristik/Anforderung etabliert hat, die mit deinem Plan kollidiert,
   den Plan ANPASSEN, bevor du implementierst** (nicht blind überschreiben). Siehe Detail-Anleitung
   in [impact-analysis methodology](../impact-analysis/methodology.md) → „Schritt 0“.
1. Geplante Dateien kategorisieren (nach Architektur-Schicht)
2. Aufwärts-Verfolgung (Bottom-Up Tracing) — welche Controller/Frontend-Bereiche nutzen die
   geplant geänderten Klassen?
3. Business-Logik-Verzweigungen erkennen — welche Enum- und Property-Verzweigungen existieren
   bereits im betroffenen Code? Muss der Plan diese berücksichtigen?
4. Betroffene Test-Bereiche zusammenstellen — was muss nach der Umsetzung getestet werden?
5. Nachfragen formulieren — Offene Fragen an den Auftraggeber/Entwickler

**Bei aktivem Worktree-Routing:** Git-Befehle mit `git -C <WORKTREE_PATH> …` ausführen,
Code-Reads mit absolutem Worktree-Pfad (siehe Phase 0).

**Ergebnis:** Dokumentiere die Analyse im Task-File unter `## Impact-Analyse`.
Enthält die Analyse kritische Erkenntnisse (z.B. fehlende Enum-Abdeckung im Plan,
unerwartete Seiteneffekte), dann **passe den Lösungsplan entsprechend an** und informiere
den Benutzer über die Anpassungen.

**Schritt 7: Abschluss-Checkliste hinzufügen**

Füge folgende Checkliste im Task-File hinzu (falls nicht vorhanden):

```markdown
## Abschluss-Checkliste

- [x] Already-Solved-Check durchgeführt
- [x] Task-File korrekt benannt (Schema eingehalten)
- [x] Analyse dokumentiert
- [x] Lösungsplan erstellt
- [x] Impact-Analyse durchgeführt (Verzweigungen, Nebeneffekte, Nachfragen)
- [ ] Feature-Branch erstellt und aktiv
- [ ] Lösung vollständig implementiert
- [ ] Tests erstellt (Controller-Tests + Business-Logik-Tests)
- [ ] Tests/PHPStan ausgeführt und bestanden
- [ ] JIRA Lösungsfeld ausgefüllt (beide Abschnitte; „Für Kunde" inkl. Entscheidungen, Abweichungen von den AK und Annahmen)
- [ ] Änderungen committed (mit korrekter Commit-Message, OHNE Co-Authored-By)
- [ ] Abschluss-Zusammenfassung dem Benutzer ausgegeben
```

---

## STOPP - Analyse & Planung abgeschlossen!

Nach Abschluss von Phase 2 **IMMER** folgende Zusammenfassung ausgeben:

```
📋 ANALYSE & PLANUNG ABGESCHLOSSEN

Ticket: <TICKET-NUMMER>
Branch: <feature/<branch-name>, oder "wird bei /solve-task erstellt" falls --no-worktree>
Worktree: <Pfad falls angelegt, sonst "nicht angelegt (--no-worktree)">
Status: 🟡 Bereit zur Umsetzung

## Zusammenfassung
[1-2 Sätze was der Task macht]

## Lösungsplan
[Kurze Auflistung der geplanten Schritte]

## Betroffene Bereiche
- Backend: [ja/nein - welche]
- Frontend: [ja/nein - welche]
- Tests: [ja/nein - welche]
- Config: [ja/nein - welche]

## Impact-Analyse
- Betroffene Controller/Endpunkte: [Anzahl]
- Betroffene Frontend-Bereiche: [Anzahl]
- Erkannte Verzweigungen (Enums/Properties): [Anzahl, davon X mit Risiko]
- Offene Nachfragen: [Anzahl]
- Plan-Anpassungen aufgrund der Analyse: [ja/nein - welche]

---

👉 Zur Umsetzung: `/solve-task <TICKET-NUMMER oder task-file.md>`
```

**WICHTIG:** Nach dieser Meldung STOPPEN und auf Benutzer-Feedback warten!

---

## Wichtige Regeln

1. **Already-Solved-Check**: IMMER zuerst prüfen ob Task schon bearbeitet wurde
2. **Worktree-Default**: Worktree wird automatisch angelegt, sofern noch keiner existiert und `--no-worktree` nicht im Input ist
3. **Dokumentation**: Analyse und Lösungsplan im Task-File festhalten
4. **Nachfragen**: Bei Unklarheiten IMMER fragen, niemals raten oder annehmen
5. **Sprache**: Branch-Namen auf Englisch
6. **KEINE Umsetzung**: Dieses Command macht NUR Analyse und Planung!
7. **ULTRATHINK**: Dieses Command erfordert gründliche Analyse - nutze erweiterte Denkzeit

---

## Status-Meldungen

| Status             | Meldung                                                        |
|--------------------|----------------------------------------------------------------|
| Task abgeschlossen | `🟢 TASK BEREITS ABGESCHLOSSEN` - Commits in develop gefunden  |
| Task in Arbeit     | `🟡 TASK IN ARBEIT` - Feature-Branch existiert, nicht gemerged |
| Task neu           | `🔵 NEUER TASK` - Keine Commits gefunden, starte Analyse       |
| Planung fertig     | `📋 ANALYSE & PLANUNG ABGESCHLOSSEN` - Bereit für /solve-task  |

---

## Weitere Infos

- Importiere Namespaces prinzipiell mit "use", schreibe Namespaces niemals direkt in den Code
- Beachte bei der Planung die Konventionen in `CLAUDE.md` (Architektur, Tests, Rollen, Config) und —
  falls im Projekt vorhanden — die [Code Review Learnings](../../docs/claude/code_review_learnings.md)
- Übersetzungen: siehe `~/Library/Application Support/Kanban/claude/rules/translations.md` —
  Änderungen an den Translation-Dateien werden nur in den deutschen Dateien vorgenommen,
  keine hardcodierten Strings im Code/Template

---

Beginne jetzt mit der Argument-Auflösung, danach Phase 0: Worktree-Routing und Already-Solved-Check.
