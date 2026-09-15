import Foundation

/// Ein einzelner Merge Request in voller Breite — mehr als `MergeRequestRef`, das nur trägt, was das
/// Board für die Spaltenlogik braucht.
public struct GitLabMergeRequest: Sendable, Equatable {
    public let id: Int
    public let iid: Int
    public let projectId: Int?
    public let title: String
    public let description: String?
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
    public let mergeStatus: String?
    public let webUrl: String
    public let changesCount: String?
    public let userNotesCount: Int?
    /// Das SHA-Tripel, das die Discussions-API für einen Inline-Kommentar verlangt.
    public let diffRefs: GitLabDiffRefs?
}

public struct GitLabDiffRefs: Sendable, Equatable {
    public let baseSha: String?
    public let startSha: String?
    public let headSha: String?
}

public struct GitLabNote: Sendable, Equatable, Identifiable {
    public let id: Int
    public let author: String?
    public let body: String
    public let createdAt: String?
    public let resolved: Bool?
    public let resolvable: Bool?
    public let position: GitLabNotePosition?
}

/// Wo im Diff eine Note hängt (nil bei einem allgemeinen Kommentar).
public struct GitLabNotePosition: Sendable, Equatable {
    public let filePath: String?
    public let newLine: Int?
    public let oldLine: Int?
}

public struct GitLabDiscussion: Sendable, Equatable, Identifiable {
    public let id: String
    /// GitLabs Einzelkommentare sind auch Discussions, nehmen aber **keine** Antworten an.
    public let individual: Bool
    public let notes: [GitLabNote]

    /// Offen, sobald eine auflösbare Note offen ist — dieselbe Regel wie beim Karten-Badge.
    public var isUnresolved: Bool {
        let resolvable = notes.filter { $0.resolvable == true }
        return !resolvable.isEmpty && resolvable.contains { $0.resolved != true }
    }
}

/// Eine geänderte Datei eines MR, ohne den Diff-Text.
public struct GitLabChange: Sendable, Equatable {
    public let oldPath: String
    public let newPath: String
    public let newFile: Bool
    public let renamedFile: Bool
    public let deletedFile: Bool
}

/// Eine geänderte Datei **mit** ihrem Unified Diff — die Grundlage für Inline-Kommentare.
public struct GitLabDiff: Sendable, Equatable {
    public let oldPath: String
    public let newPath: String
    public let diff: String
    public let newFile: Bool
    public let renamedFile: Bool
    public let deletedFile: Bool
}

/// Ein Eintrag aus dem Aktivitäts-Feed (`/events`).
public struct GitLabEvent: Sendable, Equatable {
    public let projectId: Int?
    public let actionName: String?
    public let targetType: String?
    public let targetTitle: String?
    public let createdAt: String?
    public let pushRef: String?
    public let commitCount: Int?
}
