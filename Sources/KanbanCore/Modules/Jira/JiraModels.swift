import Foundation

/// A Jira user as the API returns it, reduced to what a UI shows.
public struct JiraUser: Sendable, Equatable {
    public let accountId: String?
    public let displayName: String
    public let emailAddress: String?
    public let avatarUrl: String?
}

/// An attachment of an issue. `contentUrl` needs the Jira auth header — fetch it through
/// `JiraClient.attachment(url:)`, which follows the redirect to S3 *without* the header.
public struct JiraAttachment: Sendable, Equatable {
    public let id: String?
    public let filename: String
    public let mimeType: String?
    public let size: Int?
    public let contentUrl: String?
    public let created: String?
}

/// One admin-defined field (`customfield_10058` & co.) with the human label from `?expand=names`.
public struct JiraCustomField: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let value: String
}

/// A plain `name: value` line for the exhaustive "Weitere Felder" list.
public struct JiraExtraField: Sendable, Equatable {
    public let id: String
    public let name: String
    public let value: String
}

public struct JiraSubtaskRef: Sendable, Equatable {
    public let key: String
    public let summary: String?
}

public struct JiraLinkedIssue: Sendable, Equatable {
    public let key: String
    public let summary: String?
    public let status: String?
    /// Wording from Jira's link type — „blockiert", „hängt ab von" …
    public let relation: String?
}

/// The time-tracking and bookkeeping block of an issue, formatted the way Jira writes it.
public struct JiraIssueMeta: Sendable, Equatable {
    public let status: String?
    public let priority: String?
    public let resolution: String?
    public let resolutionDate: String?
    public let storyPoints: Double?
    public let labels: [String]
    public let components: [String]
    public let fixVersions: [String]
    public let affectedVersions: [String]
    public let created: String?
    public let updated: String?
    public let dueDate: String?
    public let originalEstimate: String?
    public let remainingEstimate: String?
    public let timeSpent: String?
    /// Nur gesetzt, wenn sie von der Einzelschätzung abweichen (sonst doppelte Zahlen im UI).
    public let aggregateOriginalEstimate: String?
    public let aggregateRemainingEstimate: String?
    public let aggregateTimeSpent: String?
    public let watchers: Int
    public let votes: Int
    public let parent: JiraSubtaskRef?
}

/// A full Jira issue — the Swift counterpart of Hermes' `fetchJiraIssue` result.
public struct JiraIssue: Sendable, Equatable {
    public let key: String
    public let summary: String
    public let issueType: String?
    public let reporter: JiraUser?
    public let assignee: JiraUser?
    public let creator: JiraUser?
    public let meta: JiraIssueMeta

    /// Rich-text fields, already converted to Markdown. The four named custom fields are the ones
    /// this Jira instance uses for the task-file sections; on another instance they are simply nil.
    public let description: String?
    public let environment: String?
    public let ausgangslage: String?          // customfield_10058
    public let erwartetesErgebnis: String?    // customfield_10059
    public let erweiterteBeschreibung: String?// customfield_10077
    public let akzeptanzkriterien: String?    // customfield_10076

    public let customFields: [JiraCustomField]
    public let extraFields: [JiraExtraField]
    public let subtasks: [JiraSubtaskRef]
    public let linkedIssues: [JiraLinkedIssue]
    public let attachments: [JiraAttachment]
    /// Images referenced from the rich-text fields, in document order, with the attachment URL
    /// filled in where one matches by filename.
    public let images: [JiraIssueImage]
}

/// An `ADFImage` after matching it against the issue's attachments.
public struct JiraIssueImage: Sendable, Equatable {
    public let id: String?
    public let originalName: String
    public let filename: String
    public let index: Int
    public let url: String?
    /// True for an attachment that no rich-text field points at — Jira shows those below the
    /// description, so they belong to the issue even though nothing links them.
    public let unreferenced: Bool
}

public struct JiraComment: Sendable, Equatable, Identifiable {
    public let id: String
    public let author: String
    public let authorAccountId: String?
    public let created: String?
    public let updated: String?
    /// ADF, converted to Markdown.
    public let body: String
}

public struct JiraWorklog: Sendable, Equatable, Identifiable {
    public let id: String
    public let author: String
    public let authorAccountId: String?
    public let timeSpentSeconds: Int
    public let started: String?
    public let comment: String?
}

/// One booked entry of the logged-in user, as `userWorklogs(days:)` reports it.
public struct JiraWorklogEntry: Sendable, Equatable {
    /// Story key — a sub-task's time is reported on its parent, like in Hermes.
    public let ticket: String
    public let summary: String?
    public let hours: Double
    public let comment: String
    public let started: String?
}

/// A ticket the current user booked time on within the queried window.
public struct JiraWorklogTicket: Sendable, Equatable {
    public let key: String
    public let summary: String?
    /// Set when the time was actually booked on a sub-task of `key`.
    public let originalKey: String?
}
