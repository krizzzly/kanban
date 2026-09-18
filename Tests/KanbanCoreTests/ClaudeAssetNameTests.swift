import XCTest
@testable import KanbanCore

/// Der Name ist Ordnername, Symlink-Ziel **und** Aufruf (`/name` bzw. `$name`) — bei einem Asset
/// wie bei einem Set. Was dort nicht funktioniert, darf gar nicht erst als Set eingelesen werden.
final class ClaudeAssetNameTests: XCTestCase {
    func testNamenWerdenNormalisiert() {
        XCTAssertEqual(ClaudeAssetName.normalisiert("  Mein Neuer Skill  "), "mein-neuer-skill")
        XCTAssertEqual(ClaudeAssetName.normalisiert("db_access"), "db-access")
        XCTAssertEqual(ClaudeAssetName.normalisiert("a--b"), "a-b")
        XCTAssertEqual(ClaudeAssetName.normalisiert("-rand-"), "rand")
    }

    func testUnbrauchbareNamenWerdenAbgelehnt() {
        XCTAssertThrowsError(try ClaudeAssetName.pruefen(""))
        XCTAssertThrowsError(try ClaudeAssetName.pruefen("1-start-mit-ziffer"))
        XCTAssertThrowsError(try ClaudeAssetName.pruefen("mit/slash"))
        XCTAssertThrowsError(try ClaudeAssetName.pruefen("Gross"))
        XCTAssertThrowsError(try ClaudeAssetName.pruefen("umlaut-ä"))
        XCTAssertNoThrow(try ClaudeAssetName.pruefen("create-task"))
        XCTAssertNoThrow(try ClaudeAssetName.pruefen("a1"))
    }

    func testIstGueltigIstDieselbePruefungOhneWurf() {
        XCTAssertTrue(ClaudeAssetName.istGueltig("iwf"))
        XCTAssertTrue(ClaudeAssetName.istGueltig("skills-backup-2026-08-20"))
        XCTAssertFalse(ClaudeAssetName.istGueltig("Christian_RULES_SKILLS_v2.zip"))
        XCTAssertFalse(ClaudeAssetName.istGueltig(".versions"))
    }
}
