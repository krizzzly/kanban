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

    // MARK: - Stückweise (Log-Ansicht hängt nur den Zuwachs an)

    /// Eine Farbe gilt bis zum nächsten Reset — auch über die Stückgrenze hinweg. Ohne
    /// fortgeschriebenen Zustand begänne jedes angehängte Stück wieder in der Vordergrundfarbe.
    func testColourCarriesAcrossChunks() {
        var state = ANSIParser.State()
        XCTAssertEqual(ANSIParser.parse("\u{1B}[32mgrün ", state: &state).first?.foreground, 2)
        let next = ANSIParser.parse("immer noch grün", state: &state)
        XCTAssertEqual(next.first?.foreground, 2)
        XCTAssertEqual(next.map(\.text).joined(), "immer noch grün")
    }

    func testResetCarriesAcrossChunks() {
        var state = ANSIParser.State()
        _ = ANSIParser.parse("\u{1B}[1;31mrot fett\u{1B}[0m", state: &state)
        XCTAssertEqual(ANSIParser.parse("normal", state: &state).first?.bold, false)
        XCTAssertNil(ANSIParser.parse("normal", state: &state).first?.foreground)
    }

    /// Der pty liefert im Schnitt 47 Byte je Lesevorgang — eine Sequenz wird dabei ständig
    /// zerschnitten. Die angefangene Sequenz wartet auf das nächste Stück, statt als Text
    /// durchzufallen.
    func testSequenceSplitAcrossChunks() {
        var state = ANSIParser.State()
        XCTAssertEqual(ANSIParser.parse("Text \u{1B}[3", state: &state).map(\.text).joined(), "Text ")
        let next = ANSIParser.parse("2mgrün", state: &state)
        XCTAssertEqual(next.map(\.text).joined(), "grün")
        XCTAssertEqual(next.first?.foreground, 2)
    }

    func testLoneEscapeAtTheChunkEndWaitsForTheNextChunk() {
        var state = ANSIParser.State()
        XCTAssertEqual(ANSIParser.parse("Text \u{1B}", state: &state).map(\.text).joined(), "Text ")
        XCTAssertEqual(ANSIParser.parse("[31mrot", state: &state).first?.foreground, 1)
    }

    /// Stückweise gelesen muss derselbe Text herauskommen wie am Stück — an einer echten
    /// iwf-artigen Zeile, an jeder möglichen Schnittstelle geprüft.
    func testChunkedParsingMatchesWholeInput() {
        let line = "\u{1B}[32m ✔\u{1B}[0m Container \u{1B}[36meven-3563-fpm\u{1B}[0m Started\n"
        let whole = ANSIParser.parse(line)
        let bytes = Array(line.utf8)
        for cut in 1..<bytes.count {
            guard let head = String(bytes: bytes[..<cut], encoding: .utf8),
                  let tail = String(bytes: bytes[cut...], encoding: .utf8) else { continue }
            var state = ANSIParser.State()
            let spans = ANSIParser.parse(head, state: &state) + ANSIParser.parse(tail, state: &state)
            XCTAssertEqual(spans.map(\.text).joined(), whole.map(\.text).joined(),
                           "Text weicht ab bei Schnitt \(cut)")
            XCTAssertEqual(colouring(spans), colouring(whole), "Farben weichen ab bei Schnitt \(cut)")
        }
    }

    /// Farbe je Zeichen — so lässt sich die Färbung unabhängig von der Span-Aufteilung vergleichen.
    private func colouring(_ spans: [ANSISpan]) -> [Int?] {
        spans.flatMap { span in Array(repeating: span.foreground, count: span.text.count) }
    }
}
