import Foundation

/// Kanbans GitHub-Modul — das Gegenstück zu `GitLabClient`, für Projekte, die auf GitHub liegen.
///
/// Vier Dinge sind dort **anders gebaut**, nicht bloss anders benannt:
///
/// | Sache | GitLab | GitHub |
/// |---|---|---|
/// | Auth | Header `PRIVATE-TOKEN` | `Authorization: Bearer …` + `Accept: application/vnd.github+json` |
/// | Zustand | `opened` / `merged` / `closed` | nur `open` / `closed`, dazu `merged_at` |
/// | Zustimmung | `/approvals` → `approved_by` | `/pulls/{n}/reviews` → je Person der **letzte** Zustand |
/// | Threads aufgelöst | `/discussions` → `resolved` | **nicht im REST** — nur GraphQL (`reviewThreads.isResolved`) |
///
/// **Normalisiert wird hier**, nicht in der Domäne: `closed` + `merged_at != nil` → `"merged"`,
/// `open` → `"opened"`, sonst `"closed"`. Damit bleiben `WorkflowStatus`, `TicketMatching`, die
/// Badges und die Spaltenlogik unverändert. Wer stattdessen GitHubs Vokabular durchreichte, müsste
/// jede dieser Stellen anfassen und bräche dabei die vorhandenen Tests.
///
/// **Fail-open** an jeder Zusatzabfrage: Zustimmung und Thread-Zähler sind Hinweise. Fehlt das
/// Recht, scheitert GraphQL oder greift die Ratenbegrenzung, fallen die Zähler auf 0 und das Badge
/// entfällt — eine Karte in die falsche Spalte zu schieben wäre der schlechtere Ausgang.
public struct GitHubClient: Sendable, ForgeClient {
    /// REST-Basis: `https://api.github.com` bzw. `https://<host>/api/v3` bei GitHub Enterprise.
    let apiBaseUrl: String
    /// GraphQL liegt daneben, nicht darunter — bei Enterprise unter `/api/graphql`.
    let graphQLUrl: String
    let http: ModuleHTTPClient

    public var kind: ForgeKind { .github }

    /// Vorgabe der Base-URL, wenn die Config keine nennt.
    public static let defaultApiBaseUrl = "https://api.github.com"

    /// Aus der App-Config — nil, wenn kein Token da ist. GitHub ist so optional wie GitLab.
    public init?(config: AppConfig) {
        guard let token = config.githubApiToken, !token.isEmpty else { return nil }
        self.init(apiBaseUrl: config.githubApiUrl, token: token)
    }

    public init(apiBaseUrl: String, token: String) {
        let base = Self.trimTrailingSlash(apiBaseUrl)
        let graphQL = Self.graphQLURL(forApiBase: base)
        self.apiBaseUrl = base
        self.graphQLUrl = graphQL
        self.http = .github(baseUrls: [base, graphQL], apiToken: token)
    }

    // MARK: - Listen

    /// Die Pull Requests eines Repos in einem GitHub-Zustand (`open` / `closed`), übersetzt in
    /// `MergeRequestRef` samt normalisiertem Zustand.
    public func listPullRequests(projectPath: String, state: String,
                                 sortedByUpdate: Bool = false) async throws -> [MergeRequestRef] {
        var url = "\(apiBaseUrl)/repos/\(projectPath)/pulls?state=\(state)&per_page=100"
        if sortedByUpdate { url += "&sort=updated&direction=desc" }
        let raw: [JSONValue] = try await http.getJSON(url)
        return raw.map(Self.parseListEntry)
    }

