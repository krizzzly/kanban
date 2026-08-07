import Foundation

public struct JiraBoard: Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let type: String?
}

public struct JiraSprint: Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let state: String?        // active / future / closed
    public let startDate: String?
    public let endDate: String?
}

/// Read-only Jira Agile/REST client. Auth = Basic base64(email:apiToken), host-guarded.
public struct JiraClient: Sendable {
    private let email: String
    private let apiToken: String

    public init(email: String, apiToken: String) {
        self.email = email
        self.apiToken = apiToken
    }

    private var headers: [String: String] {
        let creds = Data("\(email):\(apiToken)".utf8).base64EncodedString()
        return ["Authorization": "Basic \(creds)", "Accept": "application/json"]
    }

    /// Resolves the board for a project prefix, preferring a scrum board.
    public func board(prefix: String, baseUrl: String) async throws -> JiraBoard? {
        let url = "\(baseUrl)/rest/agile/1.0/board?projectKeyOrId=\(prefix.uppercased())&maxResults=50"
        let list: BoardList = try await HTTPHelper.getJSON(url, headers: headers)
        let boards = list.values.map { JiraBoard(id: $0.id, name: $0.name, type: $0.type) }
        return boards.first { $0.type == "scrum" } ?? boards.first
    }

    /// Lists sprints of a board for the given states (comma-separated, e.g. "active,future,closed").
    public func sprints(boardId: Int, baseUrl: String, states: String) async throws -> [JiraSprint] {
        let url = "\(baseUrl)/rest/agile/1.0/board/\(boardId)/sprint?state=\(states)&maxResults=50"
        let list: SprintList = try await HTTPHelper.getJSON(url, headers: headers)
        return list.values.map {
            JiraSprint(id: $0.id, name: $0.name, state: $0.state, startDate: $0.startDate, endDate: $0.endDate)
        }
    }

    /// Issues of a sprint, mapped to lightweight `Ticket`s. `epic` is an Agile-API-only field and
    /// carries the epic's colour; `parent` lets a sub-task inherit it (see `EpicResolution`).
    public func sprintIssues(sprintId: Int, baseUrl: String) async throws -> [Ticket] {
        let fields = "summary,status,assignee,issuetype,priority,storyPoints,customfield_10016,epic,parent"
        let url = "\(baseUrl)/rest/agile/1.0/sprint/\(sprintId)/issue?maxResults=100&fields=\(fields)"
        let list: IssueList = try await HTTPHelper.getJSON(url, headers: headers)
        return list.issues.map { issue in
            let fields = issue.fields
            let points: Double? = fields.customfield_10016 ?? fields.storyPoints
            return Ticket(
                key: issue.key,
                summary: fields.summary ?? "",
                status: fields.status?.name,
                statusCategory: fields.status?.statusCategory?.key,
                assignee: fields.assignee?.displayName,
                assigneeAvatarUrl: fields.assignee?.bestAvatarUrl,
                type: fields.issuetype?.name,
                priority: fields.priority?.name,
                storyPoints: points,
                epic: fields.epic?.asEpicRef,
                parentKey: fields.parent?.key,
                isSubtask: fields.issuetype?.subtask ?? false
            )
        }
    }

    /// Books a worklog on `issueKey`. `started` is when the work is logged (Jira keys the day off it);
    /// `comment` is optional and wrapped into the ADF shape the v3 API requires. Throws on rejection
    /// (`APIError.jira` carries Jira's own message), so the caller only records a booking that stuck.
    public func addWorklog(issueKey: String, timeSpentSeconds: Int,
                           started: Date, comment: String?, baseUrl: String) async throws {
        let url = "\(baseUrl)/rest/api/3/issue/\(issueKey)/worklog"
        var body: [String: Any] = [
            "timeSpentSeconds": timeSpentSeconds,
            "started": Self.jiraTimestamp(started),
        ]
        if let comment, !comment.isEmpty {
            body["comment"] = [
                "type": "doc", "version": 1,
                "content": [["type": "paragraph",
                             "content": [["type": "text", "text": comment]]]],
            ]
        }
        try await HTTPHelper.postJSON(url, headers: headers, body: body)
    }

