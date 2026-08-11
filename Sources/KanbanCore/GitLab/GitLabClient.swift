import Foundation

/// Read-only GitLab client. The transport follows `modules.gitlab.backend`, mirroring Hermes:
///   • `api`       → direct REST with the `PRIVATE-TOKEN` header (needs a token with `read_api`),
///   • `extension` → via the Hermes daemon's browser session (default; works when the configured
///     token is an AI/MCP token that GitLab rejects for the REST merge-request API). See `HermesDaemon`.
public struct GitLabClient: Sendable {
    private let apiBaseUrl: String   // e.g. https://git.iwf.io/api/v4
    private let token: String
    private let useDirectAPI: Bool   // true when backend == "api"

    public init(apiBaseUrl: String, token: String, backend: String? = nil) {
        self.apiBaseUrl = apiBaseUrl
        self.token = token
        self.useDirectAPI = (backend == "api")
    }

    private var headers: [String: String] { ["PRIVATE-TOKEN": token, "Accept": "application/json"] }

    /// Lists merge requests of a project for a given state ("opened" / "merged"). First page (100).
    public func listMergeRequests(projectPath: String, state: String) async throws -> [MergeRequestRef] {
        let encoded = projectPath.replacingOccurrences(of: "/", with: "%2F")
        let url = "\(apiBaseUrl)/projects/\(encoded)/merge_requests?state=\(state)&per_page=100"
        let raw: [RawMR] = useDirectAPI
            ? try await HTTPHelper.getJSON(url, headers: headers)
            : try await HermesDaemon.fetchJSON(url, as: [RawMR].self)
        return raw.map {
            MergeRequestRef(
                iid: $0.iid,
                title: $0.title,
                state: $0.state,
                sourceBranch: $0.source_branch,
                targetBranch: $0.target_branch,
                mergedAt: $0.merged_at,
                webUrl: $0.web_url,
                draft: $0.isDraft
            )
        }
    }

    /// Convenience: opened + merged MRs in one call. Opened MRs additionally carry their number of
    /// unresolved review discussions (fetched per MR, concurrently); merged MRs stay at 0 — their
    /// comments require no action anymore.
    public func openedAndMergedMRs(projectPath: String) async throws -> [MergeRequestRef] {
        async let opened = listMergeRequests(projectPath: projectPath, state: "opened")
        async let merged = listMergeRequests(projectPath: projectPath, state: "merged")
        let openedMRs = await withUnresolvedCounts(try await opened, projectPath: projectPath)
        let mergedMRs = try await merged
        return openedMRs + mergedMRs
    }

    // MARK: - Unresolved discussions (open comments)

    /// Number of unresolved discussions of one MR. A failed fetch counts as 0 — the badge is a
    /// hint, it must never break the board refresh.
    public func unresolvedDiscussionCount(projectPath: String, iid: Int) async -> Int {
        let encoded = projectPath.replacingOccurrences(of: "/", with: "%2F")
        let url = "\(apiBaseUrl)/projects/\(encoded)/merge_requests/\(iid)/discussions?per_page=100"
        guard let raw: [RawDiscussion] = useDirectAPI
            ? try? await HTTPHelper.getJSON(url, headers: headers)
            : try? await HermesDaemon.fetchJSON(url, as: [RawDiscussion].self) else { return 0 }
        return Self.unresolvedCount(raw)
    }

    private func withUnresolvedCounts(_ mrs: [MergeRequestRef],
                                      projectPath: String) async -> [MergeRequestRef] {
        await withTaskGroup(of: (Int, Int).self) { group in
            for mr in mrs {
                group.addTask { (mr.iid, await unresolvedDiscussionCount(projectPath: projectPath, iid: mr.iid)) }
            }
            var byIid: [Int: Int] = [:]
            for await (iid, count) in group { byIid[iid] = count }
            return mrs.map { mr in
                MergeRequestRef(iid: mr.iid, title: mr.title, state: mr.state,
                                sourceBranch: mr.sourceBranch, targetBranch: mr.targetBranch,
                                mergedAt: mr.mergedAt, webUrl: mr.webUrl, draft: mr.draft,
                                unresolvedDiscussions: byIid[mr.iid] ?? 0)
            }
        }
    }

    /// A discussion is "open" when it has at least one resolvable, not-yet-resolved note. System
    /// notes (`resolvable == false`) never count.
    static func unresolvedCount(_ discussions: [RawDiscussion]) -> Int {
        discussions.filter { discussion in
            discussion.notes?.contains { $0.resolvable == true && $0.resolved != true } ?? false
        }.count
    }

    struct RawDiscussion: Decodable {
        let notes: [RawNote]?
    }

    struct RawNote: Decodable {
        let resolvable: Bool?
        let resolved: Bool?
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
