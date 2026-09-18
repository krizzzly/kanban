import XCTest
@testable import KanbanCore

/// Was die Kopier-Knöpfe in die Zwischenablage legen. Seit die Task-Files in Application Support
/// liegen, ist der Normalfall der **absolute** Pfad — die alte Fassung liess dort den Ordner weg und
/// kopierte den blossen Dateinamen, mit dem weder Claude noch der Finder etwas anfängt.
final class ClipboardPathTests: XCTestCase {

    func testInsideTheRepoItIsRelativeToIt() {
        let url = URL(fileURLWithPath: "/Users/x/code/hermes/.claude/tasks/EVEN-3530_foo.md")
        XCTAssertEqual(ClipboardPath.forCopying(url, repoDir: "/Users/x/code/hermes"),
                       ".claude/tasks/EVEN-3530_foo.md")
    }

    func testOutsideTheRepoItIsAbsolute() {
        let url = URL(fileURLWithPath: "/Users/x/Library/Application Support/Kanban/tasks/even/EVEN-3530/bild.png")
        XCTAssertEqual(ClipboardPath.forCopying(url, repoDir: "/Users/x/code/even"),
                       "/Users/x/Library/Application Support/Kanban/tasks/even/EVEN-3530/bild.png")
    }

    func testWithoutARepoItIsAbsolute() {
        let url = URL(fileURLWithPath: "/tmp/a/b.md")
        XCTAssertEqual(ClipboardPath.forCopying(url, repoDir: nil), "/tmp/a/b.md")
        XCTAssertEqual(ClipboardPath.forCopying(url, repoDir: ""), "/tmp/a/b.md")
    }

    /// Ein Nachbar-Repo mit gemeinsamem Präfix darf nicht als „drin" durchgehen: `even-support`
    /// fängt mit `even` an, liegt aber woanders.
    func testASiblingRepoIsNotInsideIt() {
        let url = URL(fileURLWithPath: "/Users/x/code/even-support/docs/tasks/a.md")
        XCTAssertEqual(ClipboardPath.forCopying(url, repoDir: "/Users/x/code/even"),
                       "/Users/x/code/even-support/docs/tasks/a.md")
    }

    /// Ein Schrägstrich am Ende des Repo-Pfads (so steht er in mancher Config) ändert nichts, und
    /// `..` im Pfad wird vorher aufgelöst — sonst stünde die Bastelform in der Zwischenablage.
    func testTrailingSlashAndUnstandardizedPaths() {
        let url = URL(fileURLWithPath: "/Users/x/code/even/docs/../docs/tasks/a.md")
        XCTAssertEqual(ClipboardPath.forCopying(url, repoDir: "/Users/x/code/even/"),
                       "docs/tasks/a.md")
    }
}
