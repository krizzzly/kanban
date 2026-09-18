---
name: review-merge
description: Analysiere einen Merge-Request / Feature-Branch für Code-Review
argument-hint: <task-file.md oder branch-name>
disable-model-invocation: true
---

# REVIEW MERGE - Code-Review Arbeitsanweisung

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `dockerStack`, `stackDomain`,
> `gitlabProjectPath`): stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen
> Projektwert brauchst — nie raten. `dockerStack: false` heisst: kein Docker-Stack — dann gibt es weder
> `stackDomain` noch `iwf`, und Befehle laufen direkt im Worktree.

Du bist ein erfahrener Code-Reviewer, der Merge-Requests systematisch analysiert und konstruktives Feedback gibt.

## Dein Input

Analysiere: $ARGUMENTS

**Akzeptierte Formate:**
- MR-Nummer: `!969` oder `969`
- Branch-Name: `feature/<PREFIX>-1234_feature`
- Task-File: `<tasksPath>/<PREFIX>-1234_feature.md`
- Ticket-Nummer: `<PREFIX>-1234`

**Falls kein Branch angegeben:** Frage den Benutzer nach dem Branch-Namen oder der MR-Nummer, bevor du fortfährst!

**Haupt-Branch `<BASE>`:** der Merge-Ziel-Branch des Projekts (`develop` oder `main`) — ermitteln über
`git symbolic-ref refs/remotes/origin/HEAD --short` (→ `origin/<BASE>`); im Zweifel den Benutzer fragen.

---

## Workflow

### Phase 1: Kontext erfassen

**Schritt 1: Task-File und Branch identifizieren**

**Bei MR-Nummer (z.B. `!969` oder `969`):**
1. Suche das Task-File mit dieser MR-Nummer:
   ```bash
   grep -r "MR !969" <tasksPath>/
   ```
2. Lies das gefundene Task-File - dort steht auch die Ticket-Nummer und der Branch

**Bei Task-File oder Ticket-Nummer:**
1. Lies das Task-File und finde die Sektion `## Merge-Review (MR !...)`
2. Extrahiere Branch-Name und MR-Nummer aus dem Task-File

**Branch ermitteln:**
```bash
git branch -a | grep -i "<TICKET-NUMMER>"
```

**WICHTIG:** Falls der Branch nicht eindeutig ist:
- **Frage den Benutzer** nach dem exakten Branch-Namen
- Warte auf Antwort bevor du fortfährst

**Schritt 1b: In den Branch wechseln**

**PFLICHT:** Wechsle IMMER in den zu reviewenden Branch:
```bash
git checkout <branch-name>
```

Dies stellt sicher, dass:
- Du die aktuellen Dateien im Branch siehst
- Eventuelle Fixes direkt committed werden können
- Der Kontext korrekt ist

**Schritt 2: MR-Kommentare aus Task-File lesen (ggf. automatisch laden)**

Die MR-Kommentare und Hinweise vom Kollegen sind im Task-File unter der Sektion dokumentiert:

```markdown
## Merge-Review (MR !<NUMMER>)
```

**Prüfe zuerst ob die Sektion im Task-File existiert:**

```bash
grep -l "## Merge-Review" <tasksPath>/<TICKET-NUMMER>*.md
```

**Falls die Sektion FEHLT → MR-Daten automatisch laden:**

1. Ermittle die MR-Nummer (aus dem Argument, Branch-Name oder via GitLab):
   ```bash
   # Falls nur Branch/Ticket bekannt:
   git log --oneline origin/<BASE>..origin/<branch-name> | head -5
   ```
2. Rufe `mcp__hermes__enhance-claude-task-with-mr` auf mit der MR-Nummer
   - Das Tool lädt alle MR-Discussions und Kommentare
   - Speichert die Discussions als JSON unter `<tasksPath>/<TICKET>/discussions/`
   - Erweitert das Task-File automatisch um eine `## Merge-Review (MR !XXX)` Sektion
3. Lies das aktualisierte Task-File erneut

**Falls die Sektion EXISTIERT → direkt lesen.**

Beachte insbesondere:
- Hinweise/Kommentare vom Kollegen
- Offene Punkte oder bekannte TODOs
- Scope bei Teil-MRs
- Abhängigkeiten zu anderen MRs

→ Diese Informationen sind wichtig für die Analyse!

**Schritt 3: Änderungen erfassen**

**WICHTIG: Branch-Alter beachten!**

`git diff <BASE>..branch` zeigt ALLE Unterschiede zwischen `<BASE>` und dem Branch - auch Änderungen die in `<BASE>` sind, aber noch nicht im Branch (weil er früher abgezweigt wurde). Das kann zu falschen Findings führen!

