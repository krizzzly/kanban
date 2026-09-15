import XCTest
@testable import KanbanCore

/// Der Puffer der Command-Ausgabe: anhängen, kappen, und der Zuwachs, den die Log-Ansicht rendert.
final class LogTextTests: XCTestCase {

    // MARK: - Anhängen und Kappen

    func testAppendsBelowTheLimit() {
        XCTAssertEqual(LogText.appending("abc", "def"), "abcdef")
    }

    func testKeepsEverythingUntilTheLimitIsExceeded() {
        let text = String(repeating: "x", count: LogText.limitBytes - 10)
        XCTAssertEqual(LogText.appending(text, "0123456789").utf8.count, LogText.limitBytes)
    }

    func testTrimsToAboutKeepBytesWhenTheLimitIsExceeded() {
        let line = String(repeating: "y", count: 99) + "\n"      // 100 Byte je Zeile
        let text = String(repeating: line, count: 3000)          // 300 000 Byte
        let result = LogText.appending(text, line)
        XCTAssertLessThanOrEqual(result.utf8.count, LogText.keepBytes)
        XCTAssertGreaterThan(result.utf8.count, LogText.keepBytes - 200)
    }

    func testTrimCutsAtALineBoundary() {
        var text = ""
        var line = 0
        while text.utf8.count <= LogText.limitBytes {
            text += "Zeile \(line) — Container gestartet\n"
            line += 1
        }
        let result = LogText.appending(text, "")
        XCTAssertTrue(result.hasPrefix("Zeile "), "der Rest muss an einem Zeilenanfang beginnen: \(result.prefix(30))")
        XCTAssertTrue(result.hasSuffix("\n"))
    }

    /// Der Schnitt läuft über die UTF-8-Sicht und kann mitten in ein Mehrbyte-Zeichen fallen — das
    /// Verwerfen der angeschnittenen Zeile muss den Rest davon mitnehmen, sonst steht ein `�` da.
    func testTrimLeavesNoBrokenCharacters() {
        var text = ""
        while text.utf8.count <= LogText.limitBytes {
            text += "Grüße — Gebäude läuft ✔\n"
        }
        let result = LogText.appending(text, "")
        XCTAssertFalse(result.unicodeScalars.contains("\u{FFFD}"), "kein Ersatzzeichen im gekappten Text")
    }

    /// Die Grössenprüfung geht über Bytes, nicht über Zeichen — sonst kappt Text mit Umlauten zu früh.
    func testLimitCountsBytesNotCharacters() {
        let text = String(repeating: "ä", count: 60_000)   // 60 000 Zeichen, 120 000 Byte
        XCTAssertEqual(LogText.appending(text, "").utf8.count, 120_000)
    }

    // MARK: - Zuwachs

    func testAppendedPartIsTheNewTail() {
        XCTAssertEqual(LogText.appendedPart(of: "abcdef", after: "abc"), "def")
    }

    func testAppendedPartIsEmptyWhenNothingChanged() {
        XCTAssertEqual(LogText.appendedPart(of: "abc", after: "abc"), "")
    }

    func testAppendedPartIsNilWhenTheStartChanged() {
        XCTAssertNil(LogText.appendedPart(of: "xbcdef", after: "abc"))   // neuer Befehl
        XCTAssertNil(LogText.appendedPart(of: "ef", after: "abcdef"))    // vorne gekappt
    }

    func testAppendedPartSurvivesMultibyteCharacters() {
        XCTAssertEqual(LogText.appendedPart(of: "Grüße ✔ fertig", after: "Grüße ✔"), " fertig")
    }

    /// Nach dem Kappen passt der alte Stand nicht mehr — genau daran erkennt die Ansicht, dass sie
    /// neu aufbauen muss statt anzuhängen.
    func testTrimmedBufferIsNotAnAppend() {
        let line = String(repeating: "z", count: 99) + "\n"
        let text = String(repeating: line, count: 3000)
        let trimmed = LogText.appending(text, line)
        XCTAssertNil(LogText.appendedPart(of: trimmed, after: text))
    }
}
