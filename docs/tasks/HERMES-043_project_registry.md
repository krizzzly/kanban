# HERMES-043 - Projekt-Registry: ein Ort für neue Projekte, Modul-Configs generiert

> 🌳 **REPO**: `/Users/christianhiller/code/kanban`\
> 📅 **Angelegt**: 2026-08-07\
> 🌿 **BRANCH**: `main` (kein Worktree — Kanban ist eine Swift-App ohne `.iwf.yml`/Docker-Stack)

### Status
🟡 In Arbeit

Typ: Story

## Beschreibung

Ein neues Projekt aufzuschalten heisst heute: **dieselbe Projektliste vier Mal** in
`~/.hermes/config.json` pflegen — `modules.jira.projects`, `modules.gitlab.projects`,
`modules.confluence.projects`, `modules.vertec.projects`. Jede Section hat einen anderen Ausschnitt
derselben Wahrheit, keine kennt die andere.

Ziel: **ein Ort**, an dem ein Projekt mit seiner Minimal-Konfiguration angelegt wird (das, was für
Board, Worktree, Buchung nötig ist) — die Modul-Configs werden daraus **generiert**.

### Ziel

Die Hermes-Config **bleibt die Wahrheit** und bleibt in den Modul-Bereichen editierbar. Zentral wird
nur, was verstreut wehtut: das **Anlegen** (und Entfernen) eines Projekts.

```
                    ┌──────────────────────────┐
Neues Projekt  ────▶│ Bereich „Projekte"       │──schreibt in alle 6 Sections──┐
(einmal erfasst)    │ (Vorschläge aus Mustern) │                               ▼
                    └──────────────────────────┘              ~/.hermes/config.json  ──▶ Hermes
                                                                       ▲
                              Feinschliff einzelner Werte ─────────────┘
                              (Modul-Bereiche, unverändert)
```

