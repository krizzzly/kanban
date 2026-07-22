import Foundation

/// Read-only GitLab client. Auth = `PRIVATE-TOKEN` header, host-guarded.
public struct GitLabClient: Sendable {
    private let apiBaseUrl: String   // e.g. https://git.iwf.io/api/v4
    private let token: String

    public init(apiBaseUrl: String, token: String) {
        self.apiBaseUrl = apiBaseUrl
        self.token = token
    }

    private var headers: [String: String] { ["PRIVATE-TOKEN": token, "Accept": "application/json"] }

    /// Lists merge requests of a project for a given state ("opened" / "merged"). First page (100).
    public func listMergeRequests(projectPath: String, state: String) async throws -> [MergeRequestRef] {
        let encoded = projectPath.replacingOccurrences(of: "/", with: "%2F")
        let url = "\(apiBaseUrl)/projects/\(encoded)/merge_requests?state=\(state)&per_page=100"
        let raw: [RawMR] = try await HTTPHelper.getJSON(url, headers: headers)
        return raw.map {
            MergeRequestRef(
                iid: $0.iid,
                title: $0.title,
                state: $0.state,
                sourceBranch: $0.source_branch,
                targetBranch: $0.target_branch,
                mergedAt: $0.merged_at,
                webUrl: $0.web_url
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
    }
}
