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
    /// `assignee.accountId` — the identity the board compares against the logged-in user, so a
    /// ticket assigned to *me* leaves the Sprint column. The display name is not an identity: it is
    /// not unique and it is spelled differently per instance.
    public var assigneeAccountId: String?
    public var type: String?
    /// `issuetype.iconUrl` — Jira's own type symbol (green Story, red Bug, …), so the card shows the
    /// same glyph as Jira instead of a guess mapped from the (localised) type name.
    public var typeIconUrl: String?
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
    /// Der Branch, **wenn das Ticket keine Nummer hat** (freier Modus, siehe `LocalTickets`). Ein MR
    /// auf `feature/playwright-frontend-testing` gehört zu keinem `<PREFIX>-<zahl>` — er wird über
    /// seinen Branch erkannt statt über den Key. Bei jedem normalen Ticket nil; dann gilt wie bisher
    /// die Suche nach dem Key in Branch und MR-Titel.
    public var sourceBranch: String?

    /// Ein Ticket, das es nur als Branch/MR gibt — ohne Nummer, ohne Jira, (noch) ohne Task-File.
    public var isBranchOnly: Bool { sourceBranch != nil }

    public init(key: String, summary: String, status: String? = nil, statusCategory: String? = nil,
                assignee: String? = nil, assigneeAvatarUrl: String? = nil,
                assigneeAccountId: String? = nil,
                type: String? = nil, typeIconUrl: String? = nil,
                priority: String? = nil, storyPoints: Double? = nil,
                epic: EpicRef? = nil, parentKey: String? = nil, isSubtask: Bool = false,
                sourceBranch: String? = nil) {
        self.key = key
        self.summary = summary
        self.sourceBranch = sourceBranch
        self.status = status
        self.statusCategory = statusCategory
        self.assignee = assignee
        self.assigneeAvatarUrl = assigneeAvatarUrl
        self.assigneeAccountId = assigneeAccountId
        self.type = type
        self.typeIconUrl = typeIconUrl
        self.priority = priority
        self.storyPoints = storyPoints
        self.epic = epic
        self.parentKey = parentKey
        self.isSubtask = isSubtask
    }

    /// True when Jira considers the issue done (category "done" covers "Erledigt" + "Geschlossen").
    public var isDoneInJira: Bool { jiraDoneState == .done }

    /// What Jira says about this ticket being finished — see `JiraDoneState`.
    public var jiraDoneState: JiraDoneState {
        switch statusCategory {
        case "done": return .done
        case "new", "indeterminate": return .notDone
        default: return .unknown          // no status category at all (free mode, local ticket)
        }
    }

    public var id: String { key }
}

/// Was Jira über die Erledigung eines Tickets sagt. **Drei** Zustände, kein Bool: „keine Auskunft"
/// (freier Modus, lokales Ticket ohne Jira-Vorgang) darf nicht mit „Jira führt es ausdrücklich als
/// **nicht** erledigt" verwechselt werden — nur das Zweite ist ein Mensch, der das Ticket
/// zurückgeschoben hat, und nur darauf darf das Board reagieren (siehe `WorkflowStatus`).
public enum JiraDoneState: String, Sendable, Hashable {
    /// Kein Jira-Status bekannt.
    case unknown
    /// statusCategory `done` — „Erledigt" / „Geschlossen".
    case done
    /// statusCategory `new` / `indeterminate` — „Offen", „In Arbeit", „Review", …
    case notDone
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
    /// Unresolved review discussions (open comments). Only fetched for opened MRs — merged ones
    /// keep 0, their comments require no action anymore.
    public let unresolvedDiscussions: Int
    /// Already resolved review discussions — the counterpart of `unresolvedDiscussions`, so the card
    /// can print GitLab's own "‹resolved› of ‹total›" thread counter.
    public let resolvedDiscussions: Int
    /// True when at least one person approved the MR (GitLab `/approvals`). Opened MRs only.
    public let approved: Bool
    /// Names of the approvers, for the badge's tooltip. Empty when `approved` is false.
    public let approvedBy: [String]

    public init(iid: Int, title: String, state: String, sourceBranch: String,
                targetBranch: String, mergedAt: String?, webUrl: String, draft: Bool = false,
                unresolvedDiscussions: Int = 0, resolvedDiscussions: Int = 0,
                approved: Bool = false, approvedBy: [String] = []) {
        self.iid = iid
        self.title = title
        self.state = state
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.mergedAt = mergedAt
        self.webUrl = webUrl
        self.draft = draft
        self.unresolvedDiscussions = unresolvedDiscussions
        self.resolvedDiscussions = resolvedDiscussions
        self.approved = approved
        self.approvedBy = approvedBy
    }

    /// All resolvable review threads of the MR (resolved + still open).
    public var totalDiscussions: Int { resolvedDiscussions + unresolvedDiscussions }

    /// What the card advertises about this MR's review progress.
    public var reviewState: MRReviewState { MRReviewState(mergeRequest: self) }
}

/// The one review signal a card shows for its opened MR, in GitLab's own vocabulary.
///
/// `approved` **wins over** `resolved`: once someone approved, the thread bookkeeping is water under
/// the bridge and only the approval is worth a badge. Merged MRs stay `.none` — neither approvals nor
/// discussions are fetched for them (their review is over).
public enum MRReviewState: Sendable, Hashable {
    case approved
    case resolved
    case none

    public init(mergeRequest mr: MergeRequestRef) {
        if mr.approved { self = .approved }
        // Only meaningful once threads exist — an MR nobody commented on is not "resolved".
        else if mr.totalDiscussions > 0 && mr.unresolvedDiscussions == 0 { self = .resolved }
        else { self = .none }
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
