---
name: get-doc
description: Confluence-Seite als Markdown in den Doku-Ordner des Projekts holen
argument-hint: <PAGE-ID oder Confluence-URL>
disable-model-invocation: true
---

# GET DOC - Confluence-Seite holen

> ⚙️ **Projektwerte** (`docsPath`, `prefix`, `tasksPath`, `repoDir`, …): stehen in
> `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

## Seite

$ARGUMENTS

## Wohin die Seite gehört

`docsPath` aus `.claude/project.json` — normalerweise
`~/Library/Application Support/Kanban/docs/<projekt>`.

**Nicht ins Repo.** Dokumentation wird dort nie mitcommittet (die `docs/`-Ordner sind gitignored);
sie lag im Arbeitsverzeichnis nur herum und verschwand mit dem nächsten Aufräumen. Der Ordner gilt
projektweit — mehrere Confluence-Spaces desselben Projekts teilen ihn, die Page-Id im Dateinamen
hält sie auseinander.

## Ablauf

**Schritt 1 — Exportieren**

`mcp__hermes__generate-confluence-page` mit `pageId` = dem Argument (eine Confluence-URL nimmt das
Tool ebenfalls, es zieht die Id selbst heraus). Es schreibt:

- die Seite als `<PAGE_ID>-<slug>.md` (Confluence-Storage → Markdown),
- alle Anhänge und eingebetteten Bilder nach `<PAGE_ID>/`,
- und ersetzt die Bild-URLs im Text durch die lokalen Pfade.

**Schritt 2 — Ablageort prüfen**

Das Tool meldet, in welchen Ordner es geschrieben hat. Der kommt aus `~/.hermes/config.json`
(`modules.confluence.projects.<name>.path`, gefunden über den Space der Seite) — **nicht** aus
`.claude/project.json`.

| Ergebnis | Aktion |
|---|---|
| Ordner = `<docsPath>` | Fertig. |
| anderer Ordner | `<PAGE_ID>-<slug>.md` **und** den Ordner `<PAGE_ID>/` nach `<docsPath>` verschieben (`mkdir -p` vorher). Danach dem Benutzer sagen, dass der Space in Kanban → Einstellungen → Confluence noch auf den alten Ordner zeigt — sonst wandert jede weitere Seite wieder dorthin. |

**Schritt 3 — „Datei existiert bereits"**

Das Tool überschreibt nie. Zeig den vorhandenen Stand (Pfad, Änderungsdatum) und **frag**, ob er
ersetzt werden soll. Nur nach ausdrücklichem Ja: die alte `.md` **und** den Anhang-Ordner
`<PAGE_ID>/` löschen, dann Schritt 1 wiederholen. Ohne Ja: den vorhandenen Stand lesen und damit
weiterarbeiten.

**Schritt 4 — „Kein Projekt für Space … konfiguriert"**

Dann kennt die Config den Space nicht. **Nicht raten** und nicht in einen fremden Ordner ausweichen:

1. Einmalig durchkommen: denselben Aufruf mit `project: <projekt-key>` wiederholen (überspringt die
   Space-Auflösung), danach Schritt 2.
2. Dauerhaft: den Benutzer bitten, den Space in Kanban → Einstellungen → Confluence einzutragen
   (Space-Key + Doku-Pfad). Kanban schreibt ihn nach `~/.hermes/config.json` zurück.

**Schritt 5 — Zusammenfassung**

- **Titel** der Seite und der **absolute** Zielpfad (klickbar, damit der Benutzer sie öffnen kann)
- Anzahl übernommener Anhänge
- 3–5 Zeilen: worum es auf der Seite geht

## Grenzen des Exports (und wie man sie prüft)

Der Weg ist ADF → Markdown; eine Markdown-Tabelle kann aber keine Blöcke tragen. Was in einer
**Tabellenzelle** steht, wird deshalb zu einer Zeile zusammengefügt (` <br> `):

- **Flache Listen** werden zu `- a <br> - b` — eine Zeile, aber lesbar.
- **Verschachtelte Listen** werden zu inline `<ul>/<ol>`: die Ebene ist dann echte Struktur, kein
  Zeichen, das man deuten muss. Markdown darin (Links, `**fett**`) rendert weiter.
- **Überschriften** in Zellen werden **fett**; Rauten wären dort wörtlicher Text.
- **Codeblöcke, Panels und andere Blöcke** in Zellen werden ebenfalls eingeebnet.

Ausserhalb von Tabellen ist der Export strukturtreu.

> Zählt die Struktur wirklich (Akzeptanzkriterien, tief verschachtelte Listen), lies die Seite
> zusätzlich über das Atlassian-MCP mit `contentFormat: "html"` gegen — dort steht die
> Verschachtelung als echtes `<ul>`.

Wurde eine Seite **vor dem 2026-09-01** exportiert, stammt sie aus dem alten Konverter: dort standen
Unterpunkte vor ihrem Elternpunkt, und `status`-Lozenges fehlten ganz. Solche Dateien lohnen einen
neuen Export (Schritt 3: erst fragen, dann ersetzen).

## Regeln

1. **Nie ins Repo kopieren und nie committen** — der Doku-Ordner liegt bewusst ausserhalb.
2. **Nichts überschreiben ohne Rückfrage** (Schritt 3): ein Export kann von Hand ergänzt worden sein.
3. **Immer mit absolutem Pfad verweisen**, wenn du die Seite in einem Task-File zitierst — relativ
   zum Repo gibt es sie nicht.
4. **Der Doku-Ordner ist keine Ticket-Ablage.** Task-Files gehören nach `tasksPath`, exportierte
   Seiten nach `docsPath`.
