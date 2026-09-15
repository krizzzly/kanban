import XCTest
@testable import KanbanCore

/// Die Nachführung vor `solve-task`: welche Transition ein Ticket auf „In Arbeit“ bringt.
///
/// Die Transitions-Listen stammen aus echten Antworten dieser Instanz
/// (`GET /rest/api/3/issue/<KEY>/transitions`, 2026-08-28) — der Workflow ist der Grund, warum hier
/// gesucht statt hartkodiert wird.
final class JiraStartWorkTests: XCTestCase {
    private func state(_ status: String?, _ category: String?,
                       assignee: String? = nil) -> JiraWorkState {
        JiraWorkState(statusName: status, statusCategory: category,
                      assigneeAccountId: assignee, assigneeName: assignee.map { "Benutzer \($0)" })
    }

    /// Der Normalfall auf dieser Instanz: „Offen“ → „Start Progress“ (id 4) → „In Arbeit“.
    private let openIssueTransitions = [
        JiraTransition(id: "4", name: "Start Progress",
                       toStatusName: "In Arbeit", toStatusCategory: "indeterminate"),
        JiraTransition(id: "6", name: "Plan Issue",
                       toStatusName: "Zu erledigen", toStatusCategory: "new"),
        JiraTransition(id: "721", name: "Close Issue",
                       toStatusName: "Geschlossen", toStatusCategory: "done"),
    ]

    func testPicksTheTransitionIntoInArbeit() {
        let step = InProgressTransition.decide(state: state("Offen", "new"),
                                               transitions: openIssueTransitions)
        XCTAssertEqual(step, .transition(openIssueTransitions[0]))
    }

    /// Steht das Ticket schon auf „In Arbeit“, bietet Jira gar keinen Weg dorthin an — und es soll
    /// auch keiner gesucht werden, sonst liefe jedes `solve-task` in eine Fremdtransition.
    func testAlreadyInProgressWritesNothing() {
        let inProgress = [
            JiraTransition(id: "5", name: "Resolve Issue",
                           toStatusName: "Erledigt", toStatusCategory: "done"),
            JiraTransition(id: "301", name: "Stop Progress",
                           toStatusName: "Offen", toStatusCategory: "new"),
        ]
        XCTAssertEqual(InProgressTransition.decide(state: state("In Arbeit", "indeterminate"),
                                                   transitions: inProgress),
                       .already("In Arbeit"))
    }

    /// Ein wieder aufgemachtes Ticket: aus „Erledigt“ heraus heisst derselbe Weg „Incomplete“ —
    /// gefunden wird er über den **Zielstatus**, nicht über den Namen der Transition.
    func testReopensADoneIssue() {
        let done = [
            JiraTransition(id: "701", name: "Close Issue",
                           toStatusName: "Geschlossen", toStatusCategory: "done"),
            JiraTransition(id: "711", name: "Incomplete",
                           toStatusName: "In Arbeit", toStatusCategory: "indeterminate"),
        ]
        XCTAssertEqual(InProgressTransition.decide(state: state("Erledigt", "done"),
                                                   transitions: done),
                       .transition(done[1]))
    }

    /// Der Support-Workflow der zweiten Instanz kennt kein „In Arbeit“: „Wartet auf Kunden“ ist
    /// bereits ein Arbeits-Status. Nichts anfassen — zwei Transitionen führen in die Kategorie,
    /// eine davon zu wählen wäre geraten.
    func testForeignWorkflowInAWorkingStatusIsLeftAlone() {
        let support = [
            JiraTransition(id: "781", name: "Support antworten",
                           toStatusName: "Wartet auf Support", toStatusCategory: "indeterminate"),
            JiraTransition(id: "911", name: "Dieses Thema wurde eskaliert",
                           toStatusName: "Escalated", toStatusCategory: "indeterminate"),
            JiraTransition(id: "761", name: "Diesen Vorgang lösen",
                           toStatusName: "Erledigt", toStatusCategory: "done"),
        ]
        XCTAssertEqual(InProgressTransition.decide(state: state("Wartet auf Kunden", "indeterminate"),
                                                   transitions: support),
                       .already("Wartet auf Kunden"))
    }

