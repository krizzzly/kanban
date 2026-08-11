import SwiftUI
import KanbanCore

/// Modal settings editor for `~/.hermes/config.json`, styled after the macOS System Settings:
/// section sidebar on the left, a grouped form on the right, save/restart footer at the bottom.
/// Round-trip-safe — unknown keys in the config survive (see `ConfigStore`).
/// Der Claude-Workflow-Editor lebt bewusst NICHT hier, sondern im eigenen `ClaudeWorkflowWindow`.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsModel()
    @State private var selection: String? = HermesConfigSchema.sections.first?.id
    /// Called after a successful save so the app reloads its config.
    let onSaved: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
            Divider()
            footer
        }
        .frame(width: 860, height: 620)
        .onAppear { settings.load() }
    }

    private static let rawSectionID = "raw"
    private static let notificationsSectionID = "notifications"
    private static let projectsSectionID = "projects"

    private var sidebar: some View {
        List(selection: $selection) {
            // Steht bewusst oben und abgesetzt: quer zu allen Modulen, und der Ort, an dem ein
            // neues Projekt entsteht (HERMES-043).
            Label("Projekte", systemImage: "square.stack.3d.up").tag(Self.projectsSectionID)
            Divider()
            ForEach(HermesConfigSchema.sections) { section in
                Label(section.title, systemImage: section.icon).tag(section.id)
            }
            Divider()
            Label("Benachrichtigungen", systemImage: "bell.badge").tag(Self.notificationsSectionID)
            Label("Roh-JSON", systemImage: "curlybraces").tag(Self.rawSectionID)
        }
        .listStyle(.sidebar)
        .frame(width: 210)
    }

    @ViewBuilder
    private var detail: some View {
        if let error = settings.loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30)).foregroundStyle(.orange)
                Text(error)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Neu laden") { settings.load() }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selection == Self.projectsSectionID {
            ProjectsEditor(settings: settings)
        } else if selection == Self.notificationsSectionID {
            NotificationsSettingsView()
        } else if selection == Self.rawSectionID {
            RawJSONEditor(settings: settings)
        } else if let section = HermesConfigSchema.sections.first(where: { $0.id == selection }) {
            Form {
                if let intro = section.intro {
                    Text(intro).font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(section.fields) { field in
                        SchemaFieldView(spec: field, settings: settings)
                    }
                }
                if let map = section.projectMap {
                    ProjectMapEditor(spec: map, settings: settings)
                }
                if let presence = section.presenceList {
                    PresenceListEditor(spec: presence, settings: settings)
                }
                if let people = section.personList {
                    PersonListEditor(spec: people, settings: settings)
                }
            }
            .formStyle(.grouped)
            .id(section.id)   // fresh scroll position + field state per section
        } else {
            Text("Bereich wählen").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let saveError = settings.saveError { errorRow(saveError) }
            if settings.savedPendingRestart { restartBanner }

            HStack(spacing: 10) {
                Text(abbreviateHome(settings.configPath))
                    .font(.caption).foregroundStyle(.tertiary)
                if settings.dirty {
                    Text("● ungespeicherte Änderungen")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") {
                    if settings.save() { onSaved() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!settings.dirty)
            }
        }
        .padding(12)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
            Spacer()
            if settings.conflict {
                Button("Neu laden") { settings.load() }
                    .help("Verwirft die eigenen Änderungen und lädt den Stand von der Platte")
                Button("Trotzdem speichern") {
                    if settings.save(force: true) { onSaved() }
                }
            }
        }
    }

    private var restartBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Label("Gespeichert. Damit die Änderungen auch im Hermes-Daemon wirken, diesen neu starten.",
                      systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
                Spacer()
                if settings.restartBusy { ProgressView().controlSize(.small) }
                Button("Daemon neu starten") { settings.restartDaemon() }
                    .disabled(settings.restartBusy)
            }
            if let result = settings.restartResult {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
