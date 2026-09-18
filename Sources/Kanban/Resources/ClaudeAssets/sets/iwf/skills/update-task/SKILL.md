---
name: update-task
description: Aktualisiere das aktuelle Task-File — entweder mit den zuletzt besprochenen Änderungen oder mit einer konkreten Anpassung
argument-hint: (optional) konkrete Anpassung als Freitext
disable-model-invocation: true
---

# UPDATE TASK - Task-File Synchronisation

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `dockerStack`, `stackDomain`,
> `gitlabProjectPath`): stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen
> Projektwert brauchst — nie raten. `dockerStack: false` heisst: kein Docker-Stack — dann gibt es weder
> `stackDomain` noch `iwf`, und Befehle laufen direkt im Worktree.

Du aktualisierst das **aktuelle** Task-File im Projekt.

## Modus-Auswahl

**Input:** $ARGUMENTS

| Situation | Modus | Vorgehen |
|-----------|-------|----------|
| `$ARGUMENTS` ist **leer** | **Auto-Sync** | Im aktuellen Gespräch besprochene Anpassungen, Entscheidungen, Spec-Änderungen ins Task-File einarbeiten |
| `$ARGUMENTS` ist **Freitext** | **Direkt-Update** | Genau diese Anpassung im Task-File durchführen (z.B. Entscheidung hinzufügen, Section korrigieren, Status ändern) |

**WICHTIG:** Direkt loslegen, kein Plan-Mode. Keine Code-Änderungen — dieser Command ist rein dokumentarisch.

---

## Schritt 1: Aktuelles Task-File ermitteln

1. Branch-Name lesen:
   ```bash
   git branch --show-current
   ```
2. Ticket-Nummer extrahieren (z.B. `feature/<PREFIX>-1234_…` → `<PREFIX>-1234`; `prefix` aus `.claude/project.json`)
3. Task-File suchen:
   ```bash
   ls <tasksPath>/<PREFIX>-<NR>*.md
   ```

**Auswertung:**

| Situation | Aktion |
|-----------|--------|
| Genau 1 File gefunden | Verwende dieses File |
| Mehrere Files gefunden | Liste zeigen, Benutzer fragen |
| Kein File gefunden | Hinweis: `create-task` oder Branch-Name passt nicht zum Schema |

---

## Schritt 2: Modus-spezifisches Vorgehen

### Modus A — Direkt-Update (wenn `$ARGUMENTS` vorhanden)

Der Freitext aus `$ARGUMENTS` beschreibt **genau eine** Anpassung. Beispiele:

- `"Entscheidung ergänzen: Cancel-Button rot statt grau"`
- `"Status auf 🟢 Abgeschlossen setzen"`
- `"Edge-Case 'Status canceled' korrigieren — Download bleibt verfügbar"`
- `"Lösungsplan Punkt 6 entfernen, ist nicht mehr nötig"`

**Vorgehen:**
1. Den Freitext interpretieren: Ist es eine **neue** Entscheidung, eine **Korrektur**, eine **Streichung** oder ein **Status-Wechsel**?
2. Passende Stelle im Task-File finden (`## Entscheidungen`, `## Lösungsplan`, `### Status`, `## Edge Cases`, etc.)
3. Direkt anwenden:
    - Neue Entscheidung → nächste freie Nummer unter `## Entscheidungen`
    - Korrektur → bestehende Stelle ergänzen mit „(revidiert)" und Begründung
    - Streichung → mit „(obsolet)" markieren statt löschen, kurze Begründung
    - Status → `### Status`-Block aktualisieren
4. Zu Schritt 5 (Zusammenfassung) springen.

→ **Schritte 3 und 4 (Diff + Auto-Updates) überspringen** im Direkt-Update-Modus.

### Modus B — Auto-Sync (wenn `$ARGUMENTS` leer)

Gehe den **bisherigen Gesprächsverlauf** durch und sammle:

- ✅ **Entscheidungen** des Benutzers (z.B. „Status-Gate auf started ändern", „Button am Anfang der Card")
- ✅ **Spec-Korrekturen** (z.B. „nicht im Anhang, sondern als eigene Datei-Entität")
- ✅ **Scope-Änderungen** (Streichungen / Erweiterungen)
- ✅ **Implementierungsdetails** die nicht aus dem Code ablesbar sind (z.B. „RFC 5987 Filename-Fallback wegen Umlaut")
- ✅ **Konfigurations- / Permission-Anpassungen** (neue Scopes, neue Frontend-Actions)
- ✅ **DB-Schema-Änderungen** (neue Migrations, neue FKs, Relations)
- ✅ **UI-Pattern-Entscheidungen** (Button-Platzierung, disabled-States, Tooltip-Texte)

**Ignoriere reine Code-Mechanik** (Klassennamen, Methodensignaturen) — die ergibt sich aus dem Code selbst.

---

## Schritt 3: Task-File diffen

Lies das Task-File und prüfe für jeden gesammelten Punkt:

- **Ist die Entscheidung bereits dokumentiert?** → ggf. präzisieren / aktualisieren
- **Widerspricht eine alte Aussage einer neuen Entscheidung?** → die alte revidieren, „revidiert" oder „obsolet" markieren
- **Fehlt eine neue Entscheidung?** → als neuen Punkt unter `## Entscheidungen` ergänzen, fortlaufend nummeriert
- **Veraltete Sections** (z.B. Lösungsplan mit obsoleten Scope-Angaben)? → konsistent zur aktuellen Realität anpassen, Verweise auf die Entscheidungsnummern setzen

---

## Schritt 4: Task-File updaten

- Hänge neue Entscheidungen mit `✅` an die fortlaufende Nummerierung unter `## Entscheidungen` an
- Für **revidierte** Entscheidungen: bestehende ergänzen mit „(revidiert)" und neuem Inhalt — alte Variante nicht löschen, sondern verständlich machen warum sich der Plan geändert hat
- Bei Status-Änderungen am Anfang (`### Status`): aktualisieren falls nötig (`🟡 In Arbeit` / `🟢 Abgeschlossen`)
- **JIRA Lösungsfeld** am Ende: ggf. Test-Anleitung + Geänderte-Dateien-Liste nachziehen, wenn neue Dateien hinzugekommen sind
- **JIRA Lösungsfeld → `### Für Kunde`**: jede neue oder revidierte Entscheidung, jede Abweichung von den
  Akzeptanzkriterien und jede Annahme dort in den Block „Entscheidungen, Abweichungen, Annahmen"
  nachziehen — dieser Unterabschnitt geht ins Jira-Feld „Lösung" und ist nach dem Merge die einzige
  Stelle, an der das noch steht (das Task-File wird nicht mitcommittet)

---

## Schritt 5: Zusammenfassung ausgeben

Nach dem Update **kurze** Zusammenfassung (3–6 Bulletpoints) ausgeben:

```
📝 Task-File aktualisiert: <tasksPath>/<PREFIX>-<NR>_<…>.md

## Hinzugefügt
- Entscheidung #X: <Kurzbeschreibung>
- Entscheidung #Y: <Kurzbeschreibung>

## Revidiert
- Entscheidung #Z: <was geändert wurde>

## Veraltete Sections aktualisiert
- <Section-Name>: <Was geändert>
```

---

## Wichtige Regeln

1. **Argumente optional** — leer = Auto-Sync ganzes Gespräch; Freitext = genau diese eine Anpassung. Branch-Name liefert das Task-File
2. **Direkt-Update bleibt minimal** — nur das anwenden was im Freitext steht, nicht das ganze Gespräch zusätzlich durchgehen
3. **Kein neues Task-File anlegen** — wenn keins gefunden wird, abbrechen und Benutzer informieren
4. **Keine Code-Änderungen** — dieser Command ist rein dokumentarisch
5. **Konsistenz vor Vollständigkeit** — lieber präzise wenige Anpassungen als jeden Detail aus dem Chat reinkopieren
6. **„Warum" statt „Was"** — die Entscheidungen begründen, nicht den Code wiederholen
7. **Sprache** — Task-File ist auf Deutsch, Code-Identifier auf Englisch (so wie der Rest des Repos)
