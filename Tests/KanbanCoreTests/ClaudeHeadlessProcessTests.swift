import XCTest
@testable import KanbanCore

/// Der Unterprozess des Watchdogs — gegen ein **echtes** Programm, denn genau hier ging es schief:
/// das Zeitlimit war zu knapp (jeder Lauf endete mit „claude hat nach 240s nicht geantwortet"), und
/// ein laufendes Kind überlebte das Beenden der App als Waise mit `ppid=1`.
final class ClaudeHeadlessProcessTests: XCTestCase {
    private var ordner: URL!
    /// Ein Skript, das sich wie ein sehr langsames `claude` verhält.
    private var langsam: String!

    override func setUpWithError() throws {
        ordner = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("headless-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let skript = ordner.appendingPathComponent("langsam.sh")
        try "#!/bin/sh\nsleep 120\n".write(to: skript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: skript.path)
        langsam = skript.path
    }

    override func tearDownWithError() throws {
        ClaudeHeadless.alleBeenden()
        try? FileManager.default.removeItem(at: ordner)
    }

    func testZeitlimitGreift() {
        let client = ClaudeHeadless(modell: "egal", executable: langsam)
        let start = Date()
        XCTAssertThrowsError(try client.frage("prompt", timeout: 1)) { fehler in
            XCTAssertEqual(fehler as? ClaudeHeadless.Fehler, .abgelaufen(1))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 20, "das Limit muss auch wirklich greifen")
    }

    /// Die Vorgabe muss über der gemessenen Laufzeit liegen: ein voller Lauf braucht hier 5½ bis 6
    /// Minuten, die alten 240 s schnitten ihn jedes Mal ab.
    func testVorgabeDesZeitlimitsHatLuft() {
        XCTAssertGreaterThanOrEqual(WatchdogSettings().timeoutSekunden, 600)
    }

    /// Der Kern gegen die Waisen: ein laufendes Kind lässt sich von aussen beenden — das tut die App
    /// beim Schliessen (`applicationWillTerminate`) und der ✕-Knopf im Panel.
    func testLaufenderAufrufLaesstSichBeenden() throws {
        let client = ClaudeHeadless(modell: "egal", executable: langsam)
        let fertig = expectation(description: "Aufruf endet")

        Thread.detachNewThread {
            _ = try? client.frage("prompt", timeout: 120)
            fertig.fulfill()
        }

        // Warten, bis das Kind wirklich läuft — sonst beendet man nichts.
        let start = Date()
        while !ClaudeHeadless.laeuftGerade, Date().timeIntervalSince(start) < 5 {
            usleep(20_000)
        }
        XCTAssertTrue(ClaudeHeadless.laeuftGerade, "der Prozess sollte laufen")

        XCTAssertEqual(ClaudeHeadless.alleBeenden(), 1)
        wait(for: [fertig], timeout: 10)
        XCTAssertFalse(ClaudeHeadless.laeuftGerade, "danach ist die Liste leer")
    }

    func testOhneLaufNichtsZuBeenden() {
        XCTAssertEqual(ClaudeHeadless.alleBeenden(), 0)
        XCTAssertFalse(ClaudeHeadless.laeuftGerade)
    }
}
