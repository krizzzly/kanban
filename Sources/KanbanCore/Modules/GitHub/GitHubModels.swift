import Foundation

/// Ein einzelner Pull Request in voller Breite — mehr als `MergeRequestRef`, das nur trägt, was das
/// Board für die Spaltenlogik braucht. Gegenstück zu `GitLabMergeRequest`, mit denselben Feldern,
/// wo GitHub dieselbe Sache kennt.
public struct GitHubPullRequest: Sendable, Equatable {
    public let id: Int
    /// GitHubs `number` — dasselbe wie GitLabs `iid`, unter dem Namen, den die Domäne benutzt.
    public let iid: Int
    public let title: String
    public let body: String?
    /// **Normalisiert** (`opened` / `merged` / `closed`), nicht GitHubs rohes `state`.
    public let state: String
    public let draft: Bool
    public let author: String?
    public let assignees: [String]
    public let reviewers: [String]
    public let sourceBranch: String
    public let targetBranch: String
    public let labels: [String]
    public let createdAt: String?
    public let updatedAt: String?
    public let mergedAt: String?
    public let mergedBy: String?
    public let mergeable: Bool?
    public let webUrl: String
    public let changedFiles: Int?
    public let commentCount: Int?
    /// Der Commit, auf den ein Inline-Kommentar zeigen muss (`head.sha`) — GitHubs Gegenstück zu
    /// GitLabs SHA-Tripel, nur eben ein einzelner Wert.
    public let headSha: String?
    public let baseSha: String?
    /// Kommt der Branch aus einem Fork? Dann liegt er nicht im eigenen Repo, und ein lokaler
    /// Checkout braucht einen anderen Weg (`gh pr checkout`).
    public let fromFork: Bool
}

/// Ein Review — GitHubs Einheit der Zustimmung. Anders als GitLabs `/approvals` ist das eine
/// **Historie**: dieselbe Person darf mehrfach darin stehen, es zählt ihr letzter Zustand.
public struct GitHubReview: Sendable, Equatable, Identifiable {
    public let id: Int
    public let author: String?
    /// `APPROVED` / `CHANGES_REQUESTED` / `COMMENTED` / `DISMISSED` / `PENDING`.
    public let state: String
    public let body: String?
    public let submittedAt: String?
    public let commitId: String?
}

/// Ein Kommentar — allgemein (Issue-Kommentar) oder an einer Diff-Zeile (Review-Kommentar).
public struct GitHubComment: Sendable, Equatable, Identifiable {
    public let id: Int
    public let author: String?
    public let body: String
    public let createdAt: String?
    /// nil bei einem allgemeinen Kommentar.
    public let position: GitHubCommentPosition?
    /// Die Antwort-Wurzel eines Review-Threads (`in_reply_to_id`), sonst nil.
    public let inReplyTo: Int?
}

/// Wo im Diff ein Review-Kommentar hängt.
public struct GitHubCommentPosition: Sendable, Equatable {
    public let path: String?
    /// Die Zeile in der **neuen** Fassung (`RIGHT`) bzw. der alten (`LEFT`) — GitHub führt nur eine.
    public let line: Int?
    public let side: String?
    public let commitId: String?
}

/// Ein Review-Thread mit seinem Auflösungsstand. **Nur über GraphQL erreichbar** — GitHubs REST
/// kennt `isResolved` nicht, und genau daran hängt neben dem Badge auch die Review-Spalte.
public struct GitHubReviewThread: Sendable, Equatable {
    public let isResolved: Bool
    public let isOutdated: Bool
}

/// Eine geänderte Datei eines PR **mit** ihrem Unified Diff (`patch`) — die Grundlage für
/// Inline-Kommentare. Feldgleich mit `GitLabDiff`, damit die Diff-Logik auf beiden Seiten dieselbe
/// Form sieht; GitHubs `filename`/`previous_filename`/`status` werden dafür übersetzt.
public struct GitHubDiff: Sendable, Equatable {
    public let oldPath: String
    public let newPath: String
    public let diff: String
    public let newFile: Bool
    public let renamedFile: Bool
    public let deletedFile: Bool

    public init(oldPath: String, newPath: String, diff: String,
                newFile: Bool, renamedFile: Bool, deletedFile: Bool) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.diff = diff
        self.newFile = newFile
        self.renamedFile = renamedFile
        self.deletedFile = deletedFile
    }
}
