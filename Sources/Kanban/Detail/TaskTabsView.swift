import AppKit
import SwiftUI
import KanbanCore

/// Dynamic native tab bar (one tab per H2 section) + rendered markdown content.
struct TaskTabsView: View {
    @Bindable var model: AppModel
    @State private var selectedTitle: String?
    @State private var copiedPath = false

    private var sections: [TaskSection] { model.displaySections }

    private var current: TaskSection? {
        sections.first { $0.title == selectedTitle } ?? sections.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: model.selectedTicketKey) { selectedTitle = nil }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(model.selectedTicketKey ?? "")
                .font(.headline.monospaced())
            if let file = model.taskFile {
                Text(file.url.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.canEditStatus { statusMenu }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    /// Sets Claude's task-file `### Status` marker (shown as the coloured dot on the card).
    private var statusMenu: some View {
        let current = model.currentStatusMarker
        return Menu(current.map { "\($0.emoji) \($0.label)" } ?? "⚪️ Status") {
            ForEach(TaskStatusMarker.allCases, id: \.self) { marker in
                Button {
                    model.setTaskStatus(marker)
                } label: {
                    if marker == current { Label("\(marker.emoji) \(marker.label)", systemImage: "checkmark") }
                    else { Text("\(marker.emoji) \(marker.label)") }
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(current?.statusColor ?? .secondary)
        .fixedSize()
        .help("Task-Status setzen (Farbpunkt auf der Karte)")
    }

    @ViewBuilder
    private var tabBar: some View {
        let showTabs = sections.count > 1
        if model.taskFile != nil || showTabs {
            HStack(spacing: 8) {
                if model.taskFile != nil { copyPathButton }
                if showTabs {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(sections) { section in
                                tabButton(section)
                            }
                        }
                    }
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    /// Copies the task-file path relative to the repo root to the clipboard.
    private var copyPathButton: some View {
        Button {
            guard let path = model.relativeTaskFilePath else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            copiedPath = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedPath = false }
        } label: {
            Image(systemName: copiedPath ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copiedPath ? Color.green : Color.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help("Relativen Pfad zum Task-File kopieren")
    }

    private func tabButton(_ section: TaskSection) -> some View {
        let isActive = current?.id == section.id
        return Button {
            selectedTitle = section.title
        } label: {
            Text(section.title)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: Capsule())
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if model.detailLoading {
            VStack { ProgressView().controlSize(.small); Text("Lade…").font(.caption).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let section = current {
            MarkdownWebView(markdown: section.markdown, baseURL: model.taskFile?.directory)
        } else {
            Text("Kein Inhalt.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
