import XCTest
@testable import KanbanCore

final class SprintSelectionTests: XCTestCase {
    private func sprint(_ id: Int, _ name: String, _ state: String?) -> JiraSprint {
        JiraSprint(id: id, name: name, state: state, startDate: nil, endDate: nil)
    }

    private var board: [JiraSprint] {
        [sprint(10, "v2.6", "closed"),
         sprint(30, "v2.9", "future"),
         sprint(20, "v2.8 Pre", "active"),
         sprint(15, "v2.7", "closed")]
    }

    func testOrderPutsActiveFirstThenNewestToOldest() {
        XCTAssertEqual(SprintSelection.ordered(board).map(\.id), [20, 30, 15, 10])
    }

    /// Das Board steht immer zur Wahl — und immer zuletzt, damit es den Sprint-Alltag nicht stört.
    func testChoicesEndWithTheWholeBoard() {
        XCTAssertEqual(SprintSelection.choices(board).map(\.id), ["20", "30", "15", "10", "board"])
        XCTAssertEqual(SprintSelection.choices([]).map(\.id), ["board"])
    }

    func testWithoutAStoredChoiceTheActiveSprintWins() {
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: nil), .sprint(sprint(20, "v2.8 Pre", "active")))
    }

    func testStoredChoiceIsRestoredEvenWhenClosed() {
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: "15").sprint?.id, 15)
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: "30").sprint?.id, 30)
    }

    func testStoredBoardChoiceIsRestored() {
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: "board"), .board)
    }

    func testStoredSprintTheBoardNoLongerKnowsFallsBackToActive() {
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: "999").sprint?.id, 20)
    }

    /// Der Fall CORE: 50 Sprints, alle geschlossen, der jüngste von 2021. Dort ist das **Board** die
    /// Vorauswahl — im jüngsten Altsprint stünde niemand freiwillig, und leer bleiben darf es nicht.
    func testWithoutAnActiveSprintTheBoardWins() {
        let closedOnly = [sprint(10, "v2.6", "closed"), sprint(15, "v2.7", "closed")]
        XCTAssertEqual(SprintSelection.resolve(sprints: closedOnly, storedId: nil), .board)
    }

    /// Ein Projekt ganz ohne Sprints (reines Kanban-Board) hat trotzdem eine gültige Wahl.
    func testBoardWithoutAnySprints() {
        XCTAssertEqual(SprintSelection.resolve(sprints: [], storedId: nil), .board)
        XCTAssertEqual(SprintSelection.resolve(sprints: [], storedId: "20"), .board)
    }

    func testLabels() {
        XCTAssertEqual(SprintChoice.board.label, "📋 Ganzes Board (offen)")
        XCTAssertEqual(SprintChoice.sprint(sprint(1, "v2.8", "active")).label, "🟢 v2.8")
        XCTAssertEqual(SprintChoice.sprint(sprint(1, "v2.7", "closed")).label, "✓ v2.7")
        XCTAssertEqual(SprintChoice.sprint(sprint(1, "v2.9", "future")).label, "🔜 v2.9")
    }
}
