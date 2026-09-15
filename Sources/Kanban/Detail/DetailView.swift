import SwiftUI
import KanbanCore

/// Right pane: task-file tabs on top, terminal-placeholder zone at the bottom.
struct DetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let session = model.newTaskConsoleSession, model.selectedTicketKey == nil {
            NewTaskConsoleView(model: model, session: session)
        } else if model.selectedTicketKey == nil {
            placeholder
        } else {
            VSplitView {
                TaskTabsView(model: model)
                    .frame(minHeight: 240)
                terminalZone
                    .frame(minHeight: 120, idealHeight: 220)
            }
        }
    }

    private var terminalZone: some View {
        TerminalTabsView(model: model)
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("Ticket auswählen")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Wähle links eine Karte, um das Task-File in Tabs zu sehen.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
