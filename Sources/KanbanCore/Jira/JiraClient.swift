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

/// Kanbans Jira-Modul (Gegenstück zu Hermes' `modules/jira`). Transport, Auth und Host-Guard
/// kommen von `ModuleHTTPClient`; hier stehen nur die Endpunkte und ihre Übersetzung in Domain-Typen.
public struct JiraClient: Sendable {
    /// Modul-intern sichtbar, damit die Endpunkte in `JiraFetch.swift` denselben Transport nutzen.
    let http: ModuleHTTPClient

    /// Aus der App-Config: Basic-Auth über den Default-Host **und** jeden Projekt-Host, der ihn
    /// überschreibt — sonst verweigerte der Host-Guard das Projekt auf der fremden Instanz.
    public init(config: AppConfig) {
        self.init(email: config.jiraEmail, apiToken: config.jiraApiToken,
                  baseUrls: [config.jiraDefaultBaseUrl] + config.projects.map(\.jiraBaseUrl))
    }

    public init(email: String, apiToken: String, baseUrls: [String]) {
        http = .jira(email: email, apiToken: apiToken, baseUrls: baseUrls)
    }

    /// Resolves the board for a project prefix, preferring a scrum board.
    public func board(prefix: String, baseUrl: String) async throws -> JiraBoard? {
        let url = "\(baseUrl)/rest/agile/1.0/board?projectKeyOrId=\(prefix.uppercased())&maxResults=50"
        let list: BoardList = try await http.getJSON(url)
        let boards = list.values.map { JiraBoard(id: $0.id, name: $0.name, type: $0.type) }
        return boards.first { $0.type == "scrum" } ?? boards.first
    }

    /// Lists sprints of a board for the given states (comma-separated, e.g. "active,future,closed").
    ///
    /// **Paginiert, und das ist keine Vorsichtsmassnahme.** Jira gibt höchstens 50 Sprints pro Seite
    /// heraus und ordnet sie **alt → neu**: ab dem 51. Sprint fällt damit ausgerechnet der *aktive*
    /// hinten runter. Beobachtet an Board 71 (CORETEST, 69 Sprints) — die App sah „0 aktiv“, wählte
    /// das ganze Board und zeigte 365 Backlog-Tickets statt der 21 des laufenden Sprints.
    public func sprints(boardId: Int, baseUrl: String, states: String) async throws -> [JiraSprint] {
        var sprints: [JiraSprint] = []
        for page in 0..<Self.sprintPageLimit {
            let url = "\(baseUrl)/rest/agile/1.0/board/\(boardId)/sprint"
                + "?state=\(states)&maxResults=\(Self.sprintPageSize)&startAt=\(page * Self.sprintPageSize)"
            let list: SprintList = try await http.getJSON(url)
            sprints += list.values.map {
                JiraSprint(id: $0.id, name: $0.name, state: $0.state,
                           startDate: $0.startDate, endDate: $0.endDate)
            }
            if list.isLast ?? (list.values.count < Self.sprintPageSize) { return sprints }
        }
        throw APIError.tooManyPages(module: "jira", pages: Self.sprintPageLimit)
    }

    /// Jiras Obergrenze für diesen Endpunkt — ein grösserer Wert wird still auf 50 gekappt.
    static let sprintPageSize = 50
    static let sprintPageLimit = 20

    /// Issues of a sprint, mapped to lightweight `Ticket`s. `epic` is an Agile-API-only field and
    /// carries the epic's colour; `parent` lets a sub-task inherit it (see `EpicResolution`).
    /// Paginiert aus demselben Grund wie `sprints`: ein Sprint mit mehr als 100 Issues gäbe sonst
    /// ein stillschweigend halbes Board.
    public func sprintIssues(sprintId: Int, baseUrl: String) async throws -> [Ticket] {
        var tickets: [Ticket] = []
        for page in 0..<Self.boardIssuePageLimit {
            let url = "\(baseUrl)/rest/agile/1.0/sprint/\(sprintId)/issue"
                + "?maxResults=100&startAt=\(page * 100)&fields=\(Self.issueFields)"
            let list: IssueList = try await http.getJSON(url)
            tickets += Self.tickets(from: list, rankOffset: tickets.count)
            if list.issues.count < 100 { return tickets }
        }
        throw APIError.tooManyPages(module: "jira", pages: Self.boardIssuePageLimit)
    }

