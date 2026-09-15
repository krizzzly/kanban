import Foundation

/// Die Endpunkte des GitLab-Moduls jenseits der MR-Liste — Gegenstück zu Hermes'
/// `modules/gitlab/fetch.js`. Die Board-Sicht (Liste + Thread-Zähler + Approval) steht in
/// `GitLabClient`.
public extension GitLabClient {
    // MARK: - Merge Request

    /// Ein einzelner MR in voller Breite, inklusive `diff_refs` — ohne die kann kein Inline-Kommentar
    /// gesetzt werden.
    func mergeRequest(projectPath: String, iid: Int) async throws -> GitLabMergeRequest {
        let raw: JSONValue = try await http.getJSON(mrURL(projectPath, iid))
        return Self.parseMergeRequest(raw)
    }

    /// Alle Notes eines MR, aufsteigend. System-Notes („changed the description") fliegen raus — sie
    /// sind Protokoll, kein Gespräch.
    func notes(projectPath: String, iid: Int) async throws -> [GitLabNote] {
        let raw: [JSONValue] = try await http.pagedJSON("\(mrURL(projectPath, iid))/notes?sort=asc")
        return raw.filter { $0.value(at: ["system"])?.boolValue != true }.map(Self.parseNote)
    }

    /// Die Review-Threads eines MR mit vollem Inhalt — dieselbe Quelle, aus der das Karten-Badge
    /// bisher nur gezählt hat (`discussionCounts`).
    func discussions(projectPath: String, iid: Int) async throws -> [GitLabDiscussion] {
        let raw: [JSONValue] = try await http.pagedJSON("\(mrURL(projectPath, iid))/discussions")
        return raw.compactMap { discussion in
            let notes = discussion.value(at: ["notes"])?.arrayValue ?? []
            guard let first = notes.first, first.value(at: ["system"])?.boolValue != true else { return nil }
            return GitLabDiscussion(
                id: discussion.value(at: ["id"])?.stringValue ?? "",
                individual: discussion.value(at: ["individual_note"])?.boolValue == true,
                notes: notes.map(Self.parseNote))
        }
    }

    /// Der Thread, in dem eine Note hängt — damit lässt sich auf den Anker antworten, den ein
    /// Reviewer aus der URL kopiert (`#note_12345`).
    func discussion(projectPath: String, iid: Int, noteId: Int) async throws
        -> (discussionId: String, individual: Bool)? {
        let raw: [JSONValue] = try await http.pagedJSON("\(mrURL(projectPath, iid))/discussions")
        for discussion in raw {
            let notes = discussion.value(at: ["notes"])?.arrayValue ?? []
            guard notes.contains(where: { $0.value(at: ["id"])?.intValue == noteId }) else { continue }
            return (discussion.value(at: ["id"])?.stringValue ?? "",
                    discussion.value(at: ["individual_note"])?.boolValue == true)
        }
        return nil
    }

    /// Die geänderten Dateien eines MR, ohne Diff-Text.
    func changes(projectPath: String, iid: Int) async throws -> [GitLabChange] {
        let raw: JSONValue = try await http.getJSON("\(mrURL(projectPath, iid))/changes")
        return (raw.value(at: ["changes"])?.arrayValue ?? []).map { change in
            GitLabChange(oldPath: change.value(at: ["old_path"])?.stringValue ?? "",
                         newPath: change.value(at: ["new_path"])?.stringValue ?? "",
                         newFile: change.value(at: ["new_file"])?.boolValue ?? false,
                         renamedFile: change.value(at: ["renamed_file"])?.boolValue ?? false,
                         deletedFile: change.value(at: ["deleted_file"])?.boolValue ?? false)
        }
    }

    /// Die Diffs je Datei. `/diffs` (GitLab ≥ 15.7) paginiert saubere Seiten; ältere Instanzen kennen
    /// nur `/changes`, das alles auf einmal liefert — deshalb der Rückfall.
    func diffs(projectPath: String, iid: Int) async throws -> [GitLabDiff] {
        if let paged: [JSONValue] = try? await http.pagedJSON("\(mrURL(projectPath, iid))/diffs"),
           !paged.isEmpty {
            return paged.map(Self.parseDiff)
        }
        let raw: JSONValue = try await http.getJSON("\(mrURL(projectPath, iid))/changes")
        return (raw.value(at: ["changes"])?.arrayValue ?? []).map(Self.parseDiff)
    }

