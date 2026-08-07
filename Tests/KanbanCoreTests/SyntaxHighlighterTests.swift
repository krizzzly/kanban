import XCTest
@testable import KanbanCore

final class SyntaxHighlighterTests: XCTestCase {
    private func kinds(_ text: String, _ language: CodeLanguage) -> [SyntaxToken.Kind] {
        SyntaxHighlighter.tokens(in: text, language: language).map(\.kind)
    }

    private func text(_ source: String, _ language: CodeLanguage, kind: SyntaxToken.Kind) -> [String] {
        let ns = source as NSString
        return SyntaxHighlighter.tokens(in: source, language: language)
            .filter { $0.kind == kind }
            .map { ns.substring(with: $0.range) }
    }

    // MARK: - Language detection

    func testDetectionCoversTheRequestedLanguages() {
        XCTAssertEqual(CodeLanguage.detect(path: "src/Foo.php"), .php)
        XCTAssertEqual(CodeLanguage.detect(path: "assets/Pendenz.jsx"), .javascript)
        XCTAssertEqual(CodeLanguage.detect(path: "assets/app.js"), .javascript)
        XCTAssertEqual(CodeLanguage.detect(path: "assets/styles.css"), .css)
        XCTAssertEqual(CodeLanguage.detect(path: "templates/page.html"), .html)
        XCTAssertEqual(CodeLanguage.detect(path: "config/services.yaml"), .yaml)
        XCTAssertEqual(CodeLanguage.detect(path: "README"), .plain)
    }

    func testTwigWinsOverHtmlForDoubleExtension() {
        // Symfony templates are `*.html.twig` — a naive pathExtension check would say "twig" anyway,
        // but `base.twig` and `mail.html.twig` must both land on Twig.
        XCTAssertEqual(CodeLanguage.detect(path: "templates/mail.html.twig"), .twig)
        XCTAssertEqual(CodeLanguage.detect(path: "templates/base.twig"), .twig)
    }

    // MARK: - Tokenising

    func testPhpVariablesStringsAndKeywords() {
        let source = #"public function foo(): void { $bar = 'text'; // Kommentar"#
        XCTAssertEqual(text(source, .php, kind: .variable), ["$bar"])
        XCTAssertEqual(text(source, .php, kind: .string), ["'text'"])
        XCTAssertTrue(text(source, .php, kind: .keyword).contains("function"))
        XCTAssertEqual(text(source, .php, kind: .comment), ["// Kommentar"])
    }

    func testPhpAttributesAreNotTreatedAsComments() {
        // PHP 8 attributes start with `#[` — the `#` comment rule would swallow the whole line and
        // grey out every Doctrine annotation.
        let source = #"#[ORM\Column(type: Types::DATE_IMMUTABLE, nullable: true)]"#
        XCTAssertEqual(text(source, .php, kind: .comment), [], "Annotation ist kein Kommentar")
        XCTAssertEqual(text(source, .php, kind: .attribute), [#"#[ORM\Column"#])
        // Die Argumente werden weiterhin normal gefärbt.
        XCTAssertTrue(text(source, .php, kind: .keyword).contains("true"))
    }

    func testRealShellStyleCommentStillWorks() {
        XCTAssertEqual(text("# echter Kommentar", .php, kind: .comment), ["# echter Kommentar"])
    }

    func testKeywordInsideAStringIsNotColoured() {
        // Strings claim their text first — otherwise "function" inside a message would light up.
        let source = #"$msg = "please call function now";"#
        XCTAssertEqual(text(source, .php, kind: .keyword), [])
        XCTAssertEqual(text(source, .php, kind: .string), [#""please call function now""#])
    }

    func testCommentWinsOverEverythingInIt() {
        let source = "// const x = 'y'"
        XCTAssertEqual(kinds(source, .javascript), [.comment])
    }

    func testJsxTagsAndAttributes() {
        let source = #"<PendenzModal width={MODAL_SIZE.LARGE} onClose={close} />"#
        XCTAssertTrue(text(source, .javascript, kind: .tag).contains("<PendenzModal"))
        XCTAssertTrue(text(source, .javascript, kind: .attribute).contains("width"))
    }

    func testTwigDelimitersAndKeywords() {
        let source = "{% if user.active %}{{ user.name }}{# Notiz #}"
        XCTAssertEqual(text(source, .twig, kind: .comment), ["{# Notiz #}"])
        XCTAssertTrue(text(source, .twig, kind: .keyword).contains("if"))
    }

    func testCssPropertiesSelectorsAndColours() {
        let source = ".pendenz-badge { color: #ff5f56; margin: 12px; }"
        XCTAssertTrue(text(source, .css, kind: .variable).contains(".pendenz-badge"))
        XCTAssertTrue(text(source, .css, kind: .number).contains("#ff5f56"))
        XCTAssertTrue(text(source, .css, kind: .number).contains("12px"))
    }

    func testHtmlCommentsAndTags() {
        let source = "<!-- weg --><div class=\"box\">Text</div>"
        XCTAssertEqual(text(source, .html, kind: .comment), ["<!-- weg -->"])
        XCTAssertTrue(text(source, .html, kind: .tag).contains("<div"))
    }

    func testPlainTextIsNotTokenised() {
        XCTAssertTrue(SyntaxHighlighter.tokens(in: "irgendein Text", language: .plain).isEmpty)
    }

    func testTokensNeverOverlap() {
        let source = #"<?php $x = "a/*b*/c"; /* echt */ $y = 12;"#
        let tokens = SyntaxHighlighter.tokens(in: source, language: .php)
        for (a, b) in zip(tokens, tokens.dropFirst()) {
            XCTAssertLessThanOrEqual(NSMaxRange(a.range), b.range.location,
                                     "Bereiche müssen disjunkt und sortiert sein")
        }
    }

    func testTokenRangesStayInsideTheText() {
        let source = "$ä = 'grüezi'; // Umlaute\n"
        let ns = source as NSString
        for token in SyntaxHighlighter.tokens(in: source, language: .php) {
            XCTAssertLessThanOrEqual(NSMaxRange(token.range), ns.length)
        }
    }
}