Das legt die Langfrist-Frage („weg von der Hermes-Config") **nicht** fest: `ProjectRecord` und die
Projektion sind genau das, was man dann braucht — es wechselt nur der Speicherort.

---

## Analyse

**Art der Änderung:** Feature (neue Core-Schicht + Settings-UI)

### Bestandsaufnahme (2026-08-07 erhoben)

Ein Projekt ist heute über **sechs** Sections verstreut:

| Section | Felder | Beispiel `even` |
|---|---|---|
| `modules.jira.projects.<key>` | `prefix`, `tasksPath`, optional `baseUrl`, `repoDir` | `EVEN`, `even/docs/tasks` |
| `modules.gitlab.projects.<key>` | `path` | `applications/even` |
| `modules.confluence.projects.<key>` | `space`, `path` | `EVEN`, `even/docs/kb` |
| `modules.vertec.projects.<key>` | `project`, `phase`, `task`, `additionalKeys` | `8100 - EVEN Basisprodukt`, … |
| `modules.jenkins.projects.<key>` | `jobs[]` | `even - DEV - Build`, … |
| `modules.dockerhub.projects.<key>` | `namespace`, `repository` | (nur `bfezvm`) |

> Jenkins und DockerHub kamen erst bei der Umsetzung dazu: `grep '\.projects\b'` über
> `mcp-server/` zeigte **sechs** Fundstellen, und die Keys (`bfezvm`, `even`) sind dieselben
> Projektnamen — es ist derselbe Begriff, nicht ein zufällig gleich heissendes Feld.

**Nicht deckungsgleich**, und das ist fachlich korrekt, nicht versehentlich:

- `jira` kennt 7 Keys, `gitlab` 4, `confluence` 3, `vertec` 3
- `tp1`, `zvmsupport`, `support` sind **Support-Projekte ohne eigenes Repo** — eigenes Jira-Prefix,
  aber Task-Files und Code liegen im Repo eines anderen Projekts (`bfezvm` bzw. `even`)
- `zvmsupport` hat einen **abweichenden Jira-Host** (`support-energie.atlassian.net`)
- `tech` existiert **nur** in Confluence (Space ohne Jira-Projekt)
- `confluence.tech.path` zeigt in ein fremdes Repo (`bfezvm/docs/kb`)

→ Das Master-Schema muss „N Prefixe teilen ein Repo" und „Modul-Zugehörigkeit ist optional" nativ
können. Ein Record mit lauter Pflichtfeldern würde diese Fälle kaputt-normalisieren.

### Was schon da ist (und wiederverwendet wird)

| Baustein | Datei | Rolle hier |
|---|---|---|
| `JSONValue` + `value(at:)`/`set(_:at:)` | `KanbanCore/Config/JSONValue.swift` | round-trip-sicherer Zugriff per Key-Pfad — die Projektion braucht **kein** neues Config-Parsing |
| `ConfigStore` | `KanbanCore/Config/ConfigStore.swift` | Laden/Speichern mit mtime-Konflikterkennung, `.bak`-Backup, atomarem Write |
| `HermesConfigLoader` | `KanbanCore/Config/HermesConfig.swift` | strikter Leser für die App (`ProjectConfig`) — bleibt unverändert, liest weiter die generierte Datei |
| `ClaudeProjectFile` | `KanbanCore/Claude/ClaudeProjectFile.swift` | schreibt schon heute `<repo>/.claude/project.json` — dasselbe Muster, eine Ebene höher |
| `SettingsModel` + `ProjectMapEditor` | `Kanban/Settings/` | schema-getriebene UI über die vier `projects`-Maps — wird durch **einen** Editor ersetzt |
| `hermes daemon-restart` | `SettingsModel.restart()` | nötig, weil Hermes die Config per mtime cached |

### Fachliche Einordnung

Der Nutzen ist nicht „weniger JSON", sondern **kein Auseinanderlaufen**: `tasksPath` steuert
gleichzeitig Kanban (Board-Spalten, Task-Tabs) und Hermes' `generate-claude-task`. Heute können die
vier Sections divergieren, ohne dass es jemand merkt — dieselbe Drift-Klasse wie bei den
Claude-Assets in HERMES-034.

### Muss Hermes umgeschrieben werden?

**Nein — heute nicht, und später nur an sechs Zeilen.** Die Config behält exakt ihre Form
(`modules.<m>.projects.<key>`), sie wird nur nicht mehr von Hand gepflegt, sondern generiert. Die
Hermes-Module merken davon nichts; das ist per Identity-Test auf der echten Config festgenagelt.

Erst wenn die Hermes-Config als Projekt-Quelle ganz wegfallen soll, gibt es überhaupt etwas zu tun —
und die Angriffsfläche ist erfreulich klein. `grep '\.projects\b'` über `mcp-server/` liefert genau
sechs Fundstellen, je eine Einzeiler-Funktion pro Modul:

```
modules/jira/config.js:21        return getJiraConfig().projects || {};
modules/gitlab/config.js:20      return getGitlabConfig().projects || {};
modules/confluence/config.js:18  return getConfluenceConfig().projects || {};
modules/vertec/config.js:9       return getModuleConfig('vertec').projects || {};
modules/jenkins/config.js:29     return getJenkinsConfig().projects || {};
modules/dockerhub/config.js:16   return getDockerHubConfig().projects || {};
```

Alle Aufrufer gehen über diese `getProjects()` — kein Modul greift direkt auf `config.projects` zu.
Ein gemeinsamer Helper in `lib/config.js` mit Fallback-Kette (`projects.json` → `config.projects`)
würde also alle sechs auf einmal umstellen, ohne einen einzigen Tool-Handler anzufassen. Wichtig
bleibt der Fallback: Hermes-CLI und MCP müssen **ohne installiertes Kanban** lauffähig bleiben.

### Technische Einordnung

Neue Core-Schicht (`ProjectRegistry` + `ProjectProjection`), rein wertbasiert und damit gut testbar.
Kein Eingriff in `HermesConfigLoader` — die App liest weiter aus der Hermes-Config, nur wird deren
Projekt-Teil ab jetzt geschrieben statt gepflegt. **Hermes braucht null Codeänderung.**

**Betroffene Dateien:**

| Datei | Änderung |
|---|---|
| `Sources/KanbanCore/Config/ProjectRegistry.swift` | **neu** — `ProjectRecord` + Store (`AppSupport/Kanban/projects.json`) |
| `Sources/KanbanCore/Config/ProjectProjection.swift` | **neu** — Import aus + Projektion in die Hermes-Config |
| `Tests/KanbanCoreTests/ProjectRegistryTests.swift` | **neu** — Round-Trip, Werterhalt, Sonderfälle |
| `Sources/Kanban/Settings/ProjectsEditor.swift` | **neu** — ein Editor statt vier `ProjectMapEditor` |
| `Sources/Kanban/Settings/SettingsSheet.swift` | Projekt-Bereich einhängen |
| `Sources/KanbanCore/Config/ConfigSchema.swift` | die vier `projects`-Specs aus der generischen Form nehmen |

**Abhängigkeiten:** keine neuen Pakete.

---

## Entscheidungen

1. **Keine eigene Master-Datei** *(Revision 2026-08-07, Entscheidung des Users während der
   Umsetzung — ursprünglich war `~/Library/Application Support/Kanban/projects.json` geplant)*:
   eine persistierte Projektliste **neben** den weiterhin handeditierbaren Modul-Sections wären
   zwei Wahrheiten, die auseinanderlaufen, sobald jemand eine Section direkt anfasst — dieselbe
   Drift-Klasse wie bei den Claude-Assets in HERMES-034 („zwei Wahrheiten wären schlimmer als ein
   sauberer Schnitt"). Die Config bleibt die einzige Wahrheit.
2. **Zentral ist nur das Anlegen und Entfernen**, nicht die Pflege. Der Schmerz sitzt beim Anlegen
   (sechs Sections, leicht eine zu vergessen); ein einzelner Wert wird im Modul-Kontext geändert,
   wo er hingehört — eine Vertec-Phase wechselt jährlich und gehört zu Vertec.
3. **`ProjectRegistry` ist eine Sicht, kein Zustand**: `importing(from:)` liest sie live aus der
   Config. Deshalb kann sie gar nicht driften.
4. **Vorschläge statt leerer Felder**: das Formular liest die Muster, die in der Config ohnehin
   stehen (`applications/<key>`, `<key>/docs/tasks`, `<key> - DEV - Build`). Ohne das wäre zentrales
   Anlegen bloss ein Ortswechsel. Übernommen wird nur ein **eindeutiges** Mehrheitsmuster — bei
   Gleichstand die Konvention bzw. gar kein Vorschlag; ein falsch geratener Pfad ist teurer als ein
   leeres Feld.
5. **Additiv, nie destruktiv**: `apply` fasst nur eigene Felder an, ein unbekannter Projekt-Key
   bleibt stehen. Löschen ist eine ausdrückliche Aktion (`remove`) und damit klar vom Schreiben
   getrennt.
6. **Kein impliziter Task-File-Umzug**: `tasksPath` bleibt ein expliziter Wert. Der Umzug bleibt
   HERMES-034 Schritt 5, pro Projekt einzeln.

## Zielbild

Ein Bereich „Projekte" ganz oben in den Einstellungen:

```
Projekte                          ← quer zu allen Modulen, deshalb oben und abgesetzt
  bfezvm  BFEZVM   [Jira][GitLab][Confluence][Vertec][Jenkins][DockerHub]   🗑
  even    EVEN     [Jira][GitLab][Confluence][Vertec][Jenkins]              🗑
  tech             [Confluence]                                             🗑

Neues Projekt
  Projekt-Key:  neu
  → Ticket-Präfix NEU · Tasks-Pfad neu/docs/tasks · GitLab applications/neu
    Confluence NEU / neu/docs/kb · Jenkins "neu - DEV - Build, neu - DEV - Tests"
    DockerHub iwfwebsolutions/neu           (alles vorausgefüllt und editierbar)
  [Projekt anlegen]
```

Die Badges beantworten nebenbei eine Frage, für die man bisher durch sechs Bereiche blättern
musste: *in welchen Modulen ist dieses Projekt überhaupt konfiguriert?*

---

## Lösungsplan

### Schritt 1 — Core: Registry + Projektion (Fundament, ohne UI)
1. `ProjectRecord`/`ProjectRegistry` + Store (laden/speichern, fehlende Datei = leere Registry)
2. `ProjectProjection.importing(from:)` — Registry aus einer Hermes-Config ableiten
3. `ProjectProjection.apply(_:to:)` — Registry in eine `JSONValue`-Config schreiben, additiv
4. Tests: Import→Projektion ist **identity** auf der echten Config-Form; Sonderfälle (fremder
   Jira-Host, Repo-Teilung, Confluence-only, fremde Keys bleiben stehen)

### Schritt 2 — UI: Bereich „Projekte"
5. Übersicht mit Modul-Badges, Anlegen-Formular mit vorausgefüllten Vorschlägen, zentrales Entfernen
6. Speichern läuft über den bestehenden Footer (`ConfigStore.save()` + Daemon-Neustart-Banner) —
   das Anlegen ändert nur das Dokument, wie jede andere Einstellung auch
7. die Modul-Bereiche bleiben **unverändert** (Revision, siehe Entscheidung 1/2)

### Schritt 3 — Anschluss (offen)
8. Beim Anlegen: Task-Ordner erzeugen und `.claude/project.json` schreiben (bestehender Code)
9. Prüfen, ob die App nach dem Anlegen ohne Neustart auf das neue Projekt umschalten kann

### Edge Cases
- **Hermes-Config fehlt/kaputt**: Registry bleibt bedienbar, Projektion legt die Sections neu an
- **Externe Änderung während der Bearbeitung**: `ConfigStore`-Konflikterkennung greift (mtime)
- **Von Hand ergänzter Projekt-Key in einem Modul**: bleibt stehen (additiv), erscheint aber nicht
  in der Registry — bewusst, sonst würde Handarbeit stillschweigend gelöscht
- **Key-Umbenennung**: v1 nicht unterstützt (entfernen + neu anlegen) — Umbenennen müsste
  Task-Ordner, Worktrees und Buchungshistorie mitziehen, das ist ein eigener Task

---

## Risiken

- Die Projektion schreibt in eine Datei, an der auch Hermes-CLI/MCP hängen → `.bak` + atomarer Write
  (hat `ConfigStore` bereits), und Schritt 1 wird per Test auf **Werterhalt** festgenagelt
- Vergessener Daemon-Neustart ⇒ Hermes arbeitet mit der alten Config (mtime-Cache) — die UI muss
  aktiv darauf hinweisen (`savedPendingRestart` existiert)

---

## Abschluss-Checkliste

- [ ] Already-Solved-Check durchgeführt
- [ ] Task-File korrekt benannt
- [ ] Analyse dokumentiert
- [ ] Lösungsplan erstellt
- [x] Schritt 1: Registry + Projektion implementiert (`ProjectRegistry.swift`, `ProjectProjection.swift`)
- [x] Schritt 1: Tests grün — 16 Stück, inkl. Identity-Test gegen die **echte** `~/.hermes/config.json`
      (`XCTSkipUnless`, damit CI ohne Config nicht rot wird)
- [x] Jenkins + DockerHub nachgezogen (Fund während der Umsetzung: sechs Sections, nicht vier)
- [x] Revision: keine eigene `projects.json` — Config bleibt Wahrheit, zentral ist nur das Anlegen
- [x] `ProjectSuggestion`: Muster aus bestehenden Einträgen, nur bei eindeutiger Mehrheit
- [x] Schritt 2: Bereich „Projekte" in den Einstellungen (Übersicht + Anlegen + Entfernen)
- [x] Volle Suite grün (285 Tests) + `./build-app.sh` erfolgreich
- [ ] Schritt 3: Task-Ordner + `.claude/project.json` beim Anlegen
- [ ] Im laufenden Betrieb testen: ein echtes Projekt anlegen
- [ ] Änderungen committed
- [ ] Abschluss-Zusammenfassung ausgegeben
