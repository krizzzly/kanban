---
description: Lösche einen Git-Worktree und seinen Docker-Stack
argument-hint: <TICKET-NUMMER> [--delete-branch] [--keep-data] [--force]
---

# DESTROY WORKTREE - Worktree und Docker-Stack abräumen

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`):
> stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

Du räumst einen bestehenden Worktree komplett ab: Stack stoppen, Container/Volumes entfernen, Worktree
löschen. Per Default bleibt der `feature/*`-Branch erhalten.

Platzhalter in spitzen Klammern (`<PREFIX>`, `<tasksPath>`, `<worktreePrefix>`) stehen im Folgenden für die
entsprechenden Werte aus `.claude/project.json`.

> Vollständige Befehls-/Flag-Referenz zu `iwf worktree`: `.claude/rules/worktree.md`.

## Input

$ARGUMENTS

Akzeptierte Formate:

- `<PREFIX>-1234`
- `<PREFIX>-1234 --delete-branch`
- `<PREFIX>-1234 --keep-data`
- `<PREFIX>-1234 --force`
- Kombinationen, z.B. `<PREFIX>-1234 --delete-branch --force`

---

## Voraussetzungen

- Aktueller Pfad ist das Haupt-Repository (`<repoDir>`), NICHT der Worktree
  selbst — sonst verweigert `iwf` die Ausführung.
- Du weisst, dass die Aktion DESTRUKTIV ist (Container + DB-Volume werden gelöscht, sofern nicht
  `--keep-data` gesetzt ist).

---

## Workflow

### Phase 1: Eingabe prüfen

**Schritt 1: Nummer extrahieren**

Aus `$ARGUMENTS` das TICKET (Format `<PREFIX>-<zahl>`) als erstes Token nehmen und daraus die nackte
**Nummer** ableiten — `iwf worktree destroy` erwartet `4519`, nicht `<PREFIX>-4519`. Flags wie
`--delete-branch`, `--keep-data`, `--force` werden 1:1 an `iwf` weitergegeben.

**Schritt 2: Sanity-Check**

- Existiert der Worktree-Pfad (`<worktreePrefix>/<TICKET>`)?
  - Ja → fortfahren
  - Nein → `iwf` kann trotzdem stale Worktree-Einträge prunen. Benutzer informieren, dass nichts
    physisches gelöscht wird.
- Ist der Feature-Branch bereits in `develop` gemerged?
  - `git log develop --oneline --grep="<TICKET>"` ausführen
  - Wenn JA: Benutzer informieren — Branch-Löschung mit `--delete-branch` ist sicher.
  - Wenn NEIN: Benutzer warnen — `--delete-branch` würde unveröffentlichte Arbeit verlieren.

---

### Phase 2: `iwf worktree destroy` aufrufen

**Schritt 3: Worktree + Stack abräumen**

**WICHTIG für Claude-getriggerte Aufrufe:** Immer mit `--force` aufrufen, damit die interaktiven
Bestätigungs-Prompts übersprungen werden — Claude kann nicht interaktiv `y` eingeben. Ausnahme: User hat
explizit `--delete-branch` verlangt → dann muss vorher Phase 1 Schritt 2 (Branch-merged-Check)
durchgelaufen sein.

```bash
# Default für Claude:
iwf worktree destroy <NUMMER> --force

# Mit zusätzlichen Flags:
iwf worktree destroy <NUMMER> --force [--delete-branch] [--keep-data]
```

`iwf worktree destroy`:

1. Prüft, dass du nicht im zu löschenden Worktree stehst
2. Fährt den Docker-Stack runter (Container + Netzwerk; DB-Volume nur ohne `--keep-data`)
3. Entfernt das Worktree-Verzeichnis
4. Optional (`--delete-branch`): löscht den lokalen Branch
5. Gibt eine Zusammenfassung aus

**Interaktive Prompts:** Ohne `--force` fragt `iwf` vor jeder destruktiven Aktion nach Bestätigung; mit
`--force` werden alle übersprungen.

**WICHTIG:** Während `destroy` läuft, NICHT abbrechen — sonst bleibt ein halb-zerstörter Zustand zurück
(z.B. Stack gestoppt aber Worktree noch da).

> Nur den Stack stoppen statt komplett abräumen? → `iwf worktree stop <NUMMER>` (Worktree + Volume + Branch
> bleiben, `iwf worktree start <NUMMER>` bringt alles zurück). Siehe `.claude/rules/worktree.md`.

---

### Phase 3: Task-File aufräumen

**Schritt 4: Worktree-Block aus Task-File entfernen**

Falls `destroy` erfolgreich war:

1. Suche `<tasksPath>/<TICKET>*.md`
2. Entferne den Worktree-Quote-Block (zwischen H1 und nächster Sektion)
3. Falls Branch gelöscht UND in develop gemerged: Status auf `🟢 Abgeschlossen` setzen
4. Falls Branch behalten: Status auf `🔴 Offen` zurücksetzen (Worktree weg, Branch noch da → Arbeit kann
   später im Haupt-Repo via `git switch <BRANCH>` fortgesetzt werden)

**WICHTIG:** Falls das Task-File noch ungespeicherte/wichtige Notizen enthält, NICHT komplett umschreiben —
nur den Worktree-Block entfernen.

---

### Phase 4: Zusammenfassung

**Schritt 5: Ergebnis ausgeben**

Übernimm den Output von `iwf worktree destroy` und ergänze:

```
✅ WORKTREE ABGERÄUMT

Ticket:    <PREFIX>-XXXX
Worktree:  entfernt
Stack:     gestoppt, Container entfernt
Volumes:   <removed | kept>
Branch:    <kept (feature/...) | deleted (local)>
Task-File: <tasksPath>/<PREFIX>-XXXX*.md — Worktree-Block entfernt, Status angepasst

Nächste Schritte:
- Falls Branch behalten: Arbeit im Haupt-Repo fortsetzen mit
    git switch feature/<PREFIX>-XXXX
- Falls Task abgeschlossen + gemerged: Task-File kann archiviert werden
```

---

## Wichtige Regeln

1. **Niemals im Worktree ausführen:** `iwf` verweigert das automatisch.
2. **Destruktiv per Default:** Container und DB-Volume werden gelöscht. Mit `--keep-data` bleibt das
   Volume — z.B. wenn du den Worktree später neu aufsetzen willst.
3. **Branch bleibt per Default erhalten** (Schutz vor versehentlichem Verlust unveröffentlichter Arbeit).
   Nur mit `--delete-branch` wird er entfernt — und das ist eine **lokale** Löschung; Remote bleibt
   unangetastet.
4. **Bestätigungen:** Ohne `--force` fragt `iwf` vor jedem destruktiven Schritt nach. Bei `--force` werden
   Prompts übersprungen — für Claude-getriggerte Aufrufe nötig.
5. **Nicht abbrechen:** Wenn der Stack-Stop schon läuft, `destroy` durchlaufen lassen — sonst bleibt
   halb-zerstörter Zustand zurück.
6. **Task-File anpassen** (nicht löschen): Nur den Worktree-Block entfernen und Status aktualisieren.
7. Vollständige Befehls-/Flag-Referenz: `.claude/rules/worktree.md`.

---

## Fehlerbehandlung

| Fehler                                                    | Reaktion                                                                          |
|-----------------------------------------------------------|-----------------------------------------------------------------------------------|
| `iwf` läuft aus dem zu löschenden Worktree heraus         | Benutzer ins Haupt-Repo schicken (`cd <repoDir>`)                                 |
| Worktree-Pfad existiert nicht (mehr)                      | `iwf` prunt stale Einträge i.d.R. automatisch — kein Eingreifen nötig             |
| Docker-Stack-Stop schlägt fehl                            | Benutzer manuell prüfen mit `docker ps`                                           |
| Task-File hat keinen Worktree-Block                       | Trotzdem fortfahren, Status ggf. anpassen                                         |
| Branch ist nicht in develop gemerged + `--delete-branch`  | WARNEN vor Ausführung, Benutzer bestätigen lassen — sonst gehen Commits verloren  |

---

Beginne jetzt mit Phase 1: Eingabe prüfen.