    /// Fremder Workflow, Ticket noch nicht in Arbeit, **mehrere** Wege in die Arbeits-Kategorie:
    /// nicht raten, sondern sagen, was es gäbe.
    func testAmbiguousWorkflowReportsInsteadOfGuessing() {
        let ambiguous = [
            JiraTransition(id: "781", name: "Support antworten",
                           toStatusName: "Wartet auf Support", toStatusCategory: "indeterminate"),
            JiraTransition(id: "911", name: "Eskalieren",
                           toStatusName: "Escalated", toStatusCategory: "indeterminate"),
        ]
        XCTAssertEqual(InProgressTransition.decide(state: state("Neu", "new"), transitions: ambiguous),
                       .noMatch(available: ["Wartet auf Support", "Escalated"]))
    }

    /// Führt genau ein Weg in die Arbeits-Kategorie, ist er es — auch wenn der Zielstatus anders
    /// heisst.
    func testSingleWorkingTargetIsTaken() {
        let single = [
            JiraTransition(id: "21", name: "Sichtung starten",
                           toStatusName: "Sichtung", toStatusCategory: "indeterminate"),
            JiraTransition(id: "31", name: "Abschliessen",
                           toStatusName: "Fertig", toStatusCategory: "done"),
        ]
        XCTAssertEqual(InProgressTransition.decide(state: state("Neu", "new"), transitions: single),
                       .transition(single[0]))
    }

    /// Heisst der Zielstatus fremd, greift der Name der Transition.
    func testFallsBackToTheTransitionName() {
        let english = [
            JiraTransition(id: "11", name: "Start Progress",
                           toStatusName: "Doing", toStatusCategory: "new"),
            JiraTransition(id: "12", name: "Blocked",
                           toStatusName: "Blocked", toStatusCategory: "indeterminate"),
        ]
        XCTAssertEqual(InProgressTransition.decide(state: state("Backlog", "new"),
                                                   transitions: english),
                       .transition(english[0]))
    }

    // MARK: - Antwort lesen

    /// Gegen eine echte Antwort: die Id kommt als **String**, die Kategorie liegt unter
    /// `to.statusCategory.key`, und `isAvailable: false` fliegt raus.
    func testParsesARealTransitionsResponse() throws {
        let json = """
        {"expand": "transitions", "transitions": [
          {"id": "4", "name": "Start Progress", "hasScreen": false, "isAvailable": true,
           "to": {"name": "In Arbeit", "id": "3",
                  "statusCategory": {"id": 4, "key": "indeterminate", "name": "In Arbeit"}}},
          {"id": "6", "name": "Plan Issue", "hasScreen": true, "isAvailable": true,
           "to": {"name": "Zu erledigen", "id": "10046",
                  "statusCategory": {"id": 2, "key": "new", "name": "Zu erledigen"}}},
          {"id": "999", "name": "Nicht erlaubt", "isAvailable": false,
           "to": {"name": "Geschlossen", "statusCategory": {"key": "done"}}}
        ]}
        """
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let transitions = JiraClient.parseTransitions(raw)

        XCTAssertEqual(transitions.count, 2)
        XCTAssertEqual(transitions[0], JiraTransition(id: "4", name: "Start Progress",
                                                      toStatusName: "In Arbeit",
                                                      toStatusCategory: "indeterminate"))
        XCTAssertEqual(transitions[1].toStatusCategory, "new")
    }

    // MARK: - Meldung

    func testSummaryOfAFullRun() {
        let result = JiraStartWork(issueKey: "EVEN-3963", status: .moved(to: "In Arbeit"),
                                   assignee: .assigned("Christian Hiller"))
        XCTAssertEqual(result.summary, "EVEN-3963: Status → In Arbeit, zugewiesen an Christian Hiller")
        XCTAssertTrue(result.didWrite)
        XCTAssertFalse(result.isWarning)
    }

    /// Nichts zu tun ist kein Warnfall — und kein Grund für einen Board-Refresh.
    func testNothingToDoIsNoWarning() {
        let result = JiraStartWork(issueKey: "EVEN-3963", status: .already("In Arbeit"),
                                   assignee: .already("Christian Hiller"))
        XCTAssertFalse(result.didWrite)
        XCTAssertFalse(result.isWarning)
    }

    /// Was **nicht** passiert ist, muss stehen bleiben: kein Weg im Workflow, abgelehnte Zuweisung.
    func testUnfinishedStepsWarn() {
        XCTAssertTrue(JiraStartWork(issueKey: "X-1", status: .notPossible("Erledigt, Geschlossen"),
                                    assignee: .assigned("Christian Hiller")).isWarning)
        XCTAssertTrue(JiraStartWork(issueKey: "X-1", status: .moved(to: "In Arbeit"),
                                    assignee: .failed("Feld nicht beschreibbar")).isWarning)
    }
}
