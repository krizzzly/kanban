import SwiftUI
import KanbanCore

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            if let error = model.configError {
                ConfigErrorView(message: error) { model.settingsPresented = true }
            } else {
                HSplitView {
                    BoardSidebar(model: model)
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
                    DetailView(model: model)
                        .frame(minWidth: 460)
                }
                .toolbar { TopBarToolbar(model: model) }
            }
        }
        .task { model.bootstrap() }
        // Eigenes Fenster statt Sheet (wie der Commit-Dialog): frei zentrier- und vergrösserbar,
        // nicht an die Grösse des Board-Fensters gebunden — der Claude-Workflow-Editor braucht Platz.
        .onChange(of: model.settingsPresented) { _, presented in
            if presented { SettingsWindow.shared.show(model: model) }
            else { SettingsWindow.shared.close(model: model) }
        }
        .sheet(isPresented: $model.bookingSheetPresented) {
            BookingSheet(model: model)
        }
        // Eigenes Fenster statt Sheet: ein Sheet hängt am Board-Fenster und erscheint dort, wo das
        // gerade steht — der Commit-Dialog soll mittig auf dem Bildschirm aufgehen.
        .onChange(of: model.commitSheetPresented) { _, presented in
            if presented { CommitWindow.shared.show(model: model) }
            else { CommitWindow.shared.close(model: model) }
        }
    }
}

struct ConfigErrorView: View {
    let message: String
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("Hermes-Config konnte nicht geladen werden")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Erwartet: ~/.hermes/config.json mit modules.jira.{baseUrl,email,apiToken}.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Einstellungen öffnen…", action: openSettings)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
