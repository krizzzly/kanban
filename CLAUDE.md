# Kanban (HERMES-034)

A standalone native macOS app: a **sprint board + task-file cockpit** for Claude-Code work.
Reduced to a single view — top bar (project + sprint picker), a vertical Kanban board on the
left, and the structured task-file content as tabs on the right.

Die App ist **eigenständig**: sie besitzt ihre Jira- und GitLab-Module selbst und konfiguriert sie in
der **eigenen** Config (`~/Library/Application Support/Kanban/config.json`, editierbar über den
Zahnrad-Button). Hermes ist eine **optionale** Integration — liegt eine `~/.hermes/config.json`, wird
sie beim ersten Start einmalig übernommen; liegt keine, startet die App in den Setup-Schirm, nicht in
einen Fehler. Das Hermes-**Repo** wird nie verändert.

## Zwei Modi: Sprint und Frei

Der Umschalter steht in der Toolbar neben der Sprint-Auswahl, die Wahl gilt **je Projekt** und
überlebt den Neustart (`SelectionStore`, wie der gewählte Sprint) — ein Projekt ohne Jira-Board darf
dauerhaft frei laufen, während ein anderes im Sprint bleibt.

| | Sprint | Frei |
|---|---|---|
| Ticketliste | Jira: die Issues des gewählten Sprints | lokal: `LocalTickets` — jedes Task-File, dazu Worktrees und MRs ohne Task-File, **und offene MRs ganz ohne Ticketnummer** |
| Titel | Jira-Summary | H1 des Task-Files (`# EVEN-3687 - Titel`) — **keine** Jira-Anfrage |
| Sprint-Selektor | da | weg |
| Sprint-Spalte | da | weg — sie heisst „in Jira eingeplant, niemandem zugewiesen, lokal noch nichts da" und ist ohne Sprint gegenstandslos |
| Statt dessen | — | Knopf **„Task erstellen"** über den Spalten |

Alles danach ist identisch: Spalten-Herleitung, Badges, ⏱-Zeit, Kontextmenü. Nur die Sortierung ist
**numerisch** (`TicketNumber`) statt lexikografisch — sonst stünde EVEN-999 hinter EVEN-1000, was bei
30 Sprint-Karten kaum auffällt, bei 136 Karten Historie sofort. „Done" sortiert absteigend, das
zuletzt Fertige oben.

### Arbeit ohne Ticketnummer (`!<iid>`-Karten, nur im freien Modus)

Nicht jeder Branch trägt ein `<PREFIX>-<zahl>`. `feature/playwright-frontend-testing`,
`feature/remove_pure_base64_inclusions` — Arbeit, die jemand ohne Ticket angefangen hat. Bis jetzt
fiel sie **ganz vom Brett**: `LocalTickets` fand keinen Key und liess den MR weg. Gemessen: in `zba`
sind das 14 von 107 MRs, **4 davon offen**; in `bfezvm` 2, beide gemergt.

Genau diese Arbeit ist die, aus der man noch einen Task machen will — deshalb steht sie jetzt als
Karte da, mit „Task erstellen …" im Kontextmenü (Titel und Branch sind vorbelegt, damit
`/create-task` den vorhandenen Branch weiterbenutzt statt einen zweiten anzulegen).

- **Nur offene MRs.** Ein gemergter ohne Nummer ist erledigte Geschichte, aus der nichts mehr zu
  erstellen ist; ihn mitzunehmen hiesse, Done mit Altlasten zu füllen — in `zba` wären das 10 von
  14, der älteste von 2023, gegen die 4, um die es geht.
- **Der Key ist die Schreibweise der Forge** — `!<iid>` bei GitLab, `#<nummer>` bei GitHub,
  dieselbe, die `review-merge` als Argument nimmt (`MergeRequestRef.numberLabel`). Task-Files
  werden **nicht** rückwirkend umbenannt: `LocalTickets.mrKey(inFileName:)` erkennt beide
  Schreibweisen, damit ein `!49_slug.md` aus GitLab-Zeiten seine Karte behält. Gefunden wird die Karte aber **nicht** über ihn: `!130` steht
  in keinem Branchnamen. Sie trägt ihren Branch (`Ticket.sourceBranch`), und
  `TicketMatching.matches` vergleicht dann den Branch statt den Key zu suchen. Damit funktionieren
  Spalte, Badges, 🔀-Nummer und der **Worktree** unverändert — `feature/e2e-test-sf7` in `zba` hat
  einen, und die Karte zeigt ihn.
- **Der Branch-Vergleich ist exakt**, nicht als Teilstring: `feature/pdf` zöge sonst
  `feature/pdf_improvements` an sich, und in `zba` gibt es beide.
- **Die Spalte wird abgeleitet wie überall**, nicht gesetzt: ein review-reifer MR → Review, ein
  Draft → In Bearbeitung. In `zba` sind das 3 in Review und 1 in Bearbeitung (der Draft, mit
  Worktree). Der Draft ist der Grund für die **neue Präzedenzstufe „offener MR → In Bearbeitung"**:
  ohne sie fiel eine solche Karte bis nach „Sprint" durch — und die Spalte gibt es im freien Modus
  gar nicht, die Karte wäre unsichtbar gewesen. Die Stufe gilt allgemein und ist auch für
  nummerierte Tickets richtig: „Sprint" heisst „eingeplant, niemand hat es angefasst", und ein
  offener Merge Request ist das Gegenteil davon.
- **Nummerierte Karten stehen vorn**, die `!`-Karten dahinter (jüngster MR zuerst) — die gewohnte
  Liste bleibt, wie sie war.
- **Kein Jira-Aufruf.** Ein Ticket ohne Nummer steht in keinem Jira; `loadDetail` zeigt statt der
  sonstigen Jira-Beschreibung einen eigenen „Branch"-Tab (MR, Branch, Hinweis auf „Task erstellen").
  Ohne das gäbe es einen 404 und die Zeile „keine Beschreibung" — und der freie Modus soll ohnehin
  ohne eine einzige Jira-Anfrage auskommen.
- **Workflow-Commands fehlen im Kontextmenü**, mit Absicht: `/solve-task !130` zeigt auf nichts.
  Angeboten wird „Task erstellen …" und, wie bei jeder Karte mit offenem MR,
  `/review-merge !<iid>`.
- **Worktrees ohne Nummer** bleiben draussen (in `bfezvm` gäbe es 4, z. B. `E2E-Environment`): ein
  Checkout allein ist noch keine Arbeit, die jemand eingereicht hat, und der Ausgangspunkt hier war
  die Review-Spalte.

### „Task erstellen" → Projekt-Console

Der Knopf öffnet ein Modal mit einer Textarea; der Text geht als `/create-task <text>` in die
**Projekt-Console** — eine eigene tmux-Session je Projekt (`kanban-<KEY>-new`, cwd = Repo) mit
eigener, stabiler Claude-Session-Id im `SessionIdStore` (Pseudo-Key `new:<projekt>`). Ein Ticket gibt
es zu dem Zeitpunkt ja noch nicht; die Nummer erfindet erst der Command. Sobald das Task-File steht,
taucht die Karte beim nächsten Refresh auf und bringt ihre **eigene** Console mit.

- **Gepastet, nicht getippt** (`TmuxController.pasteText`: `load-buffer` + `paste-buffer -p`). Als
  Tastendruck würde der erste Zeilenumbruch einer mehrzeiligen Beschreibung sie zur Hälfte
  abschicken. Verifiziert: gegen eine echte Claude-Console landen drei Zeilen ungesendet im Prompt —
  gegen eine **zsh** dagegen führt derselbe Paste sie aus, Bracketed Paste hängt am Empfänger.
- **Kein Enter**, wie bei allen Commands: du liest in der Console gegen und schickst selbst ab.
- Die Console steht im Detailbereich (`NewTaskConsoleView`) statt des Ticket-Details und bleibt
  bestehen; ein Klick auf eine Karte schiebt sie beiseite, „Console anzeigen" holt sie zurück.
- **„Console anzeigen" legt sie nötigenfalls an** (`ensureNewTaskSession`, derselbe Weg wie beim
  Absenden — nur ohne Paste). Dass der Knopf da steht, sagt bloss, dass dieses Projekt schon einmal
  eine Console hatte: `hasNewTaskConsole` liest den `SessionIdStore`, und der überlebt den Neustart,
  die **tmux-Session** dagegen nicht. Vorher wurde der Name nur gesetzt, und das Terminal zeigte
  `can't find session: kanban-<KEY>-new` (an CORE beobachtet). Scheitert das Anlegen — `tmux
  new-session -c` gibt auf, wenn es das Repo-Verzeichnis nicht gibt —, bleibt statt eines toten
  Terminals eine Warnung in der Toolbar stehen.
- **Eine neu angelegte Session räumt den Terminal-Cache** (`TerminalCache.remove`), hier wie in
  `setupTerminal`: was eben noch nicht existierte, kann keinen lebenden View haben, und ein
  gescheitertes Attach bliebe sonst als tote Ansicht stehen — auch über die frische Session.

## Key idea: derived workflow status (NOT Jira status)

A ticket's column is derived from the **real local artifact state**, never from a manually
maintained Jira field. The board is therefore always honest and read-only — no card is ever
dragged by hand.

Columns (fixed order): `Sprint → Offen → In Bearbeitung → Review → Done`

Precedence (top-down, first match wins):

| # | Column | Condition | Source |
|---|---|---|---|
| 1 | Done | merged MR for `<TICKET>` exists | GitLab `merge_requests?state=merged` |
| 2 | Review | **non-draft** opened MR for `<TICKET>` exists | GitLab `merge_requests?state=opened` |
| 3 | In Bearbeitung | task-file `### Status` = 🟡 In Arbeit | task-file marker |
| 4 | Offen | task-file `<TICKET>*.md` exists OR worktree branch `*<TICKET>*` exists | local FS + `git worktree` |
| 5 | In Bearbeitung | nichts davon, aber ein **offener MR** | GitLab `merge_requests?state=opened` |
| 6 | Offen | lokal noch nichts, aber das Ticket ist **mir zugewiesen** | Jira `assignee.accountId` == `/myself` |
| 7 | Sprint | otherwise | Jira (default) |

**Zugewiesen heisst verantwortlich** (Stufe 5, `WorkflowStatus.resolve(isAssignedToMe:)`): „Sprint"
heisst „in Jira eingeplant, niemand hat es angefasst" — sobald das Ticket jemandem gehört, ist das
keine Beschreibung mehr, und es gehört in die Spalte, aus der man sich die nächste Arbeit holt. Es
ist bewusst die **letzte** Stufe: die Zuweisung sticht weder einen gemergten MR noch ein ✅ noch
einen laufenden Worktree — ein Ticket bleibt mir ja auch zugewiesen, während es in Review steht (23
von 32 Sprint-Tickets in bfezvm, fast alle in Done). Verglichen wird die **`accountId`**, nie der
Anzeigename: der ist nicht eindeutig und je Instanz anders geschrieben. `/myself` wird je Instanz
einmal geholt und gemerkt (derselbe Cache, den die `solve-task`-Nachführung benutzt); bleibt die
Auskunft aus, ist eben kein Ticket „meins" und die Ableitung bleibt, wie sie war.

### Sprint **oder** ganzes Board (`SprintChoice`)

Der Picker neben der Modus-Umschaltung bietet nicht nur die Sprints, sondern zuunterst auch
**„📋 Ganzes Board (offen)"**. Grund ist kein Sonderwunsch, sondern ein Projekt, das es wirklich so
gibt: `CORE` hat ein Scrum-Board mit 50 Sprints, **alle geschlossen**, der letzte endete 2021-02-15 —
dort wird ohne Sprint gearbeitet. Vorher meldete die App „Keine Sprints für dieses Board" und blieb
leer.

- **Vorauswahl** (`SprintSelection.resolve`): die zuletzt getroffene Wahl, sonst der aktive Sprint,
  sonst das **Board**. Ohne die letzte Stufe landete CORE im jüngsten Altsprint von 2021.
- **Immer im Menü**, nicht nur bei sprintlosen Projekten: auch mit laufendem Sprint will man
  gelegentlich das ganze Brett sehen, und ein Eintrag am Ende der Liste stört den Alltag nicht.
