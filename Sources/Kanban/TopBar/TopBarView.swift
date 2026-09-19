import AppKit
import SwiftUI
import KanbanCore

/// Native window-toolbar content (project + sprint pull-downs, status, refresh). Placing plain
/// `Menu`s in a real `.toolbar` gives them the native macOS pull-down look — the same approach as
/// the sibling kanban-code app — instead of a custom bar with styled controls.
struct TopBarToolbar: ToolbarContent {
    var model: AppModel

    /// Was das Projekt der Kopfzeile vorgibt — fast immer `.none`.
    private var appearance: ProjectAppearance { model.selectedProject?.appearance ?? .none }

    /// Die Textfarbe der Zeile, sofern gesetzt. Siehe `chrome(_:)` dazu, worauf sie **nicht** wirkt.
    private var headerForeground: Color? {
        appearance.headerForeground.flatMap(Color.init(hex:))
    }

    /// Färbt ein Element der Leiste ein — aber nur, wenn eine Farbe konfiguriert ist. Ohne Eintrag
    /// bleibt die Ansicht unangetastet, statt auf `.primary` gesetzt zu werden: die Leiste ist voll
    /// von Elementen, die ihre Farbe absichtlich selbst wählen (`.secondary` an den Zählern).
    @ViewBuilder
    private func chrome<V: View>(_ view: V) -> some View {
        if let headerForeground { view.foregroundStyle(headerForeground) } else { view }
    }

    var body: some ToolbarContent {
        // Bild und Projektauswahl in **einer** Gruppe: das Bild steht links daneben, und
        // `ToolbarContent` nimmt nur zehn Einträge — die sind vergeben.
        ToolbarItemGroup(placement: .navigation) {
            projectImage
            chrome(projectMenu)
        }
        ToolbarItem(placement: .navigation) { chrome(sprintMenu) }
        // Gruppe statt drei Einträgen: `ToolbarContent` nimmt nur zehn Elemente, und die Leiste ist
        // voll. Alle drei beantworten dieselbe Frage — was füllt gerade das Fenster: Sprint/Frei
        // sagt, woher die Karten kommen, die Suche siebt sie, der Knowledgebase-Knopf tauscht das
        // Board ganz aus.
        ToolbarItemGroup(placement: .navigation) {
            modePicker
            chrome(autoModeButton)
            searchField
            chrome(reihenfolgeButton)
            chrome(knowledgebaseButton)
        }
        // Ohne `chrome`: der Status färbt sich selbst — orange heisst Warnung. Die Textfarbe des
        // Projekts darüberzulegen würde genau das Signal löschen, wegen dem er da steht.
        ToolbarItem(placement: .navigation) { statusView }
        ToolbarItem(placement: .navigation) { sprintTimeView }
        // Gruppe statt zwei Einträge: `ToolbarContent` nimmt nur zehn Elemente, und beide sind
        // ohnehin Aufräum-Knöpfe, die je nach Lage ganz verschwinden.
        ToolbarItemGroup(placement: .primaryAction) {
            bookButton
            stackSweepButton
        }
        // Gruppe statt zweier Einträge — das Zehner-Budget von `ToolbarContent` ist voll. Passt
        // auch inhaltlich: beide holen frischen Stand, der eine für dieses Brett, der andere für
        // eines, das noch aussteht.
        ToolbarItemGroup(placement: .primaryAction) {
            chrome(newWindowButton)
            chrome(refreshButton)
        }
        ToolbarItem(placement: .primaryAction) { watchdogButton }
        ToolbarItem(placement: .primaryAction) { chrome(dataFolderButton) }
        ToolbarItem(placement: .primaryAction) { chrome(settingsButton) }
    }

    /// Das Projektbild, links neben der Projektauswahl — auf Zeilenhöhe skaliert, Seitenverhältnis
    /// erhalten. Ohne konfiguriertes (oder mit verschwundenem) Bild entsteht gar keine Ansicht: eine
    /// leere Fläche neben der Auswahl wäre ein Platzhalter für nichts.
    ///
    /// Gelesen wird bei jedem Aufbau von der Platte. Das ist hier in Ordnung — AppKit hält geladene
    /// Bilder selbst vor, und die Datei wechselt nur, wenn jemand in den Einstellungen eine andere
    /// wählt. SVG und PDF kommen als Vektor an und bleiben auf jeder Zeilenhöhe scharf.
    @ViewBuilder
    private var projectImage: some View {
        if let bild = NSImage.projectImage(atPath: appearance.imagePath) {
            Image(nsImage: bild)
                .resizable()
                .scaledToFit()
                .frame(height: 18)
                .accessibilityLabel(model.selectedProject?.key ?? "Projekt")
        }
    }

