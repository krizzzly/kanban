---
name: create-task
description: Erstelle ein neues Task-File mit der nächsten freien Ticket-Nummer
argument-hint: <Kurze Beschreibung des Tasks> [--no-worktree]
disable-model-invocation: true
---

# CREATE TASK - Task-File Generator

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`):
> stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

Du erstellst ein neues Task-File im Projekt nach dem etablierten Schema und legst **per Default** direkt
einen Git-Worktree dafür an.

Platzhalter in spitzen Klammern (`<PREFIX>`, `<tasksPath>`, `<worktreePrefix>`, `<stackDomain>`) stehen im
Folgenden für die entsprechenden Werte aus `.claude/project.json` — im Task-File landen immer die
**aufgelösten** Werte, keine Platzhalter. `<stackDomain>` ist nur die TLD (z.B. `test`): der Haupt-Stack
läuft auf `https://<repo-ordnername>.<stackDomain>`, ein Worktree-Stack auf
`https://<worktree-ordnername>.<stackDomain>` (Ordnername = letzter Pfadbestandteil).

## Input

Beschreibung des neuen Tasks: $ARGUMENTS

## Worktree-Verhalten (Default: AN)

- **Standard:** Nach Erstellung des Task-Files wird automatisch ein Worktree angelegt (Schritt 5) — nur der
  Worktree (Branch + Configs), **kein** Docker-Stack.
- **Opt-out:** Wenn `$ARGUMENTS` das Flag `--no-worktree` enthält, Worktree-Erstellung überspringen.
  Entferne `--no-worktree` aus der Beschreibung, bevor sie ins Task-File geschrieben wird.

> Vollständige Befehls-/Flag-Referenz zu `iwf worktree`: `~/Library/Application Support/Kanban/claude/rules/worktree.md`.

---

## Workflow

### Schritt 1: Nächste Ticket-Nummer ermitteln

Lies alle bestehenden Task-Files:

```bash
ls <tasksPath>/<PREFIX>-*.md | sort -t'-' -k2 -n | tail -5
```

Ermittle die höchste vorhandene Nummer und erhöhe um 1.
Beispiel: `<PREFIX>-4383` existiert → nächste Nummer ist `<PREFIX>-4384`.

### Schritt 2: Dateinamen generieren

Schema: `<PREFIX>-{NNNN}_{kurzer_englischer_titel}.md`

- `{NNNN}`: die nackte Ticket-Nummer — gleiche Stellenzahl wie die bestehenden Task-Files (z.B. `4384`)
- `{kurzer_englischer_titel}`: snake_case, lowercase, max 5 Wörter
- Aus der Beschreibung ableiten

Beispiele:
- "Speichern-Button Bug" → `<PREFIX>-4384_save_button_fix.md`
- "Export erweitern" → `<PREFIX>-4384_extend_export.md`
- "Neue Berechtigung für eine Rolle" → `<PREFIX>-4384_role_permission.md`

### Schritt 3: Task-File erstellen

Erstelle die Datei `<tasksPath>/{DATEINAME}` mit folgendem Inhalt.
**Passe die Inhalte an die Beschreibung des Users an!** Die Sections müssen gefüllt werden basierend auf dem was der User beschrieben hat.

```markdown
# {TICKET-NR} - {Deutscher Titel}
Typ: [Story / Bug / Task]

### Status
🔴 Offen

## Beschreibung

{Ausführliche Beschreibung basierend auf User-Input}

### Ziel

{Was soll erreicht werden und warum}

---

## Analyse

**Art der Änderung:** [Feature / Bugfix / Refactoring / UI-Anpassung]

**Betroffene Bereiche:**
- [z.B. Frontend: Seite/Komponente XY]
- [z.B. Backend: API-Endpunkt XY]
- [z.B. Config: Permissions/Rollen]

**Fachliche Einordnung:**
[Kurze Beschreibung was erreicht werden soll und warum — geschäftlicher Kontext]

**Technische Einordnung:**
[Welche Komponenten/Patterns sind betroffen, geschätzte Komplexität]

**Betroffene Dateien:**

| Datei | Änderung |
|---|---|
| `pfad/zur/datei.php` | Beschreibung der Änderung |

**Abhängigkeiten:**
- [Bestehende Module/Funktionen die benötigt werden]

---

## Lösungsplan

### Backend
1. [Erster Schritt — z.B. Controller, Handler, Service, Command]

### Frontend
2. [z.B. Komponente/Template, API-Integration]

### Tests
3. [z.B. Controller-Test, Unit-Test]

### Config
4. [z.B. Permissions/Rollen, weitere Projekt-Konfiguration gemäss Projekt-Doku]

### Edge Cases
- [Mögliche Problemfälle und deren Behandlung]

---

## Abschluss-Checkliste

- [ ] Already-Solved-Check durchgeführt
- [ ] Task-File korrekt benannt
- [ ] Analyse dokumentiert
- [ ] Lösungsplan erstellt
- [ ] Impact-Analyse durchgeführt
- [ ] Feature-Branch erstellt und aktiv
- [ ] Lösung vollständig implementiert
- [ ] Tests erstellt (Controller-Tests + Business-Logik-Tests)
- [ ] Tests/PHPStan ausgeführt und bestanden
- [ ] JIRA Lösungsfeld ausgefüllt (beide Abschnitte; „Für Kunde" inkl. Entscheidungen, Abweichungen von den AK und Annahmen)
- [ ] Änderungen committed (mit korrekter Commit-Message, OHNE Co-Authored-By)
- [ ] Abschluss-Zusammenfassung dem Benutzer ausgegeben
```

