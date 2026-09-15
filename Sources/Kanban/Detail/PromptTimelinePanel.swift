import SwiftUI
import KanbanCore

/// Slide-in over the right edge of the terminal: every prompt of this ticket's Claude session as a
/// chat bubble, newest at the bottom.
///
/// Clicking a bubble scrolls the terminal to the place that prompt was sent (tmux copy-mode, see
/// `TerminalCache.jump`). Prompts older than the pane's scrollback cannot be scrolled to — those
/// expand in place instead, rendered from the transcript (`ClaudeTurnReader`), which keeps the whole
/// conversation reachable even though tmux only holds the last couple of thousand lines.
struct PromptTimelinePanel: View {
    @Bindable var model: AppModel
    /// Closes the panel — the same button that opened it.
    let close: () -> Void

    /// Turn index whose transcript content is open below its bubble.
    @State private var expanded: Int?
    @State private var content: ClaudeTurnContent?
    @State private var loading = false

    /// Turns the user actually typed. Running a local command opens a turn whose entire text is
    /// Claude Code's `<local-command-caveat>` boilerplate — it belongs in the ⏱ list (it carries
    /// time), not in a list of prompts.
    private var turns: [ClaudeTurn] { model.selectedPrompts.filter { !$0.promptFull.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if turns.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .leading) { Divider() }
        .task { await model.refreshPromptReachability() }
        // A new prompt (or a new ticket) changes what the pane holds.
        .onChange(of: turns.count) { Task { await model.refreshPromptReachability() } }
        // After an app restart the terminal attaches *after* the panel can already be open. Without
        // this the first scan ran against no session at all and every bubble stayed grey for good.
        .onChange(of: model.activeTerminalSession) { Task { await model.refreshPromptReachability() } }
        .onChange(of: model.selectedTicketKey) { expanded = nil; content = nil }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble").font(.app(.subheadline))
            Text("Prompts").font(.app(.headline))
            Text("\(turns.count)").font(.app(.caption)).foregroundStyle(.tertiary)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Prompt-Liste schließen")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var empty: some View {
        VStack {
            Spacer()
            Text("Noch keine Prompts in dieser Session")
                .font(.app(.caption)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding()
            Spacer()
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(turns) { turn in
                        bubble(turn)
                            .id(turn.index)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo(turns.last?.index, anchor: .bottom) }
            .onChange(of: turns.count) { proxy.scrollTo(turns.last?.index, anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func bubble(_ turn: ClaudeTurn) -> some View {
        let reachable = model.reachablePrompts.contains(turn.index)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                activate(turn)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(turn.promptFull)
                        .font(.app(.subheadline))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .lineLimit(expanded == turn.index ? nil : 8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    footer(turn, reachable: reachable)
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(bubbleShape(reachable: reachable))
            }
            .buttonStyle(.plain)
            .help(reachable
                  ? "Springt im Terminal zu diesem Prompt"
                  : "Nicht mehr im tmux-Scrollback — klicken zeigt den Turn aus dem Transcript")

            if expanded == turn.index { expansion }
        }
    }

    private func bubbleShape(reachable: Bool) -> some View {
        // The chat-bubble tail sits bottom-left: the prompts are the user's own side of the
        // conversation, and the panel reads left-aligned like a chat. On the white panel the fill
        // stays a light accent tint — a reachable prompt a touch stronger than one that can only be
        // read back from the transcript.
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 3,
                                           bottomTrailingRadius: 12, topTrailingRadius: 12)
        return shape
            .fill(Color.accentColor.opacity(reachable ? 0.10 : 0.05))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(reachable ? 0.22 : 0.10), lineWidth: 1))
    }

    private func footer(_ turn: ClaudeTurn, reachable: Bool) -> some View {
        HStack(spacing: 5) {
            Text(turn.start, format: .dateTime.day().month().hour().minute())
            Text("·")
            Text("\(turn.isExact ? "" : "≈")\(TimeFormatting.compact(turn.seconds))")
            Spacer(minLength: 4)
            Image(systemName: reachable ? "arrow.turn.down.right" : "doc.text")
                .font(.system(size: 10))
        }
        .font(.app(.caption2))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var expansion: some View {
        VStack(alignment: .leading, spacing: 6) {
            if loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Transcript wird gelesen …").font(.app(size: 10)).foregroundStyle(.secondary)
                }
            } else if let content, !content.isEmpty {
                if !content.answer.isEmpty {
                    MarkdownWebView(markdown: content.answer, baseURL: nil)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if !content.tools.isEmpty { toolSummary(content) }
            } else {
                Text("Kein Text zu diesem Turn im Transcript")
                    .font(.app(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 8)
    }

    private func toolSummary(_ content: ClaudeTurnContent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.tools.map { "\($0.name) ×\($0.count)" }.joined(separator: " · "))
                .font(.app(size: 9))
                .foregroundStyle(.secondary)
            if content.hiddenResults > 0 {
                // Named, not rendered: one measured turn held 621 KB of tool output.
                Text("\(content.hiddenResults) Tool-Ergebnisse (\(byteSize(content.hiddenBytes))) nicht angezeigt")
                    .font(.app(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func byteSize(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes) B"
                     : bytes < 1024 * 1024 ? "\(bytes / 1024) KB" : String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // MARK: - Actions

    private func activate(_ turn: ClaudeTurn) {
        if expanded == turn.index {          // second click closes the expansion again
            expanded = nil
            content = nil
            return
        }
        Task {
            // Always try the terminal, whatever the last scan said: it re-scans against a fresh
            // capture anyway, and a stale "gone" (the pane grew, the session only just attached)
            // must never be the reason a jump is not even attempted. `reachable` colours the bubble,
            // it does not decide the action.
            if await model.jumpToPrompt(turnIndex: turn.index) {
                expanded = nil
                content = nil
                return
            }
            expanded = turn.index
            content = nil
            loading = true
            content = await model.turnContent(turnIndex: turn.index)
            loading = false
        }
    }
}
