import Foundation

/// Die Endpunkte des GitHub-Moduls jenseits der PR-Liste — Gegenstück zu `GitLabFetch`. Die
/// Board-Sicht (Liste + Thread-Zähler + Zustimmung) steht in `GitHubClient`.
///
/// Wie bei GitLab hat ein Teil dieser Fläche vorerst **nur Tests als Aufrufer**: die Oberfläche
/// liest heute nur Listen. Das ist so entschieden — die Detail-Ebene kommt pro Feature, und eine
/// halbe Forge wäre schlechter als eine ganze, die noch nicht überall angeschlossen ist.
public extension GitHubClient {
    // MARK: - Pull Request

    /// Ein einzelner PR in voller Breite, inklusive `head.sha` — ohne den kann kein Inline-Kommentar
    /// gesetzt werden (GitHubs Gegenstück zu GitLabs `diff_refs`).
    func pullRequest(projectPath: String, iid: Int) async throws -> GitHubPullRequest {
        let raw: JSONValue = try await http.getJSON(prURL(projectPath, iid))
        return Self.parsePullRequest(raw)
    }

    /// Die Reviews eines PR, aufsteigend — die Historie, aus der `approval` sein Urteil zieht.
    func reviews(projectPath: String, iid: Int) async throws -> [GitHubReview] {
        let raw: [JSONValue] = try await http.pagedJSON("\(prURL(projectPath, iid))/reviews")
        return raw.map(Self.parseReview)
    }

    /// Die allgemeinen Kommentare eines PR. GitHub führt sie als **Issue**-Kommentare — ein Pull
    /// Request ist dort ein Issue mit Branch, und `/pulls/{n}/comments` meint etwas anderes
    /// (die Kommentare an Diff-Zeilen, siehe `reviewComments`).
    func comments(projectPath: String, iid: Int) async throws -> [GitHubComment] {
        let raw: [JSONValue] = try await http.pagedJSON(
            "\(apiBaseUrl)/repos/\(projectPath)/issues/\(iid)/comments")
        return raw.map(Self.parseComment)
    }

    /// Die Kommentare an Diff-Zeilen. `in_reply_to_id` verkettet sie zu Threads; ob ein Thread
    /// **aufgelöst** ist, steht hier trotzdem nicht — das gibt es nur in GraphQL
    /// (`GitHubClient.discussionCounts`).
    func reviewComments(projectPath: String, iid: Int) async throws -> [GitHubComment] {
        let raw: [JSONValue] = try await http.pagedJSON("\(prURL(projectPath, iid))/comments")
        return raw.map(Self.parseComment)
    }

    /// Die geänderten Dateien eines PR samt Unified Diff (`patch`).
    ///
    /// Eine Datei ohne `patch` ist kein Fehler: GitHub lässt ihn bei binären und bei sehr grossen
    /// Dateien weg. Sie bleibt in der Liste (sie **ist** geändert), nur kommentierbar ist sie nicht
    /// — `PRDiffPosition` sagt das dann mit eigener Meldung.
    func diffs(projectPath: String, iid: Int) async throws -> [GitHubDiff] {
        let raw: [JSONValue] = try await http.pagedJSON("\(prURL(projectPath, iid))/files")
        return raw.map(Self.parseDiff)
    }

    // MARK: - Schreiben

    /// Ein allgemeiner Kommentar am PR (GitHubs Issue-Kommentar, siehe `comments`).
    @discardableResult
    func addComment(projectPath: String, iid: Int, body: String) async throws -> Int? {
        let response: JSONValue = try await http.postJSON(
            "\(apiBaseUrl)/repos/\(projectPath)/issues/\(iid)/comments",
            body: ["body": body], as: JSONValue.self)
        return response.value(at: ["id"])?.intValue
    }

    /// Ein Inline-Kommentar an einer Diff-Zeile. Die Position kommt aus `PRDiffPosition.resolve`,
    /// der Commit aus `pullRequest(...).headSha` — GitHub lehnt den POST ohne beides ab.
    @discardableResult
    func addReviewComment(projectPath: String, iid: Int, body: String,
                          position: [String: Any]) async throws -> Int? {
        var payload = position
        payload["body"] = body
        let response: JSONValue = try await http.postJSON("\(prURL(projectPath, iid))/comments",
                                                          body: payload, as: JSONValue.self)
        return response.value(at: ["id"])?.intValue
    }

    /// Antwort auf einen bestehenden Review-Kommentar. Ohne Position — die Antwort erbt die des
    /// Threads, genau wie bei GitLab.
    @discardableResult
    func reply(projectPath: String, iid: Int, commentId: Int, body: String) async throws -> Int? {
        let response: JSONValue = try await http.postJSON(
            "\(prURL(projectPath, iid))/comments/\(commentId)/replies",
            body: ["body": body], as: JSONValue.self)
        return response.value(at: ["id"])?.intValue
    }

    // MARK: - Hilfen

    private func prURL(_ projectPath: String, _ iid: Int) -> String {
        "\(apiBaseUrl)/repos/\(projectPath)/pulls/\(iid)"
    }