### Schritt 4: Analyse ausfüllen

Bevor du das Task-File erstellst, führe eine **kurze Codebase-Analyse** durch:

1. Lies die `CLAUDE.md` um den Kontext zu verstehen
2. Identifiziere welche bestehenden Module/Dateien betroffen sind
3. Füge die Analyse-Ergebnisse direkt in die entsprechenden Sections ein
4. Der Lösungsplan sollte so konkret sein, dass `solve-task` damit arbeiten kann

**Wichtig:** Fülle möglichst viele Felder basierend auf deiner Codebase-Analyse aus.
Felder die du nicht sicher bestimmen kannst, markiere mit `[TODO: ...]`.

### Schritt 5: Worktree anlegen (Default — siehe Worktree-Verhalten oben)

**Falls `--no-worktree` NICHT im Input enthalten ist:**

1. Branch-Suffix aus dem Dateinamen ableiten (englischer Titel ohne `<PREFIX>-NNNN_` und `.md`).
2. `iwf worktree create NNNN <suffix>` ausführen (NNNN = nackte Ticket-Nummer; oder ohne Suffix, falls keiner vorhanden).
3. Nach erfolgreichem Script-Lauf den Worktree-Block direkt unter die H1 des Task-Files einfügen:

   ```markdown
   > 🌳 **WORKTREE**: `<worktreePrefix>/<PREFIX>-NNNN`\
   > 🌿 **BRANCH**: `feature/<PREFIX>-NNNN[_<suffix>]`\
   > 🐳 **STACK**: `https://<worktree-ordnername>.<stackDomain>`\
   > 📅 **Angelegt**: <YYYY-MM-DD>
   >
   > 🧭 **Routing-Modell für Claude:** cwd bleibt Haupt-Repo. Code-Edits gehen mit absolutem Worktree-Pfad
   > in den WORKTREE. Git-Befehle mit `git -C <WORKTREE> ...`. Task-File/CLAUDE.md/Docs aus dem Haupt-Repo.
   ```

   Alle Platzhalter mit den aufgelösten Werten aus `.claude/project.json` füllen. Die Stack-URL ist erst
   nach Stack-Start erreichbar.

4. Stack NICHT automatisch starten — also `iwf worktree create` ohne `--start` aufrufen; nur in der
   Zusammenfassung erwähnen, wie er später gestartet wird (`iwf worktree start NNNN`).

**Falls `--no-worktree` gesetzt:** Worktree-Schritt komplett überspringen.

### Schritt 6: Zusammenfassung ausgeben

Nach Erstellung des Task-Files IMMER folgende Zusammenfassung ausgeben:

```
📋 TASK-FILE ERSTELLT

Ticket: {TICKET-NR}
Datei: <tasksPath>/{DATEINAME}
Status: 🔴 Offen
Worktree: [Pfad / "nicht angelegt (--no-worktree)"]

## Beschreibung
[1-2 Sätze]

## Nächste Schritte
- Analyse verfeinern: `/start-task <tasksPath>/{DATEINAME}`
- Direkt umsetzen: `/solve-task <tasksPath>/{DATEINAME}`
[falls Worktree angelegt:]
- Stack im Worktree starten: `iwf worktree start {NNNN}`
```

---

## Wichtige Regeln

1. **Nummerierung:** IMMER die nächste freie `<PREFIX>`-Nummer verwenden
2. **Sprache:** Dateiname auf Englisch (snake_case), Inhalt auf Deutsch
3. **Keine Umsetzung:** Dieses Command erstellt NUR das Task-File!
4. **Analyse:** Soweit möglich basierend auf Codebase-Kenntnissen ausfüllen
5. **Konkret:** Der Lösungsplan muss konkret genug für `solve-task` sein
6. **Abschluss-Checkliste:** IMMER am Ende einfügen — Items an den konkreten Task anpassen
7. **Sections:** Alle Pflicht-Sections müssen vorhanden sein: Status, Beschreibung, Analyse, Lösungsplan, Abschluss-Checkliste
8. **Pfad:** Task-Files liegen unter `<tasksPath>` (aus `.claude/project.json`) — nirgendwo sonst
9. **Worktree-Default:** Worktree wird automatisch angelegt — Opt-out nur via `--no-worktree` im Input