    /// Der Auto-Modus: eine **Meldung**, wenn die Arbeit an einem Ticket beginnt, das laut Plan noch
    /// wartet (`start-task`/`solve-task` auf einer gesperrten Karte).
    ///
    /// Auf den Karten steht dazu bewusst **nichts**. Ein ⛔ zwischen 📄/🌳/🔀 beantwortet keine
    /// Frage, die man beim Blick aufs Brett stellt — „was hält das auf" gehört in die
    /// Reihenfolge-Ansicht, wo geordnet wird. Der Auto-Modus ist deshalb unsichtbar, bis er etwas
    /// zu sagen hat.
    ///
    /// Ohne Jira gibt es den Knopf nicht: ohne Backlog gibt es keine Reihenfolge, die man führen
    /// könnte.
    @ViewBuilder
    private var autoModeButton: some View {
        if model.selectedProject?.usesJira == true {
            Button {
                model.setAutoMode(!model.autoMode)
            } label: {
                Image(systemName: model.autoMode ? "play.circle.fill" : "play.circle")
            }
            .help(model.autoMode
                  ? "Auto-Modus aus — keine Meldung mehr beim Vorziehen"
                  : "Auto-Modus an — meldet, wenn Arbeit an einem Ticket beginnt, das laut Plan noch wartet")
        }
    }

    /// Die Reihenfolge als Liste, per Ziehen umsortierbar.
    ///
    /// Auch ohne Jira: dort wird die Reihenfolge lokal gemerkt (`LocalOrder`). Ein kleines Projekt
    /// ordnet man schneller von Hand, als ein Orchestrator seine Beschreibungen liest.
    private var reihenfolgeButton: some View {
        Button {
            model.toggleReihenfolge()
        } label: {
            Image(systemName: model.reihenfolgeOffen ? "list.number.rtl" : "list.number")
        }
        .help(model.reihenfolgeOffen
              ? "Zurück zum Board"
              : (model.reihenfolgeQuelle == .jira
                 ? "Reihenfolge öffnen — Ziehen schreibt den Rang nach Jira"
                 : "Reihenfolge öffnen — Ziehen wird lokal gemerkt"))
    }

    /// Schaltet die Knowledgebase des Projekts auf: Ordnerbaum links, Datei rechts, anstelle von
    /// Board und Detail. Derselbe Knopf schaltet zurück, und der gefüllte Buchrücken sagt, welcher
    /// Zustand gerade gilt.
    ///
    /// Ohne konfigurierten `kbPath` gibt es den Knopf gar nicht, wie bei den Aufräum-Knöpfen: eine
    /// dauerhaft graue Schaltfläche wäre nur Rauschen. Ist der Pfad gesetzt, der Ordner aber nicht
    /// da, bleibt der Knopf und die Ansicht **sagt**, was fehlt — das ist der Fall, den man beheben
    /// will, nicht einer, den man verstecken sollte. (In den Finder führt der Ordner-Knopf **in**
    /// der Ansicht; der Ordner-Knopf rechts in der Leiste öffnet Kanbans Datenordner, anderer Ort.)
    @ViewBuilder
    private var knowledgebaseButton: some View {
        if let path = model.selectedProject?.kbPathAbsolute {
            Button {
                model.toggleKnowledgebase()
            } label: {
                Image(systemName: model.knowledgebaseOpen ? "books.vertical.fill" : "books.vertical")
            }
            .help(model.knowledgebaseOpen
                  ? "Zurück zum Board"
                  : "Knowledgebase öffnen: \(path)")
        }
    }

    /// Wählt das Projekt **dieses** Fensters — wie immer. Ein neues Fenster gibt es über den
    /// +-Knopf, nicht als Nebenwirkung der Auswahl. Das Fenstersymbol sagt, dass ein Projekt auch in
    /// einem anderen Fenster steht; wer es dort haben will, wechselt dorthin.
    private var projectMenu: some View {
        Menu(model.selectedProject?.key.uppercased() ?? "Projekt") {
            ForEach(model.projects) { project in
                Button {
                    model.selectProject(project)
                } label: {
                    if project.id == model.selectedProject?.id {
                        Label(project.key.uppercased(), systemImage: "checkmark")
                    } else if ProjectWindows.shared.zeigtProjekt(project.key) {
                        Label(project.key.uppercased(), systemImage: "macwindow")
                    } else {
                        Text(project.key.uppercased())
                    }
                }
            }
            profilAbschnitt
        }
        .disabled(model.projects.isEmpty && model.profile.count < 2)
        .help("Projekt und Profil wählen")
    }

