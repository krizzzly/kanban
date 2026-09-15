import XCTest
@testable import KanbanCore

/// Der Schreibweg wird gegen den gelesenen Weg geprüft: was `MarkdownToADF` erzeugt, muss
/// `ADFToMarkdown` wieder als denselben Text lesen. Der Rückweg ist zeichengleich gegen Hermes'
/// JS-Original verifiziert, taugt also als Referenz.
final class MarkdownToADFTests: XCTestCase {
    private func roundTrip(_ markdown: String) -> String {
        ADFToMarkdown.convert(MarkdownToADF.convert(markdown)).markdown
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func adf(_ markdown: String) -> [String: JSONValue] {
        MarkdownToADF.convert(markdown).objectValue ?? [:]
    }

    func testEmptyTextIsAnEmptyDoc() {
        let doc = adf("")
        XCTAssertEqual(doc["type"], .string("doc"))
        XCTAssertEqual(doc["version"], .int(1))
        XCTAssertEqual(doc["content"], .array([]))
    }

    func testParagraphRoundTrip() {
        XCTAssertEqual(roundTrip("Ein einfacher Absatz."), "Ein einfacher Absatz.")
    }

    func testTwoParagraphsStayTwo() {
        XCTAssertEqual(roundTrip("Erster Absatz.\n\nZweiter Absatz."),
                       "Erster Absatz.\n\nZweiter Absatz.")
    }

    func testHeadingsRoundTrip() {
        XCTAssertEqual(roundTrip("## Lösung\n\nText darunter."), "## Lösung\n\nText darunter.")
        XCTAssertEqual(roundTrip("# Eins\n\n### Drei"), "# Eins\n\n### Drei")
    }

    func testInlineMarksRoundTrip() {
        XCTAssertEqual(roundTrip("Das ist **fett**, das *kursiv*, das `code`."),
                       "Das ist **fett**, das *kursiv*, das `code`.")
        XCTAssertEqual(roundTrip("~~weg~~ damit"), "~~weg~~ damit")
    }

    func testLinkRoundTrip() {
        XCTAssertEqual(roundTrip("Siehe [den MR](https://git.example.com/mr/1)."),
                       "Siehe [den MR](https://git.example.com/mr/1).")
    }

    func testBulletListRoundTrip() {
        let markdown = "- erster Punkt\n- zweiter Punkt\n- dritter Punkt"
        XCTAssertEqual(roundTrip(markdown), markdown)
    }

    func testOrderedListRoundTrip() {
        XCTAssertEqual(roundTrip("1. eins\n2. zwei"), "1. eins\n2. zwei")
    }

    func testNestedListKeepsItsLevels() {
        let markdown = "- oben\n  - drunter\n  - auch drunter\n- wieder oben"
        XCTAssertEqual(roundTrip(markdown), markdown)
    }

    func testCodeBlockKeepsLanguageAndBody() {
        let markdown = "```swift\nlet x = 1\nprint(x)\n```"
        XCTAssertEqual(roundTrip(markdown), markdown)
        // Und die Sprache landet auch wirklich in den attrs, nicht nur im Text.
        let content = adf(markdown)["content"]?.arrayValue?.first?.objectValue
        XCTAssertEqual(content?["type"], .string("codeBlock"))
        XCTAssertEqual(content?["attrs"]?.objectValue?["language"], .string("swift"))
    }

    /// Zitat bleibt Zitat. Der Rückweg hängt an einen Blockquote noch leere Zitatzeilen an — das ist
    /// seine Formatierung, nicht unsere: geprüft wird der Inhalt, nicht das Nachspiel.
    func testBlockquoteRoundTrip() {
        let result = roundTrip("> zitiert\n> weiter")
        XCTAssertTrue(result.hasPrefix("> zitiert"), result)
        XCTAssertTrue(result.contains("> weiter"), result)
        let content = adf("> zitiert\n> weiter")["content"]?.arrayValue ?? []
        XCTAssertEqual(content.first?.objectValue?["type"], .string("blockquote"))
    }

    func testRuleBecomesRule() {
        let content = adf("oben\n\n---\n\nunten")["content"]?.arrayValue ?? []
        XCTAssertEqual(content.count, 3)
        XCTAssertEqual(content[1].objectValue?["type"], .string("rule"))
    }

    /// Ein realistischer Lösungstext, wie solve-task ihn schreibt.
    func testRealisticSolutionSection() {
        let markdown = """
        Die Ursache lag in **ConfigStore**: der Schreibpfad hat `basePath` nicht expandiert.

        Umgesetzt:

        - `expand()` vor jedem Vergleich
        - Test `testTildeIsExpanded`
        - Doku in [CLAUDE.md](https://git.example.com/kanban/CLAUDE.md)

        ```bash
        swift test --filter ConfigStoreTests
        ```
        """
        let result = roundTrip(markdown)
        XCTAssertTrue(result.contains("**ConfigStore**"))
        XCTAssertTrue(result.contains("- `expand()` vor jedem Vergleich"))
        XCTAssertTrue(result.contains("[CLAUDE.md](https://git.example.com/kanban/CLAUDE.md)"))
        XCTAssertTrue(result.contains("```bash"))
        XCTAssertTrue(result.contains("swift test --filter ConfigStoreTests"))
    }

    /// Weiche Umbrüche innerhalb eines Absatzes bleiben Umbrüche (hardBreak), nicht neue Absätze.
    func testSoftLineBreakBecomesHardBreak() {
        let content = adf("Zeile eins\nZeile zwei")["content"]?.arrayValue ?? []
        XCTAssertEqual(content.count, 1)
        let inline = content[0].objectValue?["content"]?.arrayValue ?? []
        XCTAssertEqual(inline.count, 3)
        XCTAssertEqual(inline[1].objectValue?["type"], .string("hardBreak"))
    }

    /// Listenzeichen `*` darf nicht als Kursiv-Marker gelesen werden.
    func testAsteriskBulletIsNotItalic() {
        let content = adf("* ein Punkt")["content"]?.arrayValue ?? []
        XCTAssertEqual(content.first?.objectValue?["type"], .string("bulletList"))
    }
}
