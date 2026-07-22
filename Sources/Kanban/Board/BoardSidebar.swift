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
                if model.cards.isEmpty {
                    emptyState
                } else {
                    ForEach(model.columns, id: \.column) { entry in
                        ColumnSection(
                            column: entry.column,
                            cards: entry.cards,
                            isCollapsed: collapsed.contains(entry.column.rawValue),
                            selectedKey: model.selectedTicketKey,
                            onToggle: { withAnimation(.easeInOut(duration: 0.2)) { toggle(entry.column) } },
                            onSelect: { model.selectTicket($0) }
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            Text(model.selectedSprint == nil ? "Kein Sprint ausgewählt." : "Keine Tickets im Sprint.")
                .font(.app(.callout))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
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
