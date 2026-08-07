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

    func testWithoutAStoredChoiceTheActiveSprintWins() {
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: nil)?.id, 20)
    }

    func testStoredChoiceIsRestoredEvenWhenClosed() {
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: 15)?.id, 15)
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: 30)?.id, 30)
    }

    func testStoredSprintTheBoardNoLongerKnowsFallsBackToActive() {
        XCTAssertEqual(SprintSelection.resolve(sprints: board, storedId: 999)?.id, 20)
    }

    func testWithoutAnActiveSprintTheFirstOneWins() {
        let closedOnly = SprintSelection.ordered([sprint(10, "v2.6", "closed"), sprint(15, "v2.7", "closed")])
        XCTAssertEqual(SprintSelection.resolve(sprints: closedOnly, storedId: nil)?.id, 15)
    }

    func testEmptyBoardResolvesToNothing() {
        XCTAssertNil(SprintSelection.resolve(sprints: [], storedId: 20))
    }
}
