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
                // Row 1: type icon + title + (key over Claude's status dot)
                HStack(alignment: .top, spacing: 8) {
                    // Own HStack so the icon centres on the title line instead of hanging from the
                    // row's top edge (the key/dot stack next to it is what needs `.top`).
                    HStack(spacing: 6) {
                        IssueTypeIcon(type: ticket.type, urlString: ticket.typeIconUrl)
                        Text(ticket.summary)
                            .font(.app(.subheadline))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

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
                        BadgeView(badge: badge, mergeRequestURL: card.mergeRequestURL)
                    }
                    // Right after the MR badge (last in `badges`), so the count reads as its detail.
                    if card.unresolvedMRComments > 0 {
                        OpenCommentsBadge(resolved: card.resolvedMRComments,
                                          total: card.totalMRComments,
                                          mergeRequestURL: card.commentsURL ?? card.mergeRequestURL)
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
                    // Flush right, directly under the ticket key: the MR's review verdict.
                    MRReviewBadge(state: card.mrReviewState,
                                  approvedBy: card.approvedBy,
                                  mergeRequestURL: card.commentsURL ?? card.mergeRequestURL)
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

/// Review threads on the card's MR, in GitLab's own MR-list notation: a grey pill with the comments
/// icon and "‹resolved› of ‹total›". Shown only while something is still open — once every thread is
/// resolved, GitLab (and this card, via `MRReviewBadge`) switches to the green "Resolved" pill.
struct OpenCommentsBadge: View {
    let resolved: Int
    let total: Int
    /// Click target: the MR whose discussions these are (nil → the badge stays inert).
    var mergeRequestURL: String?

    private var hint: String {
        let open = total - resolved
        let subject = open == 1
            ? "1 offener Thread im Merge Request (\(resolved) von \(total) erledigt)"
            : "\(open) offene Threads im Merge Request (\(resolved) von \(total) erledigt)"
        return mergeRequestURL == nil ? subject : "\(subject) — klicken zum Öffnen im Browser"
    }

    var body: some View {
        GitLabPill(icon: "bubble.left.and.bubble.right.fill",
                   text: "\(resolved) of \(total)",
                   foreground: GitLabColors.neutralText,
                   fill: GitLabColors.neutralFill)
            .accessibilityLabel("\(total - resolved) offene MR-Threads")
            .modifier(BrowserLink(urlString: mergeRequestURL, hint: hint))
    }
}

/// The MR's review verdict, flush right under the ticket key — GitLab's green badges: **Approved**
/// once someone approved, otherwise **Resolved** when every review thread is settled. Approved wins,
/// so only one pill is ever on the card (see `MRReviewState`); `.none` renders nothing at all.
struct MRReviewBadge: View {
    let state: MRReviewState
    var approvedBy: [String] = []
    var mergeRequestURL: String?

    var body: some View {
        switch state {
        case .approved:
            pill("checkmark.circle.fill", "Approved", hint: approvedHint)
        case .resolved:
            pill("bubble.left.and.bubble.right.fill", "Resolved",
                 hint: "Alle Review-Threads im Merge Request sind erledigt")
        case .none:
            EmptyView()
        }
    }

    private var approvedHint: String {
        approvedBy.isEmpty ? "Merge Request ist approved"
                           : "Approved von \(approvedBy.joined(separator: ", "))"
    }

    private func pill(_ icon: String, _ text: String, hint: String) -> some View {
        GitLabPill(icon: icon, text: text,
                   foreground: GitLabColors.successText, fill: GitLabColors.successFill)
            .accessibilityLabel(text)
            .modifier(BrowserLink(urlString: mergeRequestURL,
                                  hint: mergeRequestURL == nil ? hint : "\(hint) — klicken zum Öffnen im Browser"))
    }
}

/// GitLab's badge shape: icon + label in a tinted capsule.
private struct GitLabPill: View {
    let icon: String
    let text: String
    let foreground: Color
    let fill: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.app(size: 9))
            Text(text).font(.app(size: 10, weight: .medium))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(fill))
        .fixedSize()
    }
}

/// Makes a badge open a URL in the browser. The tap gesture sits *inside* the card, so it wins over
/// the card's own `onTapGesture` (SwiftUI resolves to the innermost gesture) — clicking the badge
/// opens the page without also switching the selected ticket. Without a URL the badge stays inert.
private struct BrowserLink: ViewModifier {
    let urlString: String?
    /// Tooltip — shown with or without a link; nil for badges that explain themselves.
    let hint: String?

    @State private var hovering = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let urlString, let url = URL(string: urlString) {
            content
                .opacity(hovering ? 0.6 : 1)
                .contentShape(Rectangle())
                .onTapGesture { StatusLinkOpener.open(url) }
                .onHover { inside in
                    hovering = inside
                    // `set` rather than push/pop: scrolling a hovered card away would otherwise
                    // leave an unbalanced push and the pointing hand stuck.
                    (inside ? NSCursor.pointingHand : NSCursor.arrow).set()
                }
                .help(hint ?? "")
        } else if let hint {
            content.help(hint)
        } else {
            content
        }
    }
}

/// Badge in kanban-code's icon+text style (cf. `CardBadgesRow`): 📄 file · 🌳 worktree · 🔀 MR.
struct BadgeView: View {
    let badge: CardBadge
    /// Click target for the MR badge — the other badges ignore it.
    var mergeRequestURL: String?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.app(.caption2))
            if let label { Text(label).font(.app(.caption2)) }
        }
        .foregroundStyle(color)
        .modifier(BrowserLink(urlString: linkURL,
                              hint: linkURL == nil ? nil : "Merge Request im Browser öffnen"))
    }

    /// Only the MR badge links out; 📄 file and 🌳 worktree have no web page.
    private var linkURL: String? {
        if case .mergeRequest = badge { return mergeRequestURL }
        return nil
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
