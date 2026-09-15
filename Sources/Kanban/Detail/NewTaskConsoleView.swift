import SwiftUI
import KanbanCore

/// Die Projekt-Console des freien Modus, dort wo sonst das Ticket-Detail steht.
///
/// Sie hängt an keinem Ticket — `/create-task` erfindet die Nummer ja erst. Sobald Claude das
/// Task-File angelegt hat, taucht die Karte beim nächsten Refresh links auf und bringt ihre **eigene**
/// Console mit; diese hier bleibt für den nächsten neuen Task bestehen.
struct NewTaskConsoleView: View {
    let model: AppModel
    let session: String

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalContainerView(session: session).id(session)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Neuer Task · \(model.selectedProject?.key.uppercased() ?? "—")")
                    .font(.app(.headline))
                Text("Sobald das Task-File steht, erscheint die Karte links.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.newTaskSheetPresented = true
            } label: {
                Label("Weiterer Task", systemImage: "plus")
            }
            .help("Noch eine Beschreibung in dieselbe Console geben")
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Board neu einlesen — holt das eben angelegte Task-File aufs Board")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
