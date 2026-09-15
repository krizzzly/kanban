import XCTest
@testable import KanbanCore

final class ADFToMarkdownTests: XCTestCase {
    private func adf(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private func markdown(_ json: String) throws -> String {
        ADFToMarkdown.convert(try adf(json)).markdown
    }

    private func doc(_ content: String) -> String {
        #"{"type":"doc","version":1,"content":[\#(content)]}"#
    }

    // MARK: - Golden test gegen das JS-Original

    /// Ein Dokument mit allem, was in unseren Tickets vorkommt. Der Erwartungswert ist **die Ausgabe
    /// von Hermes' `lib/adf-to-markdown.js`** für dieselbe Eingabe (beim Portieren zeichenweise
    /// verglichen) — damit ist das hier kein „was ich mir gedacht habe", sondern Parität.
    func testMatchesTheJavaScriptOriginal() throws {
        let source = doc("""
        {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Ausgangslage"}]},
        {"type":"paragraph","content":[
          {"type":"text","text":"Normal, "},
          {"type":"text","text":"fett","marks":[{"type":"strong"}]},
          {"type":"text","text":", "},
          {"type":"text","text":"kursiv","marks":[{"type":"em"}]},
          {"type":"text","text":", "},
          {"type":"text","text":"code","marks":[{"type":"code"}]},
          {"type":"text","text":" und ein "},
          {"type":"text","text":"Link","marks":[{"type":"link","attrs":{"href":"https://x.test/a"}}]},
          {"type":"hardBreak"},
          {"type":"text","text":"zweite Zeile"},
          {"type":"mention","attrs":{"id":"acc-1","text":"@Christian Hiller"}}]},
        {"type":"bulletList","content":[
          {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"erster"}]}]},
          {"type":"listItem","content":[
            {"type":"paragraph","content":[{"type":"text","text":"zweiter"}]},
            {"type":"orderedList","content":[
              {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"verschachtelt a"}]}]},
              {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"verschachtelt b"}]}]}]}]}]},
        {"type":"codeBlock","attrs":{"language":"php"},"content":[{"type":"text","text":"$a = 1;\\nreturn $a;"}]},
        {"type":"table","content":[
          {"type":"tableRow","content":[
            {"type":"tableHeader","content":[{"type":"paragraph","content":[{"type":"text","text":"Spalte A"}]}]},
            {"type":"tableHeader","content":[{"type":"paragraph","content":[{"type":"text","text":"Spalte B"}]}]}]},
          {"type":"tableRow","content":[
            {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"Wert | mit Pipe"}]}]},
            {"type":"tableCell","content":[{"type":"bulletList","content":[
              {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Punkt 1"}]}]},
              {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Punkt 2"}]}]}]}]}]}]},
        {"type":"paragraph","content":[{"type":"inlineCard","attrs":{"url":"https://x.atlassian.net/browse/EVEN-123"}}]}
        """)

        let expected = """
        ## Ausgangslage

        Normal, **fett**, *kursiv*, `code` und ein [Link](https://x.test/a)
        zweite Zeile@Christian Hiller

        - erster
        - zweiter
          1. verschachtelt a
          2. verschachtelt b
        ```php
        $a = 1;
        return $a;
        ```


        | Spalte A | Spalte B |
        | --- | --- |
        | Wert \\| mit Pipe | - Punkt 1 <br> - Punkt 2 |

        [EVEN-123](https://x.atlassian.net/browse/EVEN-123)
        """

        XCTAssertEqual(try markdown(source), expected)
    }

    // MARK: - Einzelheiten

    /// Der Grund für den Port: `ADFFlattener` hat Struktur weggeworfen. Überschrift, Liste und Link
    /// müssen als Markdown ankommen, nicht als aneinandergehängter Text.
    func testKeepsStructureTheOldFlattenerLost() throws {
        let result = try markdown(doc("""
        {"type":"heading","attrs":{"level":3},"content":[{"type":"text","text":"Titel"}]},
        {"type":"bulletList","content":[
          {"type":"listItem","content":[{"type":"paragraph","content":[
            {"type":"text","text":"Punkt","marks":[{"type":"strong"}]}]}]}]}
        """))
        XCTAssertEqual(result, "### Titel\n\n- **Punkt**")
    }

    /// Bilder werden gesammelt und im Text durch einen Platzhalter ersetzt — die Datei selbst muss
    /// separat geholt werden, und nur der Aufrufer weiss, wohin damit.
    func testCollectsImagesAndLeavesAPlaceholder() throws {
        let result = ADFToMarkdown.convert(try adf(doc("""
        {"type":"mediaSingle","content":[
          {"type":"media","attrs":{"id":"m-1","alt":"bild.png","collection":"c"}}]},
        {"type":"mediaSingle","content":[
          {"type":"media","attrs":{"id":"m-2","alt":"zweites.png"}}]}
        """)))

        XCTAssertEqual(result.images.map(\.filename), ["1-bild.png", "2-zweites.png"])
        XCTAssertEqual(result.images.map(\.index), [0, 1])
        XCTAssertTrue(result.markdown.contains("![1-bild.png]({{IMG_0}})"))
        XCTAssertTrue(result.markdown.contains("![2-zweites.png]({{IMG_1}})"))
    }

    /// Die Nummerierung läuft über mehrere Dokumente eines Tickets weiter (Beschreibung, dann jedes
    /// Custom Field) — sonst überschrieben sich zwei Bilder gleichen Namens.
    func testImageCounterContinuesAcrossDocuments() throws {
        let source = doc(#"{"type":"media","attrs":{"id":"m","alt":"a.png"}}"#)
        let result = ADFToMarkdown.convert(try adf(source), imageCounter: 4)
        XCTAssertEqual(result.images.first?.filename, "5-a.png")
        XCTAssertEqual(result.images.first?.index, 4)
        XCTAssertTrue(result.markdown.contains("{{IMG_4}}"))
    }

    /// Smart Links tragen ihr Ziel als Label: Ticketnummer bei Jira, Seitentitel bei Confluence.
    func testCardLabels() {
        XCTAssertEqual(ADFToMarkdown.cardLabel("https://x.atlassian.net/browse/EVEN-123"), "EVEN-123")
        XCTAssertEqual(ADFToMarkdown.cardLabel("https://conf.test/pages/456/Meine+Seite"), "Meine Seite")
        XCTAssertEqual(ADFToMarkdown.cardLabel("https://irgendwo.test/x"), "https://irgendwo.test/x")
        XCTAssertEqual(ADFToMarkdown.cardLabel(""), "")
    }

    func testEmptyDocument() throws {
        XCTAssertEqual(ADFToMarkdown.convert(try adf(#"{"type":"doc"}"#)).markdown, "")
        XCTAssertEqual(try markdown(doc("")), "")
    }

    // MARK: - Tabellenzellen: Block-Inhalt in einem Inline-Kontext

    /// Eine Zelle wird mit ` <br> ` zusammengefügt. Alles, was Block-Syntax braucht (Einrückung,
    /// Rauten), verliert dort seine Bedeutung. Dieselben Fälle stehen in Hermes'
    /// `tests/lib/adf-to-markdown.test.js` — die beiden Konverter bleiben paarweise geprüft.
    private func cell(_ content: String) -> String {
        let json = doc("""
        {"type":"table","content":[{"type":"tableRow","content":[
          {"type":"tableCell","content":[\(content)]}]}]}
        """)
        return (try? markdown(json)) ?? "FEHLER"
    }

    private func item(_ text: String, _ children: String = "") -> String {
        let extra = children.isEmpty ? "" : ",\(children)"
        return #"{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"\#(text)"}]}\#(extra)]}"#
    }

    func testFlatListStaysReadableMarkdown() {
        let markdown = cell("""
        {"type":"bulletList","content":[\(item("eins")),\(item("zwei"))]}
        """)
        XCTAssertTrue(markdown.contains("| - eins <br> - zwei |"), markdown)
        XCTAssertFalse(markdown.contains("<ul>"), markdown)
    }

    func testOrderedListsKeepTheirNumbers() {
        let markdown = cell("""
        {"type":"orderedList","content":[\(item("erstens")),\(item("zweitens"))]}
        """)
        XCTAssertTrue(markdown.contains("| 1. erstens <br> 2. zweitens |"), markdown)
    }

    /// Sobald verschachtelt wird, trägt nur HTML die Ebene — und die Kinder hängen an ihrem
    /// eigenen Elternteil. Vorher standen sie davor, wodurch in einer Anforderungstabelle die
    /// Akzeptanzkriterien zweier Zeilen die Besitzer tauschten.
    func testNestedListBecomesInlineHTML() {
        let markdown = cell("""
        {"type":"bulletList","content":[
          \(item("Speichern", #"{"type":"bulletList","content":[\#(item("ohne Pflichtfelder")),\#(item("Entwurf bleibt"))]}"#)),
          \(item("Einreichen", #"{"type":"bulletList","content":[\#(item("Fehlerliste oben"))]}"#))]}
        """)
        XCTAssertTrue(markdown.contains(
            "<ul><li>Speichern<ul><li>ohne Pflichtfelder</li><li>Entwurf bleibt</li></ul></li>"
            + "<li>Einreichen<ul><li>Fehlerliste oben</li></ul></li></ul>"), markdown)
    }

    func testThreeLevelsStayThreeLevels() {
        let markdown = cell("""
        {"type":"bulletList","content":[\(item("eins",
          #"{"type":"bulletList","content":[\#(item("zwei", #"{"type":"bulletList","content":[\#(item("drei"))]}"#))]}"#))]}
        """)
        XCTAssertTrue(markdown.contains("<ul><li>eins<ul><li>zwei<ul><li>drei</li></ul></li></ul></li></ul>"),
                      markdown)
    }

    /// Gemischte Verschachtelung behält ihre Listenart.
    func testMixedNestingKeepsItsKind() {
        let markdown = cell("""
        {"type":"orderedList","content":[\(item("Schritt",
          #"{"type":"bulletList","content":[\#(item("Hinweis"))]}"#))]}
        """)
        XCTAssertTrue(markdown.contains("<ol><li>Schritt<ul><li>Hinweis</li></ul></li></ol>"), markdown)
    }

    /// `#### x` ist in einer Zelle keine Überschrift, sondern wörtlicher Text.
    func testHeadingInACellBecomesBold() {
        let markdown = cell(#"{"type":"heading","attrs":{"level":4},"content":[{"type":"text","text":"I-1"}]}"#)
        XCTAssertTrue(markdown.contains("| **I-1** |"), markdown)
        XCTAssertFalse(markdown.contains("####"), markdown)
    }

    /// Ohne den `status`-Fall sah die Zelle leer aus, obwohl auf der Seite „In Arbeit" steht.
    func testStatusMacroKeepsItsText() {
        let markdown = cell(#"{"type":"paragraph","content":[{"type":"status","attrs":{"text":"In Arbeit","color":"yellow"}}]}"#)
        XCTAssertTrue(markdown.contains("| In Arbeit |"), markdown)
    }
}
