import SwiftUI
import KanbanCore

/// Lower detail zone: a tab bar over the terminals. **Claude** (main tree) and **Terminal** (plain
/// shell in the worktree, only when one exists) are always present; the user can spawn any number of
/// extra terminals via the trailing "+" button, each with its own closable "✕" tab. All terminals
/// stay alive in `TerminalCache` / tmux; the tab bar only chooses which one is visible.
struct TerminalTabsView: View {
    @Bindable var model: AppModel
    @State private var selected: Tab = .claude

    private enum Tab: Hashable { case stack, claude, worktree, extra(String) }

    private var claudeSession: String? { model.activeTerminalSession }
    private var worktreeSession: String? { model.activeWorktreeTerminalSession }
    private var extras: [String] { model.extraTerminalSessions }

    var body: some View {
        if let claude = claudeSession {
            VStack(spacing: 0) {
                tabBar
                Divider()
                content(claude: claude)
            }
            .onChange(of: model.selectedTicketKey) { selected = .claude }
            .onChange(of: worktreeSession) {
                if worktreeSession == nil, selected == .worktree { selected = .claude }
            }
        } else {
            TerminalPlaceholderView(ticketKey: model.selectedTicketKey)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            pill("Worktree", active: selected == .stack) { selected = .stack }
            pill("Claude", active: selected == .claude) { selected = .claude }
            if worktreeSession != nil {
                pill("Terminal", active: selected == .worktree) { selected = .worktree }
            }
            ForEach(Array(extras.enumerated()), id: \.element) { index, session in
                closablePill("Term \(index + 1)",
                             active: selected == .extra(session),
                             select: { selected = .extra(session) },
                             close: { closeExtra(session) })
            }
            addButton
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var addButton: some View {
        Button {
            if let name = model.addExtraTerminal() { selected = .extra(name) }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Weiteres Terminal öffnen")
    }

    @ViewBuilder
    private func content(claude: String) -> some View {
        switch selected {
        case .stack:
            WorktreeStackView(model: model)
        case .worktree:
            if let worktreeSession {
                TerminalContainerView(session: worktreeSession).id(worktreeSession)
            } else {
                TerminalContainerView(session: claude).id(claude)
            }
        case .extra(let session) where extras.contains(session):
            TerminalContainerView(session: session).id(session)
        default:
            TerminalContainerView(session: claude).id(claude)
        }
    }

    private func closeExtra(_ session: String) {
        if selected == .extra(session) { selected = .claude }
        model.closeExtraTerminal(session)
    }

    private func pill(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(active ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func closablePill(_ title: String, active: Bool,
                              select: @escaping () -> Void, close: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Terminal schließen")
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .contentShape(Capsule())
        .onTapGesture(perform: select)
    }
}
