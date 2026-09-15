import XCTest
@testable import KanbanCore

final class HermesDebug: XCTestCase {
    func testDiscoverHermes() throws {
        let dir = NSString(string: "~/code/hermes/.claude/tasks").expandingTildeInPath
        let files = LocalTickets.taskFiles(in: dir, prefix: "HERMES")
        print("TASKFILES gefunden:", files.count)
        for f in files.prefix(5) { print("   \(f.key) — \(f.title ?? "<kein Titel>")") }

        let tickets = LocalTickets.discover(tasksDirectory: dir, prefix: "HERMES")
        print("TICKETS:", tickets.count, tickets.prefix(5).map(\.key))

        // Gegenprobe: was liegt überhaupt im Ordner?
        let all = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let md = all.filter { $0.hasSuffix(".md") }
        print("MD-DATEIEN im Ordner:", md.count)
        for name in md.sorted().prefix(5) {
            let key = LocalTickets.key(inFileName: name, prefix: "HERMES")
            let review = key.map { TaskFileLoader.isReviewFilename(name, keyPrefix: $0) }
            print("   \(name) → key=\(key ?? "nil") review=\(review.map(String.init(describing:)) ?? "-")")
        }
    }
}