    /// Was „das Board“ zeigt, wenn kein Sprint es eingrenzt: alles **Offene** — plus, was in den
    /// letzten zwei Wochen fertig wurde.
    ///
    /// Das Nachlauf-Fenster ist nötig, nicht kosmetisch: ohne es verschwindet eine Karte in der
    /// Sekunde, in der Jira sie auf „Erledigt“ setzt — samt ⏱-Zeit, Task-File-Tabs und
    /// Commit-Knopf, also genau dann, wenn noch der Merge und die Lösung anstehen. Ein Sprint
    /// behält seine fertigen Tickets ja auch bis zum Sprint-Ende.
    public static let openBoardJQL = "statusCategory != Done OR resolutiondate >= -14d"

    /// Höchstens so viele Seiten à 100 — ein Board ohne Sprint kann Jahre an Tickets führen.
    /// Lieber ein sichtbarer Abbruch als eine stillschweigend halbe Liste.
    static let boardIssuePageLimit = 5

    /// Issues eines ganzen Boards (statt eines Sprints), gefiltert über `jql` — der Parameter wird
    /// mit dem Board-Filter **und**-verknüpft, das Board bleibt also die Grenze.
    public func boardIssues(boardId: Int, baseUrl: String,
                            jql: String = JiraClient.openBoardJQL) async throws -> [Ticket] {
        let encoded = jql.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? jql
        var tickets: [Ticket] = []
        for page in 0..<Self.boardIssuePageLimit {
            let url = "\(baseUrl)/rest/agile/1.0/board/\(boardId)/issue"
                + "?maxResults=100&startAt=\(page * 100)&jql=\(encoded)&fields=\(Self.issueFields)"
            let list: IssueList = try await http.getJSON(url)
            tickets += Self.tickets(from: list, rankOffset: tickets.count)
            if list.issues.count < 100 { return tickets }
        }
        throw APIError.tooManyPages(module: "jira", pages: Self.boardIssuePageLimit)
    }

    /// `issuelinks` trägt die `Blocks`-Verknüpfungen **samt Status des verknüpften Vorgangs** —
    /// deshalb kostet die Sperr-Ableitung keine einzige Zusatzanfrage (siehe `TicketOrder`).
    private static let issueFields =
        "summary,status,assignee,issuetype,priority,storyPoints,customfield_10016,epic,parent,issuelinks"

    /// `rankOffset` setzt die Rank-Position über Seitengrenzen hinweg fort: die Agile-API liefert
    /// Issues in **Rank-Reihenfolge**, die Position in der Liste *ist* also der Rang. Ohne den
    /// Versatz begänne jede Seite wieder bei 0 und „als nächstes" zeigte auf die falsche Karte.
    static func tickets(from list: IssueList, rankOffset: Int = 0) -> [Ticket] {
        list.issues.enumerated().map { index, issue in
            let fields = issue.fields
            let points: Double? = fields.customfield_10016 ?? fields.storyPoints
            return Ticket(
                key: issue.key,
                summary: fields.summary ?? "",
                status: fields.status?.name,
                statusCategory: fields.status?.statusCategory?.key,
                assignee: fields.assignee?.displayName,
                assigneeAvatarUrl: fields.assignee?.bestAvatarUrl,
                assigneeAccountId: fields.assignee?.accountId,
                type: fields.issuetype?.name,
                typeIconUrl: fields.issuetype?.iconUrl,
                priority: fields.priority?.name,
                storyPoints: points,
                epic: fields.epic?.asEpicRef,
                parentKey: fields.parent?.key,
                isSubtask: fields.issuetype?.subtask ?? false,
                blockedBy: fields.blockers,
                rankIndex: rankOffset + index
            )
        }
    }

    /// Schiebt Vorgänge im Backlog an eine neue Stelle — Jiras **Rank**, dieselbe Ordnung, die die
    /// Backlog-Ansicht per Ziehen ändert.
    ///
    /// Die Agile-API kennt nur „vor" oder „hinter" einem Anker, keine absolute Position: LexoRank
    /// vergibt Schlüssel *zwischen* zwei bestehenden, damit ein Verschieben nicht die ganze Liste
    /// neu nummerieren muss. Genau eines von beidem muss gesetzt sein.
    ///
    /// Höchstens 50 Keys je Aufruf (Jiras Grenze); die Reihenfolge **innerhalb** der Liste bleibt
    /// erhalten.
    public func rankIssues(_ keys: [String], baseUrl: String,
                           before: String? = nil, after: String? = nil) async throws {
        guard !keys.isEmpty else { return }
        precondition(before != nil || after != nil, "rankIssues braucht einen Anker")
        var body: [String: Any] = ["issues": Array(keys.prefix(50))]
        if let before { body["rankBeforeIssue"] = before }
        if let after { body["rankAfterIssue"] = after }
        _ = try await http.putJSON("\(baseUrl)/rest/agile/1.0/issue/rank", body: body)
    }

