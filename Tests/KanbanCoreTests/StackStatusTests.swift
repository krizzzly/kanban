import XCTest
@testable import KanbanCore

final class StackStatusTests: XCTestCase {
    /// Real `docker ps -a` output from a worktree stack, including the two silent failures.
    private let output = """
    even-3602-nginx\trunning\tUp 13 minutes
    even-3602-mailcatcher\trunning\tUp 13 minutes (healthy)
    even-3602-minio-setup\texited\tExited (1) 13 minutes ago
    even-3602-keycloak\texited\tExited (134) 10 hours ago
    even-3602-db\trunning\tUp 13 minutes (unhealthy)
    even-3518-nginx\trunning\tUp 11 hours
    dns\trunning\tUp 13 minutes
    """

    private var services: [StackService] {
        StackStatusParser.services(from: output, stackName: "even-3602")
    }

    func testOnlyThisStacksContainersAreTaken() {
        // `even-3518-*` belongs to another worktree, `dns` is the shared router.
        XCTAssertEqual(services.map(\.name).sorted(),
                       ["db", "keycloak", "mailcatcher", "minio-setup", "nginx"])
    }

    func testPrefixIsStrippedFromTheServiceName() {
        XCTAssertEqual(services.first { $0.container == "even-3602-minio-setup" }?.name, "minio-setup")
    }

    func testExitCodeIsExtracted() {
        // The number that today's raw `stack ps` output buries.
        XCTAssertEqual(services.first { $0.name == "keycloak" }?.exitCode, 134)
        XCTAssertEqual(services.first { $0.name == "minio-setup" }?.exitCode, 1)
        XCTAssertNil(services.first { $0.name == "nginx" }?.exitCode)
    }

    func testHealthIsRead() {
        XCTAssertEqual(services.first { $0.name == "mailcatcher" }?.health, .healthy)
        XCTAssertEqual(services.first { $0.name == "db" }?.health, .unhealthy)
        XCTAssertEqual(services.first { $0.name == "nginx" }?.health, StackService.Health.none)
    }

    func testFailedContainersAreSeparatedFromMerelyStopped() {
        let stopped = StackStatusParser.services(
            from: "even-1-fpm\texited\tExited (0) 2 hours ago", stackName: "even-1")
        XCTAssertFalse(stopped[0].isFailed, "Exit 0 ist sauber beendet, kein Fehler")
        XCTAssertTrue(services.first { $0.name == "keycloak" }?.isFailed ?? false)
    }

    func testOneShotServicesAreRecognised() {
        XCTAssertTrue(services.first { $0.name == "minio-setup" }?.isOneShot ?? false)
        XCTAssertFalse(services.first { $0.name == "nginx" }?.isOneShot ?? true)
    }

    // MARK: - Verdict

    func testDegradedWhenAnythingFailedOrIsUnhealthy() {
        let status = WorktreeStackStatus(name: "even-3602", phases: [], services: services)
        XCTAssertEqual(status.verdict, .degraded)
        XCTAssertEqual(status.failed.map(\.name).sorted(), ["keycloak", "minio-setup"])
        XCTAssertEqual(status.unhealthy.map(\.name), ["db"])
    }

    func testRunningWhenEverythingIsUp() {
        let healthy = StackStatusParser.services(
            from: "even-1-fpm\trunning\tUp 2 hours\neven-1-db\trunning\tUp 2 hours (healthy)",
            stackName: "even-1")
        XCTAssertEqual(WorktreeStackStatus(name: "even-1", phases: [], services: healthy).verdict, .running)
    }

    func testStoppedAndNotCreatedAreDistinguished() {
        let stopped = StackStatusParser.services(
            from: "even-1-fpm\texited\tExited (0) 2 hours ago", stackName: "even-1")
        XCTAssertEqual(WorktreeStackStatus(name: "even-1", phases: [], services: stopped).verdict, .stopped)
        XCTAssertEqual(WorktreeStackStatus(name: "even-1", phases: [], services: []).verdict, .notCreated)
    }

    func testGarbageLinesAreIgnored() {
        XCTAssertTrue(StackStatusParser.services(from: "\n\nkaputt\n", stackName: "even-1").isEmpty)
    }
}