- **Was „das Board" zeigt** (`JiraClient.openBoardJQL`): `statusCategory != Done OR resolutiondate
  >= -14d`, ANDed mit dem Board-Filter. Das Nachlauf-Fenster ist nötig, nicht kosmetisch — ohne es
  verschwindet eine Karte in dem Moment, in dem Jira sie auf „Erledigt" setzt, samt ⏱-Zeit,
  Task-File-Tabs und Commit-Knopf, also genau dann, wenn Merge und Lösung noch anstehen. Ein Sprint
  behält seine fertigen Tickets ja auch bis zum Sprint-Ende.
- **Paginiert** (5 Seiten à 100): ein Board ohne Sprint führt Jahre an Tickets — CORE hat 2760.
  Darüber bricht `boardIssues` mit `APIError.tooManyPages` ab, statt eine stillschweigend halbe
  Liste zu zeigen.

#### Die Sprint-Liste muss paginiert werden — sonst fehlt der aktive Sprint

Jira gibt höchstens **50 Sprints pro Seite** heraus und ordnet sie **alt → neu**. Ab dem 51. Sprint
fällt damit ausgerechnet der *aktive* hinten runter — die Liste ist nicht irgendwo unvollständig,
sondern genau dort, wo gearbeitet wird.

Beobachtet an Board 71 (`CORETEST`, **69 Sprints**): die App meldete „0 aktiv", wählte deshalb das
ganze Board und zeigte **365 Backlog-Tickets** statt der **21** des laufenden Sprints
`CORETEST 2026-09`. Sichtbar wurde es erst im Browser — die REST-Antwort sah plausibel aus, 50
geschlossene Sprints sind ja kein Fehler. `sprints` paginiert deshalb bis `isLast` (20 Seiten à 50),
`sprintIssues` genauso (5 Seiten à 100, ein Sprint mit >100 Issues gäbe sonst ein halbes Board).

Die Board-Wahl bleibt trotzdem richtig — nur ist sie jetzt wieder das, was sie sein soll: die Antwort
für ein Board, das **wirklich** keinen aktiven Sprint hat (Board 88 `COREOLD`, 53 Sprints, alle
geschlossen), nicht der Notnagel für einen, den die Paginierung verschluckt hat.
- Die Wahl überlebt den Neustart wie der Sprint (`SelectionStore`, Wert `"board"` oder die Sprint-Id;
  eine alt gespeicherte nackte Zahl wird weiter gelesen).
- Alles danach ist unverändert — Spalten, Badges, ⏱, Kontextmenü. Die **Sprint**-Spalte heisst auch
  hier „in Jira eingeplant, lokal noch nichts da".

### Wieder aufgemachte Tickets (`WorkflowStatus.isReopened`)

Zwei Dinge halten eine Karte in Done fest, und beide sind **Fossilien**, sobald ein Ticket nach dem
„fertig" wieder aufgemacht wird: der gemergte MR der ersten Runde und das ✅ im Task-File (das die App
selbst schreibt, sobald Jira „Erledigt/Geschlossen" meldet). Zieht jemand das Ticket in Jira zurück
auf „In Arbeit" und läuft ein neuer MR, blieb die Karte trotzdem in Done — beobachtet an BFEZVM-4569
(Jira „In Arbeit", Task-File ✅, MR 1124 gemergt, 1140–1142 offen und review-reif).

**„Wieder aufgemacht"** = Jira führt das Ticket **ausdrücklich** als nicht erledigt (`statusCategory`
`new`/`indeterminate`) **und** es gibt einen offenen MR, der neuer ist als jeder gemergte (iid als
Alters-Proxy). Dann fallen Stufe 1 und das ✅ aus, und die aktuellen Artefakte entscheiden — offener
review-reifer MR → **Review**, nur ein Draft → Arbeitsspalte. Zusätzlich setzt `shouldAutoSetReview`
das veraltete ✅ im Task-File auf 🔵 zurück; ohne das bliebe der Marker für immer stehen und die
Karte klebte beim nächsten Refresh wieder.

Beide Hälften der Bedingung sind nötig, jede allein wäre falsch:

- **Jira allein** nicht: der Status hinkt hier regelmässig nach. Von 30 Sprint-Tickets in bfezvm
  stehen zwei (4535, 4554) mit gemergtem MR auf „In Arbeit" — sie müssen in Done bleiben, sonst fällt
  jedes fertige Ticket wieder heraus, bis jemand Jira nachzieht.
- **Der offene MR allein** nicht: ein liegengebliebener MR auf einem von Hand auf ✅ gesetzten Ticket
  darf es nicht aus Done ziehen — genau dafür gibt es die Stufe „✅ sticht offenen MR".

`JiraDoneState` ist deshalb **dreiwertig** (`unknown`/`done`/`notDone`): „keine Auskunft" (freier
Modus, lokales Ticket) darf nicht als „Jira sagt: nicht erledigt" gelesen werden — ohne Jira-Ticket
bleibt das ✅ final. Preis der Regel: setzt man ✅ von Hand, während Jira noch „In Arbeit" steht und
ein MR offen ist, gewinnt die Ableitung und die Karte geht nach Review (der Marker wird auf 🔵
zurückgeschrieben).

Cards carry badges (📄 file · 🌳 worktree · 🔀#iid MR) so it's visible *why* a card is where it is.
Vor dem Titel steht **Jiras eigenes Vorgangstyp-Icon** (`IssueTypeIcon`): geladen aus
`issuetype.iconUrl` (kleines SVG auf dem Jira-Host, `NSImage` rendert es nativ) über denselben
authentifizierten Cache wie die Avatare, pro URL einmal. Bewusst Jiras Bild statt einer eigenen
Zuordnung — der Typname ist lokalisiert („Unteraufgabe") und die Instanz hat eigene Typen (`Test`,
`Test Plan`, `Test Execution`). Das SF-Symbol-Mapping ist nur Fallback für die Ladezeit; unbekannte
Typen bekommen ein neutrales Glyph statt eines geratenen, der Name steht immer im Tooltip.
Rechtsklick auf eine Karte
öffnet ein Kontextmenü mit den Ticket-Workflow-Commands (tippt `/command <TICKET>` in die Claude-
Console des Tickets, bei Bedarf wird es vorher ausgewählt und das Terminal aufgebaut); Review-Karten
bieten zusätzlich `/review-merge !<iid>` mit der MR-Nummer an.

#### PROD-Daten-Bestätigung vor `get-task`/`start-task`

Beide Commands holen den Jira-Inhalt in die KI und gehen deshalb erst nach einer ausdrücklichen
Zusicherung in die Console (`ProdDataConfirmSheet`: Checkbox „keine PROD-Daten“, der Knopf bleibt
bis dahin aus — damit ein reflexhaftes Enter nicht durchgeht). `start-task` ist mit dabei, obwohl es
selbst nichts lädt: fehlt das Task-File, ruft es `get-task` auf und holt das Ticket doch.

Der Gate sitzt in `AppModel.dispatchClaudeCommand` (Liste: `AppModel.prodConfirmCommands`), nicht in
den Menüs — Board-Kontextmenü und Detail-Header laufen beide dort durch, und ein Abbruch tippt
nichts und wählt auch kein Ticket aus. Das Sheet hängt an `ContentView`, weil beide Wege dorthin
führen. Bestätigt wird **jedes Mal**; ein „nicht mehr fragen“ gibt es bewusst nicht.

#### Jira-Nachführung vor `solve-task` (Status „In Arbeit“ + Zuweisung)

`solve-task` ist der Moment, in dem die Arbeit wirklich losgeht — also zieht Kanban das Jira-Ticket
dabei nach: Status auf **„In Arbeit“**, Ticket **dir zugewiesen** (`JiraClient.startWork`, Liste:
`AppModel.startWorkCommands`). Beide Wege ins Terminal laufen durch `AppModel.deliver`, also gilt es
für Board-Kontextmenü und Detail-Header gleichermassen — und ein abgebrochener Bestätigungsdialog
schreibt auch in Jira nichts.

- **Nebenher, nicht davor**: der Command wird sofort getippt; eine hakende Jira-Antwort darf die
  Arbeit nicht aufhalten. Das Ergebnis steht als eine Zeile in der Toolbar — Erfolg räumt sich nach
  10 s selbst weg, eine **Warnung bleibt stehen** (etwas ist nicht passiert, das muss man sehen).
  Wurde etwas geschrieben, folgt ein Refresh: die Zuweisung steht als Avatar auf der Karte.
- **Geschrieben wird nur, was fehlt.** Steht der Status schon so und bist du schon zugewiesen, geht
  keine einzige Schreibanfrage raus — sonst stünde in Jiras Historie bei jedem `solve-task` ein
  Eintrag, der nichts sagt.
- **Die Transition wird gesucht, nicht geraten** (`InProgressTransition.decide`): sie gehört dem
  Workflow, nicht der API. Auf dieser Instanz führt „Start Progress“ (id 4) nach „In Arbeit“, aus
  „Erledigt“ heraus heisst derselbe Weg „Incomplete“ — ein fester Name oder eine feste Id wäre
  Glück. Gesucht wird deshalb erst nach dem **Zielstatus** („In Arbeit“/„In Progress“/…), dann nach
  dem Namen der Transition, zuletzt nach der einzigen Transition in die Kategorie `indeterminate`.
- **Ein fremder Workflow wird in Ruhe gelassen.** Der Support-Workflow der zweiten Instanz
  (`zvmsupport`) kennt kein „In Arbeit“, und „Wartet auf Kunden“ ist bereits `indeterminate` — also
  gilt das Ticket als in Arbeit und es wird nichts geschrieben. Steht ein solches Ticket dagegen
  noch auf `new` und **mehrere** Transitionen führen in die Arbeits-Kategorie, wird nicht geraten:
  die Meldung nennt die erreichbaren Status.
- **Zugewiesen wird über `/issue/<KEY>/assignee`**, nicht über `fields.assignee` — der eigene
  Endpunkt braucht keine Schreibrechte auf dem Edit-Screen. Die eigene `accountId` kommt aus
  `/myself` und wird je Instanz gemerkt.
- **Kein Ticket in Jira** (freier Modus, lokal erfundene Nummer) ist kein Fehler: ein 404 meldet
  „steht nicht in Jira“ und zählt nicht als Warnung.
- **Warum die App und nicht das Skill**: Jira schreiben kann hier nur Kanban — es hält Zugang und
  Host-Guard. Weder Hermes' MCP noch die Projekte haben ein Werkzeug für Transition und Zuweisung,
  und ein Schritt in der Arbeitsanweisung hinge daran, dass die KI ihn abarbeitet. Das Skill sagt
  deshalb nur, dass Kanban es tut — und dass es bei einem Aufruf ausserhalb von Kanban ausbleibt.

### Review-Stand des offenen MR/PR (Optik 1:1 aus der Liste der jeweiligen Forge)

Zwei Anzeigen in der zweiten Kartenzeile, beide nur für **opened** Requests geholt (je 2 Requests pro
offenem MR/PR über denselben Transport wie die Liste, Fehlschlag zählt als 0/nicht-approved —
gemergte bleiben leer, ihr Review ist vorbei):

- **Verdikt** (grünes Pill rechtsbündig **unter der Ticketnummer**, `MRReviewBadge`): `Approved`,
  sobald jemand approved hat (`/merge_requests/:iid/approvals` → `approved`, Fallback nicht-leeres
  `approved_by`; Approver im Tooltip), sonst `Resolved`, wenn **alle** Review-Threads erledigt sind.
  **Approved sticht Resolved** — es steht immer nur eins auf der Karte (`MRReviewState`). Ohne
  Threads gibt es kein `Resolved`, sonst trüge jede frische Karte das grüne Badge.
- **Offene Threads** (graues Pill neben dem 🔀-Badge, `OpenCommentsBadge`): GitLabs
  `‹erledigt› of ‹gesamt›`, solange etwas offen ist — löst das frühere rote Zähl-Badge ab.

Gezählt wird über `/discussions` (`GitLabClient.threadCounts`: ein Thread ist offen, sobald eine
seiner *resolvable* Notes offen ist; System-Notes zählen nie). Bewusst **nicht** über
`blocking_discussions_resolved` aus der MR-Liste: das Feld meldet auf dieser Instanz `true` auch bei
vier offenen Threads (es beschreibt nur, was den Merge blockiert). Farben = die Tokens der
jeweiligen Plattform (`ForgeColors`: GitLab green-100/700 bzw. gray-100/700, GitHub Primer
success-fg/muted bzw. neutral-fg/muted — beide dunkel gespiegelt).

**Bei GitHub sind dieselben zwei Zahlen anders zu holen** (siehe „Zwei Forges"): die Zustimmung aus
`/pulls/{n}/reviews` (je Person der letzte meinungsstarke Zustand), die Thread-Zähler über eine
kleine GraphQL-Abfrage, weil GitHubs REST `isResolved` nicht kennt. Schlägt die fehl, sind es
**0/0 und kein Badge** — fail-open, statt eine Karte in die falsche Spalte zu schieben.

**Draft-MRs** sind in GitLab `state == "opened"`, aber nicht review-reif — sie schieben die Karte
**nicht** nach Review (weder direkt noch über `shouldAutoSetReview`). `GitLabClient` erkennt den Draft
am `draft`-Flag, dem Legacy-`work_in_progress` oder einem `Draft:`/`WIP:`-Titelpräfix; GitHub führt
ein echtes `draft`-Feld und braucht die Titel-Erkennung nicht. Die Karte bleibt in ihrer
Arbeitsspalte und trägt statt 🔀 ein **🚧-Badge** (orange) mit der Nummer in der Schreibweise ihrer
Forge („MR !42" / „PR #42"), damit sichtbar ist, warum sie trotz Request nicht in Review steht.

**Unteraufgaben** (`issuetype.subtask`, sprachunabhängig) erscheinen **nicht** als eigene Karten — die
Story trägt die Arbeit. `AppModel.refresh` filtert sie aus der Sprint-Liste; `--selftest` meldet, wie
viele ausgeblendet wurden. (Damit ist die Epic-Vererbung auf Sub-Tasks auf dem Board gegenstandslos —
Stories tragen ihr Epic ohnehin selbst; `EpicResolution` bleibt für den Selftest erhalten.)

## Zeitmessung (⏱ Claude-Zeit pro Prompt + Antwort, kumuliert)

Genauso derived: die Zeit wird **nicht** getrackt, sondern aus Claude Codes eigenem Transcript
(`~/.claude/projects/<cwd-slug>/<session>.jsonl`) gelesen — rückwirkend für alle Sessions, ohne Hook
und ohne eigenen State.

- **Ein Turn** = ein Prompt + alles, was Claude darauf tut. Alle Einträge eines Turns tragen dieselbe
  `promptId` (auch die Tool-Results); Claudes Assistant-Einträge tragen keine → sie verlängern den
  offenen Turn. Eine neue `promptId` öffnet den nächsten Turn.
- **Dauer** = Claudes eigene Messung (`system/turn_duration` → `durationMs`), wo vorhanden (~81 % der
  Turns). Sonst Summe der Lücken zwischen den Einträgen des Turns, jede Lücke gekappt auf
  `ClaudeTurnAccumulator.idleGapCap` (10 min) — ohne Kappung landet Wartezeit auf den *User*
  (Permission-Prompt, Rückfrage) in der Messung; ein einzelner verwaister Turn kam so auf 30 h.
- Auch Claudes eigene Zahl ist **nicht** immer idle-frei: ein über Nacht am Permission-Prompt
  stehender Turn kam als 11,2 h zurück, bei 47 min Aktivität im Transcript. Sie darf die beobachtete
  Aktivität deshalb um höchstens eine weitere Kappungslücke übersteigen (1 von 774 gemeldeten Turns
  betroffen). Preis: eine echte 40-min-Stille (ein Build) zählt 20 min.
- Geschätzte **und** gekappte Turns sind im UI mit „≈" markiert (`ClaudeTurn.isExact`).
- **Kumuliert** pro Ticket (Karten-Badge ⏱), pro Session (Chip im Detail-Header, Klick → Turn-Liste
  mit Gesamt/⌀/längster Turn/„inkl. Wartezeit") und pro Sprint (Toolbar).
- **Live**: läuft ein Turn, tickt der Zähler grün. Ob ein Turn *läuft* (statt abgebrochen zu sein)
  sagt das Transcript nicht — ein abgebrochener Turn bleibt dort für immer offen (kein
  `turn_duration`). Die Regel steht als reine Logik in **`LiveTurn`** (`AppModel.runningTurnStart`
  liefert nur das Pane-Urteil dazu) und wiegt zwei Aussenzeichen gegen eine Schranke:
  - **Lebt die Konsole?** frisches mtime (`freshWindow`, 2 min — der Anfang eines Turns vor dem
    ersten Pane-Scan) **oder** die tmux-Pane-Analyse (`PaneAttention.isWorking`).
  - **Ist der offene Turn gemeint?** Sein letzter Eintrag darf höchstens `staleAfter` (2 ×
    `idleGapCap` = 20 min) alt sein. Die Schranke ist aus der Abrechnung abgeleitet, nicht geraten:
    `ClaudeTurn.seconds` lässt Claudes Dauer die beobachtete Aktivität um höchstens eine
    Kappungslücke übersteigen, ein Live-Tick darüber hinaus zählte also, was die endgültige Zahl
    nachher verweigert. Gemessen an 1145 abgeschlossenen Turns, deren längste Stille Claude selbst
    als Arbeit zählt, sind 8 (0,7 %) länger als 15 min still — ein echter Build bleibt live. Preis:
    ein stundenlang stiller Werkzeugaufruf hört nach 20 min auf zu ticken, die Summe bleibt richtig
    (Claudes eigene Dauer ersetzt die Schätzung, sobald der Turn endet).

  Beide Hälften stammen aus **einem** Fehlerbild (CORETEST-4237, 2026-09-07: 87 h auf einem
  unbeantworteten Prompt vom 2026-09-03):
  - `PaneAttention.isWorking` zählte ein blosses **„tokens"** als Arbeitsnachweis — gedacht als
    Reserve für „… · N tokens · esc to interrupt", also für eine Zeile, die den Hinweis ohnehin
    trägt. Eine eigene Statuszeile (`cc-statusline`: „ΣTokens: 917k") schreibt das Wort dauerhaft
    hin, und damit galt **jede** Konsole für immer als arbeitend. Weil `showsQuestion` bei
    „arbeitend" sofort aussteigt, wurde gleichzeitig keine Rückfrage mehr erkannt und jeder
    Hook-Marker als „wieder beschäftigt" gelöscht — die Attention war vollständig tot.
  - Die Alters-Schranke fehlte, also buchte ein Lebenszeichen über *irgendeinen* Turn den **offenen**
    weiter. Auch mit ehrlicher Pane passiert das: das Zeichen erscheint, sobald ein neuer Prompt
    läuft, und bis der im Transcript steht, ist der offene Turn noch der alte. Ebenso beim
    mtime-Weg — `claude --resume` schreibt das Transcript neu, ohne den offenen Turn
    weiterzubringen (an dem Ticket gemessen: mtime 2026-09-05 08:28, letzter Eintrag 2026-09-03
    21:41).
- Transcripts werden **inkrementell** getailt (`TranscriptTail`): der erste Blick parst die Datei
  (bis zu ~15 MB), jeder weitere nur das Angehängte. `swift run Kanban --selftest` gibt die Zeiten
  pro Ticket samt Parse-Dauer aus.

### Jira-Zeit buchen (Unterpunkt „Gebuchte Zeit")

Die ⏱-Zeit lässt sich am Tagesende als Jira-Worklog buchen — direkt über die Jira-REST-API
(`POST /rest/api/3/issue/<KEY>/worklog`, dieselbe Basic-Auth wie beim Lesen).

- **Auf den Arbeitstag, nicht auf heute** (`WorklogBooking.dailyBookings`): gebucht wird **je
  Kalendertag ein eigener Worklog**, `started` ist der **erste Turn dieses Tages**. Vorher stand dort
  `Date()` — eine vergessene Woche landete komplett am Tag des Nachbuchens, und Jiras Tages- und
  Wochenauswertung zeigte Arbeit, die dort nie stattfand. Die Tageszuordnung kommt aus den Turns
  selbst (`ClaudeTurn.start`, lokaler Kalendertag), also aus derselben abgeleiteten Quelle wie die
  Zeit. Ein Turn über Mitternacht zählt ganz auf seinen **Starttag** — aufteilen liesse sich nur
  schätzen, und geschrieben wurde der Prompt dort.
- **Immer auf 15 min aufgerundet** (`WorklogBooking`), jetzt **je Tag**: jeder Tag ist eine eigene
  Buchung und kann nicht kleiner als ein Schritt sein. Preis: fünf Tage mit je 3 min ergeben 5 × 15
  min statt einmal 15 min. Der Aufschlag ist sichtbar — das ⏱-Popover listet jeden Tag mit dem
  gemessenen Wert daneben, und geschrieben wird erst auf Knopfdruck.
- **Keine Doppelbuchung**: `WorklogLedger` (lokal, `~/Library/Application Support/Kanban/worklog.json`,
  wie [[stale-release-build]]-nahe UI-State) merkt pro Ticket `byDay` (`yyyy-MM-dd` → Sekunden) plus
  die Gesamtsumme. Gebucht wird je Tag nur `aufrunden15(gemessenAmTag) − gebuchtAmTag` — ein
  15-min-Vielfaches ≥ 0, das **0** wird, sobald an dem Tag nichts Neues dazukam. Eintrag ins Ledger
  erst **nach** erfolgreichem Jira-Write, je Tag einzeln; ein fehlgeschlagener Tag hält die anderen
  nicht auf. Das Ledger ist die App-eigene Buchungshistorie; von Hand in Jira gebuchte Worklogs sieht
  es nicht.
- **Umstieg vom alten Ledger** (39.75 h in 22 Tickets, alle ohne Tageszuordnung): die Alt-Summe wird
  als Guthaben **von alt nach neu** angerechnet, und Tage **vor** dem letzten Buchungstag
  (`lastBookedAt`) gelten als abgerechnet. Ohne das erste würde die nächste Buchung die ganze
  Historie erneut buchen; ohne das zweite würde die feinere Rundung alte Tage wieder aufmachen (zwei
  Tage à 20 min waren früher einmal 45 min, wären jetzt 2 × 30 min). Offen bleiben kann der letzte
  Buchungstag selbst — dort kann nach der Buchung weitergearbeitet worden sein, das ist einmalig
  höchstens ein 15-min-Schritt je Ticket.
- **UI**: Unterpunkt im ⏱-Popover (`Gebucht` / `Offen zum Buchen` + **Tagesliste** + Buchen-Button je
  Ticket), Sammel-Buchung über den Toolbar-Button „X buchen" → `BookingSheet` (Übersicht mit Zeitraum
  je Ticket + Bestätigung), ✓ am Karten-Badge wenn vollständig gebucht.

## Der Teiler im Detail-Bereich: beim Öffnen die Hälfte (KANBAN-009)

Rechts stehen Task-File-Tabs oben und die Terminal-Zone unten, getrennt von einem `VSplitView`. Beim
Öffnen bekommt das **Terminal die Hälfte** (`DetailView.terminalAnteil = 0.5`) — dort wird
gearbeitet, das Task-File wird gelesen. Vorher fiel dem Arbeiten ein knappes Drittel zu und der
Teiler wurde jedes Mal von Hand nachgezogen.

- **`idealHeight` ist der falsche Hebel** — er tut schlicht nichts. Gegen echtes AppKit gemessen
  (macOS 15): 220, 380, 600 und gar kein `idealHeight` ergeben dieselbe Position. `VSplitView`
  verteilt **proportional zu den Mindesthöhen**; 240 oben zu 120 unten sind 2 : 1, also genau das
  Drittel. (240/240 ergäbe 50 %, 240/480 zwei Drittel — die Regel ist nachgemessen, nicht geraten.)
- **Die Mindesthöhen anzugleichen wäre der kürzere Weg und der falsche.** Die Hälfte wäre dann ein
  Nebenprodukt zweier zufällig gleicher Zahlen — wer später die Mindesthöhe des Task-Files anhebt,
  verschiebt den Teiler, ohne es zu merken. Und eine Mindesthöhe sagt etwas über die *kleinste*
  erlaubte Grösse, nicht über die Startposition: das Terminal liesse sich nie wieder unter 240 pt
  ziehen.
- **Also die Position einmal direkt setzen** (`SplitFractionSetter` in `Detail/DetailSplit.swift`):
  eine leere Hilfsansicht im unteren Bereich sucht über die Superview-Kette den `NSSplitView`, den
  SwiftUI darunter führt, und ruft `setPosition`. Bewusst **kein** `autosaveName` — die Position soll
  das Öffnen gerade *nicht* überleben.
- **Genau einmal**, nicht bei jeder Aktualisierung: jede Teiler-Verschiebung ändert die Grösse der
  Terminal-Pane, und das ist ein SIGWINCH — tmux baut Claudes ganze TUI neu auf (derselbe Grund, aus
  dem die Prompt-Timeline über dem Terminal liegt statt daneben). Danach hat die Hand das letzte
  Wort.
- **Der Auslöser ist das Projekt, und er ergibt sich von selbst** — es braucht kein `.id(projektKey)`
  (das würde nur zusätzlich die Terminal-Ansichten abreissen). Den Split gibt es nur mit gewähltem
  Ticket; ein Projektwechsel läuft über `clearDetail()`, setzt `selectedTicketKey` auf nil und lässt
  den Platzhalter stehen, die nächste Karte baut den Split frisch auf. Ein Fenster je Projekt
  (KANBAN-006) fängt ohnehin frisch an. Ein Wechsel **von Ticket zu Ticket** bleibt dagegen im selben
  Zweig: der Split lebt weiter, die gezogene Position bleibt, Claudes TUI bleibt stehen.
- Gemessen mit der ausgelieferten Hilfsansicht: Vorgabefenster (1280 × 748 Inhalt) 374/374, kleinstes
  Fenster (540 pt hoch, 488 Inhalt) 244/244 — beide über ihren Mindesthöhen. Ein von Hand auf 180 pt
  gezogener Teiler überlebt zehn Ticketwechsel und den Weg 748 → 1100 → 748 unverändert (der Split
  hält den **Anteil**, nicht die Pixel). Wäre die Hälfte einmal kleiner als eine Mindesthöhe, klemmt
  `NSSplitView` selbst.

## Prompt-Timeline (Bubble-Button rechts in der Terminal-Tableiste)

Slide-in **über** dem Terminal (Overlay, kein Split — ein Split würde die Pane resizen und Claudes
TUI komplett neu umbrechen lassen). Zeigt jeden Prompt der Session als Chat-Bubble mit Volltext,
Zeitpunkt und Turn-Dauer; Klick springt im Terminal an die Stelle, an der er abgeschickt wurde.

- **Quelle der Bubbles** ist das Transcript (`ClaudeTurn.promptFull`, ungekürzt, Zeilenumbrüche
  erhalten; Slash-Commands bleiben zu `/name args` kollabiert). Turns ohne Prompt-Text fallen aus der
  Liste (die ⏱-Liste behält sie, sie tragen Zeit) — das sind Claude Codes eigene Einschübe und ein
  **Abbruch ohne neuen Prompt**.
- **Der öffnende Eintrag eines Turns ist nicht immer der Prompt** — deshalb zieht
  `ClaudeTurnAccumulator` den ersten *getippten* Text des Turns nach, solange noch keiner steht
  (`isTypedPrompt`). Drei Formen, alle gemessen, alle mit demselben Ergebnis „der Prompt fehlt":
  - **Esc, dann weitertippen**: Claude Code legt `[Request interrupted by user]` unter die `promptId`
    des Prompts, der *danach* kommt, und die Datei führt den Marker zuerst. In der Bubble stand dann
    der Abbruch statt dessen, was man getippt hat.
  - **Abgelehnter Werkzeugaufruf**: der Turn öffnet mit einem `tool_result` ganz ohne Text — die
    Bubble fehlte komplett, weil die Liste textlose Turns filtert.
  - **Lokaler Command** (`/exit`): die Datei führt das `<local-command-caveat>`-Geschwätz vor dem
    `<command-name>`-Eintrag, der eine Millisekunde früher entstand.

  Umfang an 80 Transcripts (974 Turns): **38** Turns zeigten den Abbruch-Marker statt des Prompts,
  **33** hatten gar keinen Text — 7 %, und immer im Muster „Esc, dann neu tippen", also gerade an dem
  Prompt, den man eben abgeschickt hat. Aus dem *nächsten* Turn kann dabei nichts einwandern: in
  demselben Korpus hat **kein einziger** getippter Eintrag keine `promptId`, ein getippter Text
  gehört also immer zu dem Turn, in dem er gelesen wird. Claude Codes eigene Einschübe
  (`<task-notification>`, `<local-command-stdout>`, …) sind ausgenommen — sie kommen als Tag, nie als
  Prosa.
- **Sprungziel** ist dagegen die tmux-Scrollback: `PromptLocator` richtet die `❯`-Zeilen der Pane als
  *Suffix* auf die Prompt-Liste aus (rückwärts, mit Suchfenster `lookback`) — keine Textsuche, weil
  Prompts sich wiederholen und `search-backward` immer auf dem jüngsten Treffer landen würde. Eine
  Pane-Zeile ohne eigenen Turn (Prompt, der während einer laufenden Antwort eingereiht wurde) wird
  übersprungen statt die älteren Zuordnungen mitzureissen.
- **Gescrollt** wird die *View*, nicht der Cursor: `copy-mode` + `scroll-up -N k` mit
  `k = totalLines − paneHeight − zielZeile + scrollTopMargin`. `goto-line` ist unbrauchbar (zählt von
  unten und parkt den Cursor in der letzten Zeile). Weil eine copy-mode-Ansicht ihren Abstand zum
  **unteren** Rand hält, schiebt jede Zeile, die die Konsole zwischen Messung und Scroll schreibt,
  das Ziel mit — `PromptScrollback.correct` misst deshalb bis zu zweimal nach.
- **Nicht mehr im Scrollback?** Dann klappt die Bubble den Turn aus dem Transcript auf
  (`ClaudeTurnReader`: Claudes Prosa als Markdown + Tool-Aufrufe aggregiert; Tool-*Ergebnisse* nur
  benannt — ein gemessener Turn trug 621 KB davon). Der Klick versucht **immer zuerst** den Sprung;
  die Bubble-Färbung ist nur eine Anzeige, keine Entscheidung — eine veraltete Reichweiten-Messung
  (Panel offen, bevor das Terminal attached war) darf keinen Sprung verhindern.
- **Scrollback-Grösse**: Kanban legt neue Sessions mit `history-limit` 20 000 an (tmux-Default 2000 —
  eine einzige Claude-Antwort füllte davon ~900 Zeilen, die Konsole hielt also ihre letzten zwei
  Prompts). Ein Pane übernimmt den Wert **bei Erzeugung**; `set-option -t` auf eine laufende Session
  wirkt nicht, deshalb hebt `withHistoryLimit` die globale Option nur um das `new-session` herum an
  und setzt sie danach zurück. Bestehende Sessions bleiben bei 2000.
- Der App-weite Scroll-Monitor (`TerminalCache.handleScroll`) entscheidet per **`hitTest`**, ob ein
  Rad-Event ins tmux-copy-mode gehört — eine Bounds-Prüfung würde jedes Event innerhalb des
  Terminal-Rechtecks abfangen und das darüberliegende Panel unscrollbar machen.

## Wortweises Bearbeiten in der Konsole (⌥← / ⌥→ / ⌥⌫)

⌥← ein Wort zurück, ⌥→ ein Wort vorwärts, ⌥⌫ das Wort davor löschen — in der Claude-Console wie im
Terminal-Tab. Vorher tat ⌥⌫ nichts und ⌥← bewegte den Cursor um **ein Zeichen**: `optionAsMetaKey`
ist bewusst **aus** (⌥ soll auf dem Schweizer Layout `@ # { }` schreiben), und mit ausgeschaltetem
Meta gibt SwiftTerm die Kombinationen an AppKit weiter, wo der Terminal-View kein `moveWordLeft:`
o. ä. behandelt.

- **Gesendet wird die emacs-Schreibweise** (`ESC b` / `ESC f` / `ESC DEL`, wie iTerm2s „natural text
  editing"), nicht die CSI-Form — gegen die echten Konsolen gemessen, nicht aus der Doku geschlossen:
  Claude Code (`\x1Bb` → meta+left → `prevWord`; `ESC DEL` → `deleteWordBefore`), Codex und die zsh
  verstehen alle drei. `ESC[1;3D` verstehen dagegen nur Claude und Codex — in der zsh landet daraus
  ein wörtliches „D" auf der Zeile, und die Konsole ist manchmal eine Shell.
- **Abgefangen wird app-seitig** (`TerminalCache.handleKeyDown` → `KanbanTerminalView.handleWordEditingKey`),
  weil SwiftTerms `keyDown` `public` und nicht `open` ist — derselbe Grund wie beim Scrollen. Nur
  ausserhalb von copy-mode: dort gilt weiter, dass ⌥/⌘/⌃-Kombinationen durchgereicht werden (⌘C muss
  kopieren können).
- Bei eingeschaltetem `terminal.optionAsMeta` macht SwiftTerm dasselbe schon selbst, deshalb greift
  die Behandlung nur, solange der Schalter aus ist.

## Lösung (Button im Detail-Header, links neben „Commit")

Schreibt das Jira-Feld **„Lösung"** — das Feld, in dem der Reviewer liest, was gemacht wurde.

- **Feld-Auflösung über den Edit-Screen** (`/rest/api/3/issue/<KEY>/editmeta`, Name „Lösung" /
  „Loesung" / „Solution"), wie Hermes' `set-jira-solution`. Auf dieser Instanz ist es
  `customfield_10052` (Typ `textarea`) — hartkodiert wäre das Glück, denn die Id gehört der Instanz,
  und der Screen sagt ausserdem, ob das Feld auf dem Vorgangstyp überhaupt beschreibbar ist. Die Id
  wird **je Projekt gemerkt**, damit das Durchklicken von Karten nicht jedes Mal `editmeta` kostet.
- **Alarm**: steht das Ticket in **Review** *oder* **Done** und ist das Feld **leer**, wird der Knopf
  rot umrandet und heisst „Lösung fehlt" (`AppModel.solutionMissingColumn` — nil heisst kein Alarm,
  sonst die Spalte, damit Knopf und Sheet sie benennen). Done ist mit dabei, weil der gemergte MR das
  Versäumnis nicht heilt: das Task-File wird **nicht mitcommittet**, nach dem Aufräumen des Worktrees
  ist das Jira-Feld die einzige Spur — ein leeres Feld in Done ist ein dauerhafter Verlust, kein
  erledigter Punkt.
- **Vorbelegt** wird der Editor mit dem Jira-Inhalt; ist der leer, mit `## JIRA Lösungsfeld` →
  `### Für Kunde` aus dem Task-File (`SolutionDraft`, gelesen aus der **rohen** Datei — in
  `displaySections` wären Bilder schon base64-eingebettet). Bewusst nur dieser Unterabschnitt: die
  Prosa mit Entscheidungen, AK-Abweichungen und Annahmen gehört in Jira, die Test-Ingenieur-Teile
  (Klickpfade, Geänderte-Dateien-Listen) sind Rauschen in dem Feld, das der Reviewer liest. Hat das
  Task-File kein `### Für Kunde` (ältere, handgeschriebene), gilt weiter der ganze Abschnitt — das
  Sheet sagt, welche der beiden Quellen es war, und bittet im Fallback ums Kürzen.
