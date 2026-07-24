import XCTest
@testable import KanbanCore

private actor Counter {
    private(set) var value = 0
    func inc() { value += 1 }
}

final class TaskFileWatcherTests: XCTestCase {
    /// Two consecutive **atomic** writes (temp + rename, as Claude/editors do) must each produce an
    /// event. Without the re-arm-on-rename fix, only the first would be seen (the fd goes stale).
    func testWatcherSurvivesAtomicReplace() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("f.md")
        try "v1".write(to: file, atomically: true, encoding: .utf8)

        let watcher = TaskFileWatcher(path: file.path)
        defer { watcher.cancel() }

        let counter = Counter()
        let consume = Task { for await _ in watcher.events { await counter.inc() } }
        defer { consume.cancel() }

        try await Task.sleep(nanoseconds: 400_000_000)          // let the watcher arm
        try "v2".write(to: file, atomically: true, encoding: .utf8)   // first atomic replace
        try await Task.sleep(nanoseconds: 500_000_000)          // event + re-arm settle
        try "v3".write(to: file, atomically: true, encoding: .utf8)   // second atomic replace
        try await Task.sleep(nanoseconds: 600_000_000)          // let the second event arrive

        let seen = await counter.value
        XCTAssertGreaterThanOrEqual(seen, 2, "watcher missed the second atomic write (got \(seen))")
    }
}
