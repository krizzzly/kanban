import XCTest
@testable import KanbanCore

final class PromptLocatorTests: XCTestCase {
    /// Baut ein Pane wie Claude es rendert: Prompt-Zeile, dann Antwortzeilen.
    private func pane(_ blocks: [(prompt: String, answerLines: Int)], leading: Int = 0) -> [String] {
        var lines = Array(repeating: "… älterer Output …", count: leading)
        for block in blocks {
            lines.append("❯ \(block.prompt)")
            lines += Array(repeating: "⏺ Antwort", count: block.answerLines)
        }
        return lines
    }

    func testMapsEachPromptToItsPaneLine() {
        let lines = pane([("erste Frage", 3), ("zweite Frage", 2)], leading: 5)
        let map = PromptLocator.locate(prompts: ["erste Frage", "zweite Frage"], paneLines: lines)
        XCTAssertEqual(map[0], 5)
        XCTAssertEqual(map[1], 9)
    }

    /// Der Kern: gleiche Prompt-Texte dürfen nicht alle auf den letzten Treffer zeigen — genau das
    /// würde eine Rückwärtssuche im Terminal tun.
    func testDuplicatePromptsKeepTheirOwnLines() {
        let lines = pane([("ok mach das bitte", 2), ("und jetzt?", 1), ("ok mach das bitte", 4)])
        let map = PromptLocator.locate(
            prompts: ["ok mach das bitte", "und jetzt?", "ok mach das bitte"], paneLines: lines)
        XCTAssertEqual(map[0], 0)
        XCTAssertEqual(map[1], 3)
        XCTAssertEqual(map[2], 5)
    }

    /// Was aus dem Scrollback gefallen ist, bleibt ungemappt — die UI graut es aus.
    func testOlderPromptsOutsideTheScrollbackStayUnmapped() {
        let lines = pane([("dritte", 1), ("vierte", 1)])
        let map = PromptLocator.locate(prompts: ["erste", "zweite", "dritte", "vierte"], paneLines: lines)
        XCTAssertNil(map[0])
        XCTAssertNil(map[1])
        XCTAssertEqual(map[2], 0)
        XCTAssertEqual(map[3], 2)
    }

    /// Realfall aus EVEN-3518: ein während Claudes Antwort eingereihter Prompt wird im Pane
    /// gezeigt, öffnet aber keinen Turn. Er darf die älteren Zuordnungen nicht mitreißen.
    func testPaneLineWithoutTurnDoesNotSwallowOlderPrompts() {
        let lines = pane([("das modal bitte breiter machen", 2),
                          ("diese komponente soll ein hover bekommen", 3),
                          ("ein tooltip", 1),                                    // kein eigener Turn
                          ("ich seh keinen tooltip in der liste", 2)])
        let map = PromptLocator.locate(
            prompts: ["das modal bitte breiter machen",
                      "diese komponente soll ein hover bekommen",
                      "ich seh keinen tooltip in der liste"],
            paneLines: lines)
        XCTAssertEqual(map[0], 0)
        XCTAssertEqual(map[1], 3)
        XCTAssertEqual(map[2], 9)
        XCTAssertEqual(map.count, 3)
    }

    /// Der Fensterlauf darf nicht über seine Grenze hinaus greifen: eine Pane-Zeile, deren Prompt
    /// weiter als `lookback` zurückliegt, bleibt lieber ungemappt als falsch gemappt.
    func testLookbackIsBounded() {
        let older = (0..<PromptLocator.lookback + 3).map { "prompt \($0)" }
        let lines = pane([("prompt 0", 1)])
        XCTAssertTrue(PromptLocator.locate(prompts: older, paneLines: lines).isEmpty)
    }

    /// Das Pane schneidet den Prompt an der Pane-Breite ab — verglichen wird ein Präfix.
    func testMatchesTruncatedPaneLine() {
        let full = "wie würde der Migrator mit descendants ausschauen ? - kannst du das bitte bauen, damit ich es sehe"
        let lines = ["❯ wie würde der Migrator mit descendants ausschauen ? - kannst du das bitte b"]
        XCTAssertEqual(PromptLocator.locate(prompts: [full], paneLines: lines)[0], 0)
    }

    /// Slash-Commands stehen im Transcript als `/name args` und im Pane genauso.
    func testMatchesSlashCommand() {
        let lines = ["❯ /review-task EVEN-3512"]
        XCTAssertEqual(PromptLocator.locate(prompts: ["/review-task EVEN-3512"], paneLines: lines)[0], 0)
    }

    /// Ältere Claude-Versionen rendern `>` statt `❯`.
    func testAcceptsLegacyMarker() {
        XCTAssertEqual(PromptLocator.promptLines(in: ["> alte Version"]).first?.line, 0)
    }

    /// Fehlt der Marker ganz (neue Claude-Version), findet der Locator nichts — und die UI fällt auf
    /// das Transcript zurück, statt an eine falsche Stelle zu springen.
    func testUnknownMarkerFindsNothing() {
        let map = PromptLocator.locate(prompts: ["irgendwas"], paneLines: ["» irgendwas"])
        XCTAssertTrue(map.isEmpty)
    }

    func testIgnoresEmptyPromptLine() {
        XCTAssertTrue(PromptLocator.promptLines(in: ["❯ ", "❯    "]).isEmpty)
    }

    // MARK: - Scroll-Arithmetik

    /// Zielzeile landet knapp unter der Oberkante: gemessen an tmux (1824 Zeilen, Pane 29) plus dem
    /// Kontext-/Drift-Rand.
    func testScrollDistancePutsLineBelowTheTopEdge() {
        XCTAssertEqual(TmuxController.scrollDistance(toLine: 803, totalLines: 1824, paneHeight: 29),
                       992 + TmuxController.scrollTopMargin)
    }

    /// Was ohnehin sichtbar ist, wird nicht gescrollt.
    func testNoScrollWhenAlreadyOnScreen() {
        XCTAssertNil(TmuxController.scrollDistance(toLine: 1800, totalLines: 1824, paneHeight: 29))
        XCTAssertNil(TmuxController.scrollDistance(toLine: 1797, totalLines: 1824, paneHeight: 29))
    }
}
