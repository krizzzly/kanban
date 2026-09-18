import Foundation

/// Kanbans GitLab-Modul (Gegenstück zu Hermes' `modules/gitlab`). Transport, Auth und Host-Guard
/// kommen von `ModuleHTTPClient`: direktes REST mit dem `PRIVATE-TOKEN`, das dafür `read_api` braucht.
///
/// Eine von zwei Forges (`ForgeClient`), die andere ist `GitHubClient`. GitLabs Vokabular ist
/// zugleich das **normalisierte**: Kanban ist hier gewachsen, und die Zustandsnamen dieser API
/// (`opened` / `merged` / `closed`) stehen unverändert in `WorkflowStatus` und `TicketMatching`.
/// Der GitHub-Adapter übersetzt auf sie — nicht umgekehrt.
public struct GitLabClient: Sendable, ForgeClient {
    /// Modul-intern sichtbar, damit die Endpunkte in `GitLabFetch.swift` denselben Transport
    /// und dieselbe Basis-URL nutzen.
    let apiBaseUrl: String   // e.g. https://git.iwf.io/api/v4
    let http: ModuleHTTPClient

    public var kind: ForgeKind { .gitlab }

    /// Aus der App-Config — nil, wenn GitLab nicht konfiguriert ist (es ist optional; ohne GitLab
    /// bleibt das Board bei den lokalen Artefakten).
    public init?(config: AppConfig) {
        guard let apiUrl = config.gitlabApiUrl, let token = config.gitlabApiToken, !token.isEmpty
        else { return nil }
        self.init(apiBaseUrl: apiUrl, token: token)
    }

    public init(apiBaseUrl: String, token: String) {
        self.apiBaseUrl = apiBaseUrl
        self.http = .gitlab(baseUrl: apiBaseUrl, apiToken: token)
    }

    /// Lists merge requests of a project for a given state ("opened" / "merged"). First page (100).
    public func listMergeRequests(projectPath: String, state: String) async throws -> [MergeRequestRef] {
        let encoded = projectPath.replacingOccurrences(of: "/", with: "%2F")
        let url = "\(apiBaseUrl)/projects/\(encoded)/merge_requests?state=\(state)&per_page=100"
        let raw: [RawMR] = try await http.getJSON(url)
        return raw.map {
            MergeRequestRef(
                iid: $0.iid,
                title: $0.title,
                state: $0.state,
                sourceBranch: $0.source_branch,
                targetBranch: $0.target_branch,
                mergedAt: $0.merged_at,
                webUrl: $0.web_url,
                draft: $0.isDraft,
                forge: .gitlab
            )
        }
    }

    /// `ForgeClient` — derselbe Weg, unter dem Namen, den das Board kennt.
    public func openedAndMergedRequests(projectPath: String) async throws -> [MergeRequestRef] {
        try await openedAndMergedMRs(projectPath: projectPath)
    }

    /// Convenience: opened + merged MRs in one call. Opened MRs additionally carry their review
    /// state — resolved/unresolved discussion counts and whether someone approved (2 requests per
    /// opened MR, all concurrent). Merged MRs stay blank: their review is over, so neither number
    /// would ask for anything anymore, and fetching them for the whole merged history is wasteful.
    public func openedAndMergedMRs(projectPath: String) async throws -> [MergeRequestRef] {
        async let opened = listMergeRequests(projectPath: projectPath, state: "opened")
        async let merged = listMergeRequests(projectPath: projectPath, state: "merged")
        let openedMRs = await withReviewState(try await opened, projectPath: projectPath)
        let mergedMRs = try await merged
        return openedMRs + mergedMRs
    }

    // MARK: - Review state (discussions + approval)

    /// Resolved / unresolved review threads of one MR. A failed fetch counts as (0, 0) — the badge
    /// is a hint, it must never break the board refresh.
    ///
    /// Deliberately *not* taken from the MR list's `blocking_discussions_resolved`: on our instance
    /// that flag reads `true` even with four unresolved threads (it only tracks what blocks a merge).
    public func discussionCounts(projectPath: String, iid: Int) async -> (resolved: Int, unresolved: Int) {
        let encoded = projectPath.replacingOccurrences(of: "/", with: "%2F")
        let url = "\(apiBaseUrl)/projects/\(encoded)/merge_requests/\(iid)/discussions?per_page=100"
        guard let raw: [RawDiscussion] = try? await http.getJSON(url) else { return (0, 0) }
        return Self.threadCounts(raw)
    }

    /// Number of unresolved discussions of one MR.
    public func unresolvedDiscussionCount(projectPath: String, iid: Int) async -> Int {
        await discussionCounts(projectPath: projectPath, iid: iid).unresolved
    }

