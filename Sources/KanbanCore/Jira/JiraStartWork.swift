import Foundation

/// Eine Workflow-Transition, wie Jira sie für ein Ticket anbietet
/// (`GET /rest/api/3/issue/<KEY>/transitions`).
public struct JiraTransition: Sendable, Equatable {
    /// Die Id, mit der die Transition ausgelöst wird — Jira nimmt beim POST nur sie, nie den Namen.
    public let id: String
    /// Der Knopf, wie er in Jira steht („Start Progress“) — **nicht** der Status danach.
    public let name: String
    /// Der Status, in dem das Ticket nach der Transition steht („In Arbeit“).
    public let toStatusName: String
    /// Jiras Kategorie des Zielstatus: `new` / `indeterminate` / `done`.
    public let toStatusCategory: String?

    public init(id: String, name: String, toStatusName: String, toStatusCategory: String?) {
        self.id = id
        self.name = name
        self.toStatusName = toStatusName
        self.toStatusCategory = toStatusCategory
    }
}

/// Der Stand, den die Nachführung vorfindet: Status und Zuweisung des Tickets.
public struct JiraWorkState: Sendable, Equatable {
    public let statusName: String?
    public let statusCategory: String?     // new / indeterminate / done
    public let assigneeAccountId: String?
    public let assigneeName: String?

    public init(statusName: String?, statusCategory: String?,
                assigneeAccountId: String?, assigneeName: String?) {
        self.statusName = statusName
        self.statusCategory = statusCategory
        self.assigneeAccountId = assigneeAccountId
        self.assigneeName = assigneeName
    }
}

/// Welche Transition ein Ticket auf „In Arbeit“ bringt. Die **Auswahl** steht hier getrennt vom
/// Aufruf, damit sie ohne Netz prüfbar ist — und weil sie die einzige Stelle ist, an der geraten
/// werden könnte.
///
/// Warum überhaupt gesucht wird: die Transitionen gehören dem Workflow, nicht der API. Auf dieser
/// Instanz führt „Start Progress“ (id 4) nach „In Arbeit“, aus „Erledigt“ heraus heisst derselbe
/// Weg „Incomplete“ — ein hartkodierter Name oder eine hartkodierte Id wäre Glück, kein Verlass.
public enum InProgressTransition {
    /// Wie der **Zielstatus** heissen darf, damit er als „in Arbeit“ zählt.
    public static let statusNames: Set<String> = [
        "in arbeit", "in bearbeitung", "in progress", "in development", "in umsetzung",
    ]

    /// Wie die **Transition** heissen darf, wenn der Zielstatus anders benannt ist.
    public static let transitionNames: Set<String> = [
        "start progress", "in arbeit nehmen", "arbeit beginnen", "bearbeitung starten",
        "in arbeit", "in progress",
    ]

    /// Was mit dem Status zu tun ist.
    public enum Step: Sendable, Equatable {
        /// Nichts zu tun — das Ticket zählt schon als in Arbeit (Text = der Status).
        case already(String)
        /// Diese Transition ausführen.
        case transition(JiraTransition)
        /// Nichts Passendes im Workflow — die erreichbaren Zielstatus, damit die Meldung sie nennt.
        case noMatch(available: [String])
    }

    public static func isInProgress(statusName: String?) -> Bool {
        guard let statusName else { return false }
        return statusNames.contains(normalized(statusName))
    }