    /// The `started` format Jira Cloud insists on: milliseconds and a `+hhmm` offset, no colon.
    private static func jiraTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter.string(from: date)
    }

    /// Minimal description fallback (when no task file exists): fetches the issue's ADF
    /// description and flattens it to plain markdown-ish text.
    public func issueDescription(key: String, baseUrl: String) async throws -> String {
        let url = "\(baseUrl)/rest/api/3/issue/\(key)?fields=description"
        let data = try await HTTPHelper.getData(url, headers: headers)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = json["fields"] as? [String: Any],
              let adf = fields["description"] as? [String: Any] else {
            return ""
        }
        return ADFFlattener.flatten(adf)
    }

    // MARK: - Raw decoding

    private struct BoardList: Decodable { let values: [RawBoard] }
    private struct RawBoard: Decodable { let id: Int; let name: String; let type: String? }

    private struct SprintList: Decodable { let values: [RawSprint] }
    private struct RawSprint: Decodable {
        let id: Int; let name: String; let state: String?
        let startDate: String?; let endDate: String?
    }

    private struct IssueList: Decodable { let issues: [RawIssue] }
    private struct RawIssue: Decodable { let key: String; let fields: RawFields }
    private struct RawFields: Decodable {
        let summary: String?
        let status: RawStatus?
        let assignee: RawUser?
        let issuetype: Named?
        let priority: Named?
        let customfield_10016: Double?
        let storyPoints: Double?
        let epic: RawEpic?
        let parent: RawParent?
    }
    private struct Named: Decodable { let name: String?; let subtask: Bool? }
    private struct RawParent: Decodable { let key: String? }
    private struct RawEpic: Decodable {
        let key: String?
        let name: String?         // empty on issue-type epics — the summary holds the name there
        let summary: String?
        let color: ColorKey?      // { "key": "color_14" }
        let issueColor: ColorKey?  // { "key": "purple" }

        struct ColorKey: Decodable { let key: String? }

        var asEpicRef: EpicRef? {
            guard let key, !key.isEmpty else { return nil }
            let title = (name?.isEmpty == false ? name : summary) ?? ""
            return EpicRef(key: key, title: title,
                           colorName: issueColor?.key, paletteKey: color?.key)
        }
    }
    private struct RawStatus: Decodable {
        let name: String?
        let statusCategory: RawStatusCategory?
    }
    private struct RawStatusCategory: Decodable { let key: String? }   // new / indeterminate / done
    private struct RawUser: Decodable {
        let displayName: String?
        let avatarUrls: [String: String]?

        /// Largest available avatar (Jira offers 16/24/32/48px keyed as "48x48" etc.).
        var bestAvatarUrl: String? {
            avatarUrls?["48x48"] ?? avatarUrls?["32x32"] ?? avatarUrls?["24x24"] ?? avatarUrls?.values.first
        }
    }
}

/// A tiny ADF → text flattener — just enough to show a description when no task file exists.
enum ADFFlattener {
    static func flatten(_ node: [String: Any]) -> String {
        var out = ""
        walk(node, into: &out)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func walk(_ node: [String: Any], into out: inout String) {
        let type = node["type"] as? String
        if type == "text", let text = node["text"] as? String {
            out += text
        }
        if let content = node["content"] as? [[String: Any]] {
            for (i, child) in content.enumerated() {
                if child["type"] as? String == "listItem" { out += "- " }
                walk(child, into: &out)
                let childType = child["type"] as? String
                if childType == "paragraph" || childType == "listItem" || childType == "heading" {
                    out += "\n"
                    if i < content.count - 1 { out += "\n" }
                }
            }
        }
    }
}
