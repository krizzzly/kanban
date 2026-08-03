import XCTest
@testable import KanbanCore

final class PaneAttentionTests: XCTestCase {
    func testDetectsPermissionPicker() {
        let pane = """
        Claude wants to edit File.swift

        Do you want to make this edit?
        ❯ 1. Yes
          2. Yes, and don't ask again
          3. No, and tell Claude what to do differently
        """
        XCTAssertTrue(PaneAttention.showsQuestion(pane))
    }

    func testDetectsNumberedMenuWithoutCursor() {
        let pane = "Which option?\n  1. Alpha\n  2. Beta\n  3. Gamma\n"
        XCTAssertTrue(PaneAttention.showsQuestion(pane))
    }

    func testWorkingPaneIsNotWaiting() {
        let pane = "· Working… (12s · 1.2k tokens · esc to interrupt)"
        XCTAssertTrue(PaneAttention.isWorking(pane))
        XCTAssertFalse(PaneAttention.showsQuestion(pane))
    }

    func testIdlePromptIsNotTreatedAsQuestion() {
        // Just the empty input box — not a blocking question (that's the hook's idle_prompt job).
        let pane = "────────────────────────────────────────\n> \n────────────────────────────────────────"
        XCTAssertFalse(PaneAttention.showsQuestion(pane))
    }
}
