import SwiftUI
import KanbanCore

/// Right pane: task-file tabs on top, terminal-placeholder zone at the bottom.
///
/// **Wann der Teiler wieder auf die Hälfte springt**, steht nirgends als Regel — es ergibt sich:
/// den `VSplitView` gibt es nur mit gewähltem Ticket. Ein Projektwechsel läuft über `clearDetail()`
/// und setzt `selectedTicketKey` auf nil, also steht hier der Platzhalter und der Split wird
/// abgebaut; die nächste Karte baut ihn frisch auf, mit `terminalAnteil`. Ein Fenster je Projekt
/// (KANBAN-006) fängt ohnehin frisch an. Ein Wechsel **von Ticket zu Ticket** bleibt dagegen in
/// diesem Zweig — der Split lebt weiter, die von Hand gezogene Position bleibt, und Claudes TUI
/// bekommt kein SIGWINCH. Ein `.id(projektKey)` am Detail-Bereich bräuchte es dafür nicht; es würde
/// nur zusätzlich die Terminal-Ansichten abreissen.
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
                    .frame(minHeight: 120)
                    .splitDividerOnce(unten: Self.terminalAnteil)
            }
        }
    }

    /// Anteil der Höhe, den die Terminal-Zone beim Öffnen bekommt.
    ///
    /// Das Terminal ist die Stelle, an der gearbeitet wird — das Task-File wird gelesen, das
    /// Terminal bedient. Aus den Mindesthöhen (240 : 120) fiel dem Arbeiten vorher ein knappes
    /// Drittel zu, und der Teiler wurde jedes Mal von Hand nachgezogen.
    ///
    /// Eine Zahl, ein Ort: eine spätere Config-Option hätte hier schon ihren Platz.
    static let terminalAnteil: CGFloat = 0.5

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
