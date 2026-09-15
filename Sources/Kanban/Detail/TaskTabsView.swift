import AppKit
import SwiftUI
import KanbanCore

/// Dynamic native tab bar (one tab per H2 section) + rendered markdown content.
struct TaskTabsView: View {
    @Bindable var model: AppModel
    @State private var selectedTitle: String?
    @State private var copiedPath = false
    /// Der Dateibaum des Task-Ordners, links eingeschoben (siehe `attachmentsButton`).
    @State private var showAttachments = false
    @State private var attachmentsExpanded: Set<String> = []
    /// Suche im Task-File: Eingabe, gefundene Stellen und welche davon gerade angesprungen ist.
    /// Die Trefferliste ist **gemerkt**, nicht bei jedem Rendern neu gerechnet — dafür muss jede
    /// Sektion durch den Markdown-Renderer (siehe `TaskSearch.visibleText`).
    @State private var query = ""
    /// Der sichtbare Text aller Tabs (siehe `TaskSearchIndex`) — gebaut, sobald **gesucht** wird,
    /// nicht bei jedem Inhaltswechsel: ihn zu bauen kostet ~20 ms auf dem grössten Task-File dieser
    /// Maschine, und der Task-File-Watcher schlägt auch an, wenn gar niemand sucht.
    @State private var searchIndex = TaskSearchIndex(sections: [])
    @State private var searchIndexStale = true
    @State private var hits: [TaskSearchHit] = []
    @State private var hitIndex = 0
    /// Steigt bei jedem Sprung, damit auch derselbe Treffer erneut angesprungen werden kann.
    @State private var searchToken = 0

    private var sections: [TaskSection] { model.displaySections }