    /// Whether the MR carries at least one approval, plus the approvers' names for the tooltip.
    /// A failed fetch counts as "not approved" — same reasoning as the discussion counts.
    public func approval(projectPath: String, iid: Int) async -> (approved: Bool, by: [String]) {
        let encoded = projectPath.replacingOccurrences(of: "/", with: "%2F")
        let url = "\(apiBaseUrl)/projects/\(encoded)/merge_requests/\(iid)/approvals"
        guard let raw: RawApprovals = try? await http.getJSON(url) else { return (false, []) }
        return (raw.isApproved, raw.approverNames)
    }

    private func withReviewState(_ mrs: [MergeRequestRef],
                                 projectPath: String) async -> [MergeRequestRef] {
        await withTaskGroup(of: (Int, ReviewState).self) { group in
            for mr in mrs {
                group.addTask {
                    async let counts = discussionCounts(projectPath: projectPath, iid: mr.iid)
                    async let approval = approval(projectPath: projectPath, iid: mr.iid)
                    let (threads, approved) = await (counts, approval)
                    return (mr.iid, ReviewState(resolved: threads.resolved, unresolved: threads.unresolved,
                                                approved: approved.approved, approvedBy: approved.by))
                }
            }
            var byIid: [Int: ReviewState] = [:]
            for await (iid, state) in group { byIid[iid] = state }
            return mrs.map { mr in
                let state = byIid[mr.iid] ?? ReviewState()
                return MergeRequestRef(iid: mr.iid, title: mr.title, state: mr.state,
                                       sourceBranch: mr.sourceBranch, targetBranch: mr.targetBranch,
                                       mergedAt: mr.mergedAt, webUrl: mr.webUrl, draft: mr.draft,
                                       unresolvedDiscussions: state.unresolved,
                                       resolvedDiscussions: state.resolved,
                                       approved: state.approved, approvedBy: state.approvedBy,
                                       forge: mr.forge)
            }
        }
    }

    private struct ReviewState: Sendable {
        var resolved = 0
        var unresolved = 0
        var approved = false
        var approvedBy: [String] = []
    }

    /// A thread counts as "open" when it has at least one resolvable, not-yet-resolved note, and as
    /// "resolved" when every resolvable note of it is resolved. System notes (`resolvable == false`)
    /// are no thread at all and never count on either side.
    static func threadCounts(_ discussions: [RawDiscussion]) -> (resolved: Int, unresolved: Int) {
        var resolved = 0, unresolved = 0
        for discussion in discussions {
            let resolvable = (discussion.notes ?? []).filter { $0.resolvable == true }
            guard !resolvable.isEmpty else { continue }
            if resolvable.contains(where: { $0.resolved != true }) { unresolved += 1 } else { resolved += 1 }
        }
        return (resolved, unresolved)
    }

    static func unresolvedCount(_ discussions: [RawDiscussion]) -> Int {
        threadCounts(discussions).unresolved
    }

    struct RawDiscussion: Decodable {
        let notes: [RawNote]?
    }

    struct RawNote: Decodable {
        let resolvable: Bool?
        let resolved: Bool?
    }

    /// `GET /merge_requests/:iid/approvals`. GitLab answers `{"approved": …, "approved_by": [{"user": …}]}`.
    struct RawApprovals: Decodable {
        let approved: Bool?
        let approved_by: [RawApproval]?

        /// Older GitLab versions omit `approved` — a non-empty `approved_by` says the same thing.
        var isApproved: Bool { approved ?? !(approved_by ?? []).isEmpty }
        var approverNames: [String] { (approved_by ?? []).compactMap { $0.user?.name } }
    }

    struct RawApproval: Decodable {
        let user: RawApprover?
    }

    struct RawApprover: Decodable {
        let name: String?
    }

    private struct RawMR: Decodable {
        let iid: Int
        let title: String
        let state: String
        let source_branch: String
        let target_branch: String
        let merged_at: String?
        let web_url: String
        let draft: Bool?
        let work_in_progress: Bool?   // legacy alias for older GitLab versions

        /// A draft MR by any of GitLab's signals: the `draft` flag, the deprecated
        /// `work_in_progress`, or the `Draft:`/`WIP:` title prefix (older servers only set the title).
        var isDraft: Bool {
            if draft == true || work_in_progress == true { return true }
            let lower = title.lowercased()
            return lower.hasPrefix("draft:") || lower.hasPrefix("wip:") || lower.hasPrefix("[wip]")
        }
    }
}
