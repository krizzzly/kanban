import SwiftUI
import KanbanCore

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            if let error = model.configError {
                ConfigErrorView(message: error)
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
    }
}

struct ConfigErrorView: View {
    let message: String
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
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
