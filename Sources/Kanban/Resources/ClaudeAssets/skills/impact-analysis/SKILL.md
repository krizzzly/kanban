---
name: impact-analysis
description: Impact-Analyse für einen Task (offen, in Bearbeitung oder abgeschlossen). Nur explizit aufrufen — kein Auto-Trigger.
argument-hint: <task-file.md, branch-name, TICKET-NUMMER oder MR-Nummer>
disable-model-invocation: true
---

# IMPACT-ANALYSE — Standalone

Führe eine Test-Impact-Analyse für einen beliebigen Task durch — unabhängig davon,
ob der Task offen, in Bearbeitung oder bereits abgeschlossen ist.

## Input

$ARGUMENTS

**Akzeptierte Formate:**
- Task-File: `docs/tasks/BFEZVM-1234_feature.md`
- Ticket-Nummer: `BFEZVM-1234`
- Branch-Name: `feature/BFEZVM-1234_feature`
- MR-Nummer: `!969` oder `969`
- Kein Argument: Aktueller Branch wird verwendet

---

## Workflow

### Schritt 1: Task und Branch identifizieren

1. **Ticket-Nummer ermitteln** aus dem Argument (Task-File-Name, Branch, MR oder direkt):
   ```bash
   # Falls kein Argument: aktuellen Branch verwenden
   git branch --show-current
   ```

2. **Task-File suchen:**
   ```bash
   ls docs/tasks/BFEZVM-<NUMMER>*.md
   ```

3. **Branch ermitteln:**
   ```bash
   git branch -a | grep -i "<TICKET-NUMMER>"
   ```

### Schritt 2: Status erkennen und Datenquelle bestimmen

| Situation | Erkennung | Datenquelle |
|-----------|-----------|-------------|
| **Offen (nur Plan)** | Task-File hat `## Lösungsplan`, aber kein Branch/keine Commits | Lösungsplan aus Task-File |
| **In Bearbeitung** | Feature-Branch existiert mit Commits, nicht gemerged | git diff des Branches |
| **Abgeschlossen** | Branch gemerged in develop/main | Commits aus git log |

**Erkennung automatisieren:**

```bash
TICKET="<TICKET-NUMMER>"

# Branch suchen
BRANCH=$(git branch -a --list "*${TICKET}*" | head -1 | tr -d ' ')

# Prüfen ob gemerged
if [ -n "$BRANCH" ]; then
    MERGED=$(git log --oneline develop --grep="$TICKET" | head -5)
    if [ -n "$MERGED" ]; then
        echo "STATUS: Abgeschlossen (gemerged)"
    else
        echo "STATUS: In Bearbeitung (Branch: $BRANCH)"
    fi
else
    echo "STATUS: Offen (kein Branch)"
fi
```

**Datenquelle je nach Status:**

**Offen (nur Lösungsplan):**
- Lies `## Lösungsplan` aus dem Task-File
- Nutze die geplanten Dateien/Klassen als Ausgangspunkt
- Entspricht dem `/start-task`-Modus

**In Bearbeitung (Branch existiert):**
```bash
MERGE_BASE=$(git merge-base origin/<branch> develop)
git diff --name-only $MERGE_BASE..origin/<branch>
```

**Abgeschlossen (gemerged):**
```bash
# Commits des Tickets in develop finden
git log --oneline develop --grep="<TICKET-NUMMER>"
# Geänderte Dateien aus diesen Commits extrahieren
git log --name-only --pretty=format: develop --grep="<TICKET-NUMMER>" | sort -u | grep -v "^$"
```

### Schritt 3: Impact-Analyse durchführen

⚠️ **PFLICHT:** Lies und befolge die vollständige, projekt-neutrale Anleitung in der gebündelten
[methodology.md](methodology.md) (`${CLAUDE_SKILL_DIR}/methodology.md`)

**Zuerst — Projekt-Profil bestimmen:** Die Auto-Detektions-Greps aus der Anleitung (Abschnitt
„Projekt-Profil zuerst bestimmen") einmal ausführen und die `‹Profil.X›`-Werte festhalten (FE-Sprache,
Read-Modell, Autorisierung, Async-Mechanismus, Hochrisiko-Enums). Diese Werte steuern alle folgenden
Schritte. Der Projekt-Doku (`architecture.md`) dabei NICHT blind trauen — aus dem Code detektieren.

Führe dann alle 6 Schritte der Anleitung aus:

0. **Historische Ticket-Verfolgung** (PFLICHT, vor allem anderen) — Git-History jeder zu ändernden Datei
   rückwärts nach Ticket-Commits durchsuchen, um bewusste frühere Design-Entscheidungen NICHT blind zu
   überschreiben. Vollständige Befehle + Doku-Tabelle → Anleitung, „Schritt 0".
1. Dateien kategorisieren (nach Architektur-Schicht)
2. Aufwärts-Verfolgung (Bottom-Up Tracing) bis Controller/Frontend — Write Flow und Read Flow getrennt
3. Business-Logik-Verzweigungen erkennen (Enums UND Properties!) — inkl. Datenfluss-Verfolgung bei
   „Feld nicht befüllt / zeigt 0"-Bugs (nach **Property** statt Setter grep'en, Calc-/Lese-Schicht zu
   Ende lesen, kanonisches Prädikat statt Eigenbau-Guard) → Anleitung, „Schritt 3c".
4. Betroffene Test-Bereiche zusammenstellen
5. Nachfragen formulieren

### Schritt 4: Ergebnis dokumentieren

**Falls Task-File existiert:** Füge die Analyse unter `## Impact-Analyse` im Task-File ein
(oder aktualisiere eine bestehende Sektion).

**Format:**

```markdown
## Impact-Analyse

**Durchgeführt am:** <DATUM>
**Basis:** [Lösungsplan / Branch `<name>` / Gemergte Commits]
**Status bei Analyse:** [Offen / In Bearbeitung / Abgeschlossen]

### Betroffene Schichten
| Schicht | Dateien |
|---------|---------|
| ... | ... |

### Impact-Pfade
...

### Verzweigungen (Risiko-Analyse)
...

### Test-Bereiche für QA
...

### Nachfragen
...
```

### Schritt 5: Zusammenfassung ausgeben

```
🔍 IMPACT-ANALYSE: <TICKET-NUMMER>

**Status:** [Offen / In Bearbeitung / Abgeschlossen]
**Basis:** [Lösungsplan / Branch / Gemergte Commits]

## Ergebnis
- Betroffene Controller/Endpunkte: [Anzahl]
- Betroffene Frontend-Bereiche: [Anzahl]
- Erkannte Verzweigungen: [Anzahl, davon X mit Risiko]
- Nachfragen: [Anzahl]

## Wichtigste Risiken
[Top 3 Findings kurz aufgelistet]

📄 Dokumentiert in: docs/tasks/<TICKET>_<name>.md → ## Impact-Analyse
```

---

## Starte jetzt!

Beginne mit Schritt 1: Task und Branch identifizieren.
