import XCTest
@testable import KanbanCore

/// Links **in** den Markdown-Dateien der Knowledgebase: sie verweisen aufeinander
/// (`../Common/HistoryEntry.md`), auf Abschnitte (`architektur.md#zwei-cqrs-generationen`) und
/// gelegentlich aus der KB heraus (`../../../../core/config/…`). Diese drei Fälle auseinanderzuhalten
/// ist der Unterschied zwischen „ich lese weiter" und „der Finder geht auf".
final class KBLinkTests: XCTestCase {
    private let root = "/kb"
    private let current = "/kb/ueberblick/architektur.md"

    private func resolve(_ url: String) -> KBLinkTarget {
        KBLink.resolve(URL(string: url)!, currentFile: current, root: root)
    }

    func testLinkToAnotherFileInTheKnowledgebase() {
        XCTAssertEqual(resolve("file:///kb/ueberblick/berechtigungen.md"),
                       .file(path: "/kb/ueberblick/berechtigungen.md", fragment: nil))
    }

    func testRelativeLinkThatWalkedUpResolvesInsideTheKnowledgebase() {
        // So kommt der Link an, nachdem WKWebView ihn gegen die Datei aufgelöst hat.
        XCTAssertEqual(resolve("file:///kb/ueberblick/../src/Model/Dossier/Dossier.md"),
                       .file(path: "/kb/src/Model/Dossier/Dossier.md", fragment: nil))
    }

    func testFileLinkKeepsItsFragment() {
        XCTAssertEqual(resolve("file:///kb/src/Service/README.md#die-command-schicht-ist-die-lua-api"),
                       .file(path: "/kb/src/Service/README.md",
                             fragment: "die-command-schicht-ist-die-lua-api"))
    }

    func testFragmentInTheSameDocumentStaysInTheDocument() {
        XCTAssertEqual(resolve("file:///kb/ueberblick/architektur.md#zwei-cqrs-generationen"),
                       .fragment("zwei-cqrs-generationen"))
    }

    func testSameDocumentWithoutFragmentIsJustThatFile() {
        XCTAssertEqual(resolve("file:///kb/ueberblick/architektur.md"),
                       .file(path: "/kb/ueberblick/architektur.md", fragment: nil))
    }

    func testPercentEncodedFragmentIsDecoded() {
        XCTAssertEqual(resolve("file:///kb/ueberblick/architektur.md#pr%C3%BCfung"),
                       .fragment("prüfung"))
    }

    func testLinkIntoTheRepoIsALocalFileOutsideTheKnowledgebase() {
        // Die KB verlinkt bis ins Projekt-Repo. Gezeigt wird sie trotzdem — als Quelltext.
        XCTAssertEqual(resolve("file:///code/core/config/packages/coala_permissions.yaml"),
                       .outsideFile(path: "/code/core/config/packages/coala_permissions.yaml"))
    }

    func testANeighbourFolderWithTheSamePrefixIsNotInsideTheKnowledgebase() {
        // "/kb-alt" beginnt mit "/kb", liegt aber daneben.
        XCTAssertEqual(resolve("file:///kb-alt/README.md"), .outsideFile(path: "/kb-alt/README.md"))
    }

    func testWebAndMailLinksGoOutside() {
        XCTAssertEqual(resolve("https://iwf.ch"), .external(URL(string: "https://iwf.ch")!))
        XCTAssertEqual(resolve("mailto:a@b.ch"), .external(URL(string: "mailto:a@b.ch")!))
    }
}

/// Sprungmarken: cmark vergibt keine, die Knowledgebase verlinkt sie aber im GitHub-Format.
final class HeadingAnchorsTests: XCTestCase {
    func testSlugFollowsGitHubsRules() {
        XCTAssertEqual(HeadingAnchors.slug("Zwei CQRS-Generationen"), "zwei-cqrs-generationen")
        // Interpunktion fällt weg, **bevor** Leerzeichen zu Bindestrichen werden — daher zwei.
        XCTAssertEqual(HeadingAnchors.slug("RealTemplates — Tests gegen echte Vorlagen"),
                       "realtemplates--tests-gegen-echte-vorlagen")
        XCTAssertEqual(HeadingAnchors.slug("1. Configurable — Daten als JSON"),
                       "1-configurable--daten-als-json")
        XCTAssertEqual(HeadingAnchors.slug("ConfigurableDataAccessTrait"), "configurabledataaccesstrait")
        // Umlaute bleiben, wie bei GitHub.
        XCTAssertEqual(HeadingAnchors.slug("Prüfung"), "prüfung")
    }

    func testSlugIgnoresInlineMarkupAndEntities() {
        XCTAssertEqual(HeadingAnchors.slug("Die <code>Command</code>-Schicht"), "die-command-schicht")
        XCTAssertEqual(HeadingAnchors.slug("Konfiguration &amp; Betrieb"), "konfiguration--betrieb")
    }

    func testHeadingsGetIDs() {
        let html = HeadingAnchors.inject(into: "<h1>Architektur</h1>\n<p>x</p>\n<h2>Zwei Generationen</h2>")
        XCTAssertTrue(html.contains("<h1 id=\"architektur\">Architektur</h1>"))
        XCTAssertTrue(html.contains("<h2 id=\"zwei-generationen\">Zwei Generationen</h2>"))
        XCTAssertTrue(html.contains("<p>x</p>"), "Der Rest des Dokuments bleibt unangetastet")
    }

    func testRepeatedHeadingsGetDistinctIDs() {
        let html = HeadingAnchors.inject(into: "<h2>Ablauf</h2><h2>Ablauf</h2><h2>Ablauf</h2>")
        XCTAssertTrue(html.contains("id=\"ablauf\""))
        XCTAssertTrue(html.contains("id=\"ablauf-1\""))
        XCTAssertTrue(html.contains("id=\"ablauf-2\""))
    }

    func testExistingIDsAreLeftAlone() {
        // Rohes HTML in einer Datei bringt seine eigene ID mit — die ist die Absicht des Autors.
        let html = HeadingAnchors.inject(into: "<h2 id=\"eigene\">Titel</h2>")
        XCTAssertEqual(html, "<h2 id=\"eigene\">Titel</h2>")
    }

    func testHeadingWithoutSluggableTextIsSkipped() {
        let html = HeadingAnchors.inject(into: "<h2>— —</h2>")
        XCTAssertEqual(html, "<h2>— —</h2>")
    }

    func testMultilineHeadingContentIsHandled() {
        // cmark bricht lange Überschriften um; ohne `dotMatchesLineSeparators` fiele die durch.
        let html = HeadingAnchors.inject(into: "<h3>Erste Zeile\nzweite Zeile</h3>")
        XCTAssertTrue(html.contains("id=\"erste-zeile-zweite-zeile\""))
    }
}