    /// Offene und gemergte Requests in einem Aufruf — dieselbe Zusage wie `openedAndMergedMRs`.
    ///
    /// **Zwei Abfragen statt `state=all`**, obwohl GitHub das anbietet: `all` liefert eine einzige
    /// Seite, und in einem Repo mit Historie besteht die aus geschlossenen PRs. Die offenen — die,
    /// um die es dem Board geht — fielen hinten heraus. Getrennt geholt kann jede Hälfte ihre
    /// eigene Sortierung haben: offene vollständig, geschlossene nach letzter Änderung, damit in
    /// „Done" das zuletzt Gemergte steht.
    public func openedAndMergedRequests(projectPath: String) async throws -> [MergeRequestRef] {
        async let openRaw = listPullRequests(projectPath: projectPath, state: "open")
        async let closedRaw = listPullRequests(projectPath: projectPath, state: "closed",
                                               sortedByUpdate: true)
        let opened = try await openRaw
        let merged = try await closedRaw.filter { $0.state == "merged" }
        // Nur die offenen bekommen ihren Review-Stand: bei einem gemergten Request fragt weder die
        // Zustimmung noch ein Thread noch etwas — und die ganze Historie abzuklappern wäre teuer.
        return await withReviewState(opened, projectPath: projectPath) + merged
    }

    // MARK: - Review-Stand (Threads + Zustimmung)

    /// Erledigte und offene Review-Threads eines PR.
    ///
    /// Der einzige Punkt, an dem GitHubs REST nicht ausreicht: `isResolved` eines Threads steht
    /// **nur** in GraphQL (`PullRequestReviewThread`). Schlägt die Abfrage fehl — kein Recht, ein
    /// Fehler, eine Zeitüberschreitung —, sind es 0/0 und das Badge entfällt.
    public func discussionCounts(projectPath: String, iid: Int) async -> (resolved: Int, unresolved: Int) {
        (try? await fetchDiscussionCounts(projectPath: projectPath, iid: iid)) ?? (0, 0)
    }

    /// Dieselbe Abfrage, aber werfend — damit `withReviewState` eine Ratenbegrenzung **sehen** kann,
    /// statt sie als leeres Ergebnis zu verwechseln.
    func fetchDiscussionCounts(projectPath: String, iid: Int) async throws -> (resolved: Int, unresolved: Int) {
        guard let (owner, repo) = Self.splitPath(projectPath) else { return (0, 0) }
        let body: [String: Any] = [
            "query": Self.reviewThreadsQuery,
            "variables": ["owner": owner, "repo": repo, "number": iid],
        ]
        let raw: JSONValue = try await http.postJSON(graphQLUrl, body: body, as: JSONValue.self)
        return Self.threadCounts(raw)
    }

    /// Ob mindestens eine Person zugestimmt hat, samt Namen für den Tooltip.
    ///
    /// GitHub kennt kein `approved`-Feld: es führt eine **Liste von Reviews**, und dieselbe Person
    /// darf mehrfach darin stehen. Es zählt je Person der zeitlich letzte *meinungsstarke* Zustand
    /// — `APPROVED` oder `CHANGES_REQUESTED`. `COMMENTED` und `PENDING` sind keine Meinung und
    /// dürfen eine ältere Zustimmung deshalb nicht aufheben (so wertet GitHub es selbst aus).
    public func approval(projectPath: String, iid: Int) async -> (approved: Bool, by: [String]) {
        (try? await fetchApproval(projectPath: projectPath, iid: iid)) ?? (false, [])
    }

    /// Werfende Fassung, aus demselben Grund wie bei den Thread-Zählern.
    func fetchApproval(projectPath: String, iid: Int) async throws -> (approved: Bool, by: [String]) {
        let url = "\(apiBaseUrl)/repos/\(projectPath)/pulls/\(iid)/reviews?per_page=100"
        let raw: [JSONValue] = try await http.getJSON(url)
        return Self.approvalFromReviews(raw)
    }

    /// Wie viele PRs gleichzeitig ihren Review-Stand holen. **Nicht** alle auf einmal, anders als
    /// bei GitLab, und aus zwei Gründen: GitHub bittet ausdrücklich darum, Abfragen nicht parallel
    /// abzufeuern, und ein Fenster ist die Voraussetzung dafür, dass `RateLimitGate` überhaupt
    /// wirken kann — ein Fan-out über alle PRs wäre längst abgeschickt, bevor die erste Absage
    /// zurückkommt.
    static let reviewWindow = 6