**→ Immer den tatsächlichen Commit anschauen:**
```bash
# RICHTIG: Zeigt nur die wirklich geänderten Dateien im Commit
git show origin/<branch-name> --name-status --oneline

# Für mehrere Commits auf dem Branch:
git log --oneline origin/<BASE>..origin/<branch-name>
git show <commit-hash> --name-status
```

**Nur zur Orientierung (kann "falsche" Änderungen zeigen):**
```bash
# Diff zwischen <BASE> und Branch (inkl. fehlender <BASE>-Änderungen)
git diff --name-status origin/<BASE>..origin/<branch-name>
```

**Vollständige Änderungen des Commits anzeigen:**
```bash
git show origin/<branch-name>
```

---

### Phase 2: Anforderungs-Analyse

**Schritt 4: Task-Anforderungen verstehen**

- Lies das Task-File und verstehe die Anforderungen
- Identifiziere:
  - Was soll implementiert werden?
  - Welche Benutzerrollen bzw. Akteur-Flows sind betroffen?
  - Welche Bereiche (Frontend/Backend/Config) sind betroffen?

**Schritt 5: Vollständigkeits-Check**

Prüfe ob alle Anforderungen aus dem Task umgesetzt wurden:

| Anforderung | Status | Kommentar |
|-------------|--------|-----------|
| [Anforderung 1] | ✅/❌/⚠️ | [Details] |
| [Anforderung 2] | ✅/❌/⚠️ | [Details] |

---

### Phase 3: Code-Analyse

**Schritt 6: Code-Qualität prüfen**

Prüfe folgende Aspekte und dokumentiere Findings:

**Backend (PHP):**
- [ ] Namespaces korrekt importiert (use-Statements, keine inline Namespaces)
- [ ] Keine hardcodierten Werte (IDs, Strings) - Konstanten/Enums verwenden
- [ ] Doctrine Queries: Parameter-Binding statt String-Konkatenation
- [ ] Exception-Handling: Sinnvolle Exceptions, keine leeren catch-Blöcke
- [ ] PHPDoc: Typen korrekt, @throws dokumentiert wo nötig
- [ ] CQRS-Pattern eingehalten (Commands/Queries via Messenger) — in Projekten mit CQRS-Stack
- [ ] Zeit/Datum: „now" über den DateProvider, nie via `new \DateTimeImmutable()`
- [ ] Architektur-Patterns des Projekts eingehalten (siehe `CLAUDE.md`)

**Frontend (React/TypeScript — Projekte mit React-Stack):**
- [ ] Keine console.log Statements (außer in Development)
- [ ] Props korrekt typisiert
- [ ] useCallback/useMemo wo sinnvoll
- [ ] Übersetzungen verwendet (kein hardcodierter Text)
- [ ] Actions korrekt geprüft (FeViewRenderer, actions-Property)

**Frontend (Twig / JS / SCSS — Projekte mit klassischem Symfony-Stack):**
- [ ] Keine hardcodierten Strings - Übersetzungen verwenden (`{{ '...'|trans }}`)
- [ ] Twig-Escaping korrekt (`|raw` nur bewusst und geprüft)
- [ ] Neuer JS/SCSS-Code unter `assets/js/` bzw. `assets/scss/`, über Encore eingebunden
- [ ] Build läuft ohne Fehler durch (projektüblicher Aufruf — mit Stack z.B. `iwf yarn build`, ohne Stack
      der Build-Befehl aus der `CLAUDE.md`)

**Berechtigungen:**
- [ ] Neue Permissions im Permission-System des Projekts definiert (z.B. `coala_permissions.yaml`) bzw.
      Rollen-Hierarchie in `config/packages/security.yaml` korrekt erweitert
- [ ] Frontend-Views konfiguriert, falls das Projekt view-basierte Berechtigungen kennt (z.B. `fe_views.yaml`)
- [ ] Controller mit `#[IsGranted()]` geschützt
- [ ] Rollen/Akteure getrennt: jede Rolle sieht nur die für sie bestimmten Daten
- [ ] Dokumentation: Permissions-/Rollen-Doku des Projekts (siehe Verweise in der `CLAUDE.md`)

**Tests:**
- [ ] Controller-Tests für neue Controller vorhanden (erweitern die Test-Basisklasse des Projekts)
- [ ] Test-Naming-Convention eingehalten (`FooController.php` → `FooTest.php`)
- [ ] Access-Tests (401/403) vorhanden (ggf. über `userAccessProvider`)
- [ ] Happy-Path-Tests vorhanden
- [ ] Fixtures via `loadFixtures()`, Uhr über den DateProvider gepinnt
- [ ] Dokumentation: `.claude/rules/testing.md`

