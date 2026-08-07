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

    /// Convenience: opened + merged MRs in one call.
    public func openedAndMergedMRs(projectPath: String) async throws -> [MergeRequestRef] {
        async let opened = listMergeRequests(projectPath: projectPath, state: "opened")
        async let merged = listMergeRequests(projectPath: projectPath, state: "merged")
        let openedMRs = try await opened
        let mergedMRs = try await merged
        return openedMRs + mergedMRs
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