    private func withReviewState(_ prs: [MergeRequestRef],
                                 projectPath: String) async -> [MergeRequestRef] {
        // Die Ratenbegrenzung ist bei GitHub eine echte Grösse: 30 offene PRs sind 60 Abfragen im
        // 45-Sekunden-Takt. Sagt die API einmal „rate limit", hört diese Runde auf zu fragen und
        // liefert für den Rest leere Zähler, statt in dieselbe Wand weiterzulaufen. Wiederholt wird
        // nichts — beim nächsten Board-Takt ist das Fenster womöglich wieder offen.
        let gate = RateLimitGate()
        return await withTaskGroup(of: (Int, ReviewState).self) { group in
            var pending = prs.makeIterator()
            for _ in 0..<Self.reviewWindow {
                guard let pr = pending.next() else { break }
                group.addTask { await reviewState(of: pr, projectPath: projectPath, gate: gate) }
            }

            var byIid: [Int: ReviewState] = [:]
            while let (iid, state) = await group.next() {
                byIid[iid] = state
                // Erst wenn einer fertig ist, rückt der nächste nach — so sieht er ein inzwischen
                // geschlossenes Tor auch wirklich.
                if let pr = pending.next() {
                    group.addTask { await reviewState(of: pr, projectPath: projectPath, gate: gate) }
                }
            }
            return prs.map { pr in
                let state = byIid[pr.iid] ?? ReviewState()
                return MergeRequestRef(iid: pr.iid, title: pr.title, state: pr.state,
                                       sourceBranch: pr.sourceBranch, targetBranch: pr.targetBranch,
                                       mergedAt: pr.mergedAt, webUrl: pr.webUrl, draft: pr.draft,
                                       unresolvedDiscussions: state.unresolved,
                                       resolvedDiscussions: state.resolved,
                                       approved: state.approved, approvedBy: state.approvedBy,
                                       forge: .github)
            }
        }
    }

    /// Der Review-Stand **eines** PR: Threads und Zustimmung parallel, beide fail-open. Ist das Tor
    /// schon zu, wird gar nicht erst gefragt.
    private func reviewState(of pr: MergeRequestRef, projectPath: String,
                             gate: RateLimitGate) async -> (Int, ReviewState) {
        guard await gate.isOpen() else { return (pr.iid, ReviewState()) }
        async let counts = reviewThreads(projectPath: projectPath, iid: pr.iid, gate: gate)
        async let verdict = reviewVerdict(projectPath: projectPath, iid: pr.iid, gate: gate)
        let (threads, approved) = await (counts, verdict)
        return (pr.iid, ReviewState(resolved: threads.resolved, unresolved: threads.unresolved,
                                    approved: approved.approved, approvedBy: approved.by))
    }

    private func reviewThreads(projectPath: String, iid: Int,
                               gate: RateLimitGate) async -> (resolved: Int, unresolved: Int) {
        do { return try await fetchDiscussionCounts(projectPath: projectPath, iid: iid) }
        catch {
            if Self.isRateLimited(error) { await gate.trip() }
            return (0, 0)
        }
    }

    private func reviewVerdict(projectPath: String, iid: Int,
                               gate: RateLimitGate) async -> (approved: Bool, by: [String]) {
        do { return try await fetchApproval(projectPath: projectPath, iid: iid) }
        catch {
            if Self.isRateLimited(error) { await gate.trip() }
            return (false, [])
        }
    }

    private struct ReviewState: Sendable {
        var resolved = 0
        var unresolved = 0
        var approved = false
        var approvedBy: [String] = []
    }

