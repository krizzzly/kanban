import XCTest
@testable import KanbanCore

final class JiraDurationTests: XCTestCase {
    /// Jiras Rechnung, nicht die des Kalenders: 1d = 8h Arbeitstag, 1w = 5d.
    func testParsesJiraTokens() throws {
        XCTAssertEqual(try JiraDuration.parse("1h 30m"), 5400)
        XCTAssertEqual(try JiraDuration.parse("90m"), 5400)
        XCTAssertEqual(try JiraDuration.parse("2d"), 2 * 8 * 3600)
        XCTAssertEqual(try JiraDuration.parse("1w"), 5 * 8 * 3600)
        XCTAssertEqual(try JiraDuration.parse("1w 1d 2h"), 5 * 8 * 3600 + 8 * 3600 + 7200)
        XCTAssertEqual(try JiraDuration.parse("1H 30M"), 5400)   // Gross-/Kleinschreibung egal
        XCTAssertEqual(try JiraDuration.parse("  2h  "), 7200)
    }

    /// Eine blosse Zahl sind **Dezimalstunden** — „1.5" heisst 90 Minuten, nicht 1,5 Sekunden.
    func testBareNumberIsDecimalHours() throws {
        XCTAssertEqual(try JiraDuration.parse("1.5"), 5400)
        XCTAssertEqual(try JiraDuration.parse("2"), 7200)
        XCTAssertEqual(try JiraDuration.parse("0.25"), 900)
    }

    /// Halb verstandene Eingaben werden abgelehnt statt geraten — sonst bucht ein Tippfehler
    /// stillschweigend die falsche Zeit.
    func testRejectsAnythingNotFullyUnderstood() {
        XCTAssertThrowsError(try JiraDuration.parse("")) {
            XCTAssertEqual($0 as? JiraDuration.ParseError, .empty)
        }
        XCTAssertThrowsError(try JiraDuration.parse(nil)) {
            XCTAssertEqual($0 as? JiraDuration.ParseError, .empty)
        }
        XCTAssertThrowsError(try JiraDuration.parse("1h zwanzig")) {
            XCTAssertEqual($0 as? JiraDuration.ParseError, .invalid("1h zwanzig"))
        }
        XCTAssertThrowsError(try JiraDuration.parse("30s")) {
            XCTAssertEqual($0 as? JiraDuration.ParseError, .invalid("30s"))
        }
    }

    /// Unter einer Minute lehnt Jira selbst ab — dann lieber hier, mit einer verständlichen Meldung.
    func testRejectsLessThanAMinute() {
        XCTAssertThrowsError(try JiraDuration.parse("0.001")) {
            XCTAssertEqual($0 as? JiraDuration.ParseError, .tooShort("0.001"))
        }
    }

    func testFormatsBack() {
        XCTAssertEqual(JiraDuration.format(5400), "1h 30m")
        XCTAssertEqual(JiraDuration.format(8 * 3600), "1d")
        XCTAssertEqual(JiraDuration.format(9 * 3600 + 1800), "1d 1h 30m")
        XCTAssertEqual(JiraDuration.format(30), "0m")       // gerundet, aber nicht verschwiegen
        XCTAssertNil(JiraDuration.format(0))
        XCTAssertNil(JiraDuration.format(nil))
    }

    /// Hin und zurück muss dieselbe Zahl ergeben, sonst driftet eine gebuchte Zeit bei jeder Anzeige.
    func testRoundTrip() throws {
        for seconds in [60, 900, 3600, 5400, 8 * 3600, 5 * 8 * 3600 + 3600] {
            let text = try XCTUnwrap(JiraDuration.format(seconds))
            XCTAssertEqual(try JiraDuration.parse(text), seconds, "bei \(text)")
        }
    }
}