    // MARK: - Schreiben

    /// Ein allgemeiner Kommentar am MR.
    @discardableResult
    func addNote(projectPath: String, iid: Int, body: String) async throws -> Int? {
        let response: JSONValue = try await http.postJSON("\(mrURL(projectPath, iid))/notes",
                                                          body: ["body": body], as: JSONValue.self)
        return response.value(at: ["id"])?.intValue
    }

    /// Ein Inline-Kommentar an einer Diff-Zeile. Die Position kommt aus `MRDiffPosition.resolve`,
    /// das SHA-Tripel aus `mergeRequest(...).diffRefs` — GitLab lehnt den POST ohne beides ab.
    @discardableResult
    func addDiscussion(projectPath: String, iid: Int, body: String,
                       position: [String: Any]) async throws -> String? {
        let response: JSONValue = try await http.postJSON(
            "\(mrURL(projectPath, iid))/discussions",
            body: ["body": body, "position": position], as: JSONValue.self)
        return response.value(at: ["id"])?.stringValue
    }

    /// Antwort in einen bestehenden Thread. Ohne `position` — die Antwort erbt die des Threads.
    @discardableResult
    func reply(projectPath: String, iid: Int, discussionId: String, body: String) async throws -> Int? {
        let encoded = discussionId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? discussionId
        let response: JSONValue = try await http.postJSON(
            "\(mrURL(projectPath, iid))/discussions/\(encoded)/notes",
            body: ["body": body], as: JSONValue.self)
        return response.value(at: ["id"])?.intValue
    }

    // MARK: - Aktivität und Projekte

    /// Der eigene Aktivitäts-Feed der letzten `days` Tage (`/events`, alle Seiten).
    func userActivity(days: Int = 7) async throws -> [GitLabEvent] {
        let after = JiraClient.isoDay(daysAgo: days + 1)
        let raw: [JSONValue] = try await http.pagedJSON("\(apiBaseUrl)/events?after=\(after)")
        return raw.map { event in
            GitLabEvent(projectId: event.value(at: ["project_id"])?.intValue,
                        actionName: event.value(at: ["action_name"])?.stringValue,
                        targetType: event.value(at: ["target_type"])?.stringValue,
                        targetTitle: event.value(at: ["target_title"])?.stringValue,
                        createdAt: event.value(at: ["created_at"])?.stringValue,
                        pushRef: event.value(at: ["push_data", "ref"])?.stringValue,
                        commitCount: event.value(at: ["push_data", "commit_count"])?.intValue)
        }
    }

    /// Numerische Projekt-Ids (wie sie im Aktivitäts-Feed stehen) → Projekt-Pfad. Ein Fehlschlag
    /// liefert `project-<id>` statt zu werfen: die Auflösung ist Beschriftung, kein Inhalt.
    func resolveProjects(ids: [Int]) async -> [Int: String] {
        await withTaskGroup(of: (Int, String).self) { group in
            for id in Set(ids) {
                group.addTask {
                    let raw: JSONValue? = try? await http.getJSON("\(apiBaseUrl)/projects/\(id)")
                    let path = raw?.value(at: ["path_with_namespace"])?.stringValue
                        ?? raw?.value(at: ["path"])?.stringValue
                    return (id, path ?? "project-\(id)")
                }
            }
            var result: [Int: String] = [:]
            for await (id, path) in group { result[id] = path }
            return result
        }
    }

    // MARK: - Hilfen

    private func mrURL(_ projectPath: String, _ iid: Int) -> String {
        "\(apiBaseUrl)/projects/\(Self.encode(projectPath))/merge_requests/\(iid)"
    }

    static func encode(_ projectPath: String) -> String {
        projectPath.replacingOccurrences(of: "/", with: "%2F")
    }

