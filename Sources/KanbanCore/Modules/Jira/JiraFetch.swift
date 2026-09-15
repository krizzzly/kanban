import Foundation

/// Die Lese- und Schreibwege des Jira-Moduls jenseits des Boards — Gegenstück zu Hermes'
/// `modules/jira/fetch.js`. Das Board selbst (Board/Sprints/Sprint-Issues) steht in `JiraClient`.
///
/// `baseUrl` ist überall ein Parameter statt Zustand, weil ein Projekt auf einer eigenen Instanz
/// liegen darf; der Host-Guard des Transports kennt sie alle.
public extension JiraClient {
    // MARK: - Issue

    /// Ein vollständiges Issue: Rich-Text-Felder als Markdown, Custom Fields mit ihren
    /// Klarnamen, Attachments und die Bilder aus dem Text.
    ///
    /// `?expand=names` liefert die Zuordnung `customfield_XXXXX` → Anzeigename gleich mit — 1–2 KB
    /// mehr pro Antwort, dafür entfällt ein zweiter Request gegen `/rest/api/3/field`.
    func issue(key: String, baseUrl: String) async throws -> JiraIssue {
        let raw: JSONValue = try await http.getJSON("\(baseUrl)/rest/api/3/issue/\(key)?expand=names")
        return Self.parseIssue(key: key, raw: raw)
    }

    /// Reine Zuordnung Key → Summary, für Listen von Fremdtickets (verlinkte Issues, Worklog-Ziele).
    /// Ein Fehlschlag pro Ticket wird geschluckt: die Liste ist Beiwerk, kein Grund zum Abbruch.
    func summaries(keys: [String], baseUrl: String) async -> [String: String] {
        await withTaskGroup(of: (String, String?).self) { group in
            for key in keys {
                group.addTask {
                    let raw: JSONValue? = try? await http.getJSON(
                        "\(baseUrl)/rest/api/3/issue/\(key)?fields=summary")
                    return (key, raw?.value(at: ["fields", "summary"])?.stringValue)
                }
            }
            var result: [String: String] = [:]
            for await (key, summary) in group {
                if let summary { result[key] = summary }
            }
            return result
        }
    }

    /// Kommentare eines Issues, ADF bereits in Markdown übersetzt.
    func comments(key: String, baseUrl: String) async throws -> [JiraComment] {
        let raw: JSONValue = try await http.getJSON("\(baseUrl)/rest/api/3/issue/\(key)?fields=comment")
        return (raw.value(at: ["fields", "comment", "comments"])?.arrayValue ?? []).map { comment in
            let author = JiraFieldExtraction.user(comment.value(at: ["author"]))
            let body = comment.value(at: ["body"]).map { ADFToMarkdown.convert($0).markdown } ?? ""
            return JiraComment(id: comment.value(at: ["id"])?.stringValue ?? "",
                               author: author?.displayName ?? "Unbekannt",
                               authorAccountId: author?.accountId,
                               created: comment.value(at: ["created"])?.stringValue,
                               updated: comment.value(at: ["updated"])?.stringValue,
                               body: body)
        }
    }

    /// Ein Attachment als Rohdaten. Der Download endet bei Atlassian auf einer S3-URL — der
    /// Host-Guard nimmt den Auth-Header beim Hostwechsel raus (`HostGuardDelegate`).
    func attachment(url: String) async throws -> (data: Data, contentType: String?) {
        try await http.getBinary(url)
    }

    // MARK: - Benutzer

    /// Der angemeldete Benutzer (`/myself`) — nötig, um in einer Worklog-Liste die eigenen Einträge
    /// von fremden zu trennen.
    func currentUser(baseUrl: String) async throws -> JiraUser {
        let raw: JSONValue = try await http.getJSON("\(baseUrl)/rest/api/3/myself")
        return JiraFieldExtraction.user(raw)
            ?? JiraUser(accountId: nil, displayName: "Unbekannt", emailAddress: nil, avatarUrl: nil)
    }

    // MARK: - Worklogs (lesend)

