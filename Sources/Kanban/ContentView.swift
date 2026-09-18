import SwiftUI
import KanbanCore

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            if let error = model.configError {
                ConfigErrorView(message: error) { model.settingsPresented = true }
            } else if model.needsSetup {
                SetupView { model.settingsPresented = true }
            } else if model.knowledgebaseOpen {
                // Die Knowledgebase bringt ihre eigene Zweiteilung mit (Baum | Inhalt) und tritt
                // deshalb an die Stelle von Board und Detail, statt sich in eine der Spalten zu
                // quetschen. Die Leiste bleibt — über sie geht es zurück.
                KnowledgebaseView(model: model)
                    .toolbar { TopBarToolbar(model: model) }
                    .headerChrome(model.selectedProject?.appearance ?? .none)
            } else {
                HSplitView {
                    BoardSidebar(model: model)
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
                    DetailView(model: model)
                        .frame(minWidth: 460)
                }
                .toolbar { TopBarToolbar(model: model) }
                // Hintergrund und unterer Rand der Kopfzeile — beides nur, wo konfiguriert. Die
                // Knowledgebase bekommt es ebenso: sie tauscht das Board aus, nicht die Leiste.
                .headerChrome(model.selectedProject?.appearance ?? .none)
            }
        }
        .task {
            model.bootstrap()
            await model.watchdog.uebernehmen(config: model.config)
        }
        .sheet(isPresented: $model.settingsPresented) {
            SettingsSheet { model.reloadConfig() }
        }
        // Eigenes Fenster statt Sheet (wie der Commit-Dialog): der Markdown-Editor über
        // Commands/Skills/Rules braucht Fläche, die ein Sheet am Board-Fenster nicht hergibt.
        .onChange(of: model.claudeWorkflowPresented) { _, presented in
            if presented { ClaudeWorkflowWindow.shared.show(model: model) }
            else { ClaudeWorkflowWindow.shared.close(model: model) }
        }
        .sheet(isPresented: $model.bookingSheetPresented) {
            BookingSheet(model: model)
        }
        .sheet(isPresented: $model.stackSweepPresented) {
            StackSweepSheet(model: model)
        }
        .sheet(isPresented: $model.newTaskSheetPresented) {
            NewTaskSheet(model: model)
        }
        // get-task/start-task holen Jira-Inhalte in die KI — davor steht die PROD-Bestätigung.
        // Hier oben, weil beide Wege dorthin führen: Board-Kontextmenü und Detail-Header.
        .sheet(item: $model.prodConfirmation) { pending in
            ProdDataConfirmSheet(model: model, pending: pending)
        }
        // Eigenes Fenster statt Sheet: ein Sheet hängt am Board-Fenster und erscheint dort, wo das
        // gerade steht — der Commit-Dialog soll mittig auf dem Bildschirm aufgehen.
        .onChange(of: model.commitSheetPresented) { _, presented in
            if presented { CommitWindow.shared.show(model: model) }
            else { CommitWindow.shared.close(model: model) }
        }
    }
}

/// Erststart: die Config ist leer (oder hat noch kein Projekt). Bewusst **kein** Fehlerbild —
/// Kanban läuft ohne Hermes und ohne Vorwissen, hier fängt die Einrichtung an. Lag eine
/// Hermes-Config bereit, hat `HermesImport` sie schon übernommen und dieser Schirm erscheint gar nicht.
struct SetupView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
            Text("Willkommen bei Kanban")
                .font(.headline)
            Text("Noch nichts konfiguriert. Trage in den Einstellungen deine Jira-Zugangsdaten ein "
                 + "und lege mindestens ein Projekt an — GitLab oder GitHub ist optional und "
                 + "ergänzt nur die Spalten Review und Done.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Einstellungen öffnen…", action: openSettings)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nur für echte Fehler: die Config-Datei existiert, ist aber kein gültiges JSON. Fehlende Werte
/// führen hierher nicht — dafür gibt es `SetupView`.
struct ConfigErrorView: View {
    let message: String
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("Config konnte nicht geladen werden")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(abbreviated(KanbanConfig.path))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Einstellungen öffnen…", action: openSettings)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