    static func parsePullRequest(_ raw: JSONValue) -> GitHubPullRequest {
        func logins(_ key: String) -> [String] {
            (raw.value(at: [key])?.arrayValue ?? []).compactMap {
                $0.value(at: ["name"])?.stringValue ?? $0.value(at: ["login"])?.stringValue
            }
        }
        let mergedAt = raw.value(at: ["merged_at"])?.stringValue
        let headRepo = raw.value(at: ["head", "repo", "full_name"])?.stringValue
        let baseRepo = raw.value(at: ["base", "repo", "full_name"])?.stringValue

        return GitHubPullRequest(
            id: raw.value(at: ["id"])?.intValue ?? 0,
            iid: raw.value(at: ["number"])?.intValue ?? 0,
            title: raw.value(at: ["title"])?.stringValue ?? "",
            body: raw.value(at: ["body"])?.stringValue,
            state: GitHubClient.normalizedState(raw.value(at: ["state"])?.stringValue,
                                                mergedAt: mergedAt),
            draft: raw.value(at: ["draft"])?.boolValue ?? false,
            author: raw.value(at: ["user", "login"])?.stringValue,
            assignees: logins("assignees"),
            reviewers: logins("requested_reviewers"),
            sourceBranch: GitHubClient.sourceBranch(raw),
            targetBranch: raw.value(at: ["base", "ref"])?.stringValue ?? "",
            labels: (raw.value(at: ["labels"])?.arrayValue ?? [])
                .compactMap { $0.value(at: ["name"])?.stringValue },
            createdAt: raw.value(at: ["created_at"])?.stringValue,
            updatedAt: raw.value(at: ["updated_at"])?.stringValue,
            mergedAt: mergedAt,
            mergedBy: raw.value(at: ["merged_by", "login"])?.stringValue,
            mergeable: raw.value(at: ["mergeable"])?.boolValue,
            webUrl: raw.value(at: ["html_url"])?.stringValue ?? "",
            changedFiles: raw.value(at: ["changed_files"])?.intValue,
            commentCount: raw.value(at: ["comments"])?.intValue,
            headSha: raw.value(at: ["head", "sha"])?.stringValue,
            baseSha: raw.value(at: ["base", "sha"])?.stringValue,
            // Nur ein **bekannter** Unterschied zählt als Fork: fehlt eine der beiden Angaben,
            // ist „nein" die Antwort, die nichts kaputtmacht.
            fromFork: headRepo != nil && baseRepo != nil && headRepo != baseRepo)
    }

    static func parseReview(_ raw: JSONValue) -> GitHubReview {
        GitHubReview(id: raw.value(at: ["id"])?.intValue ?? 0,
                     author: raw.value(at: ["user", "login"])?.stringValue,
                     state: (raw.value(at: ["state"])?.stringValue ?? "").uppercased(),
                     body: raw.value(at: ["body"])?.stringValue,
                     submittedAt: raw.value(at: ["submitted_at"])?.stringValue,
                     commitId: raw.value(at: ["commit_id"])?.stringValue)
    }

    static func parseComment(_ raw: JSONValue) -> GitHubComment {
        let path = raw.value(at: ["path"])?.stringValue
        let position: GitHubCommentPosition? = path.map { file in
            GitHubCommentPosition(path: file,
                                  line: raw.value(at: ["line"])?.intValue
                                    ?? raw.value(at: ["original_line"])?.intValue,
                                  side: raw.value(at: ["side"])?.stringValue,
                                  commitId: raw.value(at: ["commit_id"])?.stringValue)
        }
        return GitHubComment(id: raw.value(at: ["id"])?.intValue ?? 0,
                             author: raw.value(at: ["user", "login"])?.stringValue,
                             body: raw.value(at: ["body"])?.stringValue ?? "",
                             createdAt: raw.value(at: ["created_at"])?.stringValue,
                             position: position,
                             inReplyTo: raw.value(at: ["in_reply_to_id"])?.intValue)
    }

    /// Ein Eintrag aus `GET /pulls/{n}/files` in dieselbe Form wie GitLabs Diff.
    ///
    /// GitHub führt **einen** Pfad (`filename`, der neue) plus `previous_filename` beim Rename und
    /// `status` statt dreier Flags. Umbenannt heisst `renamed`, gelöscht `removed` — und bei einer
    /// gelöschten Datei ist `filename` der alte Pfad, weil es keinen neuen gibt.
    static func parseDiff(_ raw: JSONValue) -> GitHubDiff {
        let filename = raw.value(at: ["filename"])?.stringValue ?? ""
        let previous = raw.value(at: ["previous_filename"])?.stringValue
        let status = raw.value(at: ["status"])?.stringValue ?? ""
        return GitHubDiff(oldPath: previous ?? filename,
                          newPath: filename,
                          diff: raw.value(at: ["patch"])?.stringValue ?? "",
                          newFile: status == "added",
                          renamedFile: status == "renamed",
                          deletedFile: status == "removed")
    }
}
