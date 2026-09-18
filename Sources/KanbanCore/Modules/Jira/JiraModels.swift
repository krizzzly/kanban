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
    /// Die Id des Kommentars, auf den dieser antwortet. Trägt Jiras Antwort-Funktion; ohne sie ist
    /// der Export eine flache Liste und jeder Leser muss das Gespräch aus „@-Erwähnungen" raten.
    ///
    /// Nur die eigene Kommentar-Ressource liefert das Feld — die Feld-Projektion `?fields=comment`
    /// lässt es weg.
    public let parentId: String?
    public let author: String
    public let authorAccountId: String?
    /// Das Profilbild des Autors, noch als **Fernadresse**. Der Export lädt es herunter und ersetzt
    /// es durch den lokalen Pfad; in der geschriebenen `comments.json` steht dieses Feld nicht mehr.
    public let avatarUrl: String?
    public let created: String?
    public let updated: String?
    /// ADF, converted to Markdown.
    public let body: String

    public init(id: String, parentId: String? = nil, author: String, authorAccountId: String? = nil,
                avatarUrl: String? = nil, created: String? = nil, updated: String? = nil, body: String) {
        self.id = id
        self.parentId = parentId
        self.author = author
        self.authorAccountId = authorAccountId
        self.avatarUrl = avatarUrl
        self.created = created
        self.updated = updated
        self.body = body
    }
}

/// Der Inhalt einer Unteraufgabe für den Export — dasselbe, was Hermes' `fetchSubtaskData` liefert.
///
/// `nextImageIndex` ist der Grund, warum das ein eigener Typ ist und kein Tupel: der Bildzähler
/// läuft über das Haupt-Ticket **und** alle Unteraufgaben durch, sonst zeigen zwei `{{IMG_n}}` aus
/// verschiedenen Unteraufgaben auf dieselbe Datei.
public struct JiraSubtaskContent: Sendable, Equatable {
    public let key: String
    public let summary: String?
    public let description: String?
    public let akzeptanzkriterien: String?
    public let customFields: [JiraCustomField]
    public let images: [JiraIssueImage]
    public let nextImageIndex: Int

    public init(key: String, summary: String?, description: String?, akzeptanzkriterien: String?,
                customFields: [JiraCustomField], images: [JiraIssueImage], nextImageIndex: Int) {
        self.key = key
        self.summary = summary
        self.description = description
        self.akzeptanzkriterien = akzeptanzkriterien
        self.customFields = customFields
        self.images = images
        self.nextImageIndex = nextImageIndex
    }
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
