import XCTest
@testable import KanbanCore

final class WorktreeDbSeedTests: XCTestCase {
    func testFindsNewestStagedDump() throws {
        let wt = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-seed-\(UUID().uuidString)")
        let initDir = wt.appendingPathComponent(WorktreeDbSeed.defaultInitSubdir)
        try FileManager.default.createDirectory(at: initDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: wt) }

        try Data(repeating: 0, count: 1234).write(to: initDir.appendingPathComponent("00_dev-dump.sql.gz"))
        // A non-dump file must be ignored.
        try "x".write(to: initDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let dump = WorktreeDbSeed.staged(worktreePath: wt.path)
        XCTAssertEqual(dump?.fileName, "00_dev-dump.sql.gz")
        XCTAssertEqual(dump?.sizeBytes, 1234)
    }

    func testNilWhenNoDump() {
        let dump = WorktreeDbSeed.staged(worktreePath: "/nonexistent/worktree/path")
        XCTAssertNil(dump)
    }
}