    /// Einmal „rate limit exceeded", und die laufende Runde fragt nicht weiter. Bewusst **je
    /// Durchlauf** neu: der nächste Board-Takt darf es wieder versuchen, das Fenster ist dann
    /// womöglich schon offen.
    actor RateLimitGate {
        private var tripped = false
        func isOpen() -> Bool { !tripped }
        func trip() { tripped = true }
    }

    /// GitHub meldet die Ratenbegrenzung als 403 (primär) oder 429 (sekundär) und schreibt den
    /// Grund in den Body — ein 403 ohne diesen Hinweis ist ein fehlendes Recht und etwas anderes.
    static func isRateLimited(_ error: Error) -> Bool {
        guard case APIError.api(_, let status, let message) = error,
              status == 403 || status == 429 else { return false }
        let text = (message ?? "").lowercased()
        return text.contains("rate limit") || text.contains("abuse detection")
    }

    // MARK: - Normalisierung und Parser

    /// GitHubs Zustand in GitLabs Vokabular. **`merged` ist bei GitHub kein Zustand** — ein
    /// gemergter PR ist `closed` mit gesetztem `merged_at`, und ohne diese Unterscheidung landete
    /// jeder abgelehnte PR in „Done".
    static func normalizedState(_ state: String?, mergedAt: String?) -> String {
        if let mergedAt, !mergedAt.isEmpty { return "merged" }
        switch state?.lowercased() {
        case "open": return "opened"
        case "merged": return "merged"       // GraphQL und einige Webhooks sagen es doch
        default: return "closed"
        }
    }

    /// Ein Listeneintrag aus `GET /repos/{owner}/{repo}/pulls`.
    static func parseListEntry(_ raw: JSONValue) -> MergeRequestRef {
        let mergedAt = raw.value(at: ["merged_at"])?.stringValue
        let title = raw.value(at: ["title"])?.stringValue ?? ""
        return MergeRequestRef(
            iid: raw.value(at: ["number"])?.intValue ?? 0,
            title: title,
            state: normalizedState(raw.value(at: ["state"])?.stringValue, mergedAt: mergedAt),
            sourceBranch: sourceBranch(raw),
            targetBranch: raw.value(at: ["base", "ref"])?.stringValue ?? "",
            mergedAt: mergedAt,
            webUrl: raw.value(at: ["html_url"])?.stringValue ?? "",
            // GitHub führt den Entwurf als echtes Feld — anders als bei GitLab braucht es hier
            // keine Erkennung am Titelpräfix.
            draft: raw.value(at: ["draft"])?.boolValue ?? false,
            forge: .github)
    }

    /// Der Quell-Branch eines PR — **ohne** das `owner:`-Präfix.
    ///
    /// Bei einem Fork-PR (`head.repo != base.repo`) schreibt GitHub den Branch in `head.label` als
    /// `fremder-owner:branch`. `head.ref` trägt den reinen Namen; nur der lässt sich mit lokalen
    /// Branches und Worktrees vergleichen (`TicketMatching`). Der Rückfall auf `label` schneidet
    /// deshalb ab, was vor dem Doppelpunkt steht.
    static func sourceBranch(_ raw: JSONValue) -> String {
        if let ref = raw.value(at: ["head", "ref"])?.stringValue, !ref.isEmpty { return ref }
        guard let label = raw.value(at: ["head", "label"])?.stringValue else { return "" }
        guard let colon = label.firstIndex(of: ":") else { return label }
        return String(label[label.index(after: colon)...])
    }

