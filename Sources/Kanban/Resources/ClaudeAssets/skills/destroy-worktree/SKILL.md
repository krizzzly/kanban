---
name: destroy-worktree
description: Lösche einen Git-Worktree und (falls vorhanden) seinen Docker-Stack
argument-hint: <TICKET-NUMMER> [--delete-branch] [--keep-data] [--force]
disable-model-invocation: true
---

# DESTROY WORKTREE - Worktree (und ggf. Docker-Stack) abräumen

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `dockerStack`, `stackDomain`,
> `gitlabProjectPath`): stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen
> Projektwert brauchst — nie raten.

Du räumst einen bestehenden Worktree ab. Per Default bleibt der `feature/*`-Branch erhalten.

## Zwei Wege — `dockerStack` entscheidet

**Lies `.claude/project.json`, bevor du irgendetwas tust.**

| `dockerStack`         | Weg                                                                            |
|-----------------------|--------------------------------------------------------------------------------|
| `true` (oder fehlend) | **Weg A:** `iwf worktree destroy` — Stack stoppen, Container/Volumes entfernen, Worktree löschen. |
| `false`               | **Weg B:** `git worktree remove` — es gibt keinen Stack, kein Volume und kein Image. |

Platzhalter in spitzen Klammern (`<PREFIX>`, `<tasksPath>`, `<worktreePrefix>`) stehen im Folgenden für die
entsprechenden Werte aus `.claude/project.json`.

> Vollständige Befehls-/Flag-Referenz zu beiden Wegen:
> `~/Library/Application Support/Kanban/claude/rules/worktree.md`.

## Input

$ARGUMENTS

Akzeptierte Formate:

- `<PREFIX>-1234`
- `<PREFIX>-1234 --delete-branch`
- `<PREFIX>-1234 --keep-data`
- `<PREFIX>-1234 --force`
- Kombinationen, z.B. `<PREFIX>-1234 --delete-branch --force`

`--delete-branch` gilt auf beiden Wegen. `--keep-data` und `--force` gehören zu `iwf` und haben auf Weg B
keine Entsprechung: `--keep-data` ist dort gegenstandslos (kein Volume), `--force` wird **nicht**
durchgereicht — siehe Schritt 3B.

---

## Voraussetzungen

- Aktueller Pfad ist das Haupt-Repository (`<repoDir>`), NICHT der Worktree
  selbst — sonst verweigern `iwf` wie `git` die Ausführung.
- **Weg A:** Du weisst, dass die Aktion DESTRUKTIV ist (Container + DB-Volume werden gelöscht, sofern nicht
  `--keep-data` gesetzt ist).
- **Weg B:** Gelöscht wird nur das Worktree-Verzeichnis (und auf Wunsch der Branch). Uncommittete
  Änderungen darin sind trotzdem weg — deshalb die Rückfrage in Schritt 3B.

---

## Workflow

### Phase 1: Eingabe prüfen

**Schritt 1: Nummer extrahieren**

Aus `$ARGUMENTS` das TICKET (Format `<PREFIX>-<zahl>`) als erstes Token nehmen und daraus die nackte
**Nummer** ableiten — `iwf worktree destroy` erwartet `4519`, nicht `<PREFIX>-4519`. Auf Weg A werden Flags
wie `--delete-branch`, `--keep-data`, `--force` 1:1 an `iwf` weitergegeben.

**Schritt 2: Sanity-Check**

- Existiert der Worktree-Pfad (`<worktreePrefix>/<TICKET>`)?
  - Ja → fortfahren
  - Nein → sowohl `iwf` als auch `git worktree prune` räumen stale Einträge ab. Benutzer informieren,
    dass nichts physisches gelöscht wird.