**Schritt 7: Pattern-Compliance prüfen**

Prüfe Einhaltung der Projekt-Patterns:
- [ ] Bestehende Patterns wiederverwendet (nicht neu erfunden)
- [ ] Ähnliche Implementierungen als Vorlage genutzt
- [ ] Code-Style konsistent mit Rest des Projekts

**Schritt 8: Bekannte Probleme prüfen**

Prüfe gegen die dokumentierten Konventionen, Gotchas und Code-Review-Learnings des Projekts:
- Code-Review-Learnings-Doku, falls vorhanden (siehe Verweise in der `CLAUDE.md`),
  sonst die Konventions-/Gotcha-Abschnitte der `CLAUDE.md` selbst

---

### Phase 3b: Test-Impact-Analyse

**ZIEL:** Ermitteln, welche Bereiche über die direkt geänderten Dateien hinaus betroffen sind
und welche Verzweigungs-Varianten der Test-Ingenieur beachten muss.

⚠️ **PFLICHT:** Lies und befolge die Anleitung in
[impact-analysis methodology](../impact-analysis/methodology.md) (Skill `impact-analysis`)

**Modus:** `review-merge` → Datenquelle ist der **git diff** des MR-Branches:
```bash
# Commits des MR ermitteln
git log --oneline origin/<BASE>..origin/<branch-name>
# Geänderte Dateien
git show origin/<branch-name> --name-only --oneline
```

**Führe alle 5 Schritte aus der Anleitung durch:**
1. Geänderte Dateien kategorisieren (nach Architektur-Schicht)
2. Aufwärts-Verfolgung (Bottom-Up Tracing) bis Controller/Frontend
3. Business-Logik-Verzweigungen erkennen (Enums UND Properties!)
4. Betroffene Test-Bereiche zusammenstellen
5. Nachfragen an den Developer formulieren

**Ergebnis:** Findings aus der Impact-Analyse fliessen in Phase 4 ein:
- Fehlende Enum-/Property-Abdeckung → 🔴 Blocker oder 🟡 Warnung
- Unerwartete Seiteneffekte → 🟡 Warnung mit Nachfrage an Developer
- Test-Bereiche → In den Review-Report unter "Test-Hinweise" dokumentieren

---

### Phase 4: Review-Ergebnis

**Schritt 9: TODO-Liste erstellen**

**PFLICHT:** Erstelle eine TODO-Liste mit allen Findings die behoben werden müssen:

```
TodoWrite mit allen Blocker-Findings als einzelne Todos
```

Beispiel:
- "Fix src/Service/FooExport.php:30 - Falsches Feld für Kennzahl X"
- "Fix src/Service/BarExport.php - Gleiche Probleme wie im ersten Export"
- "Run PHPStan and tests after fixes"

**Schritt 10: Findings kategorisieren**

Kategorisiere alle Findings (für den Report):

| Kategorie | Bedeutung |
|-----------|-----------|
| 🔴 **Blocker** | Muss vor Merge behoben werden |
| 🟡 **Warnung** | Sollte behoben werden, blockiert nicht |
| 🔵 **Hinweis** | Verbesserungsvorschlag, optional |
| ✅ **Gut** | Besonders gute Lösung, positives Feedback |

**Schritt 11: Review-Report erstellen**

Erstelle einen strukturierten Review-Report:

```
## 📋 Merge-Review: <TICKET-NUMMER> (MR !<MR-NUMMER>)

### Zusammenfassung
[1-2 Sätze was der MR macht]

### Branch-Info
- **Branch:** `<branch-name>`
- **Basis:** `<BASE>`
- **Commits:** [Anzahl]
- **Geänderte Dateien:** [Anzahl]
- **Teil-MR:** Ja/Nein
- **Kollegen-Hinweise:** [Falls vorhanden, hier zusammenfassen]

### Anforderungs-Check
| Anforderung | Status |
|-------------|--------|
| ... | ✅/❌ |

### Findings

#### 🔴 Blocker
- [Finding 1 mit Datei:Zeile und Beschreibung]

#### 🟡 Warnungen
- [Finding 1 mit Datei:Zeile und Beschreibung]

#### 🔵 Hinweise
- [Finding 1 mit Datei:Zeile und Beschreibung]

#### ✅ Positives
- [Was besonders gut gelöst wurde]

### Test-Status
- [ ] Controller-Tests vorhanden
- [ ] Tests ausgeführt: projektüblicher Runner (siehe `.claude/rules/testing.md`) — mit Stack z.B.
      `iwf run "vendor/bin/phpunit tests/..."`, ohne Stack (`dockerStack: false`) direkt im Worktree,
      z.B. `cd <WORKTREE_PATH> && swift test`
- [ ] Statische Analyse: projektüblicher Aufruf (siehe `CLAUDE.md`) — mit Stack z.B. `iwf run phpstan`,
      ohne Stack z.B. `cd <WORKTREE_PATH> && swift build`

### Test-Hinweise (aus Impact-Analyse)
- [Betroffene Endpunkte/Frontend-Bereiche und Verzweigungs-Varianten für den Test-Ingenieur]

### Empfehlung
🟢 **Approve** - Bereit zum Merge
🟡 **Approve mit Kommentaren** - Kleine Änderungen empfohlen
🔴 **Changes Requested** - Blocker müssen behoben werden
```

