import XCTest
@testable import KanbanCore

final class EpicRefTests: XCTestCase {
    private let pendenzen = EpicRef(key: "EVEN-3345", title: "Pendenzensystem",
                                    colorName: "purple", paletteKey: "color_14")

    // MARK: - Colour

    func testEpicColourKeyDecidesTheSwatch() {
        // color_14 is Jira's ghx-label-14 = dark_orange, whatever issueColor claims.
        XCTAssertEqual(pendenzen.hex, "#FF5630")
        XCTAssertEqual(EpicRef(key: "A-1", title: "x", paletteKey: "color_4").hex, "#0052CC")
        XCTAssertEqual(EpicRef(key: "A-1", title: "x", paletteKey: "color_6").hex, "#57D9A3")
    }

    func testTwoEpicsJiraCallsPurpleStillGetTheirOwnColours() {
        // The real case this feature hit: the Agile API answers issueColor "purple" for every epic,
        // so relying on it painted an entire board one colour.
        let a = EpicRef(key: "EVEN-3345", title: "Pendenzensystem", colorName: "purple", paletteKey: "color_14")
        let b = EpicRef(key: "EVEN-8", title: "Benutzergruppen", colorName: "purple", paletteKey: "color_6")
        XCTAssertNotEqual(a.hex, b.hex)
    }

    func testColourNameIsUsedWhenNoEpicColourKeyArrives() {
        XCTAssertEqual(EpicRef(key: "A-1", title: "x", colorName: "dark_blue").hex, "#0052CC")
        XCTAssertEqual(EpicRef(key: "A-1", title: "x", colorName: "PURPLE").hex, "#8777D9")
        // Jira has been seen writing both spellings.
        XCTAssertEqual(EpicRef(key: "A-1", title: "x", colorName: "dark_gray").hex,
                       EpicRef(key: "A-1", title: "x", colorName: "dark_grey").hex)
    }

    func testEveryJiraEpicColourKeyResolvesToADistinctSwatch() {
        let hexes = (1...14).map { EpicRef(key: "E-\($0)", title: "", paletteKey: "color_\($0)").hex }
        XCTAssertEqual(Set(hexes).count, 14, "Jira's 14 epic colours must stay distinguishable")
    }

    func testUnknownColourFallsBackToAStableSwatchInsteadOfFailing() {
        // A key Jira might add later, or a colour name we don't know.
        let added = EpicRef(key: "EVEN-1", title: "A", paletteKey: "color_21")
        XCTAssertTrue(EpicColors.fallbacks.contains(added.hex))
        // Stable across calls (no randomly seeded hashing), so an epic keeps its colour.
        XCTAssertEqual(added.hex, EpicRef(key: "EVEN-1", title: "A", paletteKey: "color_21").hex)
        XCTAssertTrue(EpicColors.fallbacks.contains(
            EpicRef(key: "A-1", title: "x", colorName: "chartreuse").hex))
    }

    func testFallbackSeedsDifferingOnlyInTheirDigitDoNotShareAColour() {
        // Seeds like "color_17"/"color_25" differ by exactly the fallback count, which is where a
        // byte-sum or bare multiply-hash collapses them onto one colour.
        let a = EpicRef(key: "E-a", title: "", paletteKey: "color_17").hex
        let b = EpicRef(key: "E-b", title: "", paletteKey: "color_25").hex
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Label

    func testLabelPrefersTheWrittenOutName() {
        XCTAssertEqual(pendenzen.label, "EVEN-3345 · Pendenzensystem")
        XCTAssertEqual(EpicRef(key: "EVEN-9", title: "").label, "EVEN-9")
    }

    // MARK: - Sub-task inheritance

    private func ticket(_ key: String, epic: EpicRef? = nil, parent: String? = nil) -> Ticket {
        Ticket(key: key, summary: key, epic: epic, parentKey: parent)
    }

    func testSubTaskInheritsItsStorysEpic() {
        let result = EpicResolution.inheritFromParents([
            ticket("EVEN-3536", epic: pendenzen),
            ticket("EVEN-3627", parent: "EVEN-3536"),
            ticket("EVEN-3628", parent: "EVEN-3536"),
        ])
        XCTAssertEqual(result.map { $0.epic?.key }, ["EVEN-3345", "EVEN-3345", "EVEN-3345"])
    }

    func testSubTaskWhoseStoryIsNotOnTheBoardKeepsNoEpic() {
        let result = EpicResolution.inheritFromParents([
            ticket("EVEN-3536", epic: pendenzen),
            ticket("EVEN-9999", parent: "EVEN-1234"),   // story sits in another sprint
        ])
        XCTAssertNil(result[1].epic)
    }

    func testAnOwnEpicIsNeverOverwrittenByTheParents() {
        let other = EpicRef(key: "EVEN-1", title: "Andere", colorName: "green")
        let result = EpicResolution.inheritFromParents([
            ticket("EVEN-3536", epic: pendenzen),
            ticket("EVEN-3627", epic: other, parent: "EVEN-3536"),
        ])
        XCTAssertEqual(result[1].epic?.key, "EVEN-1")
    }

    func testBoardWithoutAnyEpicIsLeftAlone() {
        let tickets = [ticket("EVEN-1"), ticket("EVEN-2", parent: "EVEN-1")]
        XCTAssertEqual(EpicResolution.inheritFromParents(tickets), tickets)
    }
}