- Ist der Feature-Branch bereits im Basis-Branch gemerged?
  - **Basis-Branch ermitteln statt annehmen** — dieselbe Kette wie beim Anlegen (in iwf-Projekten kommt
    dabei i.d.R. `develop` heraus, in einem Repo ohne `develop` eben `main`):

    ```bash
    R=<repoDir>
    BASE=$(git -C "$R" symbolic-ref --quiet --short refs/remotes/origin/HEAD)
    if [ -z "$BASE" ]; then
      for kandidat in origin/develop origin/main develop main; do
        git -C "$R" rev-parse --verify --quiet "$kandidat" >/dev/null && { BASE="$kandidat"; break; }
      done
    fi
    [ -z "$BASE" ] && BASE=HEAD
    git -C "$R" log "$BASE" --oneline --grep="<TICKET>"
    ```

  - Wenn Treffer: Benutzer informieren — Branch-Löschung mit `--delete-branch` ist sicher.
  - Wenn kein Treffer: Benutzer warnen — `--delete-branch` würde unveröffentlichte Arbeit verlieren.
    **Nenne dabei den geprüften Branch**: „nicht in `origin/main`" ist eine andere Auskunft als „nicht
    in `develop`".

---

### Phase 2: Worktree abräumen

**Schritt 3A: Weg A — `iwf worktree destroy` (`dockerStack: true`)**

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
> bleiben, `iwf worktree start <NUMMER>` bringt alles zurück). Siehe `~/Library/Application Support/Kanban/claude/rules/worktree.md`.

**Schritt 3B: Weg B — `git worktree remove` (`dockerStack: false`)**

Es gibt keinen Stack, kein Volume und kein Image — nur das Verzeichnis und (optional) den Branch. `--force`
wird hier **nicht** blind durchgereicht: `iwf --force` überspringt nur Rückfragen, `git worktree remove
--force` löscht dagegen einen Baum **mit uncommitteten Änderungen**. Das sind zwei verschiedene Dinge.

```bash
# 1. Normaler Versuch — scheitert absichtlich, wenn der Baum schmutzig ist:
git -C <repoDir> worktree remove <worktreePrefix>/<TICKET>
```

- **Erfolg** → weiter mit Phase 3.
- **Fehlschlag wegen „contains modified or untracked files"** → **Rückfrage** via `AskUserQuestion`
  (Tool-Aufruf, nicht nur Text): erst kurz zeigen, was drin liegt
  (`git -C <worktreePrefix>/<TICKET> status --short`), dann fragen — **„Trotzdem löschen (Änderungen gehen
  verloren)"** / **„Abbrechen"**. Nur bei ausdrücklichem Ja:

  ```bash
  git -C <repoDir> worktree remove --force <worktreePrefix>/<TICKET>
  ```

  Ein `--force` im Input ist **keine** Antwort auf diese Frage: es kam für `iwf`s Prompts, nicht für
  verlorene Arbeit. Frag trotzdem.
- **Verzeichnis existiert gar nicht mehr** → `git -C <repoDir> worktree prune` räumt den stale Eintrag ab.

Branch löschen nur bei `--delete-branch` (und nach dem Merged-Check aus Phase 1):

```bash
git -C <repoDir> branch -d feature/<TICKET>[_<suffix>]     # -d, nicht -D: lehnt Ungemergtes ab
```

Lehnt `-d` ab, obwohl der Benutzer löschen will, ist das genau die Warnung aus Phase 1 — nachfragen, statt
auf `-D` auszuweichen.

`--keep-data` ist hier gegenstandslos (es gibt kein DB-Volume): einmal erwähnen, dass es ignoriert wurde,
und weitermachen.

---

### Phase 3: Task-File aufräumen

**Schritt 4: Worktree-Block aus Task-File entfernen**

Falls das Abräumen erfolgreich war:

1. Suche `<tasksPath>/<TICKET>*.md`
2. Entferne den Worktree-Quote-Block (zwischen H1 und nächster Sektion)
3. Falls Branch gelöscht UND im Basis-Branch gemerged: Status auf `🟢 Abgeschlossen` setzen
4. Falls Branch behalten: Status auf `🔴 Offen` zurücksetzen (Worktree weg, Branch noch da → Arbeit kann
   später im Haupt-Repo via `git switch <BRANCH>` fortgesetzt werden)

**WICHTIG:** Falls das Task-File noch ungespeicherte/wichtige Notizen enthält, NICHT komplett umschreiben —
nur den Worktree-Block entfernen.

---

### Phase 4: Zusammenfassung

**Schritt 5: Ergebnis ausgeben**