**Schritt 12: Analyse im Task-File speichern**

**PFLICHT:** Speichere die komplette Analyse im Task-File unter der `## Merge-Review` Sektion:

1. Aktualisiere den **Status** im Task-File Header:
   - `🟢 Abgeschlossen` → `🔴 Changes Requested (MR !XXX)` bei Blockern
   - oder `🟡 In Review (MR !XXX)` bei Warnungen

2. Füge unter `## Merge-Review (!XXX)` folgende Sektionen hinzu:
   - `### Review-Status:` mit Empfehlung und Datum
   - `### Zusammenfassung der MR-Kommentare` (falls vorhanden)
   - `### Findings` als Tabelle mit Status-Spalte
   - `### Technische Analyse` mit Erklärung der Probleme
   - `### Lösungsvorschlag` mit konkretem Code-Beispiel
   - `### Umsetzungs-Log` als Tracking-Tabelle

Beispiel-Format:
```markdown
### Review-Status: 🔴 Changes Requested

**Reviewer:** Name (@username)
**Review-Datum:** YYYY-MM-DD

### Findings

| # | Datei:Zeile | Problem | Status |
|---|-------------|---------|--------|
| 1 | `File.php:30` | Beschreibung | ⬜ Offen |

### Umsetzungs-Log

| # | Status | Umgesetzt am | Notizen |
|---|--------|--------------|---------|
| 1 | ⬜ | - | - |

**Legende:** ⬜ Offen | ✅ Umgesetzt | ⏭️ Übersprungen | ❌ Abgelehnt
```

---

## Zusätzliche Prüfungen für Sub-Task-Reviews

Bei Sub-Tasks zusätzlich prüfen:

- [ ] Änderungen passen zum Haupt-Task
- [ ] Keine Konflikte mit anderen Sub-Tasks
- [ ] Abhängigkeiten zu anderen Sub-Tasks dokumentiert
- [ ] Teilimplementierung funktioniert standalone (kein broken state)

---

## Hilfreiche Befehle

```bash
# Alle Änderungen anzeigen
git diff <BASE>..<branch>

# Nur bestimmte Dateitypen
git diff <BASE>..<branch> -- "*.php"
git diff <BASE>..<branch> -- "*.jsx" "*.tsx"            # React-Stack
git diff <BASE>..<branch> -- "*.twig" "*.js" "*.scss"   # klassischer Symfony-Stack

# Statistik
git diff --stat <BASE>..<branch>

# Tests ausführen (Runner siehe .claude/rules/testing.md) — Projekt MIT Docker-Stack, z.B.:
iwf run "vendor/bin/phpunit tests/Controller/..."

# Statische Analyse (projektüblicher Aufruf — siehe CLAUDE.md) — Projekt MIT Docker-Stack, z.B.:
iwf run phpstan

# Projekt OHNE Docker-Stack (dockerStack: false): kein iwf, kein Container — direkt im Worktree, z.B.:
cd <WORKTREE_PATH> && swift test

# Geänderte Test-Dateien finden
git diff --name-only <BASE>..<branch> | grep -E "Test\.php$"
```

---

## Wichtige Regeln

1. **Konstruktiv bleiben** - Immer erklären WARUM etwas ein Problem ist
2. **Lösungen vorschlagen** - Nicht nur Probleme aufzeigen
3. **Kontext beachten** - Manchmal gibt es gute Gründe für "unübliche" Lösungen
4. **Positives erwähnen** - Gute Lösungen auch loben
5. **Analyse dokumentieren** - Findings IMMER im Task-File speichern
6. **TODO-Liste erstellen** - Blocker als TODOs für die Umsetzung tracken
7. **In Branch wechseln** - IMMER zuerst in den Feature-Branch wechseln

---

## Starte jetzt!

Beginne mit Phase 1: Kontext erfassen.
