import SwiftUI
import KanbanCore

/// Escape hatch: edit the whole config as raw JSON. "Übernehmen" validates and folds the text
/// back into the document (still saved via the round-trip-safe `ConfigStore`). Loads fresh each
/// time the tab is opened, so edits made in the other sections are reflected here.
struct RawJSONEditor: View {
    let settings: SettingsModel
    @State private var text = ""
    @State private var parseError: String?
    @State private var applied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gesamte Konfiguration als JSON. Änderungen hier werden erst mit ‹Übernehmen› in den Editor übernommen und dann mit ‹Speichern› geschrieben.")
                .font(.callout).foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

            if let parseError {
                Label(parseError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            } else if applied {
                Label("Übernommen — jetzt unten speichern.", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            }

            HStack {
                Button("Zurücksetzen") { reload() }
                Spacer()
                Button("Übernehmen") { apply() }
            }
        }
        .padding(16)
        .onAppear(perform: reload)
    }

    private func reload() {
        text = settings.rawJSON()
        parseError = nil
        applied = false
    }

    private func apply() {
        parseError = settings.applyRawJSON(text)
        applied = parseError == nil
    }
}
