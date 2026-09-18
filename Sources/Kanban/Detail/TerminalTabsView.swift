import SwiftUI
import KanbanCore

/// Lower detail zone: a tab bar over the terminals. **Claude** (main tree) and **Terminal** (plain
/// shell in the worktree, only when one exists) are always present; the user can spawn any number of
/// extra terminals via the trailing "+" button, each with its own closable "✕" tab. All terminals
/// stay alive in `TerminalCache` / tmux; the tab bar only chooses which one is visible.
struct TerminalTabsView: View {
    @Bindable var model: AppModel
    @State private var selected: Tab = .claude
    /// The prompt timeline slides in over the terminal (see `PromptTimelinePanel`).
    @State private var showPrompts = false
    /// Das Verfassen-Fenster (siehe `PromptComposerSheet`).
    @State private var composing = false

    private static let promptPanelWidth: CGFloat = 380

    private enum Tab: Hashable { case maintree, stack, claude, worktree, extra(String) }

    private var claudeSession: String? { model.activeTerminalSession }
    private var worktreeSession: String? { model.activeWorktreeTerminalSession }
    private var extras: [String] { model.extraTerminalSessions }

    var body: some View {
        if let claude = claudeSession {
            VStack(spacing: 0) {
                tabBar
                Divider()
                // Overlay, not a split: the panel must not resize the pane — a SIGWINCH would make
                // tmux reflow Claude's whole TUI just to look at what was typed.
                ZStack(alignment: .topTrailing) {
                    content(claude: claude)
                    if showPrompts {
                        PromptTimelinePanel(model: model) { showPrompts = false }
                            .frame(width: Self.promptPanelWidth)
                            // Sits a little below the tab bar and keeps its top corner rounded, so
                            // it reads as a panel lying *on* the terminal instead of a second bar.
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10))
                            .padding(.top, 10)
                            .shadow(color: .black.opacity(0.18), radius: 8, x: -2, y: 2)
                            .transition(.move(edge: .trailing))
                    }
                }
                .clipped()
                .animation(.snappy(duration: 0.22), value: showPrompts)
            }
            .onChange(of: model.selectedTicketKey) { selected = .claude }
            .onChange(of: model.claudeTerminalFocusRequest) { selected = .claude }
            // Back to the console → the overlay gets out of the way. The click itself still reaches
            // the terminal (see `TerminalCache.handleClick`), so this costs no extra click.
            .onChange(of: model.terminalClickTick) { showPrompts = false }
            .onChange(of: worktreeSession) {
                if worktreeSession == nil, selected == .worktree { selected = .claude }
            }
            .sheet(isPresented: $composing) {
                PromptComposerSheet(model: model)
            }
        } else {
            TerminalPlaceholderView(ticketKey: model.selectedTicketKey)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            // Maintree links vom Worktree: dasselbe Panel, anderes Ziel — der Stack des Haupt-Repos.
            // Er hängt am Projekt, nicht am Ticket, und ist deshalb immer da.
            pill("Maintree", active: selected == .maintree) { selected = .maintree }
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
            composeButton
            promptsButton
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Trailing end of the bar: slides the prompt timeline in over the terminal. Only meaningful for
    /// the Claude console — the worktree/extra shells have no prompts.
    @ViewBuilder
    private var promptsButton: some View {
        if selected == .claude || selected == .stack {
            Button { showPrompts.toggle() } label: {
                Image(systemName: showPrompts ? "sidebar.right" : "text.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showPrompts ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Prompts dieser Session — klicken springt im Terminal dorthin")
        }
    }

    /// Links neben den Prompts: einen eigenen Prompt verfassen, statt ihn in die enge Eingabezeile
    /// des TUI zu tippen.
    ///
    /// `plus.bubble` und nicht `plus`: derselbe Balken trägt links schon ein `plus` für ein weiteres
    /// Terminal, und zwei gleiche Zeichen mit verschiedener Wirkung in einer Leiste wären eine
    /// Verwechslung mit Ansage. Die Sprechblase bindet es zusätzlich an den Prompt-Knopf daneben.
    @ViewBuilder
    private var composeButton: some View {
        if selected == .claude {
            Button { composing = true } label: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Prompt in Markdown verfassen und in die Console geben")
        }
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
        case .maintree:
            WorktreeStackView(model: model, target: .maintree)
        case .stack:
            WorktreeStackView(model: model, target: .worktree)
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
