import XCTest
@testable import KanbanCore

/// Ganzer Lauf gegen die echten Transcripts unter ~/.claude/projects und die echte `claude`-CLI.
/// Opt-in, weil er Tokens kostet und eine angemeldete CLI braucht:
///
///     KANBAN_WATCHDOG_LIVE=1 swift test --filter WatchdogLiveTests
///
/// Der Stand landet in einer Temp-Datei, nie in ~/Library/Application Support/Kanban.
final class WatchdogLiveTests: XCTestCase {

    func testEchterScanLiefertBrauchbareBefunde() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KANBAN_WATCHDOG_LIVE"] == "1",
                          "Live-Lauf nur mit KANBAN_WATCHDOG_LIVE=1")
        try XCTSkipUnless(ClaudeHeadless.verfuegbar, "claude-CLI nicht gefunden")

        let pfad = NSTemporaryDirectory() + "watchdog-live-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: pfad) }

        let scanner = WatchdogScanner(store: WatchdogStore(path: pfad))
        let settings = WatchdogSettings(aktiv: true, intervallMinuten: 60, rueckblickStunden: 72,
                                        maxSessions: 8, minSignale: 3, modell: "claude-sonnet-5")

        let ergebnis = try await scanner.scan(settings)

        print("""

        ── Watchdog-Livelauf ───────────────────────────────
        Sessions: \(ergebnis.sessionsGescannt)  Signale: \(ergebnis.signale)  \
        ausgewertet: \(ergebnis.ausgewertet)  \
        Kosten: \(ergebnis.state.letzteKostenUSD.map { String(format: "$%.4f", $0) } ?? "—")
        """)
        for befund in WatchdogMerge.sortiert(ergebnis.state.befunde) {
            print("""

            [\(befund.schwere.label.uppercased())] \(befund.kategorie.label) — \(befund.titel) (\(befund.anzahl)×)
              \(befund.beschreibung)
              → \(befund.empfehlung ?? "(keine Empfehlung)")
              Belege: \(befund.belege.count)
            """)
        }
        print("────────────────────────────────────────────────\n")

        XCTAssertNil(ergebnis.state.letzterFehler)
        for befund in ergebnis.state.befunde {
            XCTAssertFalse(befund.titel.isEmpty)
            XCTAssertGreaterThanOrEqual(befund.anzahl, 1)
        }
    }
}