    static func parseMergeRequest(_ raw: JSONValue) -> GitLabMergeRequest {
        func names(_ key: String) -> [String] {
            (raw.value(at: [key])?.arrayValue ?? []).compactMap {
                $0.value(at: ["name"])?.stringValue ?? $0.value(at: ["username"])?.stringValue
            }
        }
        let title = raw.value(at: ["title"])?.stringValue ?? ""
        let draft = raw.value(at: ["draft"])?.boolValue
            ?? raw.value(at: ["work_in_progress"])?.boolValue
            ?? Self.hasDraftTitle(title)

        return GitLabMergeRequest(
            id: raw.value(at: ["id"])?.intValue ?? 0,
            iid: raw.value(at: ["iid"])?.intValue ?? 0,
            projectId: raw.value(at: ["project_id"])?.intValue,
            title: title,
            description: raw.value(at: ["description"])?.stringValue,
            state: raw.value(at: ["state"])?.stringValue ?? "",
            draft: draft,
            author: raw.value(at: ["author", "name"])?.stringValue
                ?? raw.value(at: ["author", "username"])?.stringValue,
            assignees: names("assignees"),
            reviewers: names("reviewers"),
            sourceBranch: raw.value(at: ["source_branch"])?.stringValue ?? "",
            targetBranch: raw.value(at: ["target_branch"])?.stringValue ?? "",
            labels: (raw.value(at: ["labels"])?.arrayValue ?? []).compactMap(\.stringValue),
            createdAt: raw.value(at: ["created_at"])?.stringValue,
            updatedAt: raw.value(at: ["updated_at"])?.stringValue,
            mergedAt: raw.value(at: ["merged_at"])?.stringValue,
            mergedBy: raw.value(at: ["merged_by", "name"])?.stringValue,
            mergeStatus: raw.value(at: ["detailed_merge_status"])?.stringValue
                ?? raw.value(at: ["merge_status"])?.stringValue,
            webUrl: raw.value(at: ["web_url"])?.stringValue ?? "",
            changesCount: raw.value(at: ["changes_count"])?.stringValue,
            userNotesCount: raw.value(at: ["user_notes_count"])?.intValue,
            diffRefs: raw.value(at: ["diff_refs"]).map {
                GitLabDiffRefs(baseSha: $0.value(at: ["base_sha"])?.stringValue,
                               startSha: $0.value(at: ["start_sha"])?.stringValue,
                               headSha: $0.value(at: ["head_sha"])?.stringValue)
            })
    }

    static func parseNote(_ raw: JSONValue) -> GitLabNote {
        let position = raw.value(at: ["position"]).map {
            GitLabNotePosition(filePath: $0.value(at: ["new_path"])?.stringValue
                                ?? $0.value(at: ["old_path"])?.stringValue,
                               newLine: $0.value(at: ["new_line"])?.intValue,
                               oldLine: $0.value(at: ["old_line"])?.intValue)
        }
        return GitLabNote(id: raw.value(at: ["id"])?.intValue ?? 0,
                          author: raw.value(at: ["author", "name"])?.stringValue
                            ?? raw.value(at: ["author", "username"])?.stringValue,
                          body: raw.value(at: ["body"])?.stringValue ?? "",
                          createdAt: raw.value(at: ["created_at"])?.stringValue,
                          resolved: raw.value(at: ["resolved"])?.boolValue,
                          resolvable: raw.value(at: ["resolvable"])?.boolValue,
                          position: position)
    }

    static func parseDiff(_ raw: JSONValue) -> GitLabDiff {
        GitLabDiff(oldPath: raw.value(at: ["old_path"])?.stringValue ?? "",
                   newPath: raw.value(at: ["new_path"])?.stringValue ?? "",
                   diff: raw.value(at: ["diff"])?.stringValue ?? "",
                   newFile: raw.value(at: ["new_file"])?.boolValue ?? false,
                   renamedFile: raw.value(at: ["renamed_file"])?.boolValue ?? false,
                   deletedFile: raw.value(at: ["deleted_file"])?.boolValue ?? false)
    }

    /// Ältere GitLab-Versionen setzen kein Flag, nur den Titel — dieselbe Erkennung wie in
    /// `MergeRequestRef`.
    static func hasDraftTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.hasPrefix("draft:") || lower.hasPrefix("wip:") || lower.hasPrefix("[wip]")
    }
}