    /// Tickets, auf die der angemeldete Benutzer seit `after` (yyyy-MM-dd) Zeit gebucht hat.
    /// Zeit auf einer Unteraufgabe wird auf die Story gemeldet, die Unteraufgabe steht in
    /// `originalKey` — dort muss der Worklog-Abruf ansetzen.
    func worklogTickets(after date: String, baseUrl: String) async throws -> [JiraWorklogTicket] {
        let jql = "worklogDate >= \"\(date)\" AND worklogAuthor = currentUser()"
        let encoded = jql.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? jql
        let url = "\(baseUrl)/rest/api/3/search/jql?jql=\(encoded)&fields=summary,parent&maxResults=100"
        let raw: JSONValue = try await http.getJSON(url)
        return (raw.value(at: ["issues"])?.arrayValue ?? []).map { issue in
            let key = issue.value(at: ["key"])?.stringValue ?? ""
            let summary = issue.value(at: ["fields", "summary"])?.stringValue
            guard let parentKey = issue.value(at: ["fields", "parent", "key"])?.stringValue else {
                return JiraWorklogTicket(key: key, summary: summary, originalKey: nil)
            }
            return JiraWorklogTicket(
                key: parentKey,
                summary: issue.value(at: ["fields", "parent", "fields", "summary"])?.stringValue ?? summary,
                originalKey: key)
        }
    }

    /// Alle Worklogs eines Issues — auch die fremder Leute; das Filtern ist Sache des Aufrufers.
    func worklogs(key: String, baseUrl: String) async throws -> [JiraWorklog] {
        let raw: JSONValue = try await http.getJSON("\(baseUrl)/rest/api/3/issue/\(key)/worklog")
        return (raw.value(at: ["worklogs"])?.arrayValue ?? []).map { entry in
            let author = JiraFieldExtraction.user(entry.value(at: ["author"]))
            return JiraWorklog(id: entry.value(at: ["id"])?.stringValue ?? "",
                               author: author?.displayName ?? "Unbekannt",
                               authorAccountId: author?.accountId,
                               timeSpentSeconds: entry.value(at: ["timeSpentSeconds"])?.intValue ?? 0,
                               started: entry.value(at: ["started"])?.stringValue,
                               comment: Self.commentText(entry.value(at: ["comment"])))
        }
    }

    /// Die eigenen Buchungen der letzten `days` Tage, fertig aggregiert — Hermes' `get-jira-worklog`.
    /// Mehrere Unteraufgaben derselben Story werden vor dem Abruf zusammengefasst.
    func userWorklogs(days: Int = 7, baseUrl: String) async throws -> (user: String, entries: [JiraWorklogEntry]) {
        let after = Self.isoDay(daysAgo: days)
        async let userTask = currentUser(baseUrl: baseUrl)
        async let ticketsTask = worklogTickets(after: after, baseUrl: baseUrl)
        let (me, tickets) = try await (userTask, ticketsTask)
        guard !tickets.isEmpty else { return (me.displayName, []) }

        // originalKey → (Story-Key, Summary): abgefragt wird die Unteraufgabe, gemeldet die Story.
        var targets: [String: (key: String, summary: String?)] = [:]
        for ticket in tickets {
            let fetchKey = ticket.originalKey ?? ticket.key
            if targets[fetchKey] == nil { targets[fetchKey] = (ticket.key, ticket.summary) }
        }

        let entries = await withTaskGroup(of: [JiraWorklogEntry].self) { group in
            for (fetchKey, target) in targets {
                group.addTask {
                    guard let logs = try? await worklogs(key: fetchKey, baseUrl: baseUrl) else { return [] }
                    return logs
                        .filter { $0.authorAccountId == me.accountId }
                        .filter { ($0.started ?? "") >= after }
                        .map { log in
                            JiraWorklogEntry(ticket: target.key, summary: target.summary,
                                             hours: (Double(log.timeSpentSeconds) / 3600 * 100).rounded() / 100,
                                             comment: log.comment ?? "",
                                             started: log.started)
                        }
                }
            }
            var all: [JiraWorklogEntry] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all.sorted { ($0.started ?? "") < ($1.started ?? "") }
        }
        return (me.displayName, entries)
    }

