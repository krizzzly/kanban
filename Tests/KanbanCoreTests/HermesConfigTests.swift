import XCTest
@testable import KanbanCore

final class HermesConfigTests: XCTestCase {
    private var configURL: URL!

    override func setUpWithError() throws {
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-config-tests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: configURL)
    }

    private func load(_ projects: String) throws -> HermesConfig {
        let json = """
        {
          "basePath": "/base",
          "modules": {
            "jira": {
              "baseUrl": "https://x.atlassian.net", "email": "a@b.c", "apiToken": "t",
              "projects": { \(projects) }
            }
          }
        }
        """
        try json.write(to: configURL, atomically: true, encoding: .utf8)
        return try HermesConfigLoader.load(path: configURL.path)
    }

    /// Bisheriges Verhalten ohne Override: Repo = Basis + erstes Segment des Tasks-Pfads.
    func testRepoDirDerivedFromTasksPath() throws {
        let config = try load(#""even": {"prefix": "EVEN", "tasksPath": "even/docs/tasks"}"#)
        XCTAssertEqual(config.projects[0].repoDir, "/base/even")
        XCTAssertEqual(config.projects[0].tasksPathAbsolute, "/base/even/docs/tasks")
    }

    /// HERMES-034: eigener repoDir entkoppelt das Repo vom Tasks-Pfad — relativ zum Basis-Pfad …
    func testRepoDirOverrideRelative() throws {
        let config = try load(
            #""even": {"prefix": "EVEN", "tasksPath": "kanban-tasks/even", "repoDir": "even"}"#)
        XCTAssertEqual(config.projects[0].repoDir, "/base/even")
        XCTAssertEqual(config.projects[0].tasksPathAbsolute, "/base/kanban-tasks/even")
    }

    /// … oder absolut, dann zählt er unverändert. Auch der Tasks-Pfad darf absolut sein
    /// (Voraussetzung für den Umzug nach Application Support).
    func testRepoDirOverrideAndTasksPathAbsolute() throws {
        let config = try load(
            #""even": {"prefix": "EVEN", "tasksPath": "/apps/Kanban/tasks/even", "repoDir": "/repos/even"}"#)
        XCTAssertEqual(config.projects[0].repoDir, "/repos/even")
        XCTAssertEqual(config.projects[0].tasksPathAbsolute, "/apps/Kanban/tasks/even")
    }
}
