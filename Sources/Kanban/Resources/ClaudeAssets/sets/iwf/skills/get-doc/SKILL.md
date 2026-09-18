---
name: get-doc
description: Confluence-Seite als Markdown in den Doku-Ordner des Projekts holen
argument-hint: <PAGE-ID oder URL> [mit Unterseiten] | check
disable-model-invocation: true
---

# GET DOC - Confluence-Seite holen

> ⚙️ **Projektwerte** (`docsPath`, `prefix`, `tasksPath`, `repoDir`, …): stehen in
> `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen Projektwert brauchst — nie raten.

## Argument

$ARGUMENTS

**Lies das Argument, gib es nicht roh weiter.** Es enthält zweierlei:

| Argument | Bedeutung |
|---|---|
| `13369356` oder eine Confluence-URL | Diese eine Seite holen |
| zusätzlich „mit Unterseiten", „ganzer Baum", „alles darunter", „rekursiv" | `children: true` — siehe Schritt 1 |
| `check`, `status`, `prüfen` (ohne Page-Id) | Nicht exportieren, sondern **Schritt 1c** ausführen |
| leer | Frag, welche Seite gemeint ist |

Zieh die Page-Id selbst heraus, bevor du das Tool rufst — `13369356 mit Unterseiten` ist keine
gültige `pageId` und das Tool bricht damit ab. Eine reine URL darfst du unverändert übergeben, die
zerlegt das Tool selbst.

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

**`children: true`** exportiert zusätzlich den gesamten Seitenbaum unterhalb der Seite — alles, was
in der Confluence-Navigation links darunter hängt — als je eigene Datei.

Nur setzen, **wenn der Benutzer den Unterbaum ausdrücklich will** ("mit Unterseiten", "ganzer Baum",
"alles darunter"). Der Default ist `false`. Grund: ein Baum kann Dutzende Seiten und hunderte
Anhänge umfassen und mehrere Minuten laufen (CORE-Kundendoku: 34 Seiten / 222 Anhänge / ~2 min).
Schätz vorher grob ab und sag dem Benutzer, was auf ihn zukommt.

Bereits vorhandene Unterseiten werden übersprungen statt überschrieben und trotzdem verlinkt — ein
zweiter Lauf ist damit billig und ergänzt nur, was fehlt. Seiten, deren Export scheitert, bleiben in
der Liste, zeigen aber auf Confluence statt auf eine fehlende Datei.

**Schritt 1b — was der Export sonst noch schreibt**

Jede Seite bekommt oben einen Abschnitt `## Unterseiten` mit ihren **direkten** Kindern — nicht dem
ganzen Unterbaum. So referenziert genau eine Datei jede Seite; eine Umbenennung kann keine veraltete
Kopie anderswo hinterlassen. Der Gesamtbaum steht stattdessen an zwei Stellen:

| Datei | Zweck |
|---|---|
| `_index.md` | Menschenlesbar: alle Wurzeln mit vollständig verschachteltem Baum. Wird bei jedem Export komplett neu geschrieben. |
| `_confluence.json` | Maschinenlesbar: flache Map `pageId → { title, parentId, childPosition, filename, spaceKey, pageVersion, lastModified, exportedAt, attachments }`. Der Baum steckt in `parentId`. |

Beide werden **auch bei `children: false`** aktualisiert — jeder Einzelexport wächst so in denselben
Index hinein und wird prüfbar. Nicht von Hand editieren, beide sind generiert.

**Schritt 1c — Stand prüfen**

`mcp__hermes__check-confluence-docs` vergleicht das Manifest mit Confluence und meldet *geändert*,
*neu*, *verschoben*, *verschwunden*, *Stand unbekannt*, *lokal gelöscht*. Ohne `project` prüft es
alle konfigurierten Projekte. Kostet ~2 Requests pro Wurzel, läuft in Sekunden, **ändert nichts** —
zum Nachziehen danach `generate-confluence-page` für die betroffene Seite aufrufen.

Nutz es, bevor du dich beim Beantworten einer Frage auf eine exportierte Seite stützt, wenn der
Export älter sein könnte. „Geändert" heisst nur, dass eine neue Revision existiert — nicht zwingend,
dass sich inhaltlich etwas Relevantes geändert hat.

Zwei bekannte Lücken, die der Check **nicht** sieht: ausgetauschte Anhänge (die bumpen die
Seitenversion nicht), und Seiten, deren `lastModified` als „Stand unbekannt" geführt wird, weil sie
vor dem Manifest exportiert wurden — die lassen sich nur durch einen Neuexport klären.

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
