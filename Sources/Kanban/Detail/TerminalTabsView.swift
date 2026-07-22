import SwiftUI
import KanbanCore

/// Lower detail zone: a small tab bar switching between the **Claude** console (main tree) and the
/// **Terminal** (plain shell in the worktree). Both terminals stay alive in `TerminalCache`; the tab
/// bar only chooses which one is visible. The "Terminal" tab only appears when a worktree exists.
struct TerminalTabsView: View {
    @Bindable var model: AppModel
    @State private var showWorktree = false

    private var claudeSession: String? { model.activeTerminalSession }
    private var worktreeSession: String? { model.activeWorktreeTerminalSession }

    var body: some View {
        if let claude = claudeSession {
            VStack(spacing: 0) {
                tabBar
                Divider()
                content(claude: claude)
            }
            .onChange(of: model.selectedTicketKey) { showWorktree = false }
            .onChange(of: worktreeSession) { if worktreeSession == nil { showWorktree = false } }
        } else {
            TerminalPlaceholderView(ticketKey: model.selectedTicketKey)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            pill("Claude", active: !showWorktree) { showWorktree = false }
            if worktreeSession != nil {
                pill("Terminal", active: showWorktree) { showWorktree = true }
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func content(claude: String) -> some View {
        if showWorktree, let worktreeSession {
            TerminalContainerView(session: worktreeSession).id(worktreeSession)
        } else {
            TerminalContainerView(session: claude).id(claude)
        }
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
}
