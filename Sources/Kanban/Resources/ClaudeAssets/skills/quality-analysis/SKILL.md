---
name: quality-analysis
description: Qualitäts-Analyse eines Features — prüft entweder den Lösungsplan (vor der Umsetzung) oder den Feature-Branch (nach der Umsetzung) gegen Coding Principles, Architekturregeln, Qualitätsrisiken und Design Patterns. Nur explizit aufrufen — kein Auto-Trigger.
argument-hint: <task-file.md, plan-file.md, TICKET-NUMMER, Branch-Name oder Suchbegriff>
disable-model-invocation: true
---

# QUALITÄTS-ANALYSE — Lösungsplan oder Feature-Branch

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `stackDomain`, `gitlabProjectPath`):
> stehen in `.claude/project.json` im Repo-Root. Platzhalter wie `<PREFIX>`/`<tasksPath>` stehen für diese Werte.

Prüfe die Qualität eines Features gegen relevante Coding Principles, Architekturregeln,
Qualitätsanforderungen und Design Patterns — **entweder** den *Lösungsplan* vor der Implementierung
**oder** den *Feature-Branch* nach der Implementierung.

Ziel ist **nicht**, möglichst viele Prinzipien/Patterns zu erwähnen, sondern aus dem konkreten
Feature-Kontext die tatsächlich relevanten Prüfungen abzuleiten, Lücken nachzuweisen und ein belastbares
Ergebnis zu formulieren.

> **WICHTIG:** Dieser Workflow erstellt/verbessert einen Plan (Plan-Modus) bzw. weist Qualitätslücken im
> Code nach (Branch-Modus). Er implementiert das Feature nicht, sofern nicht ausdrücklich verlangt.

## Input

$ARGUMENTS

**Akzeptierte Formate:** Task-File `<tasksPath>/<PREFIX>-1234_*.md` · Plan-File `docs/plans/*.md` ·
Ticket-Nummer `<PREFIX>-1234` · Branch-Name `feature/<PREFIX>-1234_*` · Suchbegriff · kein Argument
(= aktueller Branch + zugehöriges Task-File).

## Schritt A: Modus bestimmen (Lösungsplan vs. Feature-Branch)

Beide Modi nutzen **dieselbe** Methodik (Regeln, Qualitätsprofile, Prinzipien, Patterns, Findings). Nur der
**Review-Gegenstand** unterscheidet sich:

| Modus | Review-Gegenstand | Zeitpunkt |
|-------|-------------------|-----------|
| **Plan-Modus** | `## Lösungsplan` aus dem Task-File (Text) | vor der Implementierung |
| **Branch-Modus** | tatsächlicher Code-Diff des Feature-Branches | nach der Implementierung |

Erkennung:

```bash
TICKET="<TICKET-NUMMER>"
git branch --show-current
git branch -a --list "*${TICKET}*"
# Branch-Modus-Gegenstand:
MERGE_BASE=$(git merge-base HEAD develop); git diff --name-only $MERGE_BASE..HEAD
```

- Nennt der User explizit „Branch"/„Plan" → dieser Modus (Vorrang).
- Sonst: liegt ein Feature-Branch **mit Implementierung** vor → **Branch-Modus**; liegt (nur) ein
  Lösungsplan im Task-File vor → **Plan-Modus**.
- Bei Zweideutigkeit kurz nachfragen, welcher Gegenstand geprüft werden soll.

## Schritt B: Qualitäts-Methodik durchführen

⚠️ **PFLICHT:** Lies und befolge die vollständige Methodik in der gebündelten
[methodology.md](methodology.md) (neben dieser Datei im Skill-Verzeichnis) — **alle** Schritte, mit dem in
Schritt A bestimmten Review-Gegenstand.

Kurzform der Kette: fachliches Wirkungsmodell → Repository-Evidenz (inkl. historischer Ticket-Verfolgung
und vollständiger Datenfluss-Verfolgung) → Klassifikation → Qualitätsprofile aktivieren →
Coding-Principles-Review → Design-Pattern-Fit-Analyse → Trade-offs auflösen → Vollständigkeit prüfen →
adversarialer Gegencheck → Findings bewerten (BLOCKER…INFO).

## Schritt C: Ergebnis dokumentieren & Freigabeentscheidung

Gemäß methodology.md Schritt 13–15. Zielsektion im Task-File je nach Modus:

- **Plan-Modus:** `## Lösungsplan-Qualitätsreview` (+ überarbeiteter Lösungsplan)
- **Branch-Modus:** `## Qualitätsreview (Branch)` (+ priorisierte Liste erforderlicher Code-Änderungen
  statt eines überarbeiteten Plans)

Freigabeentscheidung: `FREIGEGEBEN` / `FREIGEGEBEN MIT ÄNDERUNGEN` / `PLAN ÜBERARBEITEN` (Plan-Modus) bzw.
`CODE ÜBERARBEITEN` (Branch-Modus).

## Starte jetzt

Beginne mit **Schritt A: Modus bestimmen**. Implementiere noch keinen Code.