    // MARK: - Hilfen

    /// Ein Worklog-Kommentar ist je nach Jira-Version reiner Text oder ADF.
    static func commentText(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let text = value.stringValue {
            return text.isEmpty ? nil : text
        }
        let markdown = ADFToMarkdown.convert(value).markdown
        return markdown.isEmpty ? nil : markdown
    }

    /// `yyyy-MM-dd`, `days` Tage in der Vergangenheit (UTC, wie Hermes).
    static func isoDay(daysAgo days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Der gemeinsame Parser für `issue(key:)` — ohne Netz, damit er gegen eine Beispielantwort
    /// testbar ist.
    static func parseIssue(key: String, raw: JSONValue) -> JiraIssue {
        let fields = raw.value(at: ["fields"])?.objectValue ?? [:]
        let names = (raw.value(at: ["names"])?.objectValue ?? [:]).compactMapValues(\.stringValue)

        var imageCounter = 0
        var images: [ADFImage] = []

        /// Rich-Text-Feld → Markdown, mit fortlaufender Bildnummer über alle Felder hinweg.
        func markdown(_ field: String) -> String? {
            guard let value = fields[field], value != .null else { return nil }
            let result = ADFToMarkdown.convert(value, imageCounter: imageCounter)
            images.append(contentsOf: result.images)
            imageCounter += result.images.count
            return result.markdown.isEmpty ? nil : result.markdown
        }

        let description = markdown("description")
        let ausgangslage = markdown("customfield_10058")
        let erwartetesErgebnis = markdown("customfield_10059")
        let erweiterteBeschreibung = markdown("customfield_10077")
        let akzeptanzkriterien = markdown("customfield_10076")
        let environment = markdown("environment")

        let customFields = JiraFieldExtraction.customFields(fields, names: names,
                                                            imageCounter: &imageCounter,
                                                            images: &images)
        let attachments = JiraFieldExtraction.attachments(fields["attachment"])

        let subtasks = (fields["subtasks"]?.arrayValue ?? []).compactMap { subtask -> JiraSubtaskRef? in
            guard let key = subtask.value(at: ["key"])?.stringValue else { return nil }
            return JiraSubtaskRef(key: key, summary: subtask.value(at: ["fields", "summary"])?.stringValue)
        }

        let linked = (fields["issuelinks"]?.arrayValue ?? []).compactMap { link -> JiraLinkedIssue? in
            let outward = link.value(at: ["outwardIssue"])
            let issue = outward ?? link.value(at: ["inwardIssue"])
            guard let issue, let key = issue.value(at: ["key"])?.stringValue else { return nil }
            let relation = link.value(at: ["type", outward != nil ? "outward" : "inward"])?.stringValue
            return JiraLinkedIssue(key: key,
                                   summary: issue.value(at: ["fields", "summary"])?.stringValue,
                                   status: issue.value(at: ["fields", "status", "name"])?.stringValue,
                                   relation: relation)
        }

        return JiraIssue(
            key: key,
            summary: fields["summary"]?.stringValue ?? "",
            issueType: fields["issuetype"]?.value(at: ["name"])?.stringValue,
            reporter: JiraFieldExtraction.user(fields["reporter"]),
            assignee: JiraFieldExtraction.user(fields["assignee"]),
            creator: JiraFieldExtraction.user(fields["creator"]),
            meta: JiraFieldExtraction.meta(fields),
            description: description,
            environment: environment,
            ausgangslage: ausgangslage,
            erwartetesErgebnis: erwartetesErgebnis,
            erweiterteBeschreibung: erweiterteBeschreibung,
            akzeptanzkriterien: akzeptanzkriterien,
            customFields: customFields,
            extraFields: JiraFieldExtraction.extraFields(fields, names: names),
            subtasks: subtasks,
            linkedIssues: linked,
            attachments: attachments,
            images: JiraFieldExtraction.images(images, attachments: attachments,
                                               imageCounter: &imageCounter))
    }
}