    /// Zustimmung aus der Review-Liste: je Person der **letzte** meinungsstarke Zustand.
    static func approvalFromReviews(_ reviews: [JSONValue]) -> (approved: Bool, by: [String]) {
        // `submitted_at` ist ISO-8601 und damit lexikografisch sortierbar; fehlt es (ein `PENDING`
        // hat keins), gilt die Reihenfolge der Antwort — GitHub liefert aufsteigend.
        var verdict: [String: (order: String, state: String)] = [:]
        var names: [String: String] = [:]
        for (index, review) in reviews.enumerated() {
            let state = (review.value(at: ["state"])?.stringValue ?? "").uppercased()
            guard state == "APPROVED" || state == "CHANGES_REQUESTED" || state == "DISMISSED"
            else { continue }   // COMMENTED / PENDING sind keine Meinung
            guard let login = review.value(at: ["user", "login"])?.stringValue else { continue }
            let order = review.value(at: ["submitted_at"])?.stringValue
                ?? String(format: "~%09d", index)   // ohne Zeitstempel ans Ende, in Antwortfolge
            if let existing = verdict[login], existing.order > order { continue }
            verdict[login] = (order, state)
            names[login] = review.value(at: ["user", "name"])?.stringValue ?? login
        }
        let approvers = verdict.filter { $0.value.state == "APPROVED" }.keys.sorted()
        return (!approvers.isEmpty, approvers.map { names[$0] ?? $0 })
    }

    /// Die GraphQL-Antwort auf `reviewThreads` in „erledigt / offen".
    static func threadCounts(_ raw: JSONValue) -> (resolved: Int, unresolved: Int) {
        let nodes = raw.value(at: ["data", "repository", "pullRequest", "reviewThreads", "nodes"])?
            .arrayValue ?? []
        var resolved = 0, unresolved = 0
        for node in nodes {
            // Ein Thread, den GitHub als „outdated" führt (die Zeile gibt es nicht mehr), bleibt
            // ein Thread: solange ihn niemand aufgelöst hat, ist er offen — wie bei GitLab.
            if node.value(at: ["isResolved"])?.boolValue == true { resolved += 1 } else { unresolved += 1 }
        }
        return (resolved, unresolved)
    }

    /// Bewusst klein gehalten: gefragt wird **nur** `isResolved`. Jedes weitere Feld kostet Punkte
    /// im GraphQL-Budget, und gezählt wird hier, nicht gelesen.
    static let reviewThreadsQuery = """
        query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) {
              reviewThreads(first: 100) { nodes { isResolved } }
            }
          }
        }
        """

    // MARK: - URLs

    /// `owner/repo` → (`owner`, `repo`). Nil bei allem anderen — ein GitHub-Pfad hat genau zwei
    /// Segmente, und ein geratenes drittes führte zu einer 404 statt zu einer klaren Ursache.
    static func splitPath(_ projectPath: String) -> (owner: String, repo: String)? {
        let parts = projectPath.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// Wo GraphQL neben einer REST-Basis liegt: bei `api.github.com` als `/graphql` darunter, bei
    /// GitHub Enterprise als Geschwister von `/api/v3` unter `/api/graphql`.
    static func graphQLURL(forApiBase base: String) -> String {
        let trimmed = trimTrailingSlash(base)
        if trimmed.hasSuffix("/api/v3") { return String(trimmed.dropLast("/v3".count)) + "/graphql" }
        return trimmed + "/graphql"
    }

    /// Die **Web**-Basis zu einer API-Basis — die, unter der Branches und PRs für Menschen liegen.
    /// `https://api.github.com` → `https://github.com`, `https://ghe.firma.io/api/v3` →
    /// `https://ghe.firma.io`.
    public static func webBaseURL(forApiBase base: String) -> String {
        var trimmed = trimTrailingSlash(base)
        if trimmed.hasSuffix("/api/v3") { trimmed = String(trimmed.dropLast("/api/v3".count)) }
        guard var components = URLComponents(string: trimmed), let host = components.host else {
            return trimmed
        }
        if host.lowercased().hasPrefix("api.") { components.host = String(host.dropFirst(4)) }
        components.path = ""
        return components.string.map(trimTrailingSlash) ?? trimmed
    }

    static func trimTrailingSlash(_ value: String) -> String {
        value.hasSuffix("/") ? String(value.dropLast()) : value
    }
}
