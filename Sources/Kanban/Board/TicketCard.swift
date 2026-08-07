import SwiftUI
import KanbanCore

/// Card ported 1:1 from kanban-code's `ListCardRowView`: compact two-row layout, `.subheadline`
/// single-line title, `controlBackgroundColor` fill, padding h12/v8, corner radius 8.
struct TicketCard: View {
    let card: CardVM
    let isSelected: Bool

    private var ticket: Ticket { card.ticket }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let epic = ticket.epic { EpicColorStripe(epic: epic) }
            VStack(alignment: .leading, spacing: 3) {
                // Row 1: title + (key over Claude's status dot)
                HStack(alignment: .top, spacing: 8) {
                    Text(ticket.summary)
                        .font(.app(.subheadline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(ticket.key)
                            .font(.app(.caption))
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        StatusDot(marker: card.statusMarker)
                    }
                }

                // Row 2: assignee (avatar + name) + badges + story points
                HStack(spacing: 6) {
                    if let assignee = ticket.assignee, !assignee.isEmpty {
                        HStack(spacing: 5) {
                            AvatarView(urlString: ticket.assigneeAvatarUrl, size: 20)
                            Text(assignee)
                                .font(.app(.callout))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if card.needsAttention { AttentionBadge() }
                    ForEach(Array(card.badges.enumerated()), id: \.offset) { _, badge in
                        BadgeView(badge: badge)
                    }
                    if card.claudeSeconds > 0 || card.claudeRunningSince != nil {
                        ClaudeTimeBadge(seconds: card.claudeSeconds,
                                        baseSeconds: card.claudeBaseSeconds,
                                        runningSince: card.claudeRunningSince,
                                        fullyBooked: card.fullyBooked)
                    }
                    Spacer(minLength: 0)
                    if let points = ticket.storyPoints {
                        Text(formatPoints(points))
                            .font(.app(.caption2))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.12)
                      : Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatPoints(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) SP" : String(format: "%.1f SP", value)
    }
}

/// Claude's task-file status as a small coloured dot, tinted with the **status's own colour** (its
/// 🔴🟡🟢🔵 emoji), independent of the card's board column. ✅ Done renders as a check so it reads
/// apart from 🟢 Abgeschlossen; a faint hollow ring means "no status yet".
struct StatusDot: View {
    let marker: TaskStatusMarker?

    var body: some View {
        content
            .frame(width: 10, height: 10)
            .help(marker?.label ?? "Kein Status")
    }

    @ViewBuilder
    private var content: some View {
        if marker == .done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(TaskStatusMarker.done.statusColor)
        } else {
            Circle()
                .fill(marker?.statusColor ?? .clear)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.primary.opacity(marker == nil ? 0.2 : 0.12), lineWidth: 1))
        }
    }
}

extension TaskStatusMarker {
    /// The status's own colour, matching its emoji — used for the card dot and the status button.
    /// (Distinct from `KanbanColumn.accent`, which colours the column collapsables.)
    var statusColor: Color {
        switch self {
        case .offen: return .red
        case .inArbeit: return .yellow
        case .abgeschlossen: return .green
        case .review: return .blue
        case .done: return .green
        }
    }
}

/// Very prominent "this console is waiting for your answer" marker. Sits left of the worktree badge
/// (see `TicketCard`), pulsing red so it's impossible to miss across a busy board.
struct AttentionBadge: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "questionmark.circle.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white, .red)
            .scaleEffect(pulse ? 1.0 : 0.82)
            .shadow(color: .red.opacity(0.6), radius: pulse ? 4 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .help("Die Claude-Console dieses Tickets wartet auf eine Antwort")
            .accessibilityLabel("Wartet auf Antwort")
    }
}

/// Badge in kanban-code's icon+text style (cf. `CardBadgesRow`): 📄 file · 🌳 worktree · 🔀 MR.
struct BadgeView: View {
    let badge: CardBadge

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.app(.caption2))
            if let label { Text(label).font(.app(.caption2)) }
        }
        .foregroundStyle(color)
    }

    private var icon: String {
        switch badge {
        case .file: return "doc.text"
        case .worktree: return "arrow.triangle.branch"
        case .mergeRequest(_, let draft): return draft ? "hammer" : "arrow.triangle.pull"
        }
    }

    private var label: String? {
        if case .mergeRequest(let iid, let draft) = badge { return draft ? "#\(iid) Draft" : "#\(iid)" }
        return nil
    }

    private var color: Color {
        switch badge {
        case .file: return .blue
        case .worktree: return .green
        case .mergeRequest(_, let draft): return draft ? .orange : .purple
        }
    }
}
