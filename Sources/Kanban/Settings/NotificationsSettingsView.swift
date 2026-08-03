import SwiftUI
import KanbanCore

/// Settings pane to install/remove the global Claude Code hook that powers the ❓ "console waiting"
/// indicator. Editing `~/.claude/settings.json` happens only on explicit action here.
struct NotificationsSettingsView: View {
    @State private var installed = ClaudeHookInstaller.isInstalled()
    @State private var errorText: String?
    @State private var notifStatus = "…"

    var body: some View {
        Form {
            Section {
                Text("Sobald eine Claude-Console auf eine Antwort wartet, erscheint ein rotes ❓ auf der Karte und optional eine macOS-Mitteilung. Dafür trägt Kanban einen Hook in deine globale Claude-Code-Konfiguration ein.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Status") {
                HStack(spacing: 8) {
                    Image(systemName: installed ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(installed ? .green : .secondary)
                    Text(installed ? "Hook installiert" : "Hook nicht installiert")
                    Spacer()
                    if installed {
                        Button("Entfernen", role: .destructive) { run(ClaudeHookInstaller.uninstall) }
                    } else {
                        Button("Installieren") { run(ClaudeHookInstaller.install) }
                    }
                }
                LabeledContent("settings.json", value: abbreviate(ClaudeHookInstaller.settingsPath))
                    .font(.caption)
            }

            Section("macOS-Mitteilungen") {
                LabeledContent("Freigabe-Status", value: notifStatus)
                HStack {
                    Text("Test setzt sofort ein Dock-Badge (Lebenszeichen) und schickt eine Mitteilung.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Test senden") {
                        AttentionNotifier.shared.sendTest()
                        Task { notifStatus = await AttentionNotifier.shared.authorizationStatusText() }
                    }
                }
                Text("Falls kein Banner kommt: Systemeinstellungen → Mitteilungen → Kanban aktivieren (Stil: Banner). Bereits gesendete liegen ggf. im Mitteilungszentrum (oben rechts auf Datum/Uhrzeit klicken).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .task { notifStatus = await AttentionNotifier.shared.authorizationStatusText() }

            Section {
                Text("Bereits laufende Consolen werden zusätzlich per tmux-Analyse erkannt. Der Hook greift für neu gestartete Consolen. Änderung wirkt sofort — kein Claude-Neustart nötig.")
                    .font(.caption).foregroundStyle(.tertiary)
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func run(_ action: () throws -> Void) {
        do { try action(); errorText = nil }
        catch { errorText = error.localizedDescription }
        installed = ClaudeHookInstaller.isInstalled()
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