- **Die Skills schreiben genau dorthin, was sonst verloren geht** (`solve-task` Schritt 7,
  Rule `task.md`, nachgezogen von `update-task`): `### Für Kunde` trägt einen **Pflicht**-Block
  „Entscheidungen, Abweichungen, Annahmen" — jede Entscheidung mit Begründung, jede Abweichung von
  den AK samt betroffenem Kriterium, jede Annahme, alles bewusst Ausgelassene. Gibt es nichts davon,
  steht dort genau eine Zeile („keine Abweichungen, keine offenen Annahmen") — weglassen ist nicht
  erlaubt, sonst ist ein leerer Block nicht von einem vergessenen zu unterscheiden.
- **Geschrieben wird Markdown als ADF** (`MarkdownToADF`, der Schreibweg zu `ADFToMarkdown`):
  Überschriften, Listen (auch verschachtelt), Codeblöcke mit Sprache, Zitate, Linien und
  `**fett**`/`*kursiv*`/`` `code` ``/`~~weg~~`/`[Text](url)`. Tabellen bleiben bewusst Text — Jiras
  Tabellen-ADF verlangt Zell- und Layout-Attribute, die aus Markdown nicht ableitbar sind. Getestet
  wird gegen den Rückweg (`ADFToMarkdown`, der zeichengleich gegen Hermes' JS-Original steht); die
  Knotenmenge wurde zusätzlich gegen Hermes' eigenen Konverter im `dryRun` verglichen.
- Leerer Text schreibt `null`, leert das Feld also wirklich — ein leeres `doc` zählte Jira als Inhalt.
- Nach dem Schreiben wird **zurückgelesen**: angezeigt wird, was in Jira steht, nicht was gesendet wurde.

### WYSIWYG statt Sternchen (`RichTextEditor` + `HTMLToMarkdown`)

Bearbeitet wird **formatiert**: Überschriften, Listen und Marks stehen so da, wie sie in Jira
ankommen. Der Kreis ist **Markdown → HTML → tippen → Markdown → ADF**; die erste und die letzte
Station gab es schon (`MarkdownHTML` via cmark-gfm, `MarkdownToADF`), neu ist der Rückweg
`HTMLToMarkdown`.

- **Markdown bleibt die gespeicherte Wahrheit.** Der Umschalter „Formatiert | Markdown" zeigt und
  bearbeitet sie direkt — damit nichts hinter dem Editor verschwindet und ein Konverter-Fehler von
  Hand korrigierbar bleibt. Beim Wechsel *aus* dem Editor und **vor jedem Schreiben** wird der Stand
  ausdrücklich abgeholt (`currentMarkdown()`), statt auf den 400-ms-Entprelltimer zu hoffen: der
  übliche Ablauf ist „letztes Wort tippen, dann Speichern".
- **Zielvokabular ist nicht „alles, was HTML kann", sondern genau das, was `MarkdownToADF`
  übersetzt** — Überschriften, Absätze, Listen (verschachtelt, geordnet), Codeblöcke, Zitate, Linien,
  `**fett**`/`*kursiv*`/`` `code` ``/`~~weg~~`/`[Text](url)`. Unbekanntes wird **entpackt statt
  weggeworfen**: ein fremdes Inline-Element gibt seinen Text her, ein fremder Block seine Kinder.
  `script`/`style` sind die Ausnahme — deren Inhalt ist kein Text.
- **Geparst wird mit Foundations eigenem HTML-Tidy** (`XMLDocument(options: .documentTidyHTML)`),
  kein Fremdcode. Er verträgt, was ein `contenteditable` produziert: nackte `<div>`s, `<br>`, `<b>`
  statt `<strong>`, `style`-Attribute, `&nbsp;`, offene Tags.
- **Kein Backslash-Escaping**, mit Absicht: `MarkdownToADF` kennt kein `\*`, ein escapetes Zeichen
  stünde als Backslash in Jira. Preis: ein Absatz, der mit „- " anfängt, wird beim nächsten Umlauf
  als Liste gelesen — sichtbar und über die Markdown-Ansicht korrigierbar, ein Backslash im
  Jira-Feld wäre es nicht.
- **`execCommand` ist die Editor-Engine.** Formal veraltet, in WebKit vollständig da, und der einzige
  Weg, Auswahl, Undo-Stapel und Listen-Verschachtelung ohne eigene Engine richtig zu behandeln.
  Tab/⇧Tab rücken ein und aus.

Vier Dinge hat erst das Messen gezeigt, alle vier lautlos:

1. **Tidy wirft ohne Kodierungs-Angabe alles Nicht-ASCII weg** — aus „Gebäude — Rücksprache" wurde
   „Gebude  Rcksprache", mitten im Text, der nach Jira geht. Ein HTML5-`<meta charset>` **reicht
   nicht** (dann kommt Mojibake, „GrÃ¶ÃŸe"); nur `<meta http-equiv="Content-Type" …>` greift. Deshalb
   wird jedes Fragment auf seinen Body reduziert und mit dieser Angabe neu eingepackt. Gefangen hat
   das der Rundreise-Test (`Markdown → HTML → Markdown` muss **gleich** bleiben), nicht das Auge.
2. **Das Editor-Skript stand in `document.body.innerHTML`** — als `<script>` im Dokument wäre der
   ganze JavaScript-Quelltext als Text im Jira-Feld gelandet. Es hängt jetzt als `WKUserScript` am
   Editor, der DOM bleibt reiner Inhalt.
3. **`execCommand('indent')` ausserhalb einer Liste** baut in WebKit ein randloses `<blockquote>` —
   aus „einrücken" wäre in Jira ein **Zitat** geworden. Jetzt wirkt Einrücken nur in Listen, und der
   Konverter entpackt ein randloses `<blockquote>` statt „> " davorzuschreiben (so kommt auch
   eingefügter Browser-Inhalt daher).
4. **WebKit hängt verschachtelte Listen als Geschwister** des Listenpunkts an
   (`<ul><li>eins</li><ul><li>zwei</li></ul></ul>`); Tidy räumt das in ein *künstliches leeres* `<li>`
   um. Naiv gelesen ergibt das einen leeren Aufzählungspunkt — oder, bei einem anderen Parser, den
   Verlust der ganzen Ebene.

Geprüft wird zweistufig: der Konverter in `HTMLToMarkdownTests` (Blöcke, Marks, Kaputt-HTML,
Rundreise, plus **echte WebView-Ausgabe** als Testdaten), das JavaScript in einem kopflosen
Probelauf gegen eine echte WKWebView (Toolbar-Befehle abfeuern, `innerHTML` auslesen) — genau der
Lauf, der die Punkte 2–4 gefunden hat.

## Commit (Button im Detail-Header, links neben der ⏱-Zeit)

- Sichtbar, sobald es etwas zu committen gibt: **Task-File oder Worktree** vorhanden — bewusst *nicht*
  an den Status-Marker gebunden (nachbessern passiert in Review genauso wie bei 🟢 Abgeschlossen).
  Auf reinen Jira-Tickets bleibt er aus, weil `commitDirectory` dort auf das Haupt-Repo zurückfiele
  und `git add -A` fremde Änderungen mitnähme.
- **Message-Vorschlag** kommt aus dem Task-File: `## Lösung` → `**Commit-Message:** \`TICKET | …\``
  (`CommitMessage`; `## Lösungsplan` wird bewusst nicht verwechselt). Fehlt sie, wird `TICKET | ` als
  Stub vorgeschlagen.
- **Amend** braucht keine Message (`--amend --no-edit`), der Push dazu ist immer
  **`--force-with-lease`** — nie ein blankes `--force`, damit ein fremder Push nicht überschrieben wird.
- Diff-Ansicht im GitLab-Stil (`DiffParser`): Dateiliste links, Diff rechts, Additions hellgrün /
  Deletions hellrot, zwei Nummern-Spalten. Untracked Files haben keine HEAD-Seite und werden deshalb
  über `git diff --no-index /dev/null <file>` gezeigt.
- **Die Dateiliste ist `git status --porcelain -z --untracked-files=all`**, beide Flags aus Schaden
  gelernt: ohne `-uall` klappt git einen *neuen Ordner* zu einem einzigen `dir/`-Eintrag zusammen (die
  Liste untertreibt, was `add -A` committet, und der Diff darauf scheitert an `Could not access`);
  ohne `-z` quotet und oktal-escaped git nicht-ASCII-Pfade (`"L\303\266sung.md"`), und der so
  verstümmelte Pfad findet beim Diff keine Datei. In `-z` steht die Quelle eines Renames als eigener
  Record hinter dem Ziel — `parseStatus` überspringt ihn, gezeigt wird der neue Pfad.

### Reiter „Diff": was der Branch geändert hat

Nach dem Commit ist die Dateiliste leer — das Arbeitsverzeichnis ist ja sauber, und damit war der
Dialog genau dann blind, wenn man nachsehen will, was man abgeliefert hat. Der dritte Reiter neben
„Neuer Commit" und „Amend" zeigt deshalb den **Branch** statt des Arbeitsverzeichnisses: dieselbe
Fläche, dieselbe Dateiliste, derselbe Diff-Renderer, nur ein anderer Vergleichspunkt
(`AppModel.CommitDiffSource`) — kein zweiter Dialog.

- **Ab dem Merge-Base, nicht ab der Spitze der Basis** (`base...HEAD`). Sonst stünden die Commits,
  die `develop` seit der Abzweigung bekommen hat, als *Rücknahmen* im eigenen Diff. Das ist der
  Vergleich, den auch der Merge Request zeigt, und derselbe Dreipunkt, aus dem `BranchParent` sein
  `ahead` zieht. Aufgelöst wird der Merge-Base **einmal** und als Commit weitergereicht: so vergleicht
  jede Datei gegen denselben Stand, auch wenn sich die Basis nebenher bewegt.
- **Die Basis ist abgeleitet, nicht konfiguriert** (`BranchParentScanner`, derselbe Weg wie der
  ←-Chip im Worktree-Panel) — deshalb steht sie im Dialog, samt der Zahl eigener Commits. Ohne
  Basis (Haupt-Repo auf `develop` selbst, fremde Historie) sagt der Reiter das, statt eine leere
  Liste zu zeigen: „keine Abzweig-Basis" und „nichts geändert" sind zwei verschiedene Auskünfte.
- **`-M` ist Pflicht.** Ohne Umbenennungs-Erkennung steht eine verschobene Datei als Löschung *und*
  Neuanlage in der Liste, und ihr Diff behauptet, der ganze Inhalt sei neu geschrieben — bei der
  Command→Skill-Verschiebung wären das 10 Dateien doppelt gewesen.
- **`--name-status -z` trennt die Felder mit NUL, nicht mit Tab** (anders als ohne `-z`), und ein
  `R095`/`C070` trägt **zwei** Pfade dahinter. Wer den zweiten nicht verbraucht, liest ihn als
  nächsten Status und die ganze restliche Liste verrutscht. Am echten git abgelesen, nicht der Doku
  entnommen; die fünf Fälle stehen in `DiffParserTests`.
- **Kein Push-Schalter, kein Commit-Knopf** — ein grüner „Commit" neben einem reinen Diff wäre eine
  Einladung zum Vertippen. Der **Editor** dagegen ist da (siehe unten): man liest, was der Branch
  geändert hat, sieht dabei etwas und bessert es an Ort und Stelle nach.
- **Ungespeichertes wird genannt, nicht gezeigt.** Was noch im Arbeitsverzeichnis liegt, gehört
  nicht in den Branch-Diff — aber es schweigend wegzulassen wäre dieselbe Lücke, die diesen Reiter
  nötig macht. Eine Zeile sagt, wie viele es sind und wo sie stehen.
- Gemessen an `core-3403`: 2 Commits, **56 Dateien** gegen `origin/develop` — bei sauberem
  Arbeitsverzeichnis vorher eine leere Liste. `bfezvm-4595` (0 eigene Commits) meldet richtig
  „unterscheidet sich nicht von seiner Basis".

#### Bearbeiten im Reiter „Diff"

Der Editor stand hier zunächst nicht zur Verfügung, und der Grund war echt: er zeigte den heutigen
Dateiinhalt neben einer Einfärbung, die gegen **HEAD** gerechnet war — schon die erste eingefügte
Zeile schob alles Grün um eine Zeile weiter. Das ist jetzt behoben, statt den Editor auszusperren.

- **Die Editor-Einfärbung gilt immer der Datei auf der Platte**
  (`GitCommitController.diffWorktree`: `git diff -M <base> -- <datei>`, ohne `HEAD`). Im
  Arbeitsverzeichnis war das schon so; im Branch-Diff kommt sie jetzt aus demselben Vergleich. Damit
  steht im Editor „alles, was seit der Abzweigung neu ist" — **einschliesslich dessen, was man eben
  getippt hat**. Der Diff **daneben** bleibt der Dreipunkt-Vergleich der Commits: die beiden
  beantworten verschiedene Fragen, und die Kopfzeile sagt es.
- **Gespeichertes ist Arbeitsstand, kein Commit.** `base...HEAD` ändert sich dadurch nicht — die
  Datei taucht in der Statusliste auf und damit unter „Neuer Commit"/„Amend". Genau dieser Weg ist
  der Zweck; eine Zeile unter dem Editor sagt ihn, weil er im Branch-Reiter nicht selbstverständlich
  ist.
- **Nach dem Speichern zieht die Einfärbung nach.** `loadCommitState` hält im Branch-Reiter bewusst
  die Finger von der Auswahl (die gehört dort dem Branch-Diff), also lädt `saveCommitFile` die
  gewählte Datei dort ausdrücklich neu — sonst stünde das Grün auf dem Stand vor dem Speichern.
- **Eine vom Branch gelöschte Datei bleibt aussen vor** (`commitFileExists`). Sie steht im
  Branch-Diff, liegt aber nicht auf der Platte; der Editor wäre leer, und ein Speichern legte sie
  wieder an.
- Gegen echtes git geprüft (`BranchEditorDiffTests`): bei sauberem Arbeitsverzeichnis sind beide
  Vergleiche **gleich**; nach einer Bearbeitung zeigt nur der Arbeitsstand-Vergleich die neue Zeile,
  und die Markierung sitzt auf ihr; das Gespeicherte steht in `git status`; die gelöschte Datei ist
  im Diff, aber nicht auf der Platte.

### Einzelne Dateien abwählen (Haken je Zeile)

Jede Zeile der Dateiliste trägt ein Kästchen; abgehakt heisst „geht in den Commit". Die Abwahl gilt
für **Commit und Amend** gleichermassen, und die abgewählte Änderung bleibt im Arbeitsverzeichnis
stehen — sie wird nicht verworfen, nur nicht mitgenommen.

- **`git add -A`, danach `git restore --staged` für die Abgewählten** — nicht
  `git add -A -- <nur die Gewählten>`. So bleibt das Verhalten für alles Nicht-Abgewählte wortgleich
  wie bisher, auch für eine Datei, die zwischen dem Laden der Liste und dem Klick dazukommt.
  Abgewählt wird, was der Mensch abgewählt hat, nicht „alles ausser dem, was ich vorhin gesehen habe".
- **`restore --staged`, nicht `rm --cached`**: es stellt den Index-Stand **aus HEAD** wieder her.
  Damit bleibt eine abgewählte **Löschung** in HEAD stehen und eine abgewählte neue Datei fällt auf
  „unversioniert" zurück — beides gegen echtes git geprüft, beides in `CommitExclusionTests`.
- **Jeder Pfad einzeln.** git bricht die ganze Liste ab, sobald ihm ein Pfad unbekannt ist
  („pathspec did not match", Exit 1) — ein zwischenzeitlich verschwundener Pfad risse sonst die
  gültigen mit. Sein Fehlschlag wird geschluckt: „liegt nicht im Index" ist ja der gewünschte
  Zustand.
- **Alles abgewählt** → git verweigert („no changes added to commit"), und das ist richtig: ein
  leerer Commit sagt nichts. `canSubmit` sperrt den Knopf deshalb vorher. Beim **Amend** bleibt er
  frei — dort wird HEAD ohnehin neu geschrieben und gepusht, auch ohne neue Änderung.
- **Kein Haken im Reiter „Diff"** — dort wird gelesen, und ein Kästchen ohne Wirkung wäre schlimmer
  als keins.
- Die Kopfzeile nennt die Abwahl, sobald es eine gibt („4 von 56 — 2 abgewählt"), und eine
  abgewählte Zeile steht blass da; sonst übersieht man sie und wundert sich über einen halben Commit.

#### `.claude/project.json` per Vorgabe abwählen (`commit.excludeClaudeProjectFile`)

Schalter in den Einstellungen unter **Allgemein**, Vorgabe **an**. Die Datei erzeugt Kanban bei jedem
Projektwechsel selbst (`ClaudeProjectFile`) — sie gehört niemandem sonst und in keinen Commit.

In den meisten Repos fällt das gar nicht auf: `even`, `bfezvm` und `zba` haben `.claude/` in ihrer
`.gitignore`, die Datei taucht nie in `git status` auf. **`core` nicht** — dort steht sie als
`?? .claude/project.json` in der Liste und ginge mit jedem `git add -A` mit. Genau dieser eine Fall
ist der Grund für den Schalter.

- Er setzt den Haken nur **vorab** ab, beim Öffnen des Fensters (`AppModel.prepareCommitDialog`).
  Dazuwählen bleibt jederzeit möglich, und die Wahl hält: das Nachladen der Liste (nach einem
  Speichern im Editor, nach dem Commit) wählt **nicht** erneut ab — sonst überschriebe der Schalter
  bei jedem Neuladen die Entscheidung des Menschen.
- `commit` ist ein **Kanban-eigener** Abschnitt der Config, kein Hermes-Modul: er steht nicht in
  `ProjectProjection.moduleNames` und wandert nie in `~/.hermes/config.json`.

### Welche Session-Id gehört zum Ticket?

Ein Ticket kann **zwei** Ids tragen und sie widersprechen sich: Wird es geöffnet, bevor ein Task-File
existiert, erzeugt die App eine Id in `sessions.json` und startet Claude damit; legt diese Console
dann das Task-File an, stand im Marker früher eine **neu erfundene** Id. Das Task-File gewann — die
App zeigte auf eine Konversation, die es nie gab (24 von 35 Tickets divergent, davon 17 ohne
Transcript auf der Task-File-Id: keine ⏱-Zeit, keine Hook-Attention, und eine neue Console hätte
statt Resume leer gestartet).

`ClaudeSessionResolution.resolve` entscheidet über das Transcript auf der Platte: eine Id, unter der
Claude wirklich lief, hat eins. Bei zwei Transcripts gewinnt das Task-File (dort gehört die Id hin —
`sessions.json` enthält historisch auch Ids fremder Tickets). `setupTerminal` schreibt die aufgelöste
Id in **beide** Speicher zurück, damit sie nicht wieder auseinanderlaufen; das Board selbst löst nur
lesend auf.

## Epics (Farbcode auf der Karte, ausgeschrieben im Header)

- Quelle ist das Agile-Feld `epic` der Sprint-Issues — eine Extra-Anfrage braucht es nicht.
- **Farbe**: nur `epic.color.key` (`color_1`…`color_14`, identisch zum `ghx-label-N` des Epics)
  unterscheidet Epics. Das neuere `issueColor` liefert auf dieser Jira-Instanz für **jedes** Epic
  `purple` — darauf gebaut wäre das ganze Board einfarbig. `EpicColors.paletteNames` ist Jiras eigene
  Zuordnung `color_N` → Farbname (aus `greenhopper/1.0/xboard/plan/backlog/epics.json`, das pro Epic
  `epicColor` **und** `color` liefert); der Name geht über `EpicColors.palette` auf einen Hex.
- **Unteraufgaben** tragen kein `epic`, nur `parent`. `EpicResolution.inheritFromParents` holt das
  Epic von der Story — lokal aus derselben Sprint-Liste, ohne weiteren Request (im EVEN-Sprint
  betrifft das 15 von 34 Tickets). Story nicht im Sprint → kein Epic statt geraten.
- UI: `EpicColorStripe` (Farbbalken links auf der Karte) + `EpicPill` (Epic ausgeschrieben im
  Detail-Header, direkt nach dem Task-File/Feature-Branch). `--selftest` listet die Epic-Verteilung.

## Mehrere Board-Fenster (+-Knopf links vom Aktualisieren)

Kanban hatte genau **ein** Board-Fenster; wer das Projekt wechselte, tauschte dessen Inhalt aus.
Heute deklariert `KanbanApp` eine `WindowGroup(for: String.self)` über den Projekt-Key, und der
+-Knopf in der Kopfzeile macht ein weiteres Fenster auf — für das erste Projekt, das noch keines hat
(steht jedes schon irgendwo, ist der Knopf aus). Zwei Projekte laufen damit nebeneinander statt
nacheinander: in einem läuft ein Claude-Lauf, im anderen wird gelesen.

Das **Projekt-Menü schaltet weiterhin im eigenen Fenster um** — die Auswahl allein macht kein Fenster
auf. Ein Projekt, das auch woanders offen steht, trägt im Menü ein Fenstersymbol statt des Häkchens;
wer es dort haben will, wechselt dorthin. Dasselbe Projekt darf also zweimal dastehen.

Die halbe Arbeit war schon getan, und zwar die aufwendige: **`AppModel` ist kein Singleton**
(`ContentView` hält es als `@State`), jedes Fenster bringt seinen Zustand also selbst mit — Board,
Auswahl, Sprint, Worktrees, Console. Zu klären waren die Stellen, an denen sonst „das letzte Fenster
gewinnt" herauskäme; sie laufen in **`ProjectWindows`** zusammen (Zuordnung Fenster ↔ Model ↔
Projekt, `@Observable`, damit die Leiste mitbekommt, was offen ist):

| Prozessweit | Zuordnung |
|---|---|
| `TerminalCache.onTerminalClick` | meldet das **Fenster** mit; der Klick tickt das Model, dessen Fenster er traf |
| `AttentionNotifier` | der Klick auf die Benachrichtigung sucht das Fenster, dessen Board das Ticket zeigt, holt es nach vorn und wählt dort; kennt keines es, entscheidet der Präfix (`TicketRouting`) — und ein Fenster geht dafür auf |
| `WatchdogModel` | **eine** Instanz für den Prozess (`.shared`). Je Fenster eine hiesse N-mal `claude -p`, und das kostet Geld. `uebernehmen` ist deshalb ab dem zweiten Fenster wirkungslos; alle Fenster zeigen denselben Gesamtstand, weil der Watchdog ohnehin projektübergreifend scannt |
| `CommitWindow` | **je Fenster** eines (Schlüssel ist das `AppModel`, wie bei `MarkdownDocumentWindow` der Dateipfad) — zwei Projekte dürfen gleichzeitig committen, und der Titel trägt den Projekt-Key |
| Einstellungen speichern | lädt **alle** Fenster neu (`ProjectWindows.configNeuLaden`), nicht nur das, in dem gespeichert wurde |

### Der Fenstertitel bleibt leer — das Fenster-Menü trägt die Namen trotzdem (KANBAN-010)

Über dem Board soll kein Text stehen: welches Projekt ein Fenster zeigt, sagt das Projekt-Menü der
Kopfzeile, und ein Titel darüber wäre eine zweite Antwort auf dieselbe Frage. Im **Fenster-Menü** von
macOS dagegen standen die Fenster damit gar nicht — macOS listet ein Fenster über seinen Titel, und
der war leer. Mit einem Fenster je Projekt (KANBAN-006) nahm das dem Ganzen die halbe Wirkung: wer
vier Boards offen hat, findet das gesuchte nur durch Probieren.

Beides ist nicht über den Titel zu haben. Drei Wege wurden an echtem AppKit gemessen (SwiftUI-Fenster
900 pt breit, Knöpfe in `.navigation` und `.primaryAction`; mit sichtbarem Titel endet der rechteste
bei **894**), alle drei scheitern:

| Weg | Was passiert |
|---|---|
| `toolbar(removing: .title)` | nimmt das Titel-**Element** samt Zwischenraum — rechtester Knopf bei 207, die Knöpfe kleben links |
| `titleVisibility = .hidden` | blendet nur den Text aus, lässt das Element aber auf Breite 0 schrumpfen — **derselbe** Fehler, 207 |
| Titel setzen, Anzeige unterdrücken | geht nicht gegeneinander: SwiftUI schreibt `title` **und** `titleVisibility` bei jeder Aktualisierung zurück (gemessen: eine Sekunde nach dem eigenen Schreiben stand wieder „Kanban" mitten in der Leiste) |

Also bleibt `.navigationTitle("")` — der leere Titel hält den Zwischenraum —, und den Eintrag meldet
`ProjectWindows.menueNachfuehren` bei jedem An- und Abmelden über
**`NSApp.addWindowsItem(_:title:filename:)`** an, benannt nach `WindowTitles` (Projekt-Key in
Grossbuchstaben; ein zweites Fenster desselben Projekts bekommt `EVEN (2)`, denn das Projekt-Menü
schaltet **im** Fenster um und zwei gleiche Einträge wären nicht auseinanderzuhalten).

Der Weg dorthin ging über zwei Sackgassen, beide gemessen:

- **SwiftUIs `.commands`.** `CommandGroup(after: .windowList)` erzeugte **keinen einzigen** Eintrag:
  die Menüs entstehen beim Start, da ist noch kein Fenster angemeldet, und auf die Änderung der
  `@Observable`-Liste hin baut SwiftUI sie nicht neu (zehn Sekunden nach dem Start, mit zwei
  angemeldeten Fenstern, war das Menü unverändert leer).
- **`NSMenuItem` von Hand in `NSApp.windowsMenu` hängen.** Steht nach drei Sekunden da und ist nach
  sechs **weg**: AppKit baut das Fenster-Menü irgendwann selbst neu — aus vier Einträgen werden
  zwanzig („Minimize All", „Zoom All", „Fill", die Tab-Befehle) — und wirft dabei alles heraus, was
  nicht aus seiner eigenen Buchführung stammt. Genau das war die erste ausgelieferte Fassung, und
  genau deshalb blieb das Menü leer.

`addWindowsItem` trägt das Fenster **in diese Buchführung** ein, und der Eintrag überlebt den
Neuaufbau. Weitere Einzelheiten:

- **`changeWindowsItem` hinterher**, weil `addWindowsItem` ein schon eingetragenes Fenster nicht
  umbenennt — und umbenannt wird oft: geht `EVEN (2)` zu, muss aus dem übrigen wieder `EVEN` werden.
  Beim Schliessen trägt `removeWindowsItem` aus, **bevor** der Eintrag aus `eintraege` fällt.
- **Kein ⌘1…⌘9.** Ein von Hand gesetztes `keyEquivalent` steht an AppKits Eintrag, bis dasselbe
  Neubauen zuschlägt — danach ist der Eintrag noch da und der Kurzbefehl weg (gemessen bei t=9 s).
  Ein Kurzbefehl, der nach einer Weile verschwindet, ist schlechter als keiner.
- **Fenster ohne Projekt stehen mit drin** („Kanban"): der Setup-Schirm und ein Fenster, dessen
  Projekt aus der Config verschwand, müssen gerade dann erreichbar sein, wenn daneben drei Boards
  stehen.

**Eine lebende Terminal-Ansicht, zwei Fenster.** `TerminalCache` hält je tmux-Session genau eine
`KanbanTerminalView`, und eine `NSView` hat nur einen Superview. Dasselbe Ticket kann in zwei
Fenstern stehen — bei Projekten, die sich ein Repo teilen (`support`/`even`,
`tp1`/`zvmsupport`/`bfezvm`): deren `!<iid>`-Karten kommen aus demselben MR-Bestand und heissen in
beiden `kanban-!130`. Das zweite Fenster zeigt deshalb einen Hinweis mit Knopf „Hierher holen" statt
einer leeren Fläche; die Session läuft weiter, sichtbar ist sie nur an einer Stelle.

## Gemerkte Auswahl (offene Fenster + Sprint überleben den Neustart)

`SelectionStore` (UserDefaults, **nicht** die Hermes-Config — das ist lokaler UI-State) hält die
offenen Projekte, das zuletzt benutzte und je Projekt den gewählten Sprint. `SprintSelection.resolve`
stellt ihn wieder her, solange er auf dem Board liegt — auch einen geschlossenen, denn die Wahl war
Absicht und der Picker markiert ihn „✓"; kennt das Board die Id nicht mehr, gewinnt der aktive
Sprint. `Kanban --select <TICKET>` sticht die Erinnerung.

Der Start macht die Fenster wieder auf, die beim letzten Mal offen waren (`openProjectKeys`, Regel in
`OpenProjects.wiederherstellen`, gedeckelt bei 6):

- Der **alte Einzelwert** `selectedProjectKey` gilt weiter — ohne Liste wird er als einelementige
  gelesen; niemand verliert seine Auswahl, weil das Format gewachsen ist.
- Er bleibt daneben als **zuletzt benutzt** stehen (gepflegt von dem Fenster, das gerade nach vorn
  kommt): die Rückfallebene bei leerer Liste, und das Fenster, das nach dem Wiederherstellen vorn
  steht.
- Ein Projekt, das **nicht mehr in der Config** steht, öffnet kein Fenster; war es beim Entfernen
  offen, sagt das Fenster das und bietet Einstellungen bzw. Schliessen an, statt ungefragt ein
  anderes Board zu zeigen.
- **Alle Fenster zu heisst: Kanban beendet sich** (`applicationShouldTerminateAfterLastWindowClosed`
  bleibt `true`) — und die Liste ist leer. Der nächste Start kommt dann mit einem Fenster auf dem
  zuletzt benutzten Projekt hoch; geschlossen ist geschlossen. Beim ⌘Q dagegen bleibt die Liste
  stehen (`applicationWillTerminate` friert sie ein, bevor die Fenster abgebaut werden).

## Skill-Sets: eigene Ordner, pro Projekt verlinkt (KANBAN-004)

Die Workflow-Skills und Rules liegen in **Sets** — benannten Ordnern, von denen ein Projekt genau
einen sieht. Ein Set ist nichts weiter als *ein Ordner mit `skills/` und/oder `rules/`*, und genau
dieser Ordner ist das Ziel der Symlinks in den Projekten.

**Die Skills gehören nicht ins Kanban-Repo.** Sie sind die Arbeit des Benutzers, nicht Teil der App:
Kanban liefert keine aus, versioniert keine und kopiert keine. Vorher lagen sie flach in Application
Support und wurden in einem GUI-Editor mit selbstgebauter Versionierung gepflegt — ein zweites,
schwächeres Git neben dem richtigen; und die eine Unterscheidung, die wirklich gebraucht wird,
fehlte: nicht jedes Projekt will dieselben Skills.

- **Woher die Sets kommen**, zwei Wege nebeneinander:
  - **Sammelordner** (`claude.setsPath`, Vorgabe `~/Library/Application Support/Kanban/claude`):
    jeder Unterordner mit `skills/` oder `rules/` ist ein Set. Wer seine Sets ohnehin nebeneinander
    liegen hat, muss nichts eintragen.
  - **Einzeln registriert** (`claude.sets.<name>.path`): Name plus Ordner, und der Ordner darf
    überall liegen — im Repo eines Projekts, in einem eigenen Git-Repo, irgendwo. Angelegt wird das
    im Skill-Set-Fenster über „Set anlegen…"; bei Namensgleichheit sticht die Registrierung den
    Sammelordner, denn sie ist die ausdrückliche Angabe.
  `set.json` im Ordner gibt Anzeigename und eine Zeile Beschreibung; ohne sie heisst das Set wie
  sein Ordner. Ein Unterordner ohne `skills/`/`rules/` oder mit einem Namen, der kein kebab-case ist,
  ist **kein** Set — sonst ginge jeder dahingelegte Backup-Ordner als eins durch.
- **Keine Kopie, kein Sync, kein App-Bundle.** Die Symlinks zeigen auf den gepflegten Ordner selbst:
  eine Änderung an einem `SKILL.md` wirkt sofort in jedem verlinkten Projekt — ohne `build-app.sh`,
  ohne Neustart, ohne Knopfdruck im Übersichtsfenster. Ein Skill-Symlink zeigt auf das
  **Verzeichnis**, also reist auch eine frisch dazugelegte Beiwerk-Datei ohne Zutun mit.
- **Verlinkt wird ins Projekt, nicht ins Home** — das ist der Kern. Ein Agent-Home kann nicht zwei
  Sets gleichzeitig tragen, und Kanban fährt regelmässig mehrere tmux-Sitzungen parallel. Skills
  gehen nach `<repo>/.claude/skills/<name>` bzw. `<repo>/.codex/skills/<name>` (je nach `agent`),
  Rules nach `<repo>/.claude/rules/<name>.md` — **immer** `.claude/`, auch bei `agent: codex`: die
  Skills verweisen im Text auf `.claude/rules/…`, und dieser Pfad muss unter beiden Agents aufgehen.
  Dieselbe Überlegung wie bei `.claude/project.json`.
- **Das Standard-Set hängt zusätzlich in `~/.claude` und `~/.codex`** — damit eine Console ausserhalb
  eines Projekts nicht leer dasteht. ⚠️ Das kollidiert mit der Präzedenz (siehe unten): bei
  **Namensgleichheit** sticht die User-Ebene die Projektkopie, ein Projekt auf einem anderen Set
  sähe also weiter die Skills des Standard-Sets. Verifiziert ist diese Präzedenz für Commands
  (2026-08-07); für Skills steht die Gegenprobe aus. Wer mit zwei Sets arbeitet, prüft das zuerst
  und lässt die Home-Verlinkung nötigenfalls weg (`ClaudeAssetFactory.linkDefaultSetIntoHomes`).
- **Aufgeräumt wird beim Verlinken**: Symlinks eines vorher verlinkten Sets verschwinden, ebenso die
  im Ordner des *anderen* Agents (ein Projekt hat genau einen). Erkannt werden sie daran, dass sie
  auf etwas zeigen, das **uns** gehört: ein bekannter Set-Ordner, der Sammelordner, ein früher
  gewählter (`formerRoots` — wer den Ordner wechselt, soll die alten Links umgehängt bekommen statt
  sie als fremd stehen zu lassen) oder der alte flache Bestand. Den Wechsel bemerkt die Übersicht
  **selbst**, indem sie den zuletzt gesehenen Sammelordner in `SelectionStore` mitführt und beim
  Laden vergleicht: so zieht auch ein Pfad nach, der in den Einstellungen, im Roh-JSON-Editor oder
  von Hand in der Datei geändert wurde. Vorher hing das an einem eigenen „Ordner wählen…"-Knopf in
  der Übersicht — und damit an dem einen Weg, den ausgerechnet niemand mehr nimmt, seit der Pfad als
  Feld in den Einstellungen steht (siehe unten). **Fremdes wird nie angefasst**: eine
  echte Datei oder ein Symlink irgendwo anders hin wird gemeldet, nicht überschrieben
  (`ClaudeSymlinkState.foreign`) — und ein belegter Zielort blockiert den Rest des Sets nicht.
- **Pfade werden in beiden Schreibweisen verglichen** (`ClaudeAssetStore.schreibweisen`): macOS legt
  das Ziel eines Symlinks **aufgelöst** ab (`/private/var/…`), während der konfigurierte Ordner
  unaufgelöst dasteht (`/var/…`). Solange beide existieren, gleicht `standardizedFileURL` das aus —
  bei einem Ordner, den es nicht mehr gibt, also genau nach einem Umzug, nicht mehr.
- **Wer welches Set benutzt**, wird **am Set** entschieden: das Skill-Set-Fenster zeigt je Set alle
  Projekte als Haken. Darunter steht weiterhin `modules.jira.projects.<key>.skillSet` (leer =
  Standard-Set), und das Standard-Set global in `claude.defaultSkillSet`. Fehlt es, gilt das einzige
  vorhandene Set — gibt es mehrere und ist keins bestimmt, das erste, und die Übersicht sagt
  „Standard (nicht gesetzt)". Ein Projekt, dessen Set es nicht (mehr) gibt, fällt aufs Standard-Set
  zurück, **mit Hinweis** statt stillschweigend (`ClaudeAssetStore.resolve` liefert `missingName`).
- **Das Command-Menü am Ticket zeigt, was das Set anbietet** — alles davon, nicht eine Liste im Code
  (`ClaudeCommandScanner.commands(in:first:)`). Vorn die vier Workflow-Skills in der Reihenfolge,
  die ein Ticket nimmt (`get-` → `start-` → `solve-` → `review-task`), dahinter der Rest
  alphabetisch. Gelesen wird das **Set**, nicht der Scan der Zielorte: was ein Projekt sieht, ist
  sein Set, nicht die Vereinigung aus Projekt-Ebene und Agent-Home.
- **Der Name des aufgelösten Sets steht in `.claude/project.json`** (`skillSet`) — ein Skill soll
  wissen, mit welchem Satz er gerade läuft, und nicht, was jemand einmal in die Config geschrieben
  hat. Geschrieben wird beides an einer Stelle (`AppModel.linkSkillSet`), beim Projektwechsel und
  beim Config-Load für **alle** Projekte.
- **Keine Projektwerte in den Assets**: Platzhalter `<PREFIX>`/`<tasksPath>`/`<docsPath>`/
  `<kbPath>`/`<worktreePrefix>`/`<dockerStack>`/`<stackDomain>` (nur die TLD; Hosts =
  `<ordnername>.<stackDomain>`)/`<jiraBaseUrl>`/`<skillSet>` verweisen auf
  `<repo>/.claude/project.json`, das `ClaudeProjectFile` beim Projektwechsel aus Kanbans Config
  generiert (schreibt nur bei inhaltlicher Änderung). **Drei Schlüssel fehlen bewusst, wenn es sie
  nicht gibt**: `kbPath` ohne konfigurierte Knowledgebase, `stackDomain` ohne Docker-Stack und
  `jiraBaseUrl` ohne konfigurierte Jira-Instanz — ein Skill soll „hier ist sie" von „es gibt keine"
  unterscheiden können, und eine TLD ohne Stack dahinter wäre eine Behauptung. `dockerStack` und
  `usesJira` dagegen stehen **immer** drin (`true`/`false`): daran verzweigen die Skills, und ein
  fehlender Schlüssel würde dort als `true` gelesen.
- **`.claude/` ist nicht überall gitignored** — gemessen am 2026-09-18: in `bfezvm`, `even`,
  `reactbp` und `zba` ja, in `core`, `hermes`, `iwf-local-dev` und `rhyblox` nein. Dort stehen die
  Symlinks des Sets als untracked in `git status`. In fremden Repos ist das eine Entscheidung des
  jeweiligen Teams; lokal geht es ohne Commit über `.git/info/exclude`.
- **Alles ist ein Skill** (`skills/<name>/SKILL.md`) — die einzige Gattung, die Claude Code *und*
  Codex kennen. Die Gattung `commands` ist mit den Sets **weggefallen**: der einmalige
  Command→Skill-Umzug ist erledigt, und ein von Hand angelegter Projekt-Command bleibt als Datei
  liegen — Kanban verwaltet ihn nur nicht mehr. `ClaudeCommandScanner` liest ihn weiterhin, damit er
  im Kontextmenü nicht verschwindet.
- **Präzedenz empirisch verifiziert** (CC 2.1.222, 2026-08-07): bei Namensgleichheit sticht die
  **User-Ebene** die Projektkopie — Gegenteil der verbreiteten Doku-Annahme. `ClaudeCommandScanner`
  liest beide Ebenen, überdeckte Projektkopien stehen in `shadowedProjectURL`.
- `repoDir` ist von `tasksPath` **entkoppelt** (`modules.jira.projects.<key>.repoDir`, optional;
  absolut/`~`/relativ zum Basis-Pfad) — ohne Override gilt weiter das erste `tasksPath`-Segment.

### Die Übersicht (Einstellungen › Skill-Sets)

Sie **zeigt und stellt her**, mehr nicht: je Set Name, Beschreibung, Ordner, Anzahl
Skills/Rules und die Markierung „Standard"; darunter **alle Projekte als Chips**. Ein Klick legt
das Projekt auf dieses Set — und verlinkt es sofort.

- **Chips statt Ankreuzfelder**, weil die Frage nicht „welche Häkchen sind gesetzt" lautet, sondern
  **„welche Projekte gehören zu diesem Set"**: eine Menge, keine Liste von Schaltern. Gesetzte Chips
  sind gefüllt und lesen sich als Aufzählung, die übrigen stehen blass daneben. Dieselbe
  Kapsel-Optik wie die Epic-Chips auf den Karten. Eine fertige SwiftUI-Komponente dafür gibt es
  nicht — `NSTokenField` aus AppKit ist fürs *Eintippen* freier Tokens gedacht, hier ist die Menge
  fest und bekannt. Den Umbruch macht `Fluss`, ein `Layout` (macOS 13+): es misst jeden Chip einzeln
  und bricht um, wenn die Zeile voll ist. Ein `LazyVGrid` mit fester Spaltenbreite gäbe ein Raster,
  in dem zwischen `tp1` und `iwf-local-dev` überall Luft stünde.
- **Eine Sektion, kein eigenes Fenster** (KANBAN-010). Sie hatte einmal beides — ein Fenster
  860 × 640 und einen ✨-Knopf in der Kopfzeile. Seit sie nur noch zeigt und verlinkt (der Editor
  mit Fassungen ist mit den Sets weggefallen), ist das mehr Apparat als Inhalt: ein Knopf, den man
  dauernd sieht und dreimal im Monat braucht. Sie steht jetzt neben „Projekte" — beide gehören
  keinem Modul, sondern liegen quer über die Projekte. Damit erledigt sich zugleich die Frage, ob
  ein schon offenes Fenster nach vorn kommt; `ClaudeWorkflowWindow` und
  `AppModel.claudeWorkflowPresented` gibt es nicht mehr.
- **Sie schreibt sofort, der Speichern-Fuss gehört der Config.** Zwei Sorten Wirkung in einem
  Fenster darf man nicht raten müssen, deshalb steht das als Zeile über der Liste — und wenn oben
  Ungespeichertes liegt, sagt sie zusätzlich, was folgt: der Klick schreibt die Datei, und der
  Fuss meldet danach einen Konflikt („Neu laden" / „Trotzdem speichern", dieselbe mtime-Erkennung
  wie bei einer Änderung von aussen, nur ist die Ursache hier im selben Fenster zu sehen).
- **Keinen „Verlinken"-Knopf mehr.** Ein Projekt, das an einem Set hängt, *ist* verlinkt — sonst
  wäre die Zuordnung eine Behauptung. Hergestellt wird beim Zuordnen, beim App-Start, beim
  Projektwechsel und beim Aufschlagen der Sektion; der Aufruf ist idempotent, steht alles, passiert
  nichts. Damit zieht auch ein von Hand aufgelöster Zielort ohne Knopfdruck nach.
- **Zeilen nur für Projekte, an denen etwas nicht stimmt.** Im Normalfall sagt der Chip schon alles;
  eine zweite Liste, die dieselben Projekte noch einmal aufzählt, wäre Lärm.

Das ⋯-Menü je Set führt in den Finder, lässt einen anderen Ordner wählen und nimmt das Set wieder
aus der Liste — **ohne** den Ordner anzufassen: entfernt wird die Zuordnung, nicht die Arbeit. Im
Fuss steht „Set anlegen…".

**Den Sammelordner wählt man hier nicht**, obwohl die Übersicht ihn anzeigt (und ein Klick ihn im
Finder öffnet): er ist `claude.setsPath` und steht als Feld in derselben Seitenleiste unter
„Allgemein". Zwei Bedienelemente für einen Wert im selben Fenster wären schon deshalb verkehrt, weil
sie verschieden wirken — das Feld auf „Speichern", der Knopf sofort. Die beiden übrigen
Ordner-Dialoge bleiben: der Ordner **eines** Sets (`claude.sets.<name>.path`) und der eines neuen,
und für die gibt es kein Feld.

Drei Fälle stehen als Hinweis an der Zeile, statt still zu wirken:

- **Kein Repo-Ordner** → es gibt keinen Ort zu verlinken; der Knopf ist aus.
- **Zwei Projekte teilen ein Repo und stehen auf verschiedenen Sets** → `<repo>/.claude/` gibt es
  einmal, also gewinnt das zuletzt verlinkte und das andere Projekt sieht stillschweigend fremde
  Skills. Gemeldet wird **nur dieser** Fall: dass `support` in `even` und `tp1`/`zvmsupport` in
  `bfezvm` liegen, ist der Normalfall und stünde sonst dauerhaft als Warnung da, obwohl nichts
  kaputt ist.
- **Das gewählte Set gibt es nicht** → das Standard-Set greift, der gesuchte Name steht daneben.

Weggefallen sind mit dem Umbau: der Markdown-Editor über den Bestand, „Neues Asset", „Einlesen…",
„Auf Auslieferungsstand zurücksetzen", die **Fassungen** (`ClaudeAssetVersions`, zeitgestempelte
Kopien je Datei) und die Symlink-Schalter je Asset. Alles davon löste ein Problem, das eine Datei in
einem Git-Repo nicht hat. Vorhandene `.versions/`-Ordner werden nicht gelöscht, nur nicht mehr
gelesen.

### Zwei Agents: Claude Code oder Codex (je Projekt)

`modules.jira.projects.<key>.agent` = `claude` (Default) oder `codex`; editierbar in den
Einstellungen (Auswahlfeld am Projekt). `AgentKind` ist der **einzige** Ort, der die Unterschiede
kennt — Board, Console und Asset-Auslieferung fragen dort.

| | Claude Code | Codex 0.147 |
|---|---|---|
| Skill-Set des Projekts | `<repo>/.claude/skills/<name>/SKILL.md` | `<repo>/.codex/skills/<name>/SKILL.md` |
| Rules des Sets | `<repo>/.claude/rules/<name>.md` | **ebenfalls** `<repo>/.claude/rules/…` |
| Standard-Set (ohne Projekt) | `~/.claude/skills/<name>` | `~/.codex/skills/<name>` |
| Projekt-Ebene | `<repo>/.claude/{skills,commands}` | `<repo>/.codex/skills` |
| Aufruf | `/name args` | `$name args` (der `@`-Picker fügt genau das ein) |
| Start | `claude --session-id`/`--resume` | `codex`, danach `/rename` |
| Wiederaufnahme | `claude --resume <id>` | `codex resume <id> -c tui.resume_cwd=current` |
| ⏱-Zeit + Timeline | Transcript | Rollout (siehe unten) |
| Attention | Hook + Pane-Auswertung | **nur** Pane-Auswertung |

Das Format ist bei beiden dasselbe — verifiziert am 2026-08-19/20, nicht aus der Doku geschlossen:
Claude Code substituiert `$ARGUMENTS` in einem Skill (Probe-Skill mit Argumenten aufgerufen, `$1`
zählt dabei ab dem **zweiten** Token — deshalb benutzen die Assets nur `$ARGUMENTS`); Codex listet
ein Skill aus `~/.codex/skills` im `@`-Picker und schreibt `$name` in den Composer, und seine
gebündelte `skill-creator`-Anleitung nennt dieselben Frontmatter-Keys (`argument-hint`,
`disable-model-invocation`, `user-invocable`, `allowed-tools`) und dieselbe `$ARGUMENTS`-Syntax.
Sein `/import` trägt intern das Label `migrated-command-skills` — OpenAI konvertiert Claude-Commands
selbst zu Skills.

**Codex hat kein `/name`**: Custom Prompts (`~/.codex/prompts`) sind deprecated und seit 0.117 aus
dem Slash-Menü verschwunden — gegen 0.147 gegengeprüft, weder `/start` noch `/prompts:` zeigt einen
Eintrag. Deshalb `$`.

**Keine Session-Id für Codex — dafür ein Name.** `--session-id` gibt es dort nicht, die Id erfindet
Codex selbst. Kanban dreht die Richtung (`CodexSessions`): eine frisch erzeugte Console bekommt über
Codex' eigenen TUI-Command `/rename kanban-<TICKET>` einen deterministischen Namen, und
`~/.codex/session_index.jsonl` — die Datei, in der Codex **nur benannte** Threads führt — liefert
danach die Id. Enter drücken wir hier ausnahmsweise: `/rename` ist ein TUI-Command, kein Turn, kostet
also nichts. Bewusst **nicht** „jüngster Rollout mit passendem cwd": alle Tickets eines Projekts
laufen im selben Repo, das wäre nicht unterscheidbar.

**Wiederaufnahme** ist symmetrisch zu Claude: `codex resume <id>` nur, wenn es einen Rollout gibt —
ohne bricht es sichtbar ab („no rollout found for thread id …"), genau die Fehlermeldung, wegen der
es auf der Claude-Seite kein `||`-Fallback gibt. Dazu `-c tui.resume_cwd=current`, sonst fragt Codex
„Session- oder aktuelles Verzeichnis?" zurück, sobald die aufgezeichnete cwd abweicht (verifiziert:
mit dem Schalter kommt die Rückfrage nicht).

### ⏱-Zeit und Timeline aus Codex' Rollouts

Dieselbe Kette wie bei Claude, nur mit anderer Quelle: `ClaudeTimingStore` wählt Datei **und** Parser
je Agent, beide liefern `ClaudeTurn`s — Karten-Badge, Session-Chip, Turn-Liste, Worklog-Buchung und
Prompt-Timeline hängen unverändert daran.

- **Quelle**: `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl`, eine Datei je Session-Id
  (nachgeprüft: 45 Rollouts, 45 Ids, keine Id mit zwei Dateien) — `codex resume` schreibt in dieselbe.
  Gesucht wird von neu nach alt über die Datums-Ordner. Noch kein Turn = noch keine Datei, dann gibt
  es eben keine Zeit.
- **Dauer ist exakt**: `task_complete` trägt `duration_ms` samt `started_at`/`completed_at`
  (Unix-Sekunden). Damit braucht Codex **keine** Lücken-Heuristik und keine 10-min-Kappung wie
  Claude — es gibt kein „≈". `turn_aborted` zählt mit, die Arbeit hat ja stattgefunden.
- **Nicht** die Zeilen-Zeitstempel: in einem geforkten/fortgesetzten Rollout tragen alle
  nachgeschriebenen Zeilen dieselbe Schreibzeit — daraus berechnet waren 23 von 23 Turns 0 s. Die
  Felder im Payload sind auch dort echt.
- **Prompt** ist die `message`-Zeile mit `role: user` innerhalb des Paars; Codex' eigener
  `<environment_context>`-Block fällt raus (10 solche gegen 193 echte Prompts in den geprüften
  Dateien). `CodexTurnReader` liest für die Bubble Prosa (`role: assistant`) plus die Werkzeuge
  aggregiert (`custom_tool_call`/`function_call`), Ergebnisse nur gezählt — wie beim Claude-Leser.
- **Sprungziel**: `PromptLocator.markers` kennt jetzt `›` — so rendert Codex einen abgeschickten
  Prompt (an einer fortgesetzten Session abgelesen; seine Antwort steht als `•`).
- **Attention** läuft für Codex allein über `PaneAttention`: „… to interrupt" heisst arbeitend,
  „Allow Codex to run …" / „Codex wants to edit …" / ein Menü mit `›`-Cursor heisst wartend (Wortlaut
  aus dem Binary). Kanbans Hook-Weg schreibt in `~/.claude/settings.json`; Codex' eigene Hooks
  (`~/.codex/hooks.json`) verlangen einen Trust-Schritt und bleiben ein eigener Schritt.

## Task-Files und Doku liegen im Kanban-Ordner, nicht im Repo

Beides wurde nie committet — `docs/**` bzw. `docs/*` ist in den Repos gitignored, die
Confluence-Exporte in `bfezvm-docs` waren nicht einmal das. Sie lagen also im Arbeitsverzeichnis
herum und wären mit dem nächsten Aufräumen weg. Seit dem Umzug (HERMES-034 Schritt 5, 2026-08-28)
gilt:

```
~/Library/Application Support/Kanban/
├── tasks/<ordner>/    643 Task-Files — ein Ordner je *Quellordner*, nicht je Projekt:
│                      `tp1` und `zvmsupport` teilen sich `bfezvm-support`, wie sie sich vorher
│                      `bfezvm/docs/support` geteilt haben (die Ticket-Nummer trennt sie).
└── docs/<projekt>/    exportierte Confluence-Seiten (`<PAGE_ID>-<slug>.md` + `<PAGE_ID>/`)
```

- **`tasksPath` ist jetzt absolut**, und deshalb ist `repoDir` bei **jedem** Projekt gesetzt: die
  Ableitung „erstes Segment des Tasks-Pfads" trägt nicht mehr. Sie bleibt als Fallback für Configs,
  die noch relativ zeigen.
- **`docsPath`** (neu in `.claude/project.json`, Platzhalter `<docsPath>` wie `<tasksPath>`) kommt
  aus `modules.confluence.projects.<key>.path`; ohne Eintrag gilt
  `~/Library/Application Support/Kanban/docs/<key>`. Die Confluence-Sektion ist **kein Modul, das
  Kanban betreibt** — Kanban hält dort nur Space und Ablageort. Geholt wird die Seite von Hermes'
  `generate-confluence-page` (Skill `get-doc`), und genau dieser Eintrag sagt ihm, wohin.
- **Die Hermes-Falle** (`HermesPath` in `HermesSync`): Hermes rechnet jeden Ordner als
  `path.join(basePath, wert)` (`lib/config.js`, `getTasksDir`). Ein **absoluter** Wert landet dort
  unter dem Basis-Pfad — aus `/Users/ich/Library/…` wird `~/code/Users/ich/Library/…`, ohne
  Fehlermeldung, und `generate-claude-task` legte Task-Files in einem Phantom-Ordner ab. Der
  Rückweg schreibt absolute Pfade deshalb **relativ zu Hermes' basePath**
  (`../Library/Application Support/Kanban/tasks/even`); Kanbans eigene Config behält den absoluten
  Pfad. Relative Werte bleiben unangetastet — sie sind entweder schon Hermes' Schreibweise oder
  gegen denselben Basis-Pfad gemeint, und Umrechnen hiesse raten.
- **Aufgelöste Pfade werden normalisiert** (`standardizingPath`), sonst stünde die `../`-Form als
  `/Users/…/code/../Library/…` im UI und in `.claude/project.json`.
- Ein Space **ohne** Jira-Projekt (`tech`) bleibt ein reiner Confluence-Eintrag: er zeigt auf den
  Doku-Ordner des Projekts, zu dem er inhaltlich gehört (hier `docs/bfezvm`), und taucht auf dem
  Board nicht auf. Die Registry kann das seit HERMES-043 (`ProjectRecord` ohne Pflichtfelder).
- Zwei Projekte, die sich ein Repo teilen (`support` in `even`), teilen sich auch dessen
  `.claude/project.json` — es gewinnt das zuletzt gewählte. Das war schon vorher so, fällt mit
  `docsPath` aber mehr auf.

## Projekt-Typen: zwei Schalter, zwei Hälften

Kanban ist aus der IWF-Werkzeugkette gewachsen, und dort ist jedes Projekt eine Web-Applikation mit
Jira-Board und eigenem Docker-Stack. Seit Kanban auch eigene Projekte führt (die App selbst, Hermes,
Skript-Repos), stimmt das nicht mehr — und zwar in zwei unabhängigen Richtungen. Deshalb zwei
Schalter, **beide mit Vorgabe „an"**, beide nur geschrieben, wenn sie **aus** sind (ein Schlüssel,
der nur den Normalfall wiederholt, stünde in jedem Projekt herum):

| Config                                      | Swift             | Aus heisst                                            |
|---------------------------------------------|-------------------|-------------------------------------------------------|
| `modules.jira.projects.<key>.useJira`       | `usesJira`        | kein Board, keine Sprints, keine Worklogs — nur freier Modus |
| `modules.docker.projects.<key>.stack`       | `usesDockerStack` | keine Stack-Oberfläche, kein `iwf` — Worktrees bleiben |

- **Der Stack-Schalter hat eine eigene Sektion**, obwohl er dieselbe *Form* hat wie `useJira`. Er
  stand zuerst im Jira-Eintrag daneben — gleiche Form, gleiche Reichweite, ein Feld gespart. Das war
  eine Verwechslung von Form und Sache: mit Jira hat der lokale Docker-Stack nichts zu tun, und in
  den Einstellungen unter „Jira" sucht ihn niemand. Jetzt: Sektion **Docker** (`shippingbox`),
  zwischen Knowledgebase und Darstellung.
- **`modules.docker` ist Kanban-eigen** und steht deshalb in `ProjectProjection.kanbanOnlySections`,
  nicht in `moduleNames`: `apply(_:key:to:)` läuft über `HermesSync` auch gegen
  `~/.hermes/config.json`, und dort hätte der Schlüssel nichts zu suchen. Geschrieben wird er über
  `applyKanbanOnly(_:key:to:)`, das nur `SettingsModel.createProject` gegen Kanbans eigenes Dokument
  aufruft. Über `kanbanOnlySections` räumt `remove` den Eintrag beim Löschen eines Projekts mit ab.
  Nicht zu verwechseln mit `modules.dockerhub` — das ist die Registry, in der das Image liegt.

- **Was bei `dockerStack: false` verschwindet:** die Reiter „Maintree" und „Worktree" samt
  Snapshots (`TerminalTabsView`), der Zähler „N Stacks stoppen" in der Leiste, und jeder Docker-/
  `iwf`-Aufruf. Der eine Riegel dafür ist `AppModel.hasStack`; er sitzt unter anderem in
  `directory(for:)`, durch das **jeder** Stack-Weg kommt (Lebenszyklus, Status, Snapshots,
  Reparaturen, URL). **Ausgeblendet, nicht ausgegraut** — ein Schalter, der nie angeht, ist keine
  Auskunft, sondern sieht aus wie „gerade nicht verfügbar".
- **Was bleibt:** Worktrees, Branches, Task-Files, Commits, Merge Requests, Konsolen. Abgeschaltet
  wird nur die Docker-Hälfte, nicht das halbe Projekt.
- **Der Schalter wirkt bis in die Skills**, denn `ClaudeProjectFile` schreibt ihn nach
  `<repo>/.claude/project.json`. Die Assets sind **ein** kanonischer Bestand ohne Projekt-Varianten
  (`ClaudeAssetFactory`/`ClaudeAssetStore`), die Verzweigung steht deshalb **im Text** der Skills:
  `create-worktree` ruft ohne Stack `git worktree add` statt `iwf worktree create` (und lehnt
  `--start` ab), `destroy-worktree` `git worktree remove` statt `iwf worktree destroy --force`,
  `solve-task` fährt Tests direkt im Worktree statt über `docker exec`. `rules/worktree.md` ist
  dafür zweigeteilt: „Git-Worktree (gilt immer)" und „Per-Worktree-Stack (nur `dockerStack: true`)".
- **Der Basis-Branch muss ohne `iwf` ermittelt werden.** `iwf worktree create` zweigt immer von
  `origin/develop` ab; ohne `iwf` gibt es diese Konvention nicht, und `develop` existiert in vielen
  Repos gar nicht (im Kanban-Repo selbst z.B.). Die Kette steht in `rules/worktree.md`:
  `origin/HEAD` → `origin/develop` → `origin/main` → `develop` → `main` → `HEAD`, und der Skill sagt
  in der Zusammenfassung, welchen er genommen hat.
- **Vorbelegt, nicht entschieden:** `ProjectSuggestion` sieht beim Anlegen nach, ob im abgeleiteten
  Repo-Ordner eine `.iwf.yml` liegt — die ist die Stack-Definition selbst. Der Blick auf die Platte
  ist injizierbar (`fileExists`), damit der Vorschlag testbar bleibt. Geraten wird nur der
  Vorschlag; entschieden wird im Editor, und ein Projekt **darf** den Schalter aus haben, obwohl
  eine `.iwf.yml` existiert.
- **Einen laufenden Stack stoppt das Abschalten nicht.** Die Oberfläche verschwindet, der Container
  läuft weiter — heimlich zu stoppen wäre die unangenehmere Überraschung. Der Hilfetext des
  Schalters sagt das und nennt den Weg (`iwf worktree stop <NR>`).
- **Bestehende Task-Files werden nicht rückwirkend umgeschrieben.** Ein alter Worktree-Block mit
  `🐳 **STACK**: -` bleibt stehen; neue Blöcke lassen die Zeile ohne Stack einfach weg (nicht auf
  `-` setzen — eine Zeile, die nichts sagt, ist schlechter als keine).

## Der Status-Block unter der H1

Der Blockquote direkt unter der Überschrift eines Task-Files ist dessen Inhaltsverzeichnis — alles,
was zum Ticket gehört, steht dort und nur dort:

```markdown
# EVEN-3530 - Ausführungskontrolle Status

> 🎫 **JIRA**: `https://iwf-web-solutions.atlassian.net/browse/EVEN-3530`\
> 🌳 **WORKTREE**: `/Users/…/code/even-worktree/EVEN-3530`\
> 🌿 **BRANCH**: `feature/EVEN-3530_status`\
> 🐳 **STACK**: `https://even-3530.test`\
> 📅 **Angelegt**: 2026-09-18
```

`StatusLinks.linkify` verlinkt beim Rendern des Status-Tabs die Code-Spans: JIRA und STACK auf sich
selbst, WORKTREE auf `kanban-ide://` (die App fängt das Schema ab und öffnet PhpStorm), BRANCH auf
den GitLab-Tree. Die **H1 bleibt reiner Text** (KANBAN-003). Sie war bis dahin selbst der Jira-Link:
unsichtbar — dass eine Überschrift anklickbar ist, sieht man ihr nicht an —, im Rohtext der Datei
gar nicht vorhanden, und damit für jeden Leser ausserhalb des Status-Tabs (Claude liest die Datei,
statt sie zu rendern) schlicht nicht da.

- **Fehlende JIRA-Zeile wird abgeleitet** (`StatusLinks.withJiraLine`, aus `ticketKey` +
  `jiraBaseUrl`) und als **erste** Blockzeile eingesetzt — die Wurzel von allem anderen steht
  zuoberst. Steht sie in der Datei, gewinnt die Datei. Ohne Block (`--no-worktree`) entsteht ein
  Blockquote mit nur dieser Zeile.
- **`usesJira: false` → gar keine Zeile**, auch nicht abgeleitet. `linkify` wusste von `useJira`
  nichts und verlinkte die H1 des Projekts `kanban` auf ein `/browse/KANBAN-…`, das es nie gab.
- **`!<iid>`-Karten** haben per Definition kein Jira-Issue und bekommen keine Zeile.
- **`.claude/project.json` führt `jiraBaseUrl` und `usesJira`** — ohne beides könnte eine Skill die
  Zeile weder bauen noch korrekt weglassen. `jiraBaseUrl` **fehlt**, wenn keine konfiguriert ist
  (dieselbe Regel wie bei `kbPath`: „es gibt keine" ist eine eigene Aussage).
- **Der harte Zeilenumbruch** (`\` am Zeilenende) auf allen Metadaten-Zeilen ausser der letzten ist
  Pflicht — ohne ihn kollabiert der Blockquote beim Rendern zu einer einzigen Zeile.
- **Bestandsdateien migrieren**: `JiraLineMigration` trägt die Zeile einmalig in bestehende
  Task-Files ein (siehe „Build / run"). Die Ableitung beim Rendern rettet die Anzeige, nicht die
  Datei; wer sie im Editor öffnet oder mit `grep` liest, soll den Weg zum Ticket ebenfalls finden.

## Kommentare als Diskussion, nicht als JSON

Der Tab „Kommentare" zeigt, was `comments.json` neben dem Task-File führt — bis 2026-09-03 als
roher ```json-Block. Das war technisch ehrlich und praktisch unlesbar: die Diskussion ist der Ort,
an dem die Anforderung ausgehandelt wird, und sie in geschweiften Klammern zu lesen kostet mehr als
sie hergibt. Jetzt wird je Beitrag eine Karte gerendert (Autor, Zeitpunkt, Text).

- **Der Text bleibt Markdown.** Die Karte ist rohes HTML im Markdown, und der Body steht **mit
  Leerzeilen** darin — sonst liest cmark den ganzen Block als HTML und `**fett**` bliebe stehen.
  Betrifft real 13 Kommentare mit Links und 5 mit Listen (von 216).
- **Antworten stehen eingerückt unter ihrem Bezug.** Das war einmal anders: die damals geprüften
  78 Dateien dieser Maschine trugen ausnahmslos die flache Form `{author, created, body}`, und ohne
  Daten wäre eine Verschachtelung eine behauptete Struktur gewesen. Die Daten gibt es inzwischen —
  Jira führt `parentId` sehr wohl, nur liefert die Feld-Projektion `?fields=comment` es nicht mit;
  erst die eigene Kommentar-Ressource tut das. `CommentThread.ordered` baut daraus den Baum
  (Tiefe gedeckelt, eine Antwort ohne auffindbaren Bezug wird zur Wurzel statt zu verschwinden),
  und der native Export schreibt `id`/`parentId` mit.
- **Fremdes JSON bleibt roh.** Nur was sich als Kommentar-Liste lesen lässt, wird zur Diskussion
  (`CommentThread.parse` → nil sonst); eine beliebige `.json` zu interpretieren, weil sie so heisst,
  ginge daneben.
- Ein unlesbarer Zeitstempel bleibt stehen, wie er ist — ein falsch geratenes Datum wäre schlimmer.

## Gerendertes Markdown: Frontmatter und Farben

Beides gilt für **jede** gerenderte Markdown-Ansicht — Task-File-Tabs, Knowledgebase, das
Dokumentfenster aus dem Finder und die Lese-Ansicht des Asset-Editors —, weil beides an einer Stelle
sitzt: `MarkdownHTML.render` und `HTMLTemplate`.

### Der YAML-Kopf steht als Codeblock da

Markdown kennt kein Frontmatter, und cmark las es als etwas ganz anderes: die erste `---`-Zeile wird
eine Trennlinie, die zweite macht aus den Zeilen darüber eine **Setext-Überschrift**. Gemessen an
einem echten Skill-Kopf:

```html
<hr />
<h2>name: solve-task
description: löst ein Ticket
disable-model-invocation: true</h2>
```

Also eine fette Überschrift quer über die Seite, dort wo Metadaten stehen. `Frontmatter.alsCodeblock`
macht daraus vor dem Rendern einen ```yaml-Block.

- **Vor dem Rendern, an einer Stelle** (`MarkdownHTML.render`) — nicht bei den Aufrufern: so zeigt
  jede Ansicht dasselbe, und `TaskSearch.visibleText` geht durch denselben Renderer, zählt also
  weiter gleich mit dem DOM (der Kopf ist jetzt auch durchsuchbar, er steht ja auf dem Schirm).
- **Der Zaun ist länger als die längste Backtick-Folge im Kopf** (`zaunlaenge`): ein
  ``description: nutzt ```json``` dafür`` beendete den Block sonst mittendrin.
- Die `---`-Zeilen selbst fallen weg — im Codeblock sind sie nur Rauschen. Eine Trennlinie mitten im
  Text und ein nie geschlossener Block sind **kein** Kopf und bleiben unangetastet.

### Überschriften sind wieder Überschriften

Alle sechs Ebenen standen auf **Textgrösse** (15 px) und unterschieden sich nur an der Strichstärke
— auf einem Task-File mit `#`, `##` und `###` war die Gliederung praktisch nicht zu sehen. Die
Grössen stehen jetzt im Theme (`markdown.headings.*`, dazu `markdown.fontSize` für den Fliesstext).

Vorgabe, gemessen im DOM einer echten WKWebView (`getComputedStyle`):

| | h1 | h2 | h3 | h4 | h5 | h6 | p |
|---|---|---|---|---|---|---|---|
| px | 26 | 21 | 17 | 15 | 14 | 13 | 15 |
| weight | 700 | 600 | 600 | 600 | 600 | 600 | 400 |

- **Ab H4 gliedert die Fettung, nicht die Grösse** (H4 = Textgrösse), H5/H6 darunter und H6
  zusätzlich in der Sekundärfarbe — dieselbe Staffel wie GitHub. Sechs Ebenen linear zu spreizen
  ergäbe entweder ein winziges H6 oder ein plakatgrosses H1.
- **Die Abstände stehen in `em`, nicht in Pixeln** (`margin: 1.15em 0 0.5em`) — also relativ zur
  **eigenen** Schriftgrösse der Überschrift. Vorher standen feste 6 px darunter, und das war
  derselbe Zwischenraum wie zwischen zwei Absätzen: eine 26-px-Überschrift klebte am Text. Gemessen
  im DOM, vorher → nachher:

  | | P→H1 | H1→P | P→H2 | H2→P | P→H3 | H3→Liste | P→P |
  |---|---|---|---|---|---|---|---|
  | vorher | 18 | **6** | 16 | **6** | 12 | **6** | 6 |
  | nachher | 30 | **13** | 24 | **11** | 20 | **9** | 6 |

  In `em` gerechnet hält die Staffel auch, wenn jemand die Grössen in der Config ändert: mit
  `h1: 34` wird aus 13 px Abstand darunter 17 px, ohne dass man etwas nachziehen müsste. **Oben mehr
  als unten** (2,3 : 1), weil eine Überschrift zu dem gehört, was unter ihr steht.
- **Begrenzt auf 8–72 pt**: eine 0 oder eine 900 in der Config macht die Ansicht unbenutzbar, ohne
  dass man sähe, warum. Ein unlesbarer Wert fällt einzeln auf die Vorgabe zurück, wie bei den Farben.
- Eine Überschrift **am Textanfang** bekommt keinen Abstand nach oben (nachgemessen: 16 px vom
  Rand, genau das Body-Polster).

### Darstellung: benannte Fassungen für Markdown **und** Terminal (`markdown.*`, `terminal.*`)

Beide Themes sind gleich gebaut und stehen an derselben Stelle: **Einstellungen → Darstellung**, dort
drei Gruppen — Kopfzeile je Projekt, Markdown, Terminal. Je Gruppe eine Auswahl der aktiven Fassung
(`markdown.theme`, `terminal.theme`) und darunter ein Editor für die Fassungen selbst
(`markdown.themes.<name>`, `terminal.themes.<name>`). Der Roh-JSON-Editor bleibt für alles, was kein
Feld hat.

- **Eine Palette, deckend.** Vorher war die Fläche *durchsichtig* (der SwiftUI-Bereich schien durch)
  und die Farben wechselten mit `prefers-color-scheme`. Eine gerenderte Datei ist aber ein Blatt
  Papier, kein Fensterteil — Vorgabe ist deshalb **weiss** (`Blatt`), mit einem etwas kräftigeren
  Grau für Codeblöcke (`#f1f1f4`; das alte `#f7f7f9` war auf Weiss kaum zu sehen). Mitgeliefert ist
  `Blatt Dunkel` als zweite Fassung — **kein** Hell/Dunkel-Paar: umgeschaltet wird von Hand.
- **`color-scheme` folgt der Helligkeit des Hintergrunds**, sonst blieben die Scrollbalken weiss.
  `underPageBackgroundColor` der WebView wird mitgefärbt — sonst blitzt beim Laden die alte Fläche
  auf, und beim Überziehen am Rand käme sie wieder hervor.
- **Zwei Flächen, nicht eine.** `--flaeche` sind Tabellenkopf, Zebrastreifen und Kommentarkarten
  (Stärke `markdown.shade`), `--code-bg` ist der Code-Block samt Frontmatter
  (`markdown.codeBackground`, sonst abgeleitet mit der eingebauten Vorgabestärke). Vorher war beides
  **eine** Variable `--bg2`: ein Griff an die Abdunklung färbte die Codeblöcke mit, ein Griff an die
  Code-Farbe die Tabellen — zwei Regler für dasselbe, und keiner tat, was auf ihm stand.
- **Die Flächen folgen dem Blatt**: sie sind keine feste Farbe mehr, sondern der Hintergrund um
  `markdown.shade` Prozent abgesetzt (Vorgabe 6). Wer das Blatt cremefarben stellt, bekommt cremefarbene Flächen statt
  kaltgrauer. Auf einem dunklen Blatt geht es um denselben Anteil nach oben — `#16181c` um 6 %
  abzudunkeln wäre ein Zahlenschritt, den kein Schirm zeigt; die Richtung leitet sich wie
  `color-scheme` aus der Helligkeit ab. `codeBackground` bleibt als feste Übersteuerung, ist aber
  **nicht** mehr Teil der mitgelieferten Fassungen: eine Kopie erbte sie sonst und hielte die Fläche
  fest (`GeerbteFlaechenfarbe` räumt genau diese geerbten Werte einmalig weg).
- **Schriften kommen aus einer Liste**, nicht aus einem Textfeld (`ConfigFieldSpec.Kind.fontFamily`,
  Familien über Core Text): ein vertippter Name fällt still auf die Vorgabe zurück, und man sieht nur,
  dass nichts passiert. Fürs Terminal ist die Liste auf Festbreitenschriften gefiltert.
- **Schrift je Überschriftenebene** (`markdown.headingFonts.h1`…`h6`), in der Oberfläche direkt hinter
  der jeweiligen Grösse. Die Rückfallkette: eigene Ebene → `headingFont` (gemeinsam für H1–H6) →
  `fontFamily` → Systemschrift. Eine nicht gesetzte Ebene ändert also nichts, und die CSS-Regel je
  Ebene entsteht nur dort, wo wirklich eine eigene Schrift steht.
- **Jede Farbe einzeln mit Rückfallwert**: ein unlesbarer Hex-Wert nimmt weder die Fassung noch die
  Config mit. Eine **Terminal**-Fassung dagegen fällt ganz weg, wenn `background`/`foreground` fehlen
  oder `ansi` nicht genau 16 lesbare Farben hat (`RawTheme.resolved`) — deshalb legt der Editor eine
  neue Fassung als **Kopie** an und warnt an der Fassung, statt sie stumm verschwinden zu lassen.
- **`themes` gewinnt.** Der flache `markdown`-Block von früher bleibt lesbar, wird aber beim
  nächsten Speichern einmalig zur Fassung `Eigene` (`MarkdownAltblock`) — zwei Wahrheiten in einer
  Datei, von denen eine stumm ignoriert wird, sucht man sonst an der falschen Stelle.
- **Zahlen sind Zahlen.** `markdown.fontSize`, `markdown.headings.*` und `terminal.font.size` stehen
  als JSON-Zahl in der Datei; gelesen wird beides (`LenientNumber`), geschrieben nur die Zahl.
  Das ist kein Schönheitsthema: `RawSettings` wird mit **einem** `try?` gelesen — ein einziger Wert
  vom falschen Typ liess den Decoder werfen und setzte damit **die ganze** Darstellung auf die
  Vorgaben zurück, Terminal-Theme inklusive (nachgemessen, jetzt als Test festgehalten).
- **Gespeichert heisst sichtbar.** `KanbanSettingsStore.current` ist neu ladbar (vorher ein
  `static let`, also ein Wert pro Prozess). `AppModel.reloadConfig()` lädt neu,
  `TerminalCache.reapplyAppearance()` zieht Farben, Schrift und ⌥-Taste an den **laufenden**
  Terminals nach (der tmux-Prozess bleibt), und die gerenderten Markdown-Ansichten zeichnen über
  `Notification.Name.kanbanAppearanceChanged` neu — SwiftUI merkt von einer geänderten Datei nichts.

### Eine Suchleiste für jede gerenderte Ansicht (`MarkdownFindBar`)

Gesucht wird überall dort, wo Markdown gerendert steht — Task-File-Tabs, Dokumentfenster aus dem
Finder, Knowledgebase und die Lese-Ansicht des Asset-Editors. **Ein** Bauteil, dieselbe Optik,
dieselbe Tastatur: ⌘F springt hinein, ⏎ weiter, ⇧⏎ zurück, esc leert.

- **Die Leiste hält keinen Zustand**, der Aufrufer tut es — weil er zwei verschiedene ist: das
  Task-File sucht über **alle** Tabs und wechselt beim Sprung den Tab (`TaskTabsView`), ein Dokument
  sucht in sich selbst (`MarkdownFind`: eine Sektion, die Trefferzahl ist die Fundstellenzahl).
- **Dieselbe Maschinerie wie beim Task-File**: `TaskSearchIndex` zählt in Swift, `findScript` zählt
  im DOM, und beide zählen gleich — an der echten `solve-task/SKILL.md` (27 KB, mit Frontmatter,
  Tabellen und Codeblöcken) über sechs Suchwörter gegengeprüft: 74/74, 12/12, 87/87, 22/22, 29/29,
  2/2, die markierte Stelle ist die gemeinte, und Leeren räumt alle Markierungen weg.
- **Nur für gerendertes Markdown.** Im Quelltext sucht der Code-Editor selbst, ein HTML-Artefakt
  bringt seine eigene Seite mit. ⌘F schaltet deshalb vorher auf „gerendert" um, statt in einer
  Ansicht zu landen, in der die Leiste nichts täte.
- **Der Suchindex wird faul gebaut** und nur bei echtem Inhaltswechsel verworfen — auch hier gilt,
  dass `visibleText` das Dokument durch cmark schickt.

## Task-File durchsuchen (Feld rechts neben dem Dateinamen)

Ein Task-File hat hier bis zu 23 Tabs und 137 KB; das Gesuchte steht selten in dem, der gerade offen
ist. Das Feld sucht deshalb über **alle** Tabs — Status, **Review** und jede H2-Sektion — und ein
Sprung wechselt den Tab mit. ⏎ weiter, ⇧⏎ zurück, esc leert; daneben steht „3/12".

- **Review ist mit dabei, ohne Sonderfall**: gesucht wird über `AppModel.displaySections`, und dort
  stehen die `<KEY>_review*.md` längst als eigene Tabs (Ids −2, −3, …). Über `taskFile.sections` zu
  suchen hätte genau sie ausgelassen.
- **Gesucht wird im sichtbaren Text, nicht im Markdown** (`TaskSearch.visibleText`: durch denselben
  cmark-Renderer, der die Ansicht füllt, dann Tags und Entities weg). Wer „Lösung" tippt, meint das
  Wort auf dem Schirm — nicht `**Lösung**`, nicht die `href` eines Links, nicht den Pfad in
  `![alt](bilder/loesung.png)`.
- **Das ist zugleich die Bedingung dafür, dass der Sprung stimmt.** Die WebView zählt ihre Treffer im
  DOM ab (`HTMLTemplate.findScript`, Textknoten in Dokumentreihenfolge, hinter jedem Treffer neu
  ansetzend); `TaskSearch.bereiche` zählt genauso. Auf dem Markdown gezählt führte „der dritte
  Treffer" die beiden Seiten auf verschiedene Stellen. Gegengeprüft gegen eine echte WKWebView an
  einem Abschnitt mit Liste, Tabelle, Codeblock, Zitat, Link, rohem HTML und Umlauten: **11 = 11**,
  die markierte Stelle ist die gemeinte, und Leeren räumt alle Markierungen weg.
- **Nur Gross-/Kleinschreibung wird ignoriert**, sonst nichts. Die Gegenseite ist JavaScripts
  `toLowerCase()`; diakritika-unempfindlich zu suchen hiesse, dass „uber" in Swift „über" fände und
  im DOM nicht — zwei Zählweisen sind schlimmer als eine strenge.
- **Ab zwei Zeichen** (`minQueryLength`): ein einzelnes trifft in jedem Task-File hundertfach.
- **Markiert wird alles, hervorgehoben die gemeinte Stelle** (gelb / orange umrandet, hell und
  dunkel) — bei einem Wort, das zwölfmal vorkommt, ist sonst nicht zu sehen, wo man gerade steht.
- **Der Index ist gemerkt und wird faul gebaut** (`TaskSearchIndex`): der sichtbare Text aller Tabs
  entsteht einmal, wenn zum ersten Mal gesucht wird, nicht bei jedem Tastendruck und nicht, wenn der
  Task-File-Watcher anschlägt, während niemand sucht. Gemessen am grössten Task-File der Maschine
  (137 KB, 23 Sektionen): Index 20 ms, danach ~2 ms je Taste.
- **Die erste Fassung brauchte 2,6 s je Tastendruck.** `ohneTags` prüfte an jedem `<`, ob ein
  `<script>` beginnt — mit `html[index...].lowercased().hasPrefix(…)`, und schrieb dafür jedes Mal
  den **ganzen restlichen** HTML-Text klein. Jetzt wird vorwärts von Tag zu Tag gescannt: 2583 ms →
  21 ms, mit Index ~2 ms.

## Der Task-Ordner (📎 links in der Tableiste)

Neben dem Task-File liegt ein Ordner je Ticket (`<tasksPath>/<TICKET>/`) mit dem, was der Export
mitgeholt hat — seit dem nativen Weg (`Tasks/JiraTaskGenerator`) erzeugt ihn Kanban selbst, ohne
laufenden Hermes-Daemon; die Skill `get-task` bleibt der zweite Einstieg: die Bilder der Jira-Beschreibung, `comments.json` samt `avatars/`, dazu Anhänge, die
das Task-File nie verlinkt. Der 📎-Knopf **links neben dem Kopier-Knopf** schiebt ihn als Dateibaum
ein; ein Klick auf eine Datei zeigt die Vorschau rechts daneben — an der Stelle, an der sonst der
gewählte Task-Tab steht.

Der Ordner ist die **einzige** Stelle, an der alles steht: das Task-File zeigt nur, was es selbst
einbettet. Ein Video wird dort zu einem Link, eine `.xlsx` taucht gar nicht auf, `avatars/` sieht
niemand. Gemessen auf dieser Maschine: 193 Task-Ordner, 382 Dateien — 231 png, 101 json, 15 mp4,
9 xlsx, 9 msg, 6 pdf, 4 mov.

- **Aus, solange nichts da ist.** Die meisten Tickets haben keinen Anhang, und ein Knopf, der ein
  leeres Feld aufschlägt, sagt nichts. Die Zahl daneben nennt, was einen erwartet, ohne dass man
  aufmachen muss.
- **Den Pfad jeder Datei kopieren** (`ClipboardPath`, derselbe Knopf und dieselbe Regel wie beim
  Task-File): in der Kopfzeile der Vorschau als Knopf, im Baum als Kontextmenü je Zeile — man soll
  eine 40-MB-Datei nicht erst öffnen müssen, um ihren Pfad zu bekommen. Kopiert wird **relativ zum
  Repo**, solange die Datei darin liegt (Claudes cwd), sonst **absolut**. Der frühere Rückfall auf
  den blossen **Dateinamen** stammt aus der Zeit, als die Task-Files im Repo lagen; seit dem Umzug
  nach Application Support traf er jedes Projekt ausser `hermes` — und mit `EVEN-3530_foo.md` findet
  weder Claude noch der Finder noch eine Shell etwas.
- **📁 links neben der Büroklammer** führt dieselbe Frage nach draussen: der Task-Ordner wird im
  Finder **geöffnet** (man will die Bilder sehen, nicht den Ordner markiert). Ohne Task-Ordner —
  also bei der Mehrheit der Tickets — zeigt er statt dessen das **Task-File**, im Tasks-Verzeichnis
  ausgewählt: derselbe Ort, und „hier liegt deine Datei" ist eine bessere Antwort als ein toter
  Knopf. Bei 643 Task-Files nebeneinander ist das Auswählen der Punkt (`AppModel.taskFinderTarget`,
  Ziel aus `taskFolders` — bewusst nicht aus dem Baum: der wirft leere Ordner weg, ein leerer
  Ticket-Ordner existiert trotzdem). Ist weder das eine noch das andere da (reines Jira-Ticket),
  steht der Knopf nicht da. Denselben Knopf gibt es in der Kopfzeile des Baums, für den seltenen
  Fall mehrerer Task-Ordner.
- **Welcher Ordner zum Ticket gehört** (`TaskAttachments.belongsToTicket`) ist bewusst **lockerer**
  als bei den Dateien (`TaskFileLoader.belongsToTicket` verlangt `_` oder `.` nach dem Schlüssel):
  die Ordner sind nicht so streng benannt. 191 von 193 heissen schlicht `<KEY>`, einer trägt den
  ganzen Datei-Stamm (`EVEN-3457_fire_nachweisverfassung_…`), einer eine angehängte Zahl
  (`EVEN-3282-1`, ein zweiter Export desselben Tickets) — mit der Datei-Regel wären dessen vier
  Bilder nirgends zu sehen. Die Schranke ist statt dessen die **Ziffer**: `EVEN-3282` darf sich
  `EVEN-32820` nicht einverleiben.
- **Ein Ordner steht als sein Inhalt da**, mehrere je als eigene Zeile — flach wäre nicht mehr zu
  sehen, welches Bild aus welchem Export stammt.
- **Gebaut wird mit `KnowledgebaseTree`**, gezeigt mit denselben `KBRows`: derselbe Baum, dieselbe
  Auswahl, ein Parameter für das Symbol. Ein Task-Ordner besteht aus Bildern statt aus Text, und ein
  PNG als generisches Blatt wäre die Zeile, die man am häufigsten sieht. Aufgeklappt ist hier
  **alles** (wie im Commit-Dialog) — der Ordner hat eine Handvoll Dateien, nicht 365 wie eine
  Knowledgebase.
- **Die Vorschau ist Quick Look** (`QLPreviewView`), sobald die Datei nicht Text ist. Der Weg der
  Knowledgebase („kein Textformat — im Finder öffnen") wäre hier die Antwort für 70 % der Dateien,
  also genau für die, derentwegen man den Ordner aufmacht. Für jedes Format eine eigene Ansicht zu
  bauen hiesse dagegen nachzubauen, was das System schon kann, samt Abspielen und Blättern.
  Markdown, HTML und Text laufen unverändert durch dieselben Ansichten wie in der Knowledgebase
  (`MarkdownWebView` / `FileWebView` / `CodeEditorView`, nicht schreibbar).
- **`comments.json` wird zur Diskussion**, nicht zu JSON — dieselbe Entscheidung wie im Task-File,
  und derselbe Code (`CommentThread`). Entschieden wird über `CommentThread.parse`, nicht über den
  Dateinamen. Der Bezugspunkt der Profilbilder ist dabei das **Tasks-Verzeichnis**, nicht der
  Ticket-Ordner: die Pfade in der Datei lauten `<KEY>/avatars/…`, eine Ebene höher.
- **Fest eingeschoben statt `HSplitView`**: eine Spalte, die *erscheint*, muss von links hereinfahren
  — ein Split baut sie sprunghaft auf. Derselbe Grund, aus dem die Prompt-Timeline über dem Terminal
  liegt statt neben ihm.
- **Ein Tab-Klick beendet die Vorschau** (der Baum bleibt): einen Tab zu wählen heisst, diesen Inhalt
  sehen zu wollen, und beide stehen an derselben Stelle. Das „✕" der Vorschau tut dasselbe.
- **Neu eingelesen** wird beim Ticketwechsel und immer, wenn der Tasks-Ordner-Wächter anschlägt (er
  sieht, wie der Ticket-Ordner entsteht oder verschwindet). Was **innerhalb** des Ordners dazukommt,
  sieht er nicht — dafür steht der ⟳-Knopf in der Kopfzeile des Baums.

### Outlook-Mails (`.msg`) werden gelesen, nicht weitergereicht

Im Task-Ordner liegen `.msg`-Dateien, weil jemand den Mailverkehr zum Ticket mitgespeichert hat —
oft ist das die Anforderung selbst. Sie sind damit Inhalt, nicht Beiwerk, und bekommen eine eigene
Ansicht: Kopfzeilen (Von/An/Cc/Datum/Anhänge), darunter der Körper.

- **Quick Look scheidet aus: es hängt.** `qlmanage` auf eine dieser Dateien lief zwei Minuten ohne
  Ergebnis. Deshalb wird `.msg` **vor** dem Binär-Zweig abgefangen. (Ohne eigenen Leser wäre es
  ohnehin nur die Zeile „Binärdatei — im Finder öffnen": `msg` steht nicht in
  `KBFileKind.binaryExtensions`, die Datei landete also im Text-Pfad und fiel dort über ihre
  Null-Bytes.)
- **Zwei Schichten**: `CompoundFile` liest das Containerformat (CFBF/OLE2 — ein Dateisystem in einer
  Datei, dasselbe Format wie `.doc`/`.xls` der alten Generation), `OutlookMessage` die MAPI-
  Bedeutung darüber. Der Container weiss nichts von Mails, und das ist der Punkt: er ist gegen
  fremde Bytes ausgelegt (jeder Zugriff bereichsgeprüft, Zyklenschutz je Sektorkette, Tiefengrenze
  im Verzeichnisbaum) und gibt bei einem kaputten Feld `nil` statt eines Absturzes.
- **Die Verweise im Verzeichniseintrag liegen bei 0x44/0x48/0x4C** (davor steht das Farb-Byte des
  Rot-Schwarz-Baums, dahinter die CLSID). Vier Bytes daneben gelesen, und der Baum zeigt ins Leere:
  die erste Fassung fand so **keinen einzigen** Eintrag in einer gültigen Datei.
- **Der Körper ist nicht UTF-8**, sondern liegt in der Codepage der Nachricht (`PR_INTERNET_CPID`,
  hier durchweg 28591/1252). Gelesen wird mit **Windows-1252** auch dort, wo die Datei 28591 meldet:
  Outlook schreibt gern typografische Anführungszeichen aus 0x80–0x9F, wo Latin-1 nur Steuerzeichen
  kennt. (In den sechs Dateien hier ist der Bereich leer — die Wahl kann also nur helfen.)
- **`<style>` muss raus, nicht entschärft werden.** Der Markdown-Renderer *escapt* gefährliche Tags
  (`tagfilter`) — Outlooks seitenlanges Word-CSS stünde dann als sichtbarer Text über der Mail.
  Ebenso fliegt `<head>` samt `<meta charset>`, das nach der Umkodierung falsch wäre.
- **`cid:`-Bilder werden eingebettet** (data-URI, wie die Task-Bilder und die Kommentar-Avatare) —
  sie liegen ja nicht als Datei vor, sondern in der `.msg`. Und **„inline" heisst: im Körper zu
  sehen**, nicht „hat eine Content-Id": vier der sechs Dateien tragen Bilder mit Id, haben aber gar
  keinen HTML-Körper. Nach der Id allein zu gehen meldete „keine Anhänge" über sechs Bildern.
- **Der Absender ist manchmal keiner.** Bei intern verschickten Mails steht in `0C1F` der
  Exchange-Pfad (`/o=intraOrg/ou=Exchange Administrative Group…`) statt eines Postfachs — der sähe
  im Kopf aus wie eine Adresse und wäre keine, also fällt er weg. Zwei Dateien haben überhaupt
  keinen Absender; der Kopf verträgt das.
- **Das Datum hat drei Stufen** (abgeschickt → zugestellt → angelegt). Die dritte ist nicht
  theoretisch: zwei der sechs Dateien haben nur sie.
- Gerendert wird als **Markdown mit rohem HTML darin**, durch denselben `MarkdownWebView` wie
  Task-Files und Kommentare — damit erbt die Mail das Stylesheet samt Hell/Dunkel. Der
  Quelltext-Schalter zeigt den **Text-Körper**, die Fassung ohne Outlooks HTML.

#### Ein NUL im Text hat die halbe Vorschau gekostet

Die Text-Properties sind **uneinheitlich terminiert**: `0E04` (An) zählt die abschliessende Null
mit (36 Bytes für 17 Zeichen), `0037` (Betreff) nicht (52 Bytes für 26 Zeichen). Blieb sie stehen,
brach das gerenderte HTML mitten in der Kopfzeile ab — 208 statt 762 Zeichen, der ganze Mail-Körper
weg, ohne Fehler.

Schuld war nicht nur die Null, sondern auch `MarkdownHTML.render`: es fütterte cmark mit
`strlen(ptr)` und hörte damit beim ersten NUL auf. Beides ist behoben — die Properties werden
NUL-frei gelesen, **und** der Renderer bekommt jetzt die echte Byte-Länge. Ohne NUL sind beide
Zahlen gleich, für alle anderen Aufrufer ändert sich also nichts; mit NUL verliert keiner mehr
lautlos den Rest des Dokuments.

## Markdown-Dateien öffnen („Öffnen mit › Kanban")

Kanban ist beim System als **Betrachter** für `.md` angemeldet; eine so geöffnete Datei bekommt ein
**eigenes Fenster** (`MarkdownDocumentWindow`), gerendert wie ein Task-File, mit Umschalter auf den
Quelltext.

- **Rolle `Viewer`, Rang `Alternate`** (`CFBundleDocumentTypes`): Kanban zeigt die Datei und
  bearbeitet sie nicht — und nimmt dem Editor die Standard-Zuordnung für `.md` nicht weg. Auf dieser
  Maschine steht Kanban damit in „Öffnen mit", Standard bleibt Xcode.
- **Der Typ wird `imported`, nicht `exported`** (`UTImportedTypeDeclarations`):
  `net.daringfireball.markdown` gehört nicht uns. Ohne die Deklaration kennt eine Maschine, auf der
  keine andere Markdown-App installiert ist, den Typ gar nicht — und der Eintrag bliebe aus.
- **`lsregister -f` läuft im `build-app.sh`** gleich nach dem Signieren: sonst kennt der Finder die
  Zuordnung erst nach einem Neustart, oder er behält den alten Eintrag.
- **Ein eigenes Fenster, kein Tab im Board**: die Datei gehört zu keinem Ticket, und das Board hätte
  keinen Platz für sie, an dem sie nicht etwas anderes verdrängt. Titel und `representedURL` sind
  gesetzt, also funktionieren Proxy-Symbol und ⌘-Klick auf den Titel wie bei jedem Dokumentfenster.
- **Ein Fenster je Datei**, nach aufgelöstem Pfad — derselbe Aufruf holt das vorhandene nach vorn
  (der Finder schickt beim wiederholten „Öffnen mit" ständig dieselbe Datei), und ein **Symlink** auf
  dieselbe Datei öffnet kein zweites.
- **Gerendert wie ein Task-File** (`MarkdownWebView` + `TaskFileLoader.rewriteImagePaths`, damit
  Bilder neben der Datei erscheinen; `loadHTMLString` gibt dem Dokument keinen Dateizugriff), der
  Quelltext-Schalter zeigt `CodeEditorView` nicht-schreibbar — dieselben zwei Ansichten wie in der
  Knowledgebase. Grenze 4 MB, ebenfalls wie dort.
- **Die Datei wird beobachtet** (`TaskFileWatcher`, 150 ms entprellt) und beim Schliessen abgemeldet
  — samt `NotificationCenter`-Token, der sonst je geöffneter Datei stehen bliebe.
- Wird die App **durch** eine Datei gestartet, geht das Board-Fenster mit auf (die `Window`-Szene
  öffnet immer); läuft sie schon, erscheint nur das Dokumentfenster.

## Knowledgebase lesen (📚 neben Sprint/Frei)

Der 📚-Knopf steht neben der Modus-Umschaltung, weil er dieselbe Frage beantwortet: **was füllt
gerade das Fenster**. Er schlägt die Knowledgebase des Projekts auf
(`modules.knowledgebase.projects.<key>.path`) — Inhalt über die ganze Breite, Ordnerbaum auf Abruf
links — und derselbe Knopf schaltet zurück; der gefüllte Buchrücken sagt, welcher Zustand gilt.

- **Sie ersetzt Board und Detail, statt sich als Sheet davorzulegen.** Die Ansicht ist selbst ein
  Zwei-Spalten-Bild und wird gelesen, nicht in einem Arbeitsschritt beantwortet. Ein Sheet hätte
  beide Spalten in die Fläche eines Dialogs gequetscht.
- **Angezeigt wird nach Dateiart** (`KBFileKind`), nicht nach Vermutung: Markdown durch denselben
  Renderer wie die Task-Files (`MarkdownWebView` + `TaskFileLoader.rewriteImagePaths`, damit
  Bilder neben der Datei auch erscheinen), die generierten HTML-Artefakte (`artefacts/`) in einer
  echten Web-Ansicht, alles andere im **Code-Editor des Commit-Dialogs** (`CodeEditorView`,
  `isEditable: false`) — Zeilennummern, Syntaxfarben, dieselbe Schrift wie das Terminal.
- **Ein Link ins Repo bleibt in der Ansicht.** Die KB verweist bis in den Quelltext
  (`../../core/docs/business-case-structure.md`, `../../../../core/config/packages/…yaml`); solche
  Ziele werden **inline** gezeigt statt an den Finder gereicht, mit „Repo"-Marke in der Kopfzeile
  und einem **Zurück**-Knopf (⌘[), denn ausserhalb der KB gibt es keine Zeile im Baum, über die man
  zurückfände. Der Zurück-Stapel merkt sich auch die Sprungmarke, nicht nur die Datei.
- **Innerhalb der KB die Darstellung, ausserhalb die Datei.** Ein `.md` aus dem Repo wird als
  **Quelltext** gezeigt, nicht gerendert: wer einem Link ins Repo folgt, meint die Datei — eine
  gerenderte Fassung sähe aus wie KB-Inhalt und verwischt genau den Unterschied, den die
  „Repo"-Marke markiert. Der Knopf in der Kopfzeile schaltet für Markdown und HTML zwischen
  gerendert und Quelltext um; die Vorgabe richtet sich danach, wo die Datei liegt.
- **Binär entscheidet der Inhalt, nicht die Endung.** `KBFileKind` kennt eine Liste bekannter
  Binärformate und hält alles andere für Text — eine Liste erlaubter Text-Endungen ginge nicht, die
  Endungen eines Repos sind nicht aufzählbar (`.php`, `.twig`, `.lua`, `.lock`, `Makefile`, gar
  keine). Was trotzdem binär ist, fällt beim Lesen auf: ein Null-Byte in den ersten 8 KB, dann
  Hinweis statt Zeichensalat.
- **HTML über `loadFileURL(_:allowingReadAccessTo:)`** mit dem KB-Ordner als Wurzel — ein Artefakt
  lädt Stylesheet und Bilder relativ, mit `loadHTMLString` (dem Weg des Markdown-Renderers) käme
  eine Seite ohne Layout heraus. Links **innerhalb** der KB bleiben in der Ansicht, alles andere
  geht in den Browser.
- **Links werden in JavaScript abgefangen, nicht über die Navigation.** Ein Dokument aus
  `loadHTMLString` darf nicht nach `file://` navigieren — WebKit verwirft den Klick, **ohne** den
  Navigation-Delegate zu fragen (headless nachgemessen). Genau deshalb waren die Links tot, aus
  denen die Knowledgebase besteht (`../Common/HistoryEntry.md`, der „Siehe auch"-Fuss in 329
  Dateien), während `#anker` und `https://…` funktionierten — das „mal geht's, mal nicht".
  `HTMLTemplate.linkInterceptScript` fängt den Klick ab und schickt `anchor.href` (die vom DOM
  aufgelöste absolute Adresse, von der Sperre nicht betroffen) an den Coordinator;
  `KBLink.resolve` entscheidet dann: Datei in der KB → Ansicht springt hin, ausserhalb → Finder
  bzw. Editor, `#anker` → gar nicht abgefangen, das erledigt WebKit selbst.
- **Sprungmarken an den Überschriften** (`HeadingAnchors`): cmark vergibt keine, die Knowledgebase
  verlinkt sie aber im **GitHub-Format** — an den Dateien nachgeprüft, „RealTemplates — Tests gegen
  echte Vorlagen" wird dort zu `realtemplates--tests-gegen-echte-vorlagen`, mit zwei Bindestrichen,
  weil GitHub die Interpunktion entfernt und erst danach Leerzeichen ersetzt. Ein Verfahren, das
  Bindestrich-Folgen zusammenzieht (wie `md2html.py` der KB selbst), träfe diese Anker nicht.
- **Basis-URL ist die Datei, nicht ihr Ordner.** Nur so löst das DOM `../x.md` richtig auf und ein
  `#anker` bleibt als Sprung im selben Dokument erkennbar (gegen den Ordner ergäbe er den Ordner
  plus Marke). Eine Marke aus einem Link über Dateigrenzen hinweg überlebt den Ladevorgang als
  `pendingJump` — mit dem Pfad daneben, sonst landete sie auf der nächsten Datei.
- **Der Baum ist zu, wenn die Ansicht aufgeht** (`KnowledgebaseView.showTree`, Vorgabe aus): gelesen
  wird rechts, und ein Artefakt bringt sein eigenes Layout mit, das die Fläche braucht. Eingeblendet
  wird er über den Knopf **ganz links in der Kopfzeile der Datei** (⌘⌥S, wie im Finder) — dort, weil
  er dem Baum links gilt und weil er ohne Baum der einzige Weg dorthin ist. Der Zustand gilt für die
  geöffnete Ansicht; beim nächsten 📚 steht er wieder zu (`@State`, nicht gemerkt). Zurück zum Board
  führt dann die Leiste, nicht der Baum-Kopf.
  - **Ohne Auswahl steht er trotzdem da.** Zeigt die rechte Seite nur „Datei links auswählen"
    (leere oder fehlende Knowledgebase), gibt es keine Kopfzeile mit dem Knopf — eine Ansicht ohne
    Weg zum Baum wäre eine Sackgasse.
  - Gemessen, nicht angenommen: ein wegfallendes erstes Kind im `HSplitView` räumt AppKit sauber
    weg (rechts füllt die Breite, kein Reststreifen), **und** der rechte View behält seinen
    `@State` — die geladene Datei und die Quelltext-Umschaltung überleben das Umschalten. Geprüft
    mit einer Wegwerf-App, die sich selbst umschaltet: Klicks lassen sich auf dieser Maschine nicht
    synthetisieren.
- **Der Baum ist nicht vollständig aufgeklappt.** Der Commit-Dialog macht das, aber der zeigt eine
  Handvoll Dateien; die CORE-Knowledgebase hat 365 Dateien in 130 Ordnern — ausgeklappt wäre das
  eine Wand aus ~500 Zeilen. Offen ist die oberste Ebene (das Inhaltsverzeichnis) plus der Weg zur
  **gewählten** Datei (`KnowledgebaseTree.ancestorFolderIDs`), sonst zeigte die rechte Seite einen
  Inhalt, dessen Zeile links hinter einem Dreieck steckt.
- **Gelesen, nicht verwaltet**: `KnowledgebaseTree` kennt keine Änderungsoperationen. Leere Ordner
  fallen weg (in einer Leseansicht ist das nur ein Dreieck, hinter dem nichts steht), Symlinks
  werden nicht verfolgt (ein Link auf einen Vorfahren wäre eine Endlosschleife), Werkzeug-Ordner
  (`.git`, `.idea`, `__pycache__`, …) sind draussen — `_build/` und `assets/` bleiben, denn was zur
  Knowledgebase gehört, entscheidet die, der sie schreibt.
- **Einstieg ist `artefacts/index.html`** (`KnowledgebaseTree.entryFile`, beide Schreibweisen des
  Ordnernamens): die gebaute Übersichtsseite verweist auf die übrigen Artefakte und ist damit der
  Einstieg, den man ohne den Baum braucht. Ohne Artefakt-Ordner gilt weiter `README`/`index` auf
  oberster Ebene, sonst die erste anzeigbare Datei. **Getrennt von `landingFile`**, das eine andere
  Frage beantwortet — den Einstieg *eines Ordners*, auf den ein Link zeigt (`../Common/`); dort wäre
  die Artefakt-Übersicht des ganzen Baums die falsche Antwort.
- **Der Scan läuft detached** und beim Projektwechsel neu; die Auswahl überlebt ihn, wenn es die
  Datei noch gibt, sonst führt der Einstieg wieder irgendwohin statt ins Leere. Beim Zu- und
  Aufschlagen der Ansicht bleibt die gelesene Datei stehen — der Einstieg gilt dem ersten Öffnen,
  nicht jedem.
- Grenze fürs Einlesen: 4 MB. Darüber wird nicht gerendert, sondern die Grösse genannt — eine
  mehrere Megabyte grosse Datei durch WKWebView zu schicken hängt das Fenster auf.

## Maintree neben Worktree (dasselbe Panel, zwei Ziele)

Die Reiterleiste über dem Terminal beginnt mit **Maintree | Worktree** — beide nur in Projekten
**mit** Docker-Stack (`dockerStack`, siehe „Projekt-Typen"); ohne Stack fängt die Leiste bei
„Claude" an. Beide zeigen dasselbe
Stack-Panel — Statusabzeichen aus `iwf stack ps`, die abgeleiteten Zeilen mit ihren Reparaturen,
Start/Stop/Neustart und die laufende Ausgabe. Es ist **ein** View mit einem Parameter
(`StackTarget`), keine Kopie: eine zweite Datei hätte die Regeln unten nur einmal gekannt.

- **Die Herleitung ist identisch.** `DockerStatusScanner` bekommt schlicht den Repo-Pfad statt des
  Worktree-Pfads; der Stack-Name ist so oder so der **Ordnername** (`even` bzw. `even-3963`).
- **Zugehörigkeit entscheidet das Compose-Label, nicht der Name.** Der Ordnername des Haupt-Repos
  (`even`) ist Präfix **jedes** Worktree-Stacks (`even-3963`) — ein `hasPrefix(stackName + "-")`
  nimmt im Maintree also die Container fremder Worktrees mit und zeigt sie, um das Präfix gekürzt,
  als eigene Dienste: `even-3963-db` erschien als „3963-db", die Zählung stand auf 14/14 statt 7/7.
  `StackStatusParser.services` vergleicht deshalb `com.docker.compose.project` **exakt** (vierte
  Spalte des `docker ps -a --format`). Umgekehrt trat es nie auf: `even-3963-` ist kein Präfix von
  `even-db`, Worktree-Ansichten waren immer sauber. Der Präfix-Filter in `StackSweep` ist aus
  demselben Grund unauffällig — das Haupt-Repo ist dort per `guard` ausgeschlossen.
- **Das Statusabzeichen liest `stackStatus(for:)`**, wie das Panel darunter. `model.stackStatus`
  allein ist immer der *Worktree*-Stack; im Maintree-Tab stand dessen Zahl über den Diensten des
  Haupt-Repos — zwei Zahlen aus zwei Stacks im selben Kasten.
- **Die Image-Warnung „kein eigener Build" gilt nur Worktrees.** Sie vergleicht `local/<name>` mit
  `local/<projekt>` — im Haupt-Repo ist beides derselbe Tag, der Vergleich prüfte das Image gegen
  sich selbst und schlug immer an, samt eines `iwf stack build`, das daran nichts ändern kann.
  `imagePhase` überspringt den Vergleich, wenn `name == projectName`.
- **Bedient wird verschieden**: ein Worktree über `iwf worktree start|stop|restart` (iwf findet ihn
  über seine Nummer), das Haupt-Repo über `iwf stack start|stop|restart` im eigenen Verzeichnis —
  gegen `iwf stack --help` geprüft (build/destroy/logs/ps/restart/start/stop/update). Das ist der
  **einzige** Unterschied in den Befehlen; build, cert, composer, yarn und vite laufen ohnehin
  relativ zum Arbeitsverzeichnis und sind wortgleich (`StackPhase.Repair.commands(for:)`).
- **Zwei Dinge fehlen im Maintree, und zwar mit Absicht** (`StackTarget.allowsDestructiveActions`):
  **Destroy** — `iwf stack destroy` nähme aus dem Haupt-Repo wegen des Substring-Filters jedes
  `local/<projekt>-*`-Image mit — und der **DB-Seed**, der dort die Entwicklungsdatenbank träfe, an
  der alles hängt. Auch die Abzweig-Basis („← Branch") fällt weg: das Haupt-Repo *ist* die Basis.
- **Eigener Zustand je Ziel** (Status, Ausgabe, „busy"): die Tabs stehen nebeneinander, ihre
  Ausgaben dürfen sich nicht überschreiben, und ein laufender `iwf stack build` im Maintree darf den
  Worktree-Tab nicht sperren.
- Der Worktree-Tab hängt am **Ticket** und ist ohne Worktree leer; der Maintree-Tab hängt am
  **Projekt** und ist deshalb immer da.

### Die Command-Ausgabe ist eine Log-Ansicht, kein `Text`

Das Panel war die teuerste Fläche der App: den Trenner zu ziehen, während es offen stand, brachte
sofort den Wartecursor. Drei Dinge kamen zusammen, alle gemessen:

1. **Ein pty liefert in winzigen Häppchen.** `WorktreeStackController` las mit
   `readabilityHandler`/`availableData`; an 1500 Zeilen gemessen sind das **1407 Aufrufe, Ø 47 Byte,
   innerhalb von 68 ms** — und jeder war ein eigener Sprung auf den Main-Actor mit anschliessendem
   SwiftUI-Neuzeichnen. Gebündelt wird jetzt **dort, wo die Häppchen entstehen**
   (`flushInterval` 0,1 s, gemessen 8,6–8,8 Rückrufe/s), nicht bei den sechs Aufrufern: „höchstens
   10 Rückrufe je Sekunde" ist eine Eigenschaft des Stroms. Reihenfolge und Byte-Zahl sind dabei
   unverändert (66 393 → 66 393).
2. **`Text(CodeTheme.ansiText(…))` stand im Body.** Bei vollem Puffer **40,1 ms** je Durchlauf —
   davon nur 2,5 ms Parsen, der Rest stückweises `AttributedString.append`. Ersetzt durch
   **`LogTextView`** (`NSTextView`), die nur den **Zuwachs** anhängt. Der offene ANSI-Zustand reist
   dafür über die Stückgrenze (`ANSIParser.State`) — sonst begänne jedes angehängte Stück wieder
   weiss, und eine mitten durchgeschnittene Sequenz fiele als Text durch. Gegengeprüft an einer
   echten Zeile an **jeder** möglichen Schnittstelle (`testChunkedParsingMatchesWholeInput`) und
   kopflos gegen eine echte `NSTextView` (10 Flushes, Text vollständig, Farben richtig, keine
   Escape-Reste). Gesamtrechnung für **eine** 66-KB-Ausgabe: **32,8 s → 23 ms** Main-Thread.
3. **Der Body hing an `cards`.** `currentWorktree` war abgeleitet und las für den `sourceBranch` der
   `!<iid>`-Karten die ganze Kartenliste — die `applyTimingsToCards` alle ~1,5 s schreibt, solange
   Claude antwortet. Das Panel baute daraufhin seine Ausgabe neu, ohne dass sich an ihr etwas
   geändert hätte. `currentWorktree` ist jetzt **gespeichert** und wird bei den drei Dingen neu
   berechnet, die den Wert bestimmen: andere Auswahl, neue Worktree-Liste, neue Tickets.

Dazu zwei Kleinigkeiten mit derselben Ursache: `LogText` prüft die Puffergrösse in **Bytes**
(`String.count` zählt Graphemcluster über den ganzen Puffer — bei einem Anhängen je Häppchen war das
die teuerste Zeile des Streams) und kappt **in Blöcken auf Zeilengrenze** (200 KB → 150 KB), damit
der Schnitt weder eine Escape-Sequenz noch ein Mehrbyte-Zeichen zerteilt.

Ein `CodeTheme.ansiText` gibt es nicht mehr: den langsamen Weg stehen zu lassen hiesse, ihn wieder zu
benutzen. Der Stack-Sweep zeigt seine Ausgabe in derselben `LogTextView`.

Nebenbei zwei Verhaltensänderungen, beide gewollt: die Ansicht **scrollt nur mit, wenn man unten
steht** (vorher riss jeder Chunk die Lesestelle ans Ende; ein frisch gestarteter Befehl springt
weiterhin ans Ende, erkannt an seinem kurzen Kopf), und die Ausgabe **bricht um** statt seitwärts zu
scrollen.

### Reiter „Stack" und „Snapshots"

Das Panel ist zweigeteilt, für beide Ziele gleich. „Stack" ist der bisherige Inhalt; „Snapshots"
bedient `iwf db snapshot` — Liste, Wiederherstellen, Anlegen. Die laufende Ausgabe rechts gilt für
beide: ein `restore` will man genauso mitlesen wie ein `stack build`.

- **Die Liste kommt aus dem Ordner**, nicht aus `iwf db snapshot list`: dort steht
  „`<datei> (<n> MB)`" plus eine Hinweiszeile, und aus einer gerundeten MB-Zahl lässt sich weder
  sortieren noch das Alter ablesen. `DbSnapshots` liest `~/.iwf-dev/snapshots/<stack>/*.tar`
  (`DB_SNAPSHOTS_DIR` aus iwfs `constants.py`) — dieselbe Wahrheit, denn iwf globt dort ebenso.
  Ein Ordner **je Stack**, also getrennt für Haupt-Repo und jeden Worktree.
- **`create` kennt keinen Namen.** iwf hat nur `latest` (überschreibt `<volume>-latest.tar`) und
  `-t` (Zeitstempel). Einen benannten Snapshot macht Kanban selbst: mit `-t` erzeugen, dann auf
  `<volume>-<name>.tar` umbenennen. Gefahrlos, weil `restore -f` **jeden** Basename aus dem Ordner
  annimmt und `list` alles globt. Welche Datei gerade entstand, ergibt die Differenz vorher/nachher
  — iwfs Zeitstempelformat (`YYYY-M-D--H-M-S`, ohne führende Nullen) nachzubauen wäre eine Wette
  auf fremden Code.
- **`restore` braucht `-y`.** Der Befehl fragt sonst im Terminal nach (`confirm()` in
  `project_compose.db_restore_snapshot`) und Kanban bliebe für immer stehen. Die Rückfrage stellt
  deshalb die App — mit dem Namen des Snapshots und dem Hinweis, dass der aktuelle Bestand ersetzt
  wird.
- **Beides hält die Datenbank an** und startet sie danach wieder; das steht in der Bestätigung, weil
  es dauert.
- Namen werden zu reinen Dateinamen normalisiert (kein Trenner, kein Leerzeichen, nie leer) — ein
  `/` im Namen darf nie zu einem anderen Ordner führen.

## Stacks abräumen („N Stacks stoppen" in der Toolbar)

> Nur in Projekten **mit** Docker-Stack: `loadStackSweep` bricht ohne `hasStack` ab, der Zähler
> bleibt leer und der Knopf erscheint gar nicht (siehe „Projekt-Typen").

Jeder Worktree bringt einen eigenen Docker-Stack mit, und der läuft weiter, wenn das Ticket längst
in Review oder Done steht. Gemessen auf der Maschine, für die das gebaut wurde: 43 Worktrees, 12
laufende Stacks, 10 davon nur noch mit einem übrigen `fpm`-Container — Restposten von `iwf run`/
`docker exec`, die niemand mehr sieht und die trotzdem Speicher halten.

- **`iwf worktree stop <NR>`** ist das Werkzeug, **nicht** `destroy`. Nachgelesen in iwfs Quelle
  (`cmd_worktree.py` → `_compose_down(keep_data: true)`): `compose down --remove-orphans` nimmt
  Container und Netzwerk, **Worktree, Branch, Image und benanntes DB-Volume bleiben**, und
  `iwf worktree start <NR>` bringt alles zurück (kein Re-Seed, kein Rebuild). `stop` hat keine Flags
  und keinen Bestätigungs-Prompt — es ist von Haus aus automatisierbar, ein `--force` gibt es dort
  gar nicht.
- Aufgerufen wird mit **cwd = Haupt-Repo und expliziter Nummer** (so wie `worktree.md` es
  vorschreibt): dann braucht der Sweep kein `cd` in einen Worktree und funktioniert auch für Stacks,
  deren Worktree gleich mit abgeräumt werden soll. Sequenziell, nicht parallel — mehrere gleichzeitige
  `compose down` auf derselben Engine bringen nur Gedrängel und eine unlesbare Ausgabe.
- **Kandidaten sind abgeleitet** (`StackSweep`), nicht gemerkt: `docker ps` sagt, was läuft (**ein**
  Aufruf für die ganze Maschine, nicht einer je Worktree), `git worktree list` sagt, wozu es gehört,
  die Board-Spalte sagt, ob es noch gebraucht wird. Ein gemerkter „schon abgeräumt"-Zustand würde
  falsch, sobald jemand von Hand wieder hochfährt; so ist ein gestoppter Stack einfach kein Kandidat
  mehr. Gezählt wird über das Container-Präfix `<stack>-` — mit Bindestrich, sonst träfe `even-356`
  auch `even-3563-fpm`.
- **Das Haupt-Repo ist nie Kandidat.** Es steht hier auf `refactor/EVEN-0002_rule_engine`, also auf
  einem Ticket-Branch — ohne die Ausnahme wäre `even-*` ein Treffer und ein Sweep würde den
  Haupt-Stack abschiessen.
- **Vorgewählt sind Review und Done ohne laufenden Turn.** Ein laufender Turn hält den Stack, auch
  wenn die Spalte „fertig" sagt: in Review wird nachgebessert, und ein Stack, der unter einem
  laufenden Test verschwindet, kostet mehr als er spart. Alles andere steht sichtbar in der Liste und
  darf dazugewählt werden — gestoppt ist reversibel.
- **Stacks ohne Karte** (fremder Sprint im Sprint-Modus) stehen mit leerer Spalte da und sind nicht
  vorgewählt: geraten wird nicht. **Stacks ohne Worktree** werden nur benannt — `iwf worktree stop`
  greift dort nicht.
- **Bewusst ein Knopf mit Liste, keine stille Automatik** beim Spaltenwechsel. Dieselbe Haltung wie
  beim Worklog: geschrieben (hier: gestoppt) wird auf Bestätigung, nicht im Hintergrund.
- Exit 0 beweist nichts: `iwf worktree stop` endet auch mit 0, wenn es den Worktree nicht gefunden
  hat („No worktree found for even-9999", verifiziert). Den Beweis liefert die **neu gelesene Liste** —
  ein Stack, der noch läuft, steht danach wieder da.
### Zweite Stufe: „tief" (Volumes + Images)

Stoppen gibt nur RAM und CPU frei — die Platte liegt in den Volumes. Deshalb hat jede Zeile im Sheet
einen zweiten Schalter, der nach dem Stop die Volumes und Image-Tags des Stacks löscht.

- **Über `docker`, nicht über iwf** — weil iwf für „Volume und Image weg, Worktree bleibt" keinen
  Befehl hat: `worktree stop` lässt beides stehen, `worktree destroy` nimmt den Worktree mit
  (`--keep-data` geht nur in die andere Richtung), und `iwf stack destroy` (cwd im Worktree) fragt
  interaktiv (`click.confirm`, kein `--force`) und nimmt zusätzlich Netzwerke, DB-Snapshots und das
  **TLS-Zertifikat samt Traefik-Eintrag** mit — der Rückweg bräuchte dann auch `iwf cert create`.
  ⚠️ Und es darf **nie** aus dem Haupt-Repo laufen: dort ist `PROJECT_NAME=even`, und sein
  Image-Filter ist ein Substring-Match — das nähme jedes `local/even-*`-Image mit.
- **Gelöscht wird nur, was gefunden wurde**, nie ein geratener Name. Ein Stack hat hier **zwei**
  Volumes (`<stack>_dbdata` **und** `<stack>_appcache`) und **zwei** Image-Tags (`local/<stack>:latest`
  und `local/<stack>-base:latest`) — geratene Namen hätten je die Hälfte liegen lassen. Genau diese
  Hälfte lässt auch iwfs eigenes `worktree destroy` liegen: `_remove_image_tag` entfernt nur
  `local/<name>:latest`, das `-base`-Image bleibt.
- **Trennzeichen sind Pflicht**: `<stack>_` bei Volumes, `local/<stack>-` bei Images. Ohne sie würde
  `even-3563` das fremde `even-35630` mitnehmen, und ein falsch gelöschtes Image ist ein Rebuild in
  einem Worktree, den niemand angefasst hat.
- **Nur mit bereitgestelltem DB-Dump** (`WorktreeDbSeed.staged`, hier in 42 von 43 Worktrees
  vorhanden). Ohne ihn bleibt der Schalter aus und sagt warum: das leere Volume seedet beim nächsten
  Start aus dem Dump — ohne Dump wäre es Datenverlust, nicht Aufräumen. (`appcache` ist bloss Cache
  und käme von selbst wieder.)
- **Erst stoppen, dann löschen**, und nur nach `exit 0`: solange Container existieren, hält Docker
  die Volumes fest („volume is in use"), und ein halb gelöschter Stack wäre schlimmer als ein
  laufender.
- **Eigene, zweite Bestätigung** mit den Artefakten **namentlich** — stoppen ist ein Knopfdruck
  rückgängig, ein gelöschtes Volume nicht. Vorgewählt ist „tief" nie.
- **Was es wirklich bringt** (gemessen mit `docker system df -v`, nicht geschätzt): die Volumes
  ~0,85 GB je Stack — 24,1 GB in 41 `appcache` und 9,9 GB in 41 `dbdata`, `appcache` ist also das
  Grössere. Die Images bringen **fast nichts**: `local/even-3563` steht mit 1,51 GB in der Liste,
  davon sind 1,32 GB **geteilte** Layer und nur 187 MB exklusiv; viele Worktree-Tags zeigen ohnehin
  auf dieselbe Image-Id (der „kein eigener Build"-Fall im Stack-Panel). Sie fliegen mit, weil ein Tag
  ohne Stack nur Verwirrung ist — nicht wegen der Platte.
- Rückweg nach „tief": `iwf stack build` + `iwf worktree start` (Zertifikat und DNS-Eintrag bleiben
  ja stehen) — beide sind im Worktree-Panel schon Knöpfe. Der grösste Einzelposten der Maschine liegt
  übrigens gar nicht hier, sondern im **Build-Cache** (20,7 GB, `docker builder prune`).

### DB-Seed und „Direktimport" (`StackSeeder`)

Zwei Wege, einen Dump in die Worktree-DB zu bekommen — beide **destruktiv**, und der Unterschied ist
nicht der, den die Knöpfe zuerst suggerierten:

| | Bereitstellen (Seed) | Direktimport |
|---|---|---|
| Stack | muss **gestoppt** sein | wird von iwf gestoppt und neu gestartet |
| Ablauf | Dump als `00_dev-dump.sql[.gz]` in den Init-Ordner, `<stack>_dbdata` löschen | `iwf db import-dump -f … --service db -y` |
| Import | beim **nächsten** Start | beim Neustart, den der Befehl selbst auslöst |

- **Der Befehl heisst `db import-dump`.** `iwf db import` gab es nie — der Aufruf endete mit
  „No such command 'import'. Did you mean 'import-dump'?" (Exit 2), also ohne dass irgendetwas
  passierte. Aufgefallen ist das erst im Betrieb; seither werden **alle** iwf-Aufrufe der App gegen
  die CLI gegengeprüft (14 Unterbefehle, nur dieser war falsch).
- **„Direktimport" importiert nicht in die laufende DB.** Nachgelesen in
  `project_compose.db_import_dump`: Dump in den Init-Ordner kopieren (vorhandene wandern nach
  `backup/`) → `compose down` → **`<projekt>_dbdata` löschen** → `compose up`; MySQL liest den Dump
  beim Hochlaufen. Damit ist der Unterschied zum Seed nur, **wer** den Neustart macht.
- **Es gibt keinen Snapshot.** Der Bestätigungsdialog versprach „iwf legt vorher automatisch einen
  Snapshot an (Wiederherstellung mit `iwf db snapshot restore`)" — falsch, und genau der Satz, auf
  dessen Zusicherung hin man den destruktiven Knopf drückt. `iwf db snapshot create` ist ein eigener
  Befehl, den niemand hier aufruft; der Dialog nennt ihn jetzt als Schritt, den man selbst tut.
- **Nach dem Befehl ist der Import nicht fertig**: `compose up` kommt zurück, sobald die Container
  laufen — den Dump liest MySQL danach ein, bei mehreren hundert MB dauert das. Die Meldung sagt
  deshalb „läuft im Container weiter" statt „abgeschlossen" und verweist auf das db-Container-Log.
- **`-f` prüft nicht auf Existenz** (`click.Path` ohne `exists=True`): mit einem falschen Pfad
  verschiebt iwf erst die bereitgestellten Dumps nach `backup/` und scheitert dann beim Kopieren.
  Deshalb prüft `StackSeeder` die Datei **vorher** selbst — und deshalb ist ein „Rauchtest" mit
  erfundenem Pfad keine harmlose Probe.
- Der Remote-Weg (`iwf server dbdump <env> <projekt> --compress`) lädt **gzip-komprimiert**: gzip
  läuft im entfernten Container, nur der komprimierte Strom geht über die Verbindung. iwf dokumentiert,
  dass ein unkomprimierter Dump von mehreren hundert MB dort still abbrechen kann.

## Session-Watchdog (Knopf rechts in der Leiste)

Liest die Claude-Transcripts unter `~/.claude/projects` — **alle**, nicht nur die aus Kanban — und
sucht, was immer wieder schiefgeht. Ergebnis ist eine Liste hinter dem Knopf rechts in der Leiste;
ein- und ausgeschaltet wird er in **Einstellungen › Watchdog**. Vorgabe: aus.

### Warum zweistufig

Jedes Transcript durch ein Modell zu schicken wäre langsam und teuer, reine Regex erkennt nie,
*warum* jemand dreimal nachfassen musste. Also:

1. **Lokal vorfiltern** (`WatchdogTranscriptScanner`, kostet nichts): ein Signal, wenn ein Werkzeug
   `is_error` meldet, ein Build/Test scheitert, eine Freigabe verweigert wurde, derselbe
   Werkzeugaufruf sich zum dritten Mal mit identischer Eingabe wiederholt, oder der Benutzer
   widersprochen hat (kurze Nachricht, Phrasenliste de/en).
2. **Verdichten** (`claude -p`, nur diese Ausschnitte): das Modell macht daraus wiederkehrende
   Muster mit Beleg und Empfehlung. Unter `minSignals` Signalen wird es gar nicht erst gefragt —
   es gäbe nichts zu verdichten, und der Aufruf wäre bezahlte Leerlaufzeit.

Gemessen: 8 Sessions → 137 Signale → 8 Befunde, $0.48 und ~2,5 min mit Sonnet 5. Das ist der
**erste** Lauf; danach rücken die Cursors vor und jeder weitere wertet nur aus, was sich geändert
hat. Deshalb steht die Vorgabe auf 60 Minuten und die Kosten des letzten Laufs stehen im Panel —
ein Hintergrund-Job, der unbemerkt Geld ausgibt, wäre ein schlechter Tausch für „praktisch".

### Zwei Sorten Befund

`verhalten` behebt man mit einer Regel (CLAUDE.md, Skill), `technik` mit Werkzeug oder Umgebung.
In einem Topf gelesen wäre beides nur „irgendwas lief schief", deshalb trennt die Kategorie sie und
das Panel filtert danach. Jeder Befund trägt Belege — wörtliche Transcript-Ausschnitte mit Session
und Projekt. Ohne die wäre ein Befund eine Behauptung über die eigene Arbeit, die niemand prüfen kann.

### Was über Läufe hinweg gilt

Die Identität eines Befunds ist `kategorie:slug(titel)` — Zeichensetzung und Gross-/Kleinschreibung
fallen weg. Das trägt nur, solange das Modell denselben Titel schreibt, und genau daran ist es
gescheitert (siehe „Derselbe Befund, neu benannt"). Ein
wiedergesehener Befund **sammelt an** (Anzahl, Belege, zuletzt) und bleibt **erledigt**, wenn er
erledigt war: einen bewusst abgehakten Befund wieder aufzumachen ist der schnellste Weg, so ein
Werkzeug unglaubwürdig zu machen.

### Derselbe Befund, neu benannt

Die Id kommt aus dem **Titel**, und den formuliert das Modell bei jedem Lauf neu. Ein aussortierter
Befund stand deshalb im nächsten Lauf als neuer wieder da. In der echten `watchdog.json` dieser
Maschine: 9 aussortierte, **4 davon zurück** unter anderem Namen —

| aussortiert | kam zurück als |
|---|---|
| iwf-CLI: Subkommando 'worktree' fehlt | iwf-CLI kennt Subcommand 'worktree' nicht |
| mv der Jira-Task-Datei schlägt fehl | start-task-Skill: mv der Task-Datei schlägt fehl |
| start-task-Skill sucht CLAUDE.md am falschen Ort | CLAUDE.md wird am falschen Pfad gesucht |
| Docker-Testumgebung für zba nicht bereit | Docker-Umgebung läuft nicht beim Testen |

Zwei Linien dagegen, weil die erste am Modell hängt:

1. **Der Bestand steht im Prompt** (`WatchdogPrompt.bekannteAbschnitt`): jeder bekannte Befund mit
   `id | offen|erledigt|aussortiert | titel`, dazu die Anweisung, bei demselben Muster **genau
   dessen `id`** zurückzugeben, und Aussortiertes gar nicht erst zu melden. `WatchdogParser`
   übernimmt eine gemeldete Id **nur, wenn der Prompt sie angeboten hat** — eine erfundene Id würde
   zwei verschiedene Befunde zu einem verschmelzen, und das ist schlimmer als ein doppelter Eintrag.
2. **Der Beleg als Fingerabdruck** (`WatchdogMerge.entschiedenerMitGleichemBeleg`): kennt der
   Bestand die Id nicht, zählt das **wörtliche Zitat**. Alle vier Paare oben teilen ihre Belege (1
   von 1, 3 von 4, 2 von 2, 1 von 2) — ein Transcript-Ausschnitt benennt denselben Vorfall, ein
   umformulierter Titel nicht. Gegengeprüft an den echten Daten: die Regel fängt **genau diese 4**
   von 11 offenen Befunden, keinen mehr.

Zusammengelegt wird nur mit **entschiedenen** Befunden (erledigt oder aussortiert) und nur bei
**gleicher Kategorie**. Ein offener bleibt offen, auch bei gleichem Beleg: dort ist ein doppelter
Eintrag lästig, ein stillschweigend verschluckter wäre schlimmer — und was der Mensch entschieden
hat, darf eine Umformulierung nicht rückgängig machen.

### Aussortieren (Papierkorb)

Nicht jeder Befund ist einer — das Modell verdichtet, und manches taugt nichts oder war nie gemeint.
Der Papierkorb je Zeile (🗑 rechts, Rechtsklick, oder „Aussortieren" im aufgeklappten Befund) nimmt
ihn aus der Liste.

- **`verworfen` ist ein Flag, kein Löschen.** Die Id ist stabil, also findet der nächste Scan
  dasselbe Muster wieder — ein bloss entfernter Eintrag stünde sofort erneut da, und zwar als „NEU".
  Verworfenes bleibt deshalb stehen und `WatchdogMerge.vereinen` trägt das Flag weiter, mit derselben
  Begründung wie bei `erledigt`.
- **Getrennt von „Erledigt"**, weil es etwas anderes sagt: „ich habe es behoben" gegen „das ist kein
  Befund". Beides in einen Topf zu werfen hiesse, die Erledigt-Liste als Ablage zu missbrauchen.
- **Der Papierkorb ist nachschaubar**, ein eigener Reiter (Symbol statt Wort — fünf ausgeschriebene
  Segmente passen nicht in die Panelbreite), und jede Zeile dort ist mit einem Klick zurückzuholen.
  Ein stiller Filter, aus dem nichts zurückkommt, wäre bei einem Mis-Klick ein dauerhaft
  unterdrücktes Muster.
- **Gezählt wird weiter**: im Papierkorb steht, wie oft das aussortierte Muster seither noch auftrat.
  Aussortiert heisst „zeig es mir nicht", nicht „es passiert nicht".
- **Endgültig leeren** geht über das ⋯-Menü. Danach darf derselbe Befund wiederkommen — er war ja nur
  deshalb draussen, weil er im Papierkorb stand.
- Der Zähler am Leisten-Knopf zählt Verworfenes nicht mit, und ein „NEU" verliert es beim
  Aussortieren.

Eine gescheiterte Auswertung rückt die Cursors **nicht** vor — sonst wären genau die Sessions, für
die das Modell nicht antwortete, beim nächsten Lauf stillschweigend übersprungen.

### Der Aufruf ist wirkungslos gehalten

`claude -p` läuft mit `--strict-mcp-config --mcp-config '{"mcpServers":{}}'` und verbotenen
Datei-/Ausführ-Werkzeugen. Ein Hintergrund-Lauf kann so kein Repo anfassen, nicht sekundenlang den
MCP-Stack laden und keine Freigabe-Abfrage auslösen; alles, worüber er urteilt, steht im Prompt.

### Ein Lauf dauert Minuten — und das Zeitlimit war kürzer

Der Spinner drehte sich scheinbar endlos. Er tat genau das, was er sollte, nur zu lange und
vergeblich: gemessen an den laufenden Prozessen braucht ein voller Lauf (25 Sessions, 160 Signale,
Sonnet) **5½ bis 6 Minuten**, das Limit stand auf **240 s**. Also schlug es jedes Mal zu, warf die
bezahlte Antwort weg und hinterliess im Stand `letzterFehler: "claude hat nach 240s nicht
geantwortet."` — vier Minuten Spinner nach jedem App-Start, für nichts.

- **Vorgabe 900 s**, einstellbar (`watchdog.timeoutSeconds`, 60–3600). Wem das zu lange dauert,
  stellt ein schnelleres Modell ein, nicht ein kürzeres Limit.
- **Der Modellaufruf läuft ausserhalb des Actors.** `scan` war synchron, der Unterprozess lief also
  minutenlang *im* `WatchdogScanner` — und damit stand alles still, was über ihn geht: `state()`,
  „Erledigt", „Aussortieren", „Papierkorb leeren". Wer während eines Laufs etwas wegwarf, sah nichts
  passieren.
- **Kein verwaistes Kind mehr.** Beim Beenden der App überlebte ein laufendes `claude -p` als Waise
  (beobachtet: `ppid=1`, 5½ Minuten Restlaufzeit, 300 MB) — sein Zeitlimit lebte im Elternprozess
  und starb mit ihm. `ClaudeHeadless` führt die laufenden Prozesse in einer Liste;
  `applicationWillTerminate` beendet sie.
- **Der Spinner sagt jetzt, worauf er wartet**: verstrichene Zeit daneben und ein ✕, das den Lauf
  abbricht (beendet den Unterprozess). Ein selbst abgebrochener Lauf zählt **nicht** als Fehlschlag —
  sonst stünde „Letzter Lauf gescheitert", weil jemand auf ✕ gedrückt hat.
- Geprüft gegen ein echtes Programm (`ClaudeHeadlessProcessTests`): das Limit greift, ein laufender
  Aufruf lässt sich von aussen beenden, und die Liste ist danach leer.

### Dateien

| Was | Wo |
|---|---|
| Signale aus dem Transcript | `KanbanCore/Watchdog/WatchdogSignal.swift` — Phrasenlisten, `is_error`, Wiederholungs-Fingerabdruck; liest Projekt + ersten Prompt im selben Durchgang mit |
| Transcripts finden | `KanbanCore/Watchdog/WatchdogTranscripts.swift` |
| Prompt / Parser / Vereinen | `KanbanCore/Watchdog/WatchdogAnalysis.swift` |
| `claude -p` aufrufen | `KanbanCore/Watchdog/ClaudeHeadless.swift` |
| Ein Lauf (Actor) | `KanbanCore/Watchdog/WatchdogScanner.swift` |
| Stand auf Platte | `KanbanCore/Watchdog/WatchdogStore.swift` → `<support>/watchdog.json` |
| Takt + angezeigter Stand | `Kanban/Watchdog/WatchdogModel.swift` (`@Observable`, hängt an `AppModel.watchdog`) |
| Panel + Knopf | `Kanban/Watchdog/WatchdogPanel.swift` |
| Einstellungen | `KanbanConfigSchema.watchdog` → `watchdog.*` in der Config (top-level wie `commit`, **kein** Modul — wandert nie nach Hermes) |

Der Knopf steht **immer** da, auch bei ausgeschaltetem Watchdog: ausgeblendet wäre er genau dann weg, wenn man ihn sucht, und
das Panel sagt selbst, wo geschaltet wird. Ein einzelner Lauf lässt sich dort auch ausgeschaltet
starten — der Schalter regelt den Hintergrund-Lauf, nicht den ausdrücklichen Wunsch.

Livelauf gegen die echten Transcripts (kostet Tokens, deshalb Opt-in):
`KANBAN_WATCHDOG_LIVE=1 swift test --filter WatchdogLiveTests`

## Architecture

```
Sources/
├── KanbanCore/            pure logic, no UI (testable)
│   ├── Claude/            AgentKind (Claude vs. Codex: Ort, Präfix, Startbefehl) +
│   │                      ClaudeAssets (Skill-Sets: Inventar im gepflegten Ordner, direkte
│   │                      Verlinkung ins Projekt bzw. in die Agent-Homes, keine Kopie) +
│   │                      ClaudeAssetName (kebab-case: Datei-, Symlink- und Aufrufname) +
│   │                      ClaudeProjectFile (generiert <repo>/.claude/project.json)
│   ├── Config/            KanbanConfig (eigene Config → AppConfig/ProjectConfig, repoDir +
│   │                      docsPath, Pfade normalisiert) + HermesImport (einmalige Übernahme) +
│   │                      HermesSync (Projekte zurück; absolute Pfade in Hermes' join-Form) +
│   │                      ConfigStore/KanbanConfigSchema (Settings) + ProjectRegistry/-Projection
│   ├── Domain/            Ticket, KanbanColumn, BoardMode (Sprint/Frei), TaskSection, Worktree,
│   │                      MergeRequestRef (provider-neutral, trägt nur `forge` als Herkunft),
│   │                      CardBadge, OpenProjects (welche Fenster beim Start aufgehen) +
│   │                      WindowTitles (wie die Fenster im Fenster-Menü heissen) +
│   │                      TicketRouting (welchem Projekt ein Ticket-Key gehört),
│   │                      EpicRef + EpicColors (Jira-Palette) + EpicResolution (Sub-Task erbt Epic)
│   ├── Jira/              JiraClient (Board/Sprints/Sprint-Issues/Worklog) + SprintSelection +
│   │                      JiraSolutionField (Feld „Lösung": editmeta-Auflösung, lesen, schreiben)
│   ├── Forge/             ForgeKind (gitlab/github: Beschriftung, `!`/`#`, Branch-Pfad) +
│   │                      ForgeRef/ForgeLocation + ForgeClient (was das Board von einer Forge braucht)
│   ├── GitLab/            GitLabClient (MR-Liste + Thread-Zähler + Approval) + models
│   ├── GitHub/            GitHubClient (PR-Liste + Zustands-Normalisierung + Reviews→Zustimmung +
│   │                      GraphQL-Thread-Zähler, fail-open)
│   ├── Modules/           die zwei Module in Hermes-Bauweise (siehe „Module")
│   │   ├── ModuleHTTPClient  Transport: Auth je Modul, Host-Guard, Paging
│   │   ├── Jira/             JiraFetch (Issue/Comments/Worklogs/…) + JiraModels +
│   │   │                     JiraFieldExtraction (Custom/Extra Fields, Meta) + ADFToMarkdown +
│   │   │                     JiraDuration (1d = 8h)
│   │   ├── GitLab/           GitLabFetch (MR/Notes/Discussions/Diffs/Schreibwege/Activity) +
│   │   │                     GitLabModels + MRDiffPosition (Zeile → old/new für Inline-Kommentare)
│   │   └── GitHub/           GitHubFetch (PR/Reviews/Kommentare/Files/Schreibwege) + GitHubModels +
│   │                         PRDiffPosition (Zeile → path/line/side/commit_id, Gegenstück zu MRDiffPosition)
│   ├── Git/               WorktreeScanner (`git worktree list --porcelain`) + BranchParent
│   │                      (Abzweig-Basis abgeleitet: Kandidaten = langlebige Branches + Worktree-
│   │                      Checkouts (Branches stacken!), Gewinner = wenigste fehlende Commits
│   │                      (min ahead); backup/*-Snapshots ausgeschlossen, Kind-Branches via ahead==0)
│   │                      + BranchStack (ganzer Wald fürs Hierarchie-Popover am ←-Chip: Commit-Menge
│   │                      jenseits der Basis je Branch, Parent = größte echte Teilmenge, leere
│   │                      Mengen (gemergt/frisch) adoptieren nichts; 1 rev-list pro Branch)
│   ├── Net/               HostGuardDelegate (drops auth on cross-host redirect) + APIError
│   ├── Stack/             DbSnapshots (iwf db snapshot: ~/.iwf-dev/snapshots/<stack>) +
│   │                      DockerStatusScanner + StackStatus (abgeleiteter Zustand eines Worktree-
│   │                      Stacks) + StackSweep (welche Stacks fertiger Tickets laufen) + StackSeeder
│   ├── Status/            WorkflowStatus precedence engine
│   ├── Tasks/             TaskFile (glob + H2 parser + status marker) +
│   │                      CommentThread (comments.json → Diskussion) + TaskFileWatcher +
│   │                      TaskAttachments (Task-Ordner des Tickets → KBNode-Baum) +
│   │                      CompoundFile (CFBF/OLE2-Leser) + OutlookMessage (.msg → Kopf/Körper) +
│   │                      LocalTickets (Ticketliste des freien Modus) + TicketNumber (numerisch
│   │                      sortieren) + MarkdownHTML (cmark-gfm) + HTMLToMarkdown (Rückweg für den
│   │                      WYSIWYG-Editor, Ziel-Vokabular = was MarkdownToADF kann)
│   ├── Watchdog/          Session-Watchdog: WatchdogSignal (lokaler Vorfilter über die Transcripts) +
│   │                      WatchdogTranscripts (finden) + WatchdogAnalysis (Prompt/Parser/Vereinen) +
│   │                      ClaudeHeadless (`claude -p`, ohne MCP und ohne Werkzeuge) +
│   │                      WatchdogScanner (ein Lauf) + WatchdogStore (watchdog.json)
│   └── Timing/            ClaudeTurn/-SessionTiming, ClaudeTurnAccumulator (transcript → turns),
│                          ClaudeTimingStore (incremental tail + cache), TimeFormatting +
│                          LiveTurn (tickt der ⏱-Zähler? Lebenszeichen + Alters-Schranke)
└── Kanban/                SwiftUI/AppKit app
    ├── App.swift          @main, WindowGroup(for: String.self) — Board-Fenster je Projekt-Key
    ├── ProjectWindows.swift  wer welches Projekt zeigt: Terminal-Klick und Benachrichtigung ins
    │                      richtige Fenster, offene Projekte merken, beim Start wieder aufmachen,
    │                      die Boards ins Fenster-Menü von macOS melden (`WindowTitles`)
    ├── AppModel.swift     @Observable: config/selection/sprints/issues/MRs/worktrees/columns/refresh
    ├── ContentView.swift  VStack(TopBar, HSplitView(Board, Detail)); nimmt den Projekt-Key der Szene
    ├── TopBar/            project picker + sprint/board picker (nur Sprint-Modus) +
    │                      Modus-Umschalter + 📚-Knopf (Knowledgebase, nur mit kbPath) +
    │                      +-Knopf (neues Fenster) + refresh + Σ Claude-Zeit
    ├── Knowledgebase/     KnowledgebaseView (Baum | Inhalt) + FileWebView (HTML-Artefakte)
    ├── Settings/          SettingsSheet (Kanban-Config) + SelectionStore (gemerkte Auswahl:
    │                      offene Projekte, zuletzt benutztes, Sprint/Modus je Projekt)
    ├── Board/             BoardSidebar / ColumnSection / TicketCard / EpicViews (Stripe + Pill) /
    │                      AvatarView (+ AvatarCache: Jira-Bilder mit Auth) / IssueTypeIcon /
    │                      NewTaskSheet (freier Modus)
    ├── Detail/            DetailView (Teiler beim Öffnen auf die Hälfte) + DetailSplit
    │                      (SplitFractionSetter: setzt den NSSplitView einmal — `idealHeight` wirkt nicht) /
    │                      TaskTabsView / TerminalTabsView (Maintree|Worktree|Claude…) /
    │                      WorktreeStackView (ein Panel, Ziel via StackTarget) /
    │                      StackSnapshotsView (iwf db snapshot: Liste/Restore/Create) /
    │                      TaskAttachmentsPanel (Task-Ordner: Baum + Quick-Look-Vorschau) /
    │                      SolutionSheet (WYSIWYG + Markdown-Ansicht) /
    │                      RichTextEditor (contenteditable in WKWebView) / MarkdownWebView +
    │                      HTMLTemplate (Stylesheet, lesend und beschreibbar) /
    │                      TerminalPlaceholderView / NewTaskConsoleView (Projekt-Console)
    ├── Watchdog/          WatchdogModel (Takt + angezeigter Stand, prozessweit `.shared`) +
    │                      WatchdogPanel (Liste + Knopf)
    ├── Stack/             StackSweepSheet („N Stacks stoppen": Liste + Bestätigung + Ausgabe)
    ├── Timing/            ClaudeTimeBadge (Karte) / ClaudeTimeChip + Popover (Turn-Liste + Buchen) / BookingSheet
    └── Theme/             MarkdownTheme (ported from kanban-code's chatMarkdownTheme) +
                            ForgeColors (Badge-Palette je Forge: GitLab-Tokens, GitHub Primer)
```

## Zwei Forges: GitLab **oder** GitHub je Projekt

Ein Projekt sagt, wo sein Code liegt, und bekommt danach dieselben Funktionen — Review- und
Done-Spalte, Badge mit Zustimmung und Thread-Zähler, die Karten ohne Ticketnummer, die Branch-Links
im Task-File, die Review-Skills. Nach aussen heisst es dort „PR" statt „MR"; darunter ist es
dasselbe Modell.

**Der Schnitt ist klein, und das liegt am Domänenmodell:** `MergeRequestRef` war schon
provider-neutral (`iid`, `title`, `state`, Branches, `webUrl`, `draft`, Threads, `approved`), und die
App ruft eine Forge an **genau einer** Stelle an (`AppModel.fetchMergeRequests`). Dazu kommt
`ForgeClient` mit drei Methoden — Liste, Thread-Zähler, Zustimmung. Mehr nicht: die Detail-Ebene
(Diffs, Notes, Schreibwege) hängt an keiner Oberfläche, weder hier noch dort, und aufs Protokoll
gehoben bliebe sie Vorrat.

**Normalisiert wird im Adapter, nicht in der Domäne.** Vier Dinge sind bei GitHub anders *gebaut*,
nicht bloss anders benannt:

| Sache | GitLab | GitHub |
|---|---|---|
| Auth | Header `PRIVATE-TOKEN` | `Authorization: Bearer …` + `Accept: application/vnd.github+json` |
| Zustand | `opened` / `merged` / `closed` | nur `open` / `closed`, dazu `merged_at` — **„merged" ist dort kein Zustand** |
| Zustimmung | `/approvals` → `approved_by` | `/pulls/{n}/reviews` → je Person der **letzte** Zustand, `APPROVED` zählt |
| Threads aufgelöst | `/discussions` → `resolved` je Note | **gibt es im REST nicht** — `isResolved` steht nur in GraphQL |

`GitHubClient` übersetzt deshalb `closed` + `merged_at != nil` → `"merged"` und `open` → `"opened"`,
und `WorkflowStatus`, `TicketMatching`, die Badges und die Spaltenlogik bleiben **unverändert**
(`WorkflowStatusTests` und `MRDiffPositionTests` laufen wörtlich weiter — das ist die Gegenprobe).
Wer GitHubs Vokabular durchreichte, müsste jede dieser Stellen anfassen und bräche dabei die Tests.

Was daraus im Einzelnen folgt:

- **Der Zustand ist der gefährliche Fall.** Ein *abgelehnter* PR ist `closed` ohne `merged_at` — ohne
  die Unterscheidung landete er in Done. Beide Richtungen sind getestet.
- **Fail-open bei den Threads.** Die GraphQL-Abfrage (`pullRequest.reviewThreads { isResolved }`)
  braucht ein Token mit Repo-Lesezugriff. Fehlt es, scheitert sie oder läuft in die Frist: dann
  **0/0, kein Badge, keine Spaltenwirkung**. Eine Karte wegen einer fehlenden Antwort zu verschieben
  wäre der schlechtere Ausgang.
- **Ratenbegrenzung.** 30 offene PRs sind 60 Abfragen im 45-Sekunden-Takt. Meldet GitHub einmal
  „rate limit" (403/429 **mit** Grund im Body — ein nacktes 403 ist ein fehlendes Recht), hört die
  Runde auf zu fragen (`RateLimitGate`) und wiederholt **nichts**; der nächste Takt versucht es neu.
- **Fork-PRs.** `head.label` trägt dort `owner:branch`. Verglichen wird mit lokalen Branches, also
  gilt `head.ref` — sonst fände `TicketMatching` den Worktree nicht.
- **Zwei Listen statt `state=all`.** `all` liefert eine Seite, und die besteht in einem Repo mit
  Historie aus geschlossenen PRs; die offenen fielen hinten heraus. Getrennt geholt bekommt jede
  Hälfte ihre Sortierung: offene vollständig, geschlossene nach letzter Änderung.
- **Branch-Links.** GitLab schiebt `/-/` zwischen Projekt und Ressource, GitHub nicht
  (`ForgeKind.branchPathSegment`). Ohne das ginge der Link im Task-File still ins Leere.
- **Web- gegen API-Basis.** Die Config hält `https://api.github.com`; Branch- und PR-Links brauchen
  `https://github.com`. Abgeleitet in `GitHubClient.webBaseURL(forApiBase:)`, ebenso die GraphQL-URL
  (bei GitHub Enterprise `/api/graphql` neben `/api/v3`).
- **Ein Projekt, eine Forge.** Steht derselbe Key in beiden Abschnitten, wirft `KanbanConfig.resolve`
  mit dem Namen des Projekts (`ambiguousForge`) statt sich eine auszusuchen. Der Projekt-Editor
  blendet den jeweils anderen Block aus, solange einer gesetzt ist.
- **Umbenannt wurde nichts.** `MergeRequestRef`, `MRReviewState`, `CardBadge.mergeRequest`, `iid`
  bleiben — `ChangeRequest`/`number` wäre neutraler, zöge aber durch die halbe Codebasis und durch
  bestehende Task-Files. Die Herkunft ist ein **Feld** (`MergeRequestRef.forge`), und nur die
  Anzeige hängt daran.
- **Stufe 1.** Gebaut ist der Listen-Weg (Board vollständig) **und** die Detail-Ebene als Modul
  (`Modules/GitHub`: PR, Reviews, Kommentare, Files, Schreibwege, `PRDiffPosition`). Angeschlossen
  an die Oberfläche ist die Detail-Ebene bei **keiner** der beiden Forges — das ist so entschieden,
  nicht vergessen.

## Module (Jira + GitLab + GitHub, nach Hermes' Vorbild in Swift)

Kanban betreibt die Module, die es braucht, **selbst** — portiert aus `hermes/mcp-server`
(`lib/http.js`, `modules/jira`, `modules/gitlab`); das GitHub-Modul hat dort kein Vorbild, weil
Hermes keins hat. Damit hängt kein Board-Feature mehr an einem laufenden Daemon.

- **Transport** (`ModuleHTTPClient`, Zwilling von `lib/http.js`): Auth-Resolver je Modul und
  Host-Guard. Zwei Abweichungen von Hermes, beide bewusst: es gibt **nur** den direkten Weg mit dem
  API-Token — Hermes' `extension`-Backend (Anfrage durch die Browser-Session seines Daemons, dort
  sogar Default) ist samt `backend`-Schalter und `HermesDaemon` entfernt, weil die App ohne
  Zusatzsoftware laufen soll. Und der Host-Guard prüft **vor** der Anfrage statt erst beim Redirect.
  Erlaubt ist eine **Menge** von Hosts, weil ein Jira-Projekt eine eigene `baseUrl` haben darf
  (`zvmsupport`) — mit einem einzigen Host verweigerte der Guard genau dieses Projekt.
- **Jira**: Board/Sprints/Sprint-Issues/Worklog-Buchung in `JiraClient`, alles Weitere in
  `Modules/Jira` — Issue mit `?expand=names` (Custom Fields mit Klarnamen, Attachments, Bilder),
  Kommentare, Worklog-Historie, `/myself`, Ticket-Summaries.
  - `MarkdownToADF` ist der Schreibweg (Feld „Lösung", siehe oben); geprüft gegen den Rückweg.
  - `ADFToMarkdown` ersetzt den alten `ADFFlattener`, der nur Textknoten aneinanderhängte:
    Überschriften, Listen, Tabellen und Links waren weg. Der Port wurde gegen das JS-Original
    **zeichengleich** verglichen (`ADFToMarkdownTests.testMatchesTheJavaScriptOriginal`).
  - **Tabellenzellen sind ein Inline-Kontext**, und daran sind drei Fehler gestorben (2026-09-01,
    aufgefallen an einem Confluence-Export; in **beiden** Konvertern behoben — Kanbans Port und
    Hermes' `lib/adf-to-markdown.js` — damit die Parität hält, mit denselben fünf Tests auf beiden
    Seiten):
    1. **Unterpunkte standen vor ihrem Elternpunkt.** `flattenList` schob die Kinder in die Liste,
       während die Zeile des Elternpunkts noch entstand. Gelesen hing damit jeder Unterpunkt am
       *vorherigen* Punkt — in einer Anforderungstabelle tauschten die Akzeptanzkriterien zweier
       Zeilen lautlos die Besitzer. Jetzt werden Kinder gesammelt und **nach** dem Elternpunkt
       angehängt.
    2. **Die Ebene lag in der Einrückung** (zwei Leerzeichen) — und die verschwindet, weil die
       Zelle mit ` <br> ` zusammengefügt wird und HTML führende Leerzeichen frisst. Deshalb jetzt
       **zwei Wege, je nach Inhalt**: eine flache Liste bleibt `- a <br> - b` (die Rohdatei bleibt
       lesbar, und das ist die Mehrheit der Zellen), eine **verschachtelte** wird zu inline
       `<ul>/<ol>`. Nur das trägt die Ebene wirklich — ein Ebenen-Zeichen wie „◦" wäre eine
       Verabredung, die der Leser kennen muss, `<ul>` ist Struktur. Markdown **innerhalb** der Tags
       wird weiter gerendert (Links, `**fett**`, `` `code` ``, escapte Pipes — gegen cmark-gfm
       geprüft), und PhpStorms Vorschau zeigt es als eingerückte Liste (am Original nachgesehen).
       Ein Punkt ohne Text und ohne Unterliste fällt weg, sonst stünde dort ein leeres
       Aufzählungszeichen.
    3. **Eine Überschrift wurde `#### x`** — in einer Zelle ist das keine Überschrift, sondern
       wörtlicher Text (so in PhpStorm zu sehen). Jetzt `**x**`.
  - **`status`-Knoten** (die Lozenge „In Arbeit“/„Hoch“/„Q3 2026“) kannte keiner der beiden
    Konverter; ein unbekannter Inline-Knoten liefert `""`, also sah die Zelle leer aus, obwohl die
    Seite einen Wert zeigt. Gegen die echte Seite geprüft: die Übersichtstabelle trägt jetzt
    Status, Priorität und „Eingeplant für“.
  - Jedes Feld wird an genau **einer** Stelle gerendert: Rich-Text und Identitäten bekommen einen
    eigenen Abschnitt (`customFields`), alles flach Darstellbare bleibt in der vollständigen Liste
    „Weitere Felder" (`extraFields`). Ohne diese Trennung stand dasselbe Feld doppelt da.
  - `JiraDuration`: Jiras Rechnung, **1d = 8h**, 1w = 5d; eine blosse Zahl sind Dezimalstunden.
  - `SmartLinks` löst auf, was eine Karte in Jira/Confluence zeigt: Ticket-Key **plus Summary plus
    Status**, Seitentitel statt Slug (`/pages/…/NonEHS+ab+2025+Verf+gung+…` hat den Umlaut nicht
    mehr). Aufgelöst wird **vor** dem Konverter, damit der synchron bleibt; das Ergebnis geht als
    `smartLinks`-Map in `ADFToMarkdown.convert`. Der Default dieser Option ist `nil`, und das ist
    die wichtige Hälfte: `JiraSolutionField` liest das Feld „Lösung" in einen Editor, dessen Inhalt
    über `MarkdownToADF` **zurück nach Jira** geht — käme dort eine gerenderte Karte an, ersetzte
    der Rückweg die lebende Karte durch eingefrorenen Text samt Status von heute. Confluence läuft
    über denselben Client wie Jira (gleiche Site, gleicher Host in der Allowlist, kontogebundenes
    Token); ein Confluence-Modul betreibt Kanban weiterhin nicht. Fail-open an jeder Stelle: ein
    fremder Host, ein fehlendes Recht, eine gelöschte Seite führen auf das alte Label zurück.
  - **Profilbilder** laufen über `ModuleHTTPClient.avatars()` — dieselbe Klasse, nur ohne
    `authHeaders` und mit den Hosts aus `AvatarHosts`. Ein eigener, handgeschriebener Abruf wäre
    eine zweite Stelle, an der eine Host-Allowlist gepflegt werden müsste. Ohne Zugangsdaten gibt
    es beim Umleiten auch nichts zu entziehen — und umgeleitet **wird**: Gravatar schickt auf
    `i1.wp.com` weiter, einen Host ausserhalb der Liste. Deshalb prüft die Allowlist den Einstieg,
    und begrenzt wird die Kette stattdessen über Länge (5) und Grösse (2 MB).
- **GitHub**: PR-Liste, Thread-Zähler und Zustimmung in `GitHubClient` (siehe „Zwei Forges" für die
  vier Unterschiede), der Rest in `Modules/GitHub` — einzelner PR inkl. `head.sha`, Reviews,
  allgemeine Kommentare (GitHub führt sie als **Issue**-Kommentare) und Review-Kommentare, geänderte
  Dateien mit `patch`, und die Schreibwege (Kommentar, Inline-Kommentar, Antwort).
  - `PRDiffPosition` ist das Gegenstück zu `MRDiffPosition`: **dieselbe Eingabe, andere Ausgabe** —
    `path` + `line` + `side` (+ `start_line`/`start_side`) statt `old_line`/`new_line`, dazu
    `commit_id` statt des SHA-Tripels. Den **Hunk-Parser teilen sich beide**
    (`MRDiffPosition.parseHunks`): ein Unified Diff ist ein Unified Diff, und zwei Kopien wären zwei
    Stellen, an denen dieselbe Zählung schiefgehen kann. Die Tests laufen gegen denselben Diff wie
    `MRDiffPositionTests`.
- **GitLab**: MR-Liste, Thread-Zähler und Approval bleiben in `GitLabClient` (das braucht das Board),
  der Rest in `Modules/GitLab` — einzelner MR inkl. `diff_refs`, Notes, Threads, Changes, Diffs,
  Aktivität, Projekt-Auflösung und die Schreibwege (Kommentar, Inline-Discussion, Antwort).
  - `MRDiffPosition` löst „Datei + Zeile" in GitLabs `old_line`/`new_line` auf: hinzugefügt → nur
    `new_line`, entfernt → nur `old_line`, Kontext → **beide**. Zeilen ausserhalb eines Hunks sind
    nicht kommentierbar (GitLab: 400), das scheitert deshalb **vor** dem POST und nennt die
    kommentierbaren Bereiche. Auch dieser Port wurde gegen `position.js` auf einem echten MR-Diff
    verglichen (5 Dateien, 19 Hunks, identisch).
- **`format.js` und `index.js` sind inzwischen portiert** — die frühere Entscheidung dagegen
  („MCP-Markdown; das macht bei uns die View") galt, solange Kanban Task-Files nur **las**. Mit dem
  nativen Export (`Tasks/JiraTaskGenerator` + `JiraTaskMarkdown`) schreibt Kanban sie selbst, und
  dafür braucht es genau diese beiden Stücke. **Hermes' `format.js` bleibt die Referenz**, Kanban
  folgt ihr: eine Änderung am Task-File-Format gehört auf **beide** Seiten, genauso wie bei
  `ADFToMarkdown` (siehe der Zellen-Fix vom 2026-09-01). Gehalten wird die Gleichheit von
  `JiraTaskMarkdownTests.testMatchesTheJavaScriptFormatter`, dessen Erwartungswert aus Hermes'
  Formatter selbst stammt — ohne ihn driften die Fassungen unsichtbar, weil jede Seite nur gegen
  sich selbst prüft und beide dabei grün bleiben.
- **Nicht portiert**, mit Absicht: der Anonymizer. Die ursprüngliche Begründung („Kanbans Daten
  bleiben im lokalen UI") **trägt seit dem nativen Export nicht mehr** — ein von Kanban erzeugtes
  Task-File liest anschliessend eine Claude-Session. Gebaut ist deshalb die **Naht**
  (`Tasks/TextScrubber`, ein Closure-Struct mit Pass-through-Default) an genau den Stellen, an denen
  Hermes `rescrub` anwendet; gefüllt wird sie im Folge-Task, der den Anonymizer nach Swift portiert.
  Bis dahin schreibt der native Weg Klartext — wie Hermes auch, solange dort `anonymize` aus ist.
- Ein Teil dieser Fläche hat vorerst **nur Tests als Aufrufer** (Kommentare, Worklog-Historie,
  MR-Threads, Diffs, Activity). Das ist so entschieden — die UI-Anbindung kommt pro Feature; es ist
  kein toter Code zum Aufräumen.

## Config (`~/Library/Application Support/Kanban/config.json`)

Kanbans **eigene** Datei und die einzige Wahrheit für die Module — dieselbe, in der auch `terminal`
steht (`KanbanConfig` + `KanbanSettingsStore` teilen sich `fileURL`). Die Form ist absichtlich die von
Hermes (`modules.<name>.…`): Kanban ist daraus entstanden, der Import ist damit eine reine Wertekopie,
und wer die eine Datei kennt, kennt die andere.

- **Fehlt die Datei, ist das kein Fehler** (`KanbanConfig.load` → `AppConfig.empty`): eine frische
  Installation hat keine Zugangsdaten und landet im `SetupView`. Nur eine vorhandene Datei mit
  kaputtem JSON wirft — stilles Ignorieren sähe aus wie Datenverlust. `isConfigured` = Jira-Zugang
  vollständig **und** mindestens ein Projekt.
- **Hermes-Übernahme** (`HermesImport`): existiert `~/.hermes/config.json` und hat Kanban noch keine
  `modules`, werden `basePath` sowie `modules.jira`/`modules.gitlab` **wortgleich** kopiert
  (GitHub bleibt aussen vor — Hermes hat kein solches Modul, es gäbe dort nichts zu übernehmen) (auch
  Schlüssel, die Kanban nie liest, wie `anonymize`). Einzige Ausnahme: **`backend` fliegt raus** —
  Hermes' Umschalter zwischen REST und Browser-Session täuschte eine Wahl vor, die es hier nicht gibt.
  Ein Bootstrap, **kein** Sync — sonst käme ein in Kanban geänderter Wert bei jedem Start zurück.
  Ohne Hermes passiert nichts, ohne Fehler.
- **Rückweg** (`HermesSync`, `hermes.syncProjects`, Default an): nach jedem Speichern wandert die
  **Projektliste** additiv in eine vorhandene Hermes-Config, damit hermes-CLI und MCP-Tools dieselben
  Projekte sehen. Tokens, URLs und Unbekanntes bleiben stehen, ein nur-Hermes-Projekt wird nie
  gelöscht. **Vorher gemischt** (`HermesSync.merged`): `ProjectProjection.apply` hält die Registry für
  den Owner *aller* Modul-Blöcke und löscht, was sie nicht kennt — ungemischt hätte jeder Sync Hermes'
  Confluence-, Vertec-, Jenkins- und DockerHub-Einträge weggeräumt (ein Test hat genau das gefangen).
  Der `github`-Block wandert dabei **mit** hinüber, obwohl Hermes kein GitHub-Modul hat: er ist
  additiv, stört dort nichts und dokumentiert, wo das Repo liegt. Eine Ausnahme dafür zu bauen
  hiesse, `ProjectProjection` eine zweite Liste zu geben, die niemand pflegt.

- `basePath` (e.g. `~/code`) — tasksPath + repoDir are resolved relative to it.
- `modules.jira.{baseUrl,email,apiToken}` +
  `modules.jira.projects.<key>.{prefix,tasksPath,baseUrl?,repoDir?,agent?,skillSet?}`
  (`agent` = `claude`|`codex`, siehe „Zwei Agents"; unbekannter Wert fällt auf `claude` zurück statt
  das Projekt lahmzulegen. `skillSet` = Name eines Sets im Bestand, leer = Standard-Set; ein Set,
  das es nicht gibt, fällt ebenfalls aufs Standard-Set zurück — mit Hinweis in der Übersicht).
  Auth = `Authorization: Basic base64(email:apiToken)`.
- `claude.setsPath` — Sammelordner für Skill-Sets: jeder Unterordner mit `skills/`/`rules/` ist
  eins (absolut, `~` oder relativ zum Basis-Pfad). Leer =
  `~/Library/Application Support/Kanban/claude`.
- `claude.sets.<name>.path` — ein einzeln registriertes Set, dessen Ordner überall liegen darf.
- `claude.defaultSkillSet` — das Skill-Set für jedes Projekt ohne eigene Wahl und für die
  Agent-Homes. Beides steht in einem Kanban-eigenen Abschnitt wie `commit` und `watchdog`, **kein**
  Modul (steht nicht in `ProjectProjection.moduleNames` und wandert nie nach Hermes). Fehlt
  `defaultSkillSet`, gilt das einzige vorhandene Set.
- `modules.gitlab.{baseUrl,apiToken}` + `modules.gitlab.projects.<key>.{path}`.
  **Same key** as the Jira project → mapping. Auth = `PRIVATE-TOKEN` header. API base `${baseUrl}/api/v4`.
- `modules.github.{baseUrl?,apiToken}` + `modules.github.projects.<key>.{path}` (`owner/repo`).
  Ebenfalls derselbe Key → Zuordnung. Auth = `Authorization: Bearer` plus
  `Accept: application/vnd.github+json`. `baseUrl` ist die **API**-Basis und hat eine Vorgabe
  (`https://api.github.com`); bei GitHub Enterprise steht dort `https://<host>/api/v3`, und Kanban
  leitet daraus GraphQL (`/api/graphql`) und die Web-Basis für Links ab. Ein Projekt gehört zu
  **einer** Forge — derselbe Key unter `gitlab` *und* `github` ist ein Konfigurationsfehler, den
  `KanbanConfig.resolve` mit dem Namen des Projekts meldet.
- `modules.knowledgebase.projects.<key>.path` — ebenfalls kein Modul: nur der Ort der
  Knowledgebase, den Kanban als `kbPath` in `.claude/project.json` durchreicht (absolut, `~` oder
  relativ zum Basis-Pfad; leer = kein `kbPath`). Kanban liest den Ordner selbst nicht, und die
  Sektion wandert **nicht** nach Hermes — sie steht deshalb nicht in
  `ProjectProjection.moduleNames`, sondern nur in `kanbanOnlySections`, damit ein gelöschtes
  Projekt keinen verwaisten Eintrag hinterlässt.
  Ist ein Pfad gesetzt, steht **neben der Modus-Umschaltung** ein 📚-Knopf, der die Knowledgebase
  im Fenster aufschlägt (siehe „Knowledgebase lesen"). Ohne `kbPath` gibt es den Knopf nicht;
  existiert der Ordner nicht, bleibt er sichtbar und die Ansicht nennt den fehlenden Pfad, statt
  sich zu verstecken.
- `modules.docker.projects.<key>.stack` — **kein Modul und keins von Hermes**: ob das Projekt einen
  eigenen Docker-Stack hat (siehe „Projekt-Typen"). Fehlt der Schlüssel, gilt `true`; geschrieben
  wird nur die Abschaltung. Wie `knowledgebase` in `kanbanOnlySections` statt `moduleNames`, damit
  er nicht nach Hermes wandert, ein gelöschtes Projekt aber keinen verwaisten Eintrag hinterlässt.
- `modules.confluence.projects.<key>.{space,path}` — **kein Modul, das Kanban betreibt**: nur der
  Space und der Ablageort der exportierten Seiten (`docsPath`, siehe „Task-Files und Doku liegen im
  Kanban-Ordner"). Ohne Eintrag gilt `~/Library/Application Support/Kanban/docs/<key>`. Ein Key ohne
  Jira-Projekt (`tech`) ist erlaubt und erscheint nicht auf dem Board.
- Local repo dir for worktree scan = `modules.jira.projects.<key>.repoDir` (absolut, `~` oder relativ
  zum Basis-Pfad) — seit dem Task-File-Umzug bei jedem Projekt gesetzt. Fehlt er, gilt weiter die
  Ableitung `basePath/<erstes Segment von tasksPath>`, die nur trägt, solange die Task-Files im Repo
  liegen. `tasksPath` und `path` dürfen absolut sein; `HermesSync` schreibt sie für Hermes um.

## Build / run

```bash
swift build
swift run Kanban    # Debug-Build aus .build/ — zum Ausprobieren, NICHT das, was installiert ist
swift test          # KanbanCore unit tests (WorkflowStatus engine)

swift run Kanban --migrate-jira-line --dry-run          # zeigt, was die Migration schriebe
swift run Kanban --migrate-jira-line                    # trägt die 🎫-Zeile in Bestands-Task-Files ein
swift run Kanban --migrate-jira-line --project even     # nur ein Projekt

./build-app.sh      # ausrollen: Release + Bundle + Signatur → /Applications/Kanban.app
```

**Ausgerollt wird ausschliesslich über `./build-app.sh`.** `swift run` startet eine zweite,
unsignierte Debug-Instanz und lässt `/Applications/Kanban.app` unberührt — wer eine Änderung dort
sehen will, muss das Skript laufen lassen. Das Skript installiert bewusst direkt nach
`/Applications` statt nach `dist/`: von dort wird die App gestartet, und unter dieser Bundle-ID
(`ch.iwf.kanban`) ist sie bei macOS für Benachrichtigungen registriert. Ein zweites Bundle mit
derselben ID hatte Launch Services und die Zustellung durcheinandergebracht, deshalb räumt das
Skript ein altes `dist/Kanban.app` mit weg.

## Signierung

`build-app.sh` signiert mit der Schlüsselbund-Identität
`Apple Development: c.hiller@iwf.ch (RVX4CBNYV9)`. `CODESIGN_IDENTITY` überschreibt sie, `-` erzwingt
ad-hoc. Fehlt die Identität (fremder Rechner, abgelaufenes Zertifikat), fällt das Skript mit einer
Meldung auf ad-hoc zurück statt abzubrechen; liegt ein abgelaufenes Zertifikat dieses Namens im
Schlüsselbund, nennt die Meldung das Ablaufdatum.

**Warum überhaupt.** Eine ad-hoc-Signatur hat keinen Team-Identifier. macOS hängt erteilte TCC-Rechte
dann an den cdhash — und der ändert sich bei jedem Bau. Genau deshalb war die
Benachrichtigungs-Erlaubnis nach jedem Rollout wieder weg, obwohl die ganze Attention-Kette
(Hook → Marker → Benachrichtigung → Karte) daran hängt. Mit einer echten Identität lautet die
Anforderung „Bundle-Id + Zertifikat":

```
designated => identifier "ch.iwf.kanban" and anchor apple generic
              and certificate leaf[subject.CN] = "Apple Development: c.hiller@iwf.ch (RVX4CBNYV9)"
              and certificate 1[field.1.2.840.113635.100.6.2.1]
```

Die überlebt jeden Neubau. **Einmalig** muss die Erlaubnis nach der Umstellung trotzdem neu erteilt
werden: Für macOS ist die erste signierte Fassung eine andere App als die ad-hoc-Fassung davor.

Der Team-Identifier in der Signatur lautet `C6X9XR4KXT` — das `OU` des Zertifikats. Das `RVX4CBNYV9`
im Zertifikatsnamen ist die Kennung des Entwicklers, nicht die des Teams; in `codesign -dv` taucht
es nur als `Authority` auf.

**Was das Skript beim Signieren tut:**

- Kein `--deep` (Apple rät ausdrücklich davon ab): verschachtelte Bundles zuerst, die App zuletzt.
  Die beiden Ordner, die SwiftPM ablegt (`Kanban_Kanban.bundle`, `SwiftTerm_SwiftTerm.bundle`),
  sind reine Ressourcen-Ordner ohne `Info.plist` — codesign erkennt sie nicht als Bundle und die
  App-Signatur versiegelt sie als gewöhnliche Ressourcen. Geprüft werden sie trotzdem: Eine
  nachträgliche Änderung darin lässt `codesign --verify --strict` auffliegen.
- Hardened Runtime (`--options runtime`) mit `Kanban.entitlements`. Die Datei ist bewusst leer und
  vor allem **ohne** `com.apple.security.app-sandbox`: Kanban startet tmux, `claude`, `git` und
  `docker`, liest `~/code` und `~/.claude` und hängt an einem PTY — eine Sandbox schnitte das ab.
  Warum kein einziges Entitlement nötig ist, steht begründet in der Datei selbst.
- `--timestamp`, mit hörbarem Rückfall auf `--timestamp=none`, wenn der Zeitstempel-Dienst nicht
  erreichbar ist (kein Netz). Ein anderer codesign-Fehler fällt dagegen durch, statt als
  Netz-Problem ausgegeben zu werden.
- Danach `codesign --verify --strict`. Schlägt das fehl, wird das Bundle entfernt und der Bau bricht
  ab, statt eine kaputte App in `/Applications` zu hinterlassen.

**Für die Weitergabe reicht das nicht.** `spctl -a -t exec` sagt `rejected`; mit einem
Entwicklungs-Zertifikat ist das der erwartete Befund, deshalb gibt das Skript die Auskunft nur aus
und bricht nicht ab.

**Der Notarisierungs-Schritt steht schon im Skript, schläft aber.** ZIP via `ditto` →
`xcrun notarytool submit --wait` → `xcrun stapler staple` läuft nur an, wenn `CODESIGN_IDENTITY`
mit `Developer ID Application` beginnt — Apple notarisiert keine Entwicklungs-Signaturen. Zum
Aufwecken braucht es dreierlei:

1. Apple-Developer-Programm (99 $/Jahr) und daraus ein **Developer ID Application**-Zertifikat im
   Schlüsselbund.
2. Ein notarytool-Profil im Schlüsselbund — **nicht** im Repo:
   `xcrun notarytool store-credentials kanban-notary --apple-id <apple-id> --team-id <team-id> --password <app-spezifisches Passwort>`.
   Ein anderer Profilname geht über `NOTARY_PROFILE`.
3. Den Bau mit dieser Identität starten:
   `CODESIGN_IDENTITY="Developer ID Application: … (…)" ./build-app.sh`.

Scheitert die Notarisierung, warnt das Skript und läuft weiter — die App in `/Applications` ist
signiert und läuft hier, sie taugt nur nicht zur Weitergabe. Gelingt sie, sagt `spctl` danach
`accepted / source=Notarized Developer ID`.

Offen bleibt dafür die Versionsnummer: `CFBundleVersion` und `CFBundleShortVersionString` stehen in
`build-app.sh` fest auf `1.0`. Für eine notarisierte Auslieferung müssten sie je Bau steigen, sonst
ist eine neuere Fassung von der älteren nicht zu unterscheiden.

## Not in step 1 (deliberately)

- The embedded terminal + persistent (tmux) sessions — own follow-up step; only a placeholder zone here.
- Writing to Jira/GitLab, drag&drop between columns, own kanban config UI.
