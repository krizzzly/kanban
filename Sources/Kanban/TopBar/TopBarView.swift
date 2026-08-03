import SwiftUI
import KanbanCore

/// Native window-toolbar content (project + sprint pull-downs, status, refresh). Placing plain
/// `Menu`s in a real `.toolbar` gives them the native macOS pull-down look — the same approach as
/// the sibling kanban-code app — instead of a custom bar with styled controls.
struct TopBarToolbar: ToolbarContent {
    var model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { projectMenu }
        ToolbarItem(placement: .navigation) { sprintMenu }
        ToolbarItem(placement: .navigation) { statusView }
        ToolbarItem(placement: .primaryAction) { refreshButton }
        ToolbarItem(placement: .primaryAction) { settingsButton }
    }

    private var projectMenu: some View {
        Menu(model.selectedProject?.key.uppercased() ?? "Projekt") {
            ForEach(model.projects) { project in
                Button {
                    model.selectProject(project)
                } label: {
                    if project.id == model.selectedProject?.id {
                        Label(project.key.uppercased(), systemImage: "checkmark")
                    } else {
                        Text(project.key.uppercased())
                    }
                }
            }
        }
        .disabled(model.projects.isEmpty)
        .help("Projekt wählen")
    }

    @ViewBuilder
    private var sprintMenu: some View {
        Menu(model.selectedSprint.map(sprintLabel) ?? "—") {
            ForEach(model.sprints) { sprint in
                Button {
                    model.selectSprint(sprint)
                } label: {
                    if sprint.id == model.selectedSprint?.id {
                        Label(sprintLabel(sprint), systemImage: "checkmark")
                    } else {
                        Text(sprintLabel(sprint))
                    }
                }
            }
        }
        .disabled(model.sprints.isEmpty)
        .help("Sprint wählen")
    }

    private func sprintLabel(_ sprint: JiraSprint) -> String {
        switch sprint.state {
        case "active": return "🟢 \(sprint.name)"
        case "future": return "🔜 \(sprint.name)"
        case "closed": return "✓ \(sprint.name)"
        default: return sprint.name
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if model.isLoadingSprints || model.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(model.isLoadingSprints ? "Sprints…" : "Aktualisiere…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).lineLimit(1).help(error)
        } else if !model.hasGitlab {
            Label("kein GitLab", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .help("Ohne GitLab-Config bleiben Review/Done leer.")
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Aktualisieren")
        .disabled(model.selectedSprint == nil || model.isRefreshing)
    }

    private var settingsButton: some View {
        Button {
            model.settingsPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .help("Einstellungen (~/.hermes/config.json)")
    }
}