**Weg A** — übernimm den Output von `iwf worktree destroy` und ergänze:

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

**Weg B** — ohne Stack-/Volume-Zeilen, dafür mit dem geprüften Basis-Branch:

```
✅ WORKTREE ABGERÄUMT

Ticket:    <PREFIX>-XXXX
Worktree:  entfernt (git worktree remove)
Branch:    <kept (feature/...) | deleted (local)>  — geprüft gegen <BASE>
Task-File: <tasksPath>/<PREFIX>-XXXX*.md — Worktree-Block entfernt, Status angepasst

Dieses Projekt hat keinen Docker-Stack (dockerStack: false) — es gab nichts zu stoppen.

Nächste Schritte:
- Falls Branch behalten: Arbeit im Haupt-Repo fortsetzen mit
    git switch feature/<PREFIX>-XXXX
- Falls Task abgeschlossen + gemerged: Task-File kann archiviert werden
```

---

## Wichtige Regeln

1. **Erst `.claude/project.json` lesen:** `dockerStack` entscheidet, ob `iwf` überhaupt im Spiel ist.
2. **Niemals im Worktree ausführen:** `iwf` verweigert das automatisch, `git worktree remove` ebenso.
3. **Weg A ist destruktiv per Default:** Container und DB-Volume werden gelöscht. Mit `--keep-data` bleibt
   das Volume — z.B. wenn du den Worktree später neu aufsetzen willst.
4. **Branch bleibt per Default erhalten** (Schutz vor versehentlichem Verlust unveröffentlichter Arbeit).
   Nur mit `--delete-branch` wird er entfernt — und das ist eine **lokale** Löschung; Remote bleibt
   unangetastet. Auf Weg B mit `git branch -d`, nie mit `-D`.
5. **Bestätigungen:** Auf Weg A überspringt `--force` `iwf`s Prompts — für Claude-getriggerte Aufrufe
   nötig. Auf Weg B bedeutet `--force` etwas **anderes** (Löschen trotz uncommitteter Änderungen) und
   braucht deshalb eine eigene Rückfrage, auch wenn `--force` im Input stand.
6. **Basis-Branch ermitteln, nicht annehmen:** Der Merged-Check läuft gegen den ermittelten Branch, nicht
   gegen ein hart angenommenes `develop` — und die Meldung nennt, welcher es war.
7. **Nicht abbrechen (Weg A):** Wenn der Stack-Stop schon läuft, `destroy` durchlaufen lassen — sonst
   bleibt halb-zerstörter Zustand zurück.
8. **Task-File anpassen** (nicht löschen): Nur den Worktree-Block entfernen und Status aktualisieren.
9. Vollständige Befehls-/Flag-Referenz: `~/Library/Application Support/Kanban/claude/rules/worktree.md`.

---

## Fehlerbehandlung

| Fehler                                                    | Reaktion                                                                          |
|-----------------------------------------------------------|-----------------------------------------------------------------------------------|
| `iwf`/`git` läuft aus dem zu löschenden Worktree heraus   | Benutzer ins Haupt-Repo schicken (`cd <repoDir>`)                                 |
| Worktree-Pfad existiert nicht (mehr)                      | `iwf` prunt stale Einträge i.d.R. automatisch; auf Weg B `git worktree prune`     |
| Docker-Stack-Stop schlägt fehl (Weg A)                    | Benutzer manuell prüfen mit `docker ps`                                           |
| `git worktree remove`: „contains modified or untracked files" | `status --short` zeigen, per `AskUserQuestion` fragen, nur bei Ja `--force`   |
| Task-File hat keinen Worktree-Block                       | Trotzdem fortfahren, Status ggf. anpassen                                         |
| Branch ist nicht im Basis-Branch gemerged + `--delete-branch` | WARNEN vor Ausführung (mit Nennung des geprüften Branches), Benutzer bestätigen lassen |
| `--keep-data` bei `dockerStack: false`                    | Einmal erwähnen, dass es ohne Volume gegenstandslos ist, und weitermachen          |

---

Beginne damit, `.claude/project.json` zu lesen und `dockerStack` festzustellen, dann Phase 1: Eingabe prüfen.