    /// Die Profile — im Projekt-Menü, nicht als eigener Knopf.
    ///
    /// Inhaltlich gehören sie hierher: Profil und Projekt sind dieselbe Art Auswahl, das Profil nur
    /// eine Ebene höher. Praktisch geht es auch gar nicht anders — `ToolbarContent` nimmt zehn
    /// Einträge, und die Leiste steht genau auf zehn.
    ///
    /// Der Abschnitt bleibt weg, solange es **ein** Profil gibt: eine Auswahl mit einem Eintrag ist
    /// keine Auswahl, sondern Erklärungsbedarf. Angelegt werden Profile in den Einstellungen.
    @ViewBuilder
    private var profilAbschnitt: some View {
        if model.profile.count > 1 {
            Divider()
            Section("Profil") {
                ForEach(model.profile) { profil in
                    Button {
                        model.profilWechseln(zu: profil)
                    } label: {
                        if profil.slug == model.aktivesProfil?.slug {
                            Label(profil.name, systemImage: "checkmark")
                        } else {
                            Text(profil.name)
                        }
                    }
                }
            }
        }
    }

    /// Sprint- oder freier Modus. Steht direkt neben der Sprint-Auswahl, die im freien Modus
    /// verschwindet — dort gibt kein Sprint vor, was auf dem Board steht.
    ///
    /// Bei einem Projekt **ohne Jira-Anbindung** entfällt der Umschalter ganz: es gibt nur den
    /// freien Modus. Ein ausgegrauter Umschalter wäre die falsche Auskunft — er sähe aus wie „gerade
    /// nicht verfügbar", dabei ist es eine Eigenschaft des Projekts.
    @ViewBuilder
    private var modePicker: some View {
        if model.selectedProject?.usesJira != false {
            Picker("Modus", selection: Binding(get: { model.boardMode },
                                               set: { model.setBoardMode($0) })) {
                ForEach(BoardMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(model.selectedProject == nil)
            .help("Sprint: die Tickets des gewählten Jira-Sprints. Frei: alles, was lokal existiert.")
        }
    }

    /// Sucht über Ticketnummer **und** Titel und siebt damit die Karten links (`visibleColumns`).
    /// Steht rechts neben Sprint/Frei, weil beide dasselbe bestimmen: was links steht.
    ///
    /// Aussehen und Tastatur wie die Suchleiste der Markdown-Ansichten (`MarkdownFindBar`) — esc
    /// leert. Trefferzähler und ⏎-Sprung fehlen bewusst: hier *ist* das Ergebnis die Liste links,
    /// es gibt nichts anzuspringen.
    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Ticket", text: Binding(get: { model.ticketSearch },
                                              set: { model.ticketSearch = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 140)
                .onKeyPress(.escape, phases: .down) { _ in
                    guard !model.ticketSearch.isEmpty else { return .ignored }
                    model.ticketSearch = ""
                    return .handled
                }
            if !model.ticketSearch.isEmpty {
                Button {
                    model.ticketSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Suche leeren (esc)")
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
        .fixedSize()
        .disabled(model.selectedProject == nil)
        .help("Karten links nach Ticketnummer oder Titel filtern — mehrere Begriffe gelten zusammen")
    }

    @ViewBuilder
    private var sprintMenu: some View {
        if model.boardMode == .sprint {
            sprintMenuContent
        }
    }

    /// Sprint **oder** Board: dieselbe Frage, deshalb derselbe Picker. „Ganzes Board" steht immer
    /// zuunterst und ist bei einem Projekt ohne aktiven Sprint (CORE: 50 Sprints, alle geschlossen)
    /// die Vorauswahl.
    @ViewBuilder
    private var sprintMenuContent: some View {
        Menu(model.selectedChoice?.label ?? "—") {
            ForEach(SprintSelection.choices(model.sprints)) { choice in
                choiceButton(choice)
            }
        }
        .disabled(model.board == nil)
        .help("Sprint oder ganzes Board wählen")
    }

    private func choiceButton(_ choice: SprintChoice) -> some View {
        Button {
            model.selectChoice(choice)
        } label: {
            if choice == model.selectedChoice {
                Label(choice.label, systemImage: "checkmark")
            } else {
                Text(choice.label)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if model.isLoadingSprints || model.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(model.isLoadingSprints ? "Sprints…" : "Aktualisiere…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if let notice = model.startWorkNotice {
            // Frischer als alles andere hier: das Ergebnis der Jira-Nachführung zu dem Command, den
            // der Benutzer gerade abgesetzt hat. Erfolg räumt sich nach ein paar Sekunden selbst
            // weg, eine Warnung bleibt stehen (siehe `AppModel.startJiraWork`).
            Label(notice.text,
                  systemImage: notice.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(notice.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .help(notice.text)
        } else if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).lineLimit(1).help(error)
        } else if !model.selectedProjectHasForge {
            Label("keine Forge", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .help("Ohne GitLab- oder GitHub-Zuordnung bleiben Review und Done leer.")
        }
    }

    /// Cumulated Claude time over every card of the sprint (⏱ per prompt+answer, summed).
    @ViewBuilder
    private var sprintTimeView: some View {
        let seconds = model.sprintClaudeSeconds
        if seconds > 0 {
            // .titleAndIcon: a toolbar Label renders icon-only by default, which would hide the total.
            Label(TimeFormatting.compact(seconds), systemImage: "clock")
                .labelStyle(.titleAndIcon)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .help(model.selectedChoice?.sprint != nil
                      ? "Kumulierte Claude-Zeit aller Tickets in diesem Sprint"
                      : "Kumulierte Claude-Zeit aller Tickets auf dem Board")
        }
    }

    /// Opens the end-of-day batch-booking sheet. Shows the open (unbooked) total as its label so
    /// there's a visible reason to click; hidden entirely when nothing is open.
    @ViewBuilder
    private var bookButton: some View {
        let open = model.totalOpenToBookSeconds
        if open > 0 {
            Button {
                model.bookingSheetPresented = true
            } label: {
                Label("\(TimeFormatting.compact(open)) buchen", systemImage: "clock.badge.checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .help("Offene Claude-Zeit als Jira-Worklog buchen (auf 15 min aufgerundet)")
        }
    }

    /// „N Stacks stoppen": die laufenden Stacks fertiger Tickets (Review/Done). Zeigt nur die
    /// fertigen im Zähler — die noch arbeitenden Stacks sind kein Aufräum-Anlass, stehen im Sheet
    /// aber trotzdem. Ganz weg, wenn nichts fertig läuft: dann gibt es keinen Grund zu klicken.
    @ViewBuilder
    private var stackSweepButton: some View {
        let finished = model.stackSweep.finished.count
        // `model.hasStack` steht mit da, obwohl der Zähler ohne Stack ohnehin 0 bleibt: der Knopf
        // soll an derselben Bedingung hängen wie die Reiter, nicht an einer Nebenwirkung.
        if model.hasStack, finished > 0 {
            Button {
                model.openStackSweep()
            } label: {
                Label("\(finished) Stacks stoppen", systemImage: "square.stack.3d.down.right")
                    .labelStyle(.titleAndIcon)
            }
            .help("Docker-Stacks von Tickets in Review/Done stoppen — Worktree, Branch und "
                  + "DB-Volume bleiben (iwf worktree stop)")
        }
    }

    /// Ein weiteres Board-Fenster aufmachen — das erste Projekt, das noch keines hat.
    ///
    /// Der kurze Weg neben dem Projekt-Menü: dort wählt man ein bestimmtes Projekt, hier will man
    /// bloss noch ein Brett daneben. Steht jedes Projekt schon in einem Fenster, ist der Knopf aus —
    /// ein zweites Fenster auf dasselbe Board gibt es nicht.
    @ViewBuilder
    private var newWindowButton: some View {
        let naechstes = ProjectWindows.shared.naechstesOhneFenster(projekte: model.projects)
        Button {
            if let naechstes { ProjectWindows.shared.oeffnen(naechstes.key) }
        } label: {
            Image(systemName: "plus")
        }
        .disabled(naechstes == nil)
        .help(naechstes.map { "Neues Fenster: \($0.key.uppercased())" }
              ?? "Jedes Projekt hat bereits ein Fenster")
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Aktualisieren")
        // Im freien Modus gibt es keinen Sprint, an dem das hängen könnte.
        .disabled((model.boardMode == .sprint && model.selectedSprint == nil) || model.isRefreshing)
    }

    /// Die Befundliste des Session-Watchdogs. Steht immer da, auch wenn der Watchdog aus ist:
    /// er ist der Einstieg, und das Panel sagt selbst, dass geschaltet wird in Einstellungen ›
    /// Watchdog — ausgeblendet wäre er genau dann weg, wenn man ihn sucht.
    /// Prozessweit einer, deshalb in jedem Fenster derselbe Stand — er scannt alle Sessions, nicht
    /// die des angezeigten Projekts.
    private var watchdogButton: some View {
        WatchdogToolbarButton(watchdog: .shared)
    }

    /// Öffnet Kanbans Datenordner (tasks/, claude/, config.json) in PhpStorm.
    private var dataFolderButton: some View {
        Button {
            let dir = KanbanPaths.root
            StatusLinkOpener.open(URL(string: StatusLinks.ideURL(forPath: dir.path))!)
        } label: {
            Image(systemName: "folder")
        }
        .help("Kanban-Datenordner in PhpStorm öffnen (~/Library/Application Support/Kanban)")
    }

    private var settingsButton: some View {
        Button {
            model.settingsPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .help("Einstellungen (~/.hermes/config.json)")
    }
}
