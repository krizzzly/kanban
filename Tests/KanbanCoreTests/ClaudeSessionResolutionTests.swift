import XCTest
@testable import KanbanCore

final class ClaudeSessionResolutionTests: XCTestCase {
    /// The real case from EVEN-3513: the task file holds an id no conversation was ever started
    /// under, while the id in `sessions.json` is the running console.
    func testIdWithATranscriptWinsOverAnInventedTaskFileId() {
        let id = ClaudeSessionResolution.resolve(
            taskFileId: "27feeb8f", storeId: "1db911be", hasTranscript: { $0 == "1db911be" })
        XCTAssertEqual(id, "1db911be")
    }

    func testTaskFileWinsWhenBothHaveATranscript() {
        let id = ClaudeSessionResolution.resolve(
            taskFileId: "task", storeId: "store", hasTranscript: { _ in true })
        XCTAssertEqual(id, "task", "the task file is where the id belongs long-term")
    }

    func testWithoutAnyTranscriptTheTaskFileIdIsKept() {
        // A ticket opened for the first time: nothing has run yet, so nothing may be discarded.
        let id = ClaudeSessionResolution.resolve(
            taskFileId: "task", storeId: "store", hasTranscript: { _ in false })
        XCTAssertEqual(id, "task")
    }

    func testFallsBackToTheStoreWhenTheTaskFileHasNoMarker() {
        XCTAssertEqual(ClaudeSessionResolution.resolve(
            taskFileId: nil, storeId: "store", hasTranscript: { _ in false }), "store")
        XCTAssertEqual(ClaudeSessionResolution.resolve(
            taskFileId: "", storeId: "store", hasTranscript: { _ in false }), "store")
    }

    func testTicketWithoutAnyRecordedIdResolvesToNothing() {
        XCTAssertNil(ClaudeSessionResolution.resolve(
            taskFileId: nil, storeId: nil, hasTranscript: { _ in true }))
    }

    func testStoreIdIsUsedWhenOnlyItHasATranscriptAndTaskFileIsEmpty() {
        let id = ClaudeSessionResolution.resolve(
            taskFileId: nil, storeId: "store", hasTranscript: { $0 == "store" })
        XCTAssertEqual(id, "store")
    }
}