    /// Die ganze Entscheidung an einer Stelle, aus dem Stand des Tickets und seinen Transitionen.
    ///
    /// Reihenfolge und ihre Gründe:
    /// 1. Der Status heisst schon „In Arbeit“ → nichts schreiben (Jira bietet dann auch gar keine
    ///    Transition dorthin an).
    /// 2. Eine Transition **zu** einem so benannten Status — das ist der sichere Treffer.
    /// 3. Eine Transition, die selbst so heisst („Start Progress“), falls der Zielstatus fremd heisst.
    /// 4. Steht das Ticket schon in der Kategorie `indeterminate` (irgendein Arbeits-Status eines
    ///    fremden Workflows, z. B. „Wartet auf Support“), bleibt es dabei. Sonst würde Regel 5 dort
    ///    eine beliebige Transition auslösen und den Ticketstand verfälschen.
    /// 5. Führt genau **eine** Transition in die Arbeits-Kategorie, ist sie es. Bei mehreren wird
    ///    nicht geraten.
    public static func decide(state: JiraWorkState, transitions: [JiraTransition]) -> Step {
        if isInProgress(statusName: state.statusName) { return .already(state.statusName ?? "") }
        if let hit = transitions.first(where: { statusNames.contains(normalized($0.toStatusName)) }) {
            return .transition(hit)
        }
        if let hit = transitions.first(where: { transitionNames.contains(normalized($0.name)) }) {
            return .transition(hit)
        }
        if state.statusCategory == "indeterminate" { return .already(state.statusName ?? "") }
        let working = transitions.filter { $0.toStatusCategory == "indeterminate" }
        if working.count == 1 { return .transition(working[0]) }
        return .noMatch(available: transitions.map(\.toStatusName))
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Was die Nachführung geschrieben hat — je Schritt einzeln, weil das eine gehen kann, während das
/// andere scheitert (z. B. Transition erlaubt, Zuweisung nicht).
public struct JiraStartWork: Sendable, Equatable {
    public enum StatusOutcome: Sendable, Equatable {
        case moved(to: String)          // transitioniert
        case already(String)            // stand schon so
        case notPossible(String)        // kein passender Weg im Workflow
        case failed(String)             // Jira hat abgelehnt
    }

    public enum AssigneeOutcome: Sendable, Equatable {
        case assigned(String)
        case already(String)
        case failed(String)
    }

    public let issueKey: String
    public let status: StatusOutcome
    public let assignee: AssigneeOutcome

    public init(issueKey: String, status: StatusOutcome, assignee: AssigneeOutcome) {
        self.issueKey = issueKey
        self.status = status
        self.assignee = assignee
    }

    /// Ob etwas geschrieben wurde — nur dann lohnt ein Board-Refresh.
    public var didWrite: Bool {
        if case .moved = status { return true }
        if case .assigned = assignee { return true }
        return false
    }

    /// Ob die Meldung als Warnung stehen bleiben muss (etwas ist **nicht** passiert).
    public var isWarning: Bool {
        if case .moved = status {} else if case .already = status {} else { return true }
        if case .failed = assignee { return true }
        return false
    }

    /// Eine Zeile für die Toolbar.
    public var summary: String {
        let statusText: String
        switch status {
        case .moved(let to): statusText = "Status → \(to)"
        case .already(let name): statusText = "Status \(name)"
        case .notPossible(let reason): statusText = "Status unverändert (\(reason))"
        case .failed(let message): statusText = "Status nicht gesetzt: \(message)"
        }
        let assigneeText: String
        switch assignee {
        case .assigned(let name): assigneeText = "zugewiesen an \(name)"
        case .already(let name): assigneeText = "war schon \(name) zugewiesen"
        case .failed(let message): assigneeText = "Zuweisung fehlgeschlagen: \(message)"
        }
        return "\(issueKey): \(statusText), \(assigneeText)"
    }
}

public extension JiraClient {
    /// Status und Zuweisung eines Tickets — der Stand, auf dem die Nachführung aufsetzt.
    func workState(issueKey: String, baseUrl: String) async throws -> JiraWorkState {
        let raw: JSONValue = try await http.getJSON(
            "\(baseUrl)/rest/api/3/issue/\(issueKey)?fields=status,assignee")
        return JiraWorkState(
            statusName: raw.value(at: ["fields", "status", "name"])?.stringValue,
            statusCategory: raw.value(at: ["fields", "status", "statusCategory", "key"])?.stringValue,
            assigneeAccountId: raw.value(at: ["fields", "assignee", "accountId"])?.stringValue,
            assigneeName: raw.value(at: ["fields", "assignee", "displayName"])?.stringValue)
    }

    /// Die Transitionen, die der Workflow **für dieses Ticket in diesem Status** anbietet.
    func transitions(issueKey: String, baseUrl: String) async throws -> [JiraTransition] {
        let raw: JSONValue = try await http.getJSON(
            "\(baseUrl)/rest/api/3/issue/\(issueKey)/transitions")
        return JiraClient.parseTransitions(raw)
    }

    /// Führt eine Transition aus (Jira antwortet mit 204).
    func applyTransition(issueKey: String, transitionId: String, baseUrl: String) async throws {
        try await http.postJSON("\(baseUrl)/rest/api/3/issue/\(issueKey)/transitions",
                                body: ["transition": ["id": transitionId]])
    }

    /// Weist das Ticket zu. Eigener Endpunkt statt `fields.assignee` — er braucht keine
    /// Schreibrechte auf dem Edit-Screen.
    func assign(issueKey: String, accountId: String, baseUrl: String) async throws {
        try await http.putJSON("\(baseUrl)/rest/api/3/issue/\(issueKey)/assignee",
                               body: ["accountId": accountId])
    }

    /// **Arbeit aufnehmen**: Status auf „In Arbeit“, Ticket auf `accountId`.
    ///
    /// Geschrieben wird nur, was fehlt — steht der Status schon so und ist das Ticket schon dir
    /// zugewiesen, geht keine einzige Schreibanfrage raus (sonst stünde in Jiras Historie bei jedem
    /// `solve-task` ein Eintrag, der nichts sagt).
    ///
    /// Wirft nur, wenn der Stand nicht zu lesen ist (Ticket unbekannt, Auth) — abgelehnte Schreib-
    /// schritte landen im Ergebnis, damit der eine Schritt den anderen nicht mitreisst.
    func startWork(issueKey: String, baseUrl: String,
                   accountId: String, displayName: String) async throws -> JiraStartWork {
        let state = try await workState(issueKey: issueKey, baseUrl: baseUrl)

        var statusOutcome: JiraStartWork.StatusOutcome
        if InProgressTransition.isInProgress(statusName: state.statusName) {
            statusOutcome = .already(state.statusName ?? "")
        } else {
            let available = try await transitions(issueKey: issueKey, baseUrl: baseUrl)
            switch InProgressTransition.decide(state: state, transitions: available) {
            case .already(let name):
                statusOutcome = .already(name)
            case .noMatch(let targets):
                let list = targets.isEmpty ? "keine Transition erlaubt" : targets.joined(separator: ", ")
                statusOutcome = .notPossible(list)
            case .transition(let transition):
                do {
                    try await applyTransition(issueKey: issueKey, transitionId: transition.id,
                                              baseUrl: baseUrl)
                    statusOutcome = .moved(to: transition.toStatusName)
                } catch {
                    statusOutcome = .failed(error.localizedDescription)
                }
            }
        }

        var assigneeOutcome: JiraStartWork.AssigneeOutcome
        if state.assigneeAccountId == accountId {
            assigneeOutcome = .already(state.assigneeName ?? displayName)
        } else {
            do {
                try await assign(issueKey: issueKey, accountId: accountId, baseUrl: baseUrl)
                assigneeOutcome = .assigned(displayName)
            } catch {
                assigneeOutcome = .failed(error.localizedDescription)
            }
        }

        return JiraStartWork(issueKey: issueKey, status: statusOutcome, assignee: assigneeOutcome)
    }
}

extension JiraClient {
    /// Die Antwort von `/transitions` in `JiraTransition`s. Eigene Funktion, damit die Feldformen
    /// gegen eine echte Antwort dieser Instanz prüfbar sind.
    ///
    /// `isAvailable: false` fliegt raus: Jira liefert solche Einträge zwar normalerweise gar nicht
    /// mit, und eine nicht erlaubte Transition würde beim POST nur mit einem Fehler enden.
    static func parseTransitions(_ raw: JSONValue) -> [JiraTransition] {
        (raw.value(at: ["transitions"])?.arrayValue ?? []).compactMap { entry in
            // Die Id kommt als String („4“); eine Zahl wird trotzdem gelesen, damit ein abweichender
            // Server nicht eine leere Liste ergibt.
            let id = entry.value(at: ["id"])?.stringValue
                ?? entry.value(at: ["id"])?.intValue.map(String.init)
            guard let id, entry.value(at: ["isAvailable"])?.boolValue != false else { return nil }
            return JiraTransition(
                id: id,
                name: entry.value(at: ["name"])?.stringValue ?? "",
                toStatusName: entry.value(at: ["to", "name"])?.stringValue ?? "",
                toStatusCategory: entry.value(at: ["to", "statusCategory", "key"])?.stringValue)
        }
    }
}
