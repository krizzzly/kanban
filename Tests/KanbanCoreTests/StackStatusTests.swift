import XCTest
@testable import KanbanCore

final class StackStatusTests: XCTestCase {
    /// Real `docker ps -a` output from a worktree stack, including the two silent failures.
    /// Vierte Spalte ist `{{.Label "com.docker.compose.project"}}` — sie entscheidet die
    /// Zugehörigkeit; `dns` läuft ohne Compose-Projekt.
    private let output = """
    even-3602-nginx\trunning\tUp 13 minutes\teven-3602
    even-3602-mailcatcher\trunning\tUp 13 minutes (healthy)\teven-3602
    even-3602-minio-setup\texited\tExited (1) 13 minutes ago\teven-3602
    even-3602-keycloak\texited\tExited (134) 10 hours ago\teven-3602
    even-3602-db\trunning\tUp 13 minutes (unhealthy)\teven-3602
    even-3518-nginx\trunning\tUp 11 hours\teven-3518
    dns\trunning\tUp 13 minutes\t
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
            from: "even-1-fpm\texited\tExited (0) 2 hours ago\teven-1", stackName: "even-1")
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
            from: "even-1-fpm\trunning\tUp 2 hours\teven-1\neven-1-db\trunning\tUp 2 hours (healthy)\teven-1",
            stackName: "even-1")
        XCTAssertEqual(WorktreeStackStatus(name: "even-1", phases: [], services: healthy).verdict, .running)
    }

    func testStoppedAndNotCreatedAreDistinguished() {
        let stopped = StackStatusParser.services(
            from: "even-1-fpm\texited\tExited (0) 2 hours ago\teven-1", stackName: "even-1")
        XCTAssertEqual(WorktreeStackStatus(name: "even-1", phases: [], services: stopped).verdict, .stopped)
        XCTAssertEqual(WorktreeStackStatus(name: "even-1", phases: [], services: []).verdict, .notCreated)
    }

    func testGarbageLinesAreIgnored() {
        XCTAssertTrue(StackStatusParser.services(from: "\n\nkaputt\n", stackName: "even-1").isEmpty)
    }

    func testContainerWithoutComposeLabelIsNotPartOfAnyStack() {
        // `dns` und `traefik` laufen ausserhalb der Projekt-Stacks.
        XCTAssertNil(services.first { $0.name == "dns" })
    }

    // MARK: - Haupt-Repo

    /// Der Stack des Haupt-Repos heisst wie das Projekt (`even`) und ist damit Namens-Präfix
    /// **jedes** Worktree-Stacks. Genau daran hat die Maintree-Ansicht die Container fremder
    /// Worktrees als eigene Dienste ausgewiesen — `even-3602-db` erschien dort als „3602-db",
    /// und die Zählung stand auf 14/14 statt 7/7.
    private let mixed = """
    even-nginx\trunning\tUp 33 hours\teven
    even-db\trunning\tUp 6 hours\teven
    even-3602-nginx\trunning\tUp 4 hours\teven-3602
    even-3602-db\trunning\tUp 4 hours\teven-3602
    """

    func testMainRepoStackDoesNotAdoptWorktreeContainers() {
        let main = StackStatusParser.services(from: mixed, stackName: "even")
        XCTAssertEqual(main.map(\.name).sorted(), ["db", "nginx"])
        XCTAssertEqual(main.map(\.container).sorted(), ["even-db", "even-nginx"])
    }

    func testWorktreeStackStillSeesOnlyItsOwnContainers() {
        let worktree = StackStatusParser.services(from: mixed, stackName: "even-3602")
        XCTAssertEqual(worktree.map(\.container).sorted(), ["even-3602-db", "even-3602-nginx"])
    }

    func testContainerWithOwnNameKeepsItWhenThePrefixIsMissing() {
        // `container_name:` im Compose-File — das Label stimmt, das Präfix fehlt. Der volle Name
        // ist dann der beste, den es gibt; ihn zu verwerfen hiesse, den Dienst zu verlieren.
        let services = StackStatusParser.services(
            from: "adminer\trunning\tUp 2 hours\teven", stackName: "even")
        XCTAssertEqual(services.map(\.name), ["adminer"])
    }
}
