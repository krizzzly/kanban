import XCTest
@testable import KanbanCore

final class ANSIParserTests: XCTestCase {
    func testPlainTextStaysOneSpan() {
        let spans = ANSIParser.parse("nur Text")
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].text, "nur Text")
        XCTAssertNil(spans[0].foreground)
    }

    func testBasicColoursAreMapped() {
        let spans = ANSIParser.parse("\u{1B}[32mgrün\u{1B}[0m normal")
        XCTAssertEqual(spans.map(\.text), ["grün", " normal"])
        XCTAssertEqual(spans[0].foreground, 2)
        XCTAssertNil(spans[1].foreground)
    }

    func testBrightColoursMapToTheUpperEight() {
        XCTAssertEqual(ANSIParser.parse("\u{1B}[91mhell").first?.foreground, 9)
        XCTAssertEqual(ANSIParser.parse("\u{1B}[100mbg").first?.background, 8)
    }

    func testBoldIsTracked() {
        let spans = ANSIParser.parse("\u{1B}[1mfett\u{1B}[22mnormal")
        XCTAssertTrue(spans[0].bold)
        XCTAssertFalse(spans[1].bold)
    }

    func testResetClearsEverything() {
        let spans = ANSIParser.parse("\u{1B}[1;31mrot fett\u{1B}[0mplain")
        XCTAssertEqual(spans[0].foreground, 1)
        XCTAssertTrue(spans[0].bold)
        XCTAssertNil(spans[1].foreground)
        XCTAssertFalse(spans[1].bold)
    }

    func testNonColourSequencesAreStrippedNotRendered() {
        // Progress bars redraw with erase-line and cursor moves; those must not reach the pane.
        let spans = ANSIParser.parse("Fortschritt\u{1B}[K\u{1B}[2A fertig")
        XCTAssertEqual(spans.map(\.text).joined(), "Fortschritt fertig")
    }

    func testTrueColourOperandsAreConsumed() {
        // `38;2;r;g;b` must not leave "2", "255" … as visible text.
        let spans = ANSIParser.parse("\u{1B}[38;2;255;128;0mText")
        XCTAssertEqual(spans.map(\.text).joined(), "Text")
    }

    func test256ColourOperandsAreConsumed() {
        XCTAssertEqual(ANSIParser.parse("\u{1B}[38;5;208mText").map(\.text).joined(), "Text")
    }

    func testTruncatedSequenceDoesNotHang() {
        XCTAssertEqual(ANSIParser.parse("abc\u{1B}[32").map(\.text).joined(), "abc")
    }

    func testStripRemovesAllEscapes() {
        XCTAssertEqual(ANSIParser.strip("\u{1B}[32mgrün\u{1B}[0m"), "grün")
    }

    func testRealIwfOutput() {
        let line = "\u{1B}[32m✓\u{1B}[0m Building base image \u{1B}[1m(local)\u{1B}[0m\n"
        let spans = ANSIParser.parse(line)
        XCTAssertEqual(spans.map(\.text).joined(), "✓ Building base image (local)\n")
        XCTAssertEqual(spans.first?.foreground, 2)
        XCTAssertTrue(spans.contains { $0.bold && $0.text.contains("(local)") })
    }
}
