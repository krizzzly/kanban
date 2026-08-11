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
        ToolbarItem(placement: .navigation) { sprintTimeView }
        ToolbarItem(placement: .primaryAction) { bookButton }
        ToolbarItem(placement: .primaryAction) { refreshButton }
        ToolbarItem(placement: .primaryAction) { claudeWorkflowButton }
        ToolbarItem(placement: .primaryAction) { dataFolderButton }
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

    /// Cumulated Claude time over every card of the sprint (⏱ per prompt+answer, summed).
    @ViewBuilder
    private var sprintTimeView: some View {
        let seconds = model.sprintClaudeSeconds
        if seconds > 0 {
            // .titleAndIcon: a toolbar Label renders icon-only by default, which would hide the total.
            Label(TimeFormatting.compact(seconds), systemImage: "clock")
                .labelStyle(.titleAndIcon)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .help("Kumulierte Claude-Zeit aller Tickets in diesem Sprint")
        }
    }

    /// Opens the end-of-day batch-booking sheet. Shows the open (unbooked) total as its label so
    /// there's a visible reason to click; hidden entirely when nothing is open.
    @ViewBuilder
    private var bookButton: some View {
        let open = model.totalOpenToBookSeconds
        if open > 0 {
            Button {
                model.bookingSheetPresented = true
            } label: {
                Label("\(TimeFormatting.compact(open)) buchen", systemImage: "clock.badge.checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .help("Offene Claude-Zeit als Jira-Worklog buchen (auf 15 min aufgerundet)")
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

    private var claudeWorkflowButton: some View {
        Button {
            model.claudeWorkflowPresented = true
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .help("Claude-Workflow: Commands, Skills und Rules bearbeiten + verlinken")
    }

    /// Öffnet Kanbans Datenordner (tasks/, claude/, config.json) in PhpStorm.
    private var dataFolderButton: some View {
        Button {
            let dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Kanban", isDirectory: true)
            StatusLinkOpener.open(URL(string: StatusLinks.ideURL(forPath: dir.path))!)
        } label: {
            Image(systemName: "folder")
        }
        .help("Kanban-Datenordner in PhpStorm öffnen (~/Library/Application Support/Kanban)")
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
