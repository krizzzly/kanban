import Foundation

public struct WorkflowResolution: Sendable, Hashable {
    public let column: KanbanColumn
    public let badges: [CardBadge]

    public init(column: KanbanColumn, badges: [CardBadge]) {
        self.column = column
        self.badges = badges
    }
}

/// The derived-status precedence engine. Pure function, fully unit-testable.
///
/// Precedence (first match wins):
///   1. Done            — a matching MR is merged, OR the Jira status is Erledigt/Geschlossen (jiraDone)
///   2. Done            — task-file `### Status` == ✅ Done (user-set final; wins over an open MR)
///   3. Review          — a matching MR is opened
///   4. marker column   — task-file marker decides the *work* stage: 🔴 Offen → Offen ·
///                        🟡 In Arbeit / 🟢 Abgeschlossen → In Bearbeitung · 🔵 Review → Review.
///                        ("Abgeschlossen" = Claude finished implementing; stays In Bearbeitung —
///                        it is NOT the final Done.)
///   5. In Bearbeitung  — no marker but a matching worktree exists (work has started)
///   6. Offen           — no marker but a task file exists
///   7. Sprint          — otherwise
///
/// The full granular marker is also shown as a coloured dot on the card (coloured by the matching
/// column accent).
public enum WorkflowStatus {
    public static func resolve(ticketKey: String,
                               hasTaskFile: Bool,
                               statusMarker: TaskStatusMarker?,
                               worktree: Worktree?,
                               mergeRequests: [MergeRequestRef],
                               jiraDone: Bool = false) -> WorkflowResolution {
        let matching = mergeRequests.filter {
            TicketMatching.references($0.sourceBranch, ticketKey: ticketKey)
                || TicketMatching.references($0.title, ticketKey: ticketKey)
        }
        let merged = matching.filter { $0.state == "merged" }
        let opened = matching.filter { $0.state == "opened" }

        // Badges are independent of the column — they explain *why* the card sits where it does.
        var badges: [CardBadge] = []
        if hasTaskFile { badges.append(.file) }
        if worktree != nil { badges.append(.worktree) }
        // Prefer a merged MR for the badge, else the newest opened one (highest iid as proxy).
        if let mr = merged.max(by: { $0.iid < $1.iid }) ?? opened.max(by: { $0.iid < $1.iid }) {
            badges.append(.mergeRequest(mr.iid))
        }

        let column: KanbanColumn
        if !merged.isEmpty || jiraDone {
            column = .done                   // merged MR, or Jira status = Erledigt/Geschlossen
        } else if statusMarker == .done {
            column = .done                   // ✅ user-set final Done wins over an open MR
        } else if !opened.isEmpty {
            column = .review
        } else if let marker = statusMarker {
            column = marker.column           // 🔴 Offen · 🟡/🟢 In Bearbeitung · 🔵 Review
        } else if worktree != nil {
            column = .inBearbeitung          // work has started (a worktree exists)
        } else if hasTaskFile {
            column = .offen
        } else {
            column = .sprint
        }

        return WorkflowResolution(column: column, badges: badges)
    }
}
