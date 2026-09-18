import SwiftUI
import KanbanCore

/// Vertical board: the fixed columns stacked top-to-bottom as collapsible lanes.
struct BoardSidebar: View {
    @Bindable var model: AppModel
    @AppStorage("kanbanCollapsedColumns") private var collapsedRaw = ""

    private var collapsed: Set<String> {
        Set(collapsedRaw.split(separator: ",").map(String.init))
    }

    private func toggle(_ column: KanbanColumn) {
        var set = collapsed
        if set.contains(column.rawValue) { set.remove(column.rawValue) } else { set.insert(column.rawValue) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    var body: some View {
        ScrollView {
            // VStack (not Lazy) with spacing 0 — section headers carry their own outer padding,
            // matching kanban-code's list board.
            VStack(alignment: .leading, spacing: 0) {
                // Im freien Modus steht hier, wo sonst die Sprint-Spalte anfängt, der Einstieg in
                // die Arbeit: ein neuer Task entsteht nicht in Jira, sondern hier.
                if model.boardMode == .free { newTaskButton }
                if model.cards.isEmpty {
                    emptyState
                } else if model.visibleColumns.isEmpty {
                    noMatchState
                } else {
                    ForEach(model.visibleColumns, id: \.column) { entry in
                        ColumnSection(
                            column: entry.column,
                            cards: entry.cards,
                            isCollapsed: collapsed.contains(entry.column.rawValue),
                            selectedKey: model.selectedTicketKey,
                            onToggle: { withAnimation(.easeInOut(duration: 0.2)) { toggle(entry.column) } },
                            onSelect: { model.selectTicket($0) },
                            commands: model.claudeCommands,
                            commandPrefix: model.agent.commandPrefix,
                            onCommand: { card, command in
                                model.sendClaudeCommand(command, ticketKey: card.ticket.key)
                            },
                            onReviewMerge: { card, iid in
                                model.sendReviewMerge(ticketKey: card.ticket.key, mrIid: iid)
                            },
                            onCreateTask: { card in
                                model.startTaskFromBranch(card.ticket)
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// „Task erstellen" — im freien Modus der Platz der Sprint-Spalte.
    private var newTaskButton: some View {
        VStack(spacing: 6) {
            Button {
                model.newTaskSheetPresented = true
            } label: {
                Label("Task erstellen", systemImage: "plus.circle.fill")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedProject == nil)
            .help("Beschreibung eingeben → /create-task in der Projekt-Console")

            // Die Console bleibt am Leben, auch wenn danach eine Karte angeklickt wurde.
            if model.hasNewTaskConsole && model.newTaskConsoleSession == nil {
                Button("Console anzeigen") { model.showNewTaskConsole() }
                    .buttonStyle(.plain)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// Es gibt Karten, nur keine, die zur Suche passt. Bewusst ein eigener Text statt `emptyState`:
    /// „Keine Tickets im Sprint" wäre hier schlicht gelogen — die Tickets sind da, der Filter ist es
    /// auch. Der Knopf ist der Weg zurück, ohne das Feld oben suchen zu müssen.
    private var noMatchState: some View {
        VStack(spacing: 8) {
            Text("Kein Ticket passt zu „\(model.ticketSearch)“.")
                .font(.app(.callout))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Suche leeren") { model.ticketSearch = "" }
                .buttonStyle(.plain)
                .font(.app(.caption))
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoadingSprints || model.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Lade…").font(.app(.callout)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            Text(emptyMessage)
                .font(.app(.callout))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 40)
        }
    }

    private var emptyMessage: String {
        switch model.boardMode {
        case .free:
            return "Noch keine Task-Files, Worktrees oder MRs in diesem Projekt.\n"
                 + "Leg oben einen Task an."
        case .sprint:
            switch model.selectedChoice {
            case nil: return "Kein Sprint und kein Board ausgewählt."
            case .board: return "Keine offenen Tickets auf dem Board."
            case .sprint: return "Keine Tickets im Sprint."
            }
        }
    }
}

extension KanbanColumn {
    var accent: Color {
        switch self {
        case .sprint: return .secondary
        case .offen: return .blue
        case .inBearbeitung: return .orange
        case .review: return .purple
        case .done: return .green
        }
    }
}
