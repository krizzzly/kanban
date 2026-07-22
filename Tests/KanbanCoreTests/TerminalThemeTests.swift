import XCTest
@testable import KanbanCore

final class TerminalThemeTests: XCTestCase {
    func testHexParsing() {
        let c = TerminalRGB(hex: "#002b36")
        XCTAssertEqual(c?.r, 0x00)
        XCTAssertEqual(c?.g, 0x2b)
        XCTAssertEqual(c?.b, 0x36)

        // Without leading '#', case-insensitive.
        XCTAssertEqual(TerminalRGB(hex: "FDF6E3"), TerminalRGB(r: 0xfd, g: 0xf6, b: 0xe3))
    }

    func testHexParsingRejectsMalformed() {
        XCTAssertNil(TerminalRGB(hex: "#fff"))     // 3-digit not supported
        XCTAssertNil(TerminalRGB(hex: "#gggggg"))  // non-hex
        XCTAssertNil(TerminalRGB(hex: "12345"))    // too short
    }

    func testSolarizedDarkBuiltIn() {
        let t = TerminalTheme.solarizedDark
        XCTAssertEqual(t.name, "Solarized Dark")
        XCTAssertEqual(t.ansi.count, 16)
        XCTAssertEqual(t.background, TerminalRGB(hex: "#002b36"))
        XCTAssertEqual(t.foreground, TerminalRGB(hex: "#839496"))
        XCTAssertEqual(t.ansi[1], TerminalRGB(hex: "#dc322f"))   // ANSI red
        XCTAssertEqual(t.ansi[4], TerminalRGB(hex: "#268bd2"))   // ANSI blue
    }

    private static let ansi16 = (0..<16).map { _ in "\"#000000\"" }.joined(separator: ",")

    func testParseFontSettings() {
        let json = """
        {"terminal": {"theme": "X", "font": {"size": 18, "smoothing": false, "family": "Menlo"},
          "themes": {"X": {"background": "#000000", "foreground": "#ffffff", "ansi": [\(Self.ansi16)]}}}}
        """
        let s = KanbanSettingsStore.parse(Data(json.utf8))
        XCTAssertEqual(s.font.size, 18)
        XCTAssertFalse(s.font.smoothing)
        XCTAssertEqual(s.font.family, "Menlo")
        XCTAssertEqual(s.activeTerminalTheme.name, "X")
    }

    func testFontDefaultsWhenMissingAndSizeClamped() {
        let json = """
        {"terminal": {"font": {"size": 999},
          "themes": {"X": {"background": "#000000", "foreground": "#ffffff", "ansi": [\(Self.ansi16)]}}}}
        """
        let s = KanbanSettingsStore.parse(Data(json.utf8))
        XCTAssertEqual(s.font.size, 72)          // clamped to max
        XCTAssertTrue(s.font.smoothing)          // default when absent
        XCTAssertNil(s.font.family)              // default when absent
    }

    func testEmptyConfigFallsBackToBuiltins() {
        let s = KanbanSettingsStore.parse(Data("{}".utf8))
        XCTAssertEqual(s.activeTerminalTheme.name, "Solarized Dark")   // first built-in fallback
        XCTAssertEqual(s.font, .default)
    }
}
