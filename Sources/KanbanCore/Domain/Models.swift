import Foundation

/// The fixed Kanban columns, in display order. The column of a ticket is *derived*
/// from local artifact state (task-file / worktree / MR), never from the Jira status.
public enum KanbanColumn: String, CaseIterable, Sendable, Identifiable, Hashable {
    case sprint = "Sprint"
    case offen = "Offen"
    case inBearbeitung = "In Bearbeitung"
    case review = "Review"
    case done = "Done"

    public var id: String { rawValue }

    /// Fixed left-to-/top-to-bottom order used by the board.
    public static let ordered: [KanbanColumn] = [.sprint, .offen, .inBearbeitung, .review, .done]
}

/// A Jira issue reduced to what the board needs.
public struct Ticket: Identifiable, Sendable, Hashable {
    public let key: String          // e.g. EVEN-123
    public var summary: String
    public var status: String?      // Jira status name (informational only)
    public var statusCategory: String?  // Jira status-category key: new / indeterminate / done
    public var assignee: String?
    public var assigneeAvatarUrl: String?
    public var type: String?
    public var priority: String?
    public var storyPoints: Double?
    /// The epic this ticket belongs to. Filled by Jira for issues under an epic and, for sub-tasks,
    /// inherited from their story (see `EpicResolution`).
    public var epic: EpicRef?
    /// Parent issue key — a sub-task's story, or an issue's epic. Used to inherit the epic.
    public var parentKey: String?
    /// True for a Jira sub-task (`issuetype.subtask`). Sub-tasks are not shown as standalone cards on
    /// the board — the story carries the work. Language-independent, unlike matching the type name.
    public var isSubtask: Bool

    public init(key: String, summary: String, status: String? = nil, statusCategory: String? = nil,
                assignee: String? = nil, assigneeAvatarUrl: String? = nil,
                type: String? = nil, priority: String? = nil, storyPoints: Double? = nil,
                epic: EpicRef? = nil, parentKey: String? = nil, isSubtask: Bool = false) {
        self.key = key
        self.summary = summary
        self.status = status
        self.statusCategory = statusCategory
        self.assignee = assignee
        self.assigneeAvatarUrl = assigneeAvatarUrl
        self.type = type
        self.priority = priority
        self.storyPoints = storyPoints
        self.epic = epic
        self.parentKey = parentKey
        self.isSubtask = isSubtask
    }

    /// True when Jira considers the issue done (category "done" covers "Erledigt" + "Geschlossen").
    public var isDoneInJira: Bool { statusCategory == "done" }

    public var id: String { key }
}

/// A merge request reduced to what the status engine needs.
public struct MergeRequestRef: Sendable, Hashable {
    public let iid: Int
    public let title: String
    public let state: String         // opened / merged / closed / locked
    public let sourceBranch: String
    public let targetBranch: String
    public let mergedAt: String?
    public let webUrl: String
    /// True for a draft / work-in-progress MR. A draft is still `state == "opened"` in GitLab, but
    /// it is *not* ready for review, so it must not move a ticket into the Review column.
    public let draft: Bool

    public init(iid: Int, title: String, state: String, sourceBranch: String,
                targetBranch: String, mergedAt: String?, webUrl: String, draft: Bool = false) {
        self.iid = iid
        self.title = title
        self.state = state
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.mergedAt = mergedAt
        self.webUrl = webUrl
        self.draft = draft
    }
}

/// A git worktree (path + checked-out branch short name).
public struct Worktree: Sendable, Hashable {
    public let path: String
    public let branch: String?       // short branch name, e.g. feature/HERMES-033_…

    public init(path: String, branch: String?) {
        self.path = path
        self.branch = branch
    }
}

/// The `### Status` marker parsed out of a task file. Ordered as the workflow pipeline
/// (Offen → In Arbeit → Abgeschlossen → Review → Done); `allCases` drives the status menu.
///
/// Note: `abgeschlossen` (🟢) is Claude's "finished implementing" state and maps to **In Bearbeitung**
/// — it is NOT the final `done` (✅), which the user sets after review and maps to the Done column.
public enum TaskStatusMarker: String, Sendable, CaseIterable {
    case offen          // 🔴
    case inArbeit       // 🟡
    case abgeschlossen  // 🟢  (Claude done implementing → still In Bearbeitung)
    case review         // 🔵
    case done           // ✅  (final, user-set → Done)

    public var emoji: String {
        switch self {
        case .offen: return "🔴"
        case .inArbeit: return "🟡"
        case .abgeschlossen: return "🟢"
        case .review: return "🔵"
        case .done: return "✅"
        }
    }

    /// Canonical German status label written into the task file.
    public var label: String {
        switch self {
        case .offen: return "Offen"
        case .inArbeit: return "In Arbeit"
        case .abgeschlossen: return "Abgeschlossen"
        case .review: return "Review"
        case .done: return "Done"
        }
    }

    /// The board column this marker represents (independent of MR state). Used for the column
    /// derivation and to colour the card's status dot with the matching column accent.
    public var column: KanbanColumn {
        switch self {
        case .offen: return .offen
        case .inArbeit, .abgeschlossen: return .inBearbeitung
        case .review: return .review
        case .done: return .done
        }
    }
}

/// One H2 section of a task file → one tab.
public struct TaskSection: Identifiable, Sendable, Hashable {
    public let id: Int               // order index in the file
    public let title: String         // H2 heading text
    public let markdown: String      // section body (heading excluded)

    public init(id: Int, title: String, markdown: String) {
        self.id = id
        self.title = title
        self.markdown = markdown
    }
}

/// A small badge shown on a card so it's visible *why* a card sits in its column.
public enum CardBadge: Sendable, Hashable {
    case file
    case worktree
    case mergeRequest(iid: Int, draft: Bool)   // 🔀 opened/merged · 🚧 draft (why it's not in Review)

    public var symbol: String {
        switch self {
        case .file: return "📄"
        case .worktree: return "🌳"
        case .mergeRequest(let iid, let draft): return "\(draft ? "🚧" : "🔀")#\(iid)"
        }
    }
}