    private var current: TaskSection? {
        sections.first { $0.title == selectedTitle } ?? sections.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: model.selectedTicketKey) {
            selectedTitle = nil
            showAttachments = false
            attachmentsExpanded = []
            query = ""
            hits = []
            hitIndex = 0
            searchIndexStale = true
        }
        .onChange(of: query) { sucheAuffrischen(springen: true) }
        // Das Task-File ändert sich unter der Suche (Watcher, neues Review) — dann stimmt weder der
        // Index noch die Trefferliste. Neu bauen, aber **nicht** springen: der Blick soll bleiben,
        // wo er ist.
        .onChange(of: model.displaySections) {
            searchIndexStale = true
            if !query.isEmpty { sucheAuffrischen(springen: false) }
        }
        // Ein Ticket ohne Anhänge hat keinen Baum zu zeigen — dann schliesst sich das Panel selbst,
        // statt als leere Spalte stehen zu bleiben.
        .onChange(of: model.taskAttachments.isEmpty) { _, isEmpty in
            if isEmpty { showAttachments = false }
        }
        .sheet(isPresented: $model.solutionSheetPresented) {
            SolutionSheet(model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(model.selectedTicketKey ?? "")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            if !model.claudeCommands.isEmpty { commandsMenu }
            if let file = model.taskFile {
                Text(file.url.lastPathComponent)
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            if !sections.isEmpty { sucheFeld }
            // The epic written out, right after the task file / feature branch.
            if let epic = model.selectedEpic { EpicPill(epic: epic) }
            Spacer()
            // Links vom Commit: das Jira-Feld „Lösung". Rot umrandet, wenn das Ticket in Review oder
            // Done steht und das Feld leer ist — dann fehlt genau das, was die Reviewer lesen wollen.
            if model.canEditSolution { solutionButton }
            // Überall wo es etwas zu committen gibt (Task-File oder Worktree) — links neben der Zeit.
            if model.canCommit { commitButton }
            if let timing = model.selectedTiming, let key = model.selectedTicketKey {
                ClaudeTimeChip(model: model, ticketKey: key, timing: timing,
                               runningSince: model.runningTurnStart(ticketKey: key))
            }
            if model.canEditStatus { statusMenu }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: - Suche im Task-File

    /// Das Feld rechts neben dem Dateinamen. Gesucht wird über **alle** Tabs — Status, Review und
    /// jede H2-Sektion —, und ein Sprung wechselt dafür den Tab.
    private var sucheFeld: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Suchen", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 130)
                // ⏎ weiter, ⇧⏎ zurück — wie die Suche in jedem Editor.
                .onSubmit { weiter(1) }
                .onKeyPress(.return, phases: .down) { druck in
                    guard druck.modifiers.contains(.shift) else { return .ignored }
                    weiter(-1)
                    return .handled
                }
                .onKeyPress(.escape, phases: .down) { _ in
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
            if !query.isEmpty {
                Text(trefferText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(hits.isEmpty ? Color.red : Color.secondary)
                    .fixedSize()
                if !hits.isEmpty {
                    schrittKnopf("chevron.up", "Vorheriger Treffer (⇧⏎)") { weiter(-1) }
                    schrittKnopf("chevron.down", "Nächster Treffer (⏎)") { weiter(1) }
                }
                schrittKnopf("xmark.circle.fill", "Suche leeren (esc)") { query = "" }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
        .fixedSize()
    }

    private func schrittKnopf(_ symbol: String, _ hilfe: String,
                              _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hilfe)
    }

    /// „3/12" — und der Grund, warum nichts markiert ist, wenn es nichts zu markieren gibt.
    private var trefferText: String {
        if query.trimmingCharacters(in: .whitespaces).count < TaskSearch.minQueryLength {
            return "…"
        }
        return hits.isEmpty ? "0" : "\(hitIndex + 1)/\(hits.count)"
    }

    /// Trefferliste neu rechnen. `springen` steuert, ob danach auch angesprungen wird — beim Tippen
    /// ja, bei einem Inhaltswechsel unter der laufenden Suche nein.
    private func sucheAuffrischen(springen: Bool) {
        if searchIndexStale {
            searchIndex = TaskSearchIndex(sections: sections)
            searchIndexStale = false
        }
        hits = searchIndex.hits(query: query)
        hitIndex = min(hitIndex, max(hits.count - 1, 0))
        if springen, !hits.isEmpty {
            hitIndex = 0
            anspringen()
        } else if hits.isEmpty {
            // Auch „nichts gefunden" muss ankommen: sonst blieben die Markierungen der vorigen
            // Eingabe stehen und behaupteten einen Treffer.
            searchToken += 1
        }
    }

    private func weiter(_ schritt: Int) {
        guard !hits.isEmpty else { return }
        hitIndex = (hitIndex + schritt + hits.count) % hits.count
        anspringen()
    }

    /// Zum aktuellen Treffer: Tab wechseln (wenn er woanders liegt) und der Ansicht sagen, welche
    /// Fundstelle gemeint ist. Der Tabwechsel lädt das Dokument neu — die Markierung setzt der
    /// Coordinator danach selbst (`didFinish`).
    private func anspringen() {
        guard hits.indices.contains(hitIndex) else { return }
        let treffer = hits[hitIndex]
        if current?.id != treffer.sectionID {
            selectedTitle = treffer.sectionTitle
            // Die Vorschau eines Anhangs steht an derselben Stelle wie der Tab — sie muss weichen,
            // sonst springt man in etwas, das man nicht sieht.
            model.taskAttachmentSelection = nil
        }
        searchToken += 1
    }

    /// Was die Ansicht markieren soll — nil, solange nichts gesucht wird.
    private var markdownSuche: MarkdownSearch? {
        guard !query.isEmpty else { return nil }
        let treffer = hits.indices.contains(hitIndex) ? hits[hitIndex] : nil
        // In einer anderen Sektion als der gezeigten wird zwar markiert, aber nichts angesprungen:
        // `occurrence` gilt je Sektion.
        let stelle = (treffer?.sectionID == current?.id) ? (treffer?.indexInSection ?? 0) : -1
        return MarkdownSearch(query: hits.isEmpty ? "" : query, occurrence: stelle, token: searchToken)
    }

    /// Die Workflow-Assets des Projekts (Skills, siehe `ClaudeCommandScanner`). Ein Klick tippt
    /// `<präfix>name <TICKET>` in die Console — Enter bleibt beim Menschen.
    private var commandsMenu: some View {
        Menu {
            ForEach(model.claudeCommands) { command in
                Button {
                    model.sendClaudeCommand(command)
                } label: {
                    Text("\(model.agent.commandPrefix)\(command.name)")
                    if let description = command.description { Text(description) }
                }
            }
        } label: {
            Label("Commands", systemImage: "terminal")
                .font(.system(size: 13))
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
        .disabled(model.activeTerminalSession == nil)
        .help("Command mit dem aktuellen Ticket in die \(model.agent.displayName)-Console eintragen")
    }

    /// „Lösung" — schreibt das gleichnamige Jira-Feld (`customfield` je Instanz, über den
    /// Edit-Screen aufgelöst). Der rote Rahmen ist der Alarm aus `solutionMissingColumn`.
    private var solutionButton: some View {
        let missingIn = model.solutionMissingColumn
        let missing = missingIn != nil
        return Button {
            model.solutionSheetPresented = true
        } label: {
            Label(missing ? "Lösung fehlt" : "Lösung",
                  systemImage: missing ? "exclamationmark.bubble.fill" : "text.bubble")
                .font(.system(size: 13))
                .foregroundStyle(missing ? Color.red : Color.primary)
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .overlay {
            if missing {
                RoundedRectangle(cornerRadius: 5).strokeBorder(Color.red, lineWidth: 1.5)
            }
        }
        .help(missingIn.map {
                  "Das Ticket steht in \($0.rawValue), aber das Jira-Feld „Lösung“ ist leer — "
                  + "jetzt nachtragen (das Task-File wird nicht mitcommittet)"
              } ?? "Jira-Feld „Lösung“ bearbeiten")
    }

    /// Opens the commit dialog with the message `solve-task` proposed under `## Lösung`.
    private var commitButton: some View {
        Button {
            model.commitSheetPresented = true
        } label: {
            Label("Commit", systemImage: "checkmark.seal")
                .font(.system(size: 13))
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .help("Änderungen committen — Message aus dem Task-File, Amend + Force-Push möglich")
    }

    /// Sets Claude's task-file `### Status` marker (shown as the coloured dot on the card).
    private var statusMenu: some View {
        let current = model.currentStatusMarker
        return Menu(current.map { "\($0.emoji) \($0.label)" } ?? "⚪️ Status") {
            ForEach(TaskStatusMarker.allCases, id: \.self) { marker in
                Button {
                    model.setTaskStatus(marker)
                } label: {
                    if marker == current { Label("\(marker.emoji) \(marker.label)", systemImage: "checkmark") }
                    else { Text("\(marker.emoji) \(marker.label)") }
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .font(.system(size: 13))
        .tint(current?.statusColor ?? .secondary)
        .fixedSize()
        .help("Task-Status setzen (Farbpunkt auf der Karte)")
    }

    @ViewBuilder
    private var tabBar: some View {
        let showTabs = sections.count > 1
        if model.taskFile != nil || showTabs || !model.taskAttachments.isEmpty {
            HStack(spacing: 8) {
                attachmentsButton
                if model.taskFile != nil { copyPathButton }
                if showTabs {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(sections) { section in
                                tabButton(section)
                            }
                        }
                    }
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    /// Schiebt den Dateibaum des Task-Ordners von links ein. **Aus**, solange dort nichts liegt —
    /// die meisten Tickets haben keinen Anhang, und ein Knopf, der ein leeres Feld aufschlägt, sagt
    /// nichts. Die Zahl daneben nennt, was einen erwartet, ohne dass man aufmachen muss.
    private var attachmentsButton: some View {
        let count = TaskAttachments.fileCount(model.taskAttachments)
        return Button {
            showAttachments.toggle()
            // Beim Zuklappen fällt auch die Vorschau weg — sonst bliebe rechts eine Datei stehen,
            // zu der es links keine Zeile mehr gibt.
            if !showAttachments { model.taskAttachmentSelection = nil }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: showAttachments ? "sidebar.leading" : "paperclip")
                    .font(.system(size: 12, weight: .medium))
                if count > 0 {
                    Text("\(count)").font(.app(.caption2, weight: .medium))
                }
            }
            .foregroundStyle(showAttachments ? Color.accentColor : Color.secondary)
            .frame(height: 20)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(count == 0)
        .help(count == 0
              ? "Keine Dateien im Task-Ordner"
              : (showAttachments ? "Dateien ausblenden"
                 : "\(count) Datei\(count == 1 ? "" : "en") im Task-Ordner — Bilder, Anhänge, comments.json"))
    }

    /// Copies the task-file path relative to the repo root to the clipboard.
    private var copyPathButton: some View {
        Button {
            guard let path = model.relativeTaskFilePath else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            copiedPath = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedPath = false }
        } label: {
            Image(systemName: copiedPath ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copiedPath ? Color.green : Color.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help("Relativen Pfad zum Task-File kopieren")
    }

    private func tabButton(_ section: TaskSection) -> some View {
        let isActive = current?.id == section.id
        let hasQuestion = model.questionSectionIDs.contains(section.id)
        let hasDecision = model.decisionSectionIDs.contains(section.id)
        return Button {
            selectedTitle = section.title
            // Einen Tab zu wählen heisst: diesen Inhalt sehen wollen. Die Vorschau steht an
            // derselben Stelle und muss dafür weichen — der Baum bleibt, wo er ist.
            model.taskAttachmentSelection = nil
        } label: {
            HStack(spacing: 5) {
                if hasQuestion {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                }
                if hasDecision {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }
                Text(section.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.18)
                        : (hasQuestion ? Color.red.opacity(0.10)
                           : (hasDecision ? Color.green.opacity(0.10) : Color.clear)),
                        in: Capsule())
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(tabHelp(question: hasQuestion, decision: hasDecision))
    }

    private func tabHelp(question: Bool, decision: Bool) -> String {
        switch (question, decision) {
        case (true, true): return "Enthält offene Fragen und getroffene Entscheidungen"
        case (true, false): return "Diese Sektion enthält offene Fragen"
        case (false, true): return "Diese Sektion enthält Entscheidungen"
        case (false, false): return ""
        }
    }

    /// Breite des eingeschobenen Baums. Fest statt `HSplitView`: eine Spalte, die *erscheint*, muss
    /// dafür von links hereinfahren — ein Split baut sie stattdessen sprunghaft auf (derselbe Grund,
    /// aus dem die Prompt-Timeline über dem Terminal liegt statt neben ihm).
    private static let attachmentsWidth: CGFloat = 260

    private var content: some View {
        HStack(spacing: 0) {
            if showAttachments && !model.taskAttachments.isEmpty {
                TaskAttachmentsTree(model: model, expanded: $attachmentsExpanded)
                    .frame(width: Self.attachmentsWidth)
                    .transition(.move(edge: .leading))
                Divider()
            }
            sectionOrPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .animation(.snappy(duration: 0.22), value: showAttachments)
    }

    /// Rechts steht der gewählte Task-Tab — oder, sobald im Baum eine Datei angeklickt wurde, deren
    /// Vorschau an genau derselben Stelle. Das „✕" der Vorschau führt zurück zum Tab.
    @ViewBuilder
    private var sectionOrPreview: some View {
        if let node = selectedAttachment {
            TaskAttachmentPreview(node: node,
                                  baseDirectory: model.taskAttachmentBaseDirectory,
                                  onClose: { model.taskAttachmentSelection = nil })
        } else if model.detailLoading {
            VStack { ProgressView().controlSize(.small); Text("Lade…").font(.caption).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let section = current {
            MarkdownWebView(markdown: section.markdown, baseURL: model.taskFile?.directory,
                            search: markdownSuche)
        } else {
            Text("Kein Inhalt.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Die angeklickte Datei — nur, solange der Baum steht. Ordner sind im Baum nicht auswählbar
    /// (sie sind Aufklapp-Zeilen), die Prüfung hält die Vorschau trotzdem auf Dateien fest.
    private var selectedAttachment: KBNode? {
        guard showAttachments, let path = model.taskAttachmentSelection,
              let node = KnowledgebaseTree.node(at: path, in: model.taskAttachments),
              !node.isDirectory else { return nil }
        return node
    }
}