    /// Books a worklog on `issueKey`. `started` is when the work is logged (Jira keys the day off it);
    /// `comment` is optional and wrapped into the ADF shape the v3 API requires. Throws on rejection
    /// (`APIError.api` trägt Jiras eigene Meldung), so the caller only records a booking that stuck.
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
        try await http.postJSON(url, body: body)
    }

    /// The `started` format Jira Cloud insists on: milliseconds and a `+hhmm` offset, no colon.
    private static func jiraTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter.string(from: date)
    }

    /// Description fallback when no task file exists — jetzt über `ADFToMarkdown`, also mit
    /// Überschriften, Listen und Links statt aneinandergehängtem Text.
    public func issueDescription(key: String, baseUrl: String) async throws -> String {
        let raw: JSONValue = try await http.getJSON("\(baseUrl)/rest/api/3/issue/\(key)?fields=description")
        guard let adf = raw.value(at: ["fields", "description"]), adf != .null else { return "" }
        return ADFToMarkdown.convert(adf).markdown
    }

    // MARK: - Raw decoding

    private struct BoardList: Decodable { let values: [RawBoard] }
    private struct RawBoard: Decodable { let id: Int; let name: String; let type: String? }

    private struct SprintList: Decodable {
        let values: [RawSprint]
        let isLast: Bool?      // Jiras eigenes Ende-Signal; fehlt es, zählt die Seitengrösse
    }
    private struct RawSprint: Decodable {
        let id: Int; let name: String; let state: String?
        let startDate: String?; let endDate: String?
    }

    struct IssueList: Decodable { let issues: [RawIssue] }
    struct RawIssue: Decodable { let key: String; let fields: RawFields }
    struct RawFields: Decodable {
        let summary: String?
        let status: RawStatus?
        let assignee: RawUser?
        let issuetype: Named?
        let priority: Named?
        let customfield_10016: Double?
        let storyPoints: Double?
        let epic: RawEpic?
        let parent: RawParent?
        let issuelinks: [RawLink]?

        /// Nur die Vorgänge, die **dieses** Ticket blockieren.
        ///
        /// Die Richtung ist die Falle, und sie ist nicht zu erraten: im `issuelinks` des gelesenen
        /// Vorgangs steht immer nur die **Gegenseite**. Ein Eintrag mit `inwardIssue` heisst „der
        /// dort blockiert mich", einer mit `outwardIssue` heisst „ich blockiere den dort". Gesucht
        /// ist hier also `inwardIssue`.
        ///
        /// Am echten Jira abgelesen (CENTRISBAU-9, der Compose-Stack): `inwardIssue` ist -8, das
        /// Monorepo-Gerüst, ohne das er nicht gebaut werden kann; `outwardIssue` sind -10, -12, -21,
        /// die auf ihn warten. Aus den Feldnamen allein käme man auf das Gegenteil — siehe
        /// `JiraBlockingLinkTests`, das genau diese Antwort als Testdaten führt.
        var blockers: [BlockingRef] {
            (issuelinks ?? []).compactMap { link in
                guard link.type?.name == "Blocks", let other = link.inwardIssue else { return nil }
                guard let key = other.key else { return nil }
                return BlockingRef(key: key,
                                   summary: other.fields?.summary ?? "",
                                   statusCategory: other.fields?.status?.statusCategory?.key)
            }
        }
    }
    struct RawLink: Decodable {
        let type: LinkType?
        let inwardIssue: LinkedIssue?
        let outwardIssue: LinkedIssue?
        struct LinkType: Decodable { let name: String? }
        struct LinkedIssue: Decodable {
            let key: String?
            let fields: LinkedFields?
            struct LinkedFields: Decodable { let summary: String?; let status: RawStatus? }
        }
    }
    /// `issuetype` and `priority` — `iconUrl` is only ever set on the issue type (an SVG on the Jira host).
    struct Named: Decodable { let name: String?; let subtask: Bool?; let iconUrl: String? }
    struct RawParent: Decodable { let key: String? }
    struct RawEpic: Decodable {
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
    struct RawStatus: Decodable {
        let name: String?
        let statusCategory: RawStatusCategory?
    }
    struct RawStatusCategory: Decodable { let key: String? }   // new / indeterminate / done
    struct RawUser: Decodable {
        let accountId: String?
        let displayName: String?
        let avatarUrls: [String: String]?

        /// Largest available avatar (Jira offers 16/24/32/48px keyed as "48x48" etc.).
        var bestAvatarUrl: String? {
            avatarUrls?["48x48"] ?? avatarUrls?["32x32"] ?? avatarUrls?["24x24"] ?? avatarUrls?.values.first
        }
    }
}
