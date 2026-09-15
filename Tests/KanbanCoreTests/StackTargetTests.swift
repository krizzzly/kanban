import XCTest
@testable import KanbanCore

/// Der einzige Unterschied zwischen den beiden Stacks — und die Regel, welche Aktionen ein
/// Haupt-Repo **nicht** anbieten darf.
final class StackTargetTests: XCTestCase {
    /// Start/Neustart sind der einzige Ort, an dem sich die Befehle unterscheiden: ein Worktree wird
    /// über `iwf worktree …` bedient (iwf findet ihn über seine Nummer), das Haupt-Repo über
    /// `iwf stack …` im eigenen Verzeichnis. Beide Unterbefehle stehen in `iwf stack --help`.
    func testStartAndRestartDependOnTheTarget() {
        XCTAssertEqual(StackPhase.Repair.start.commands(for: .worktree), [["worktree", "start"]])
        XCTAssertEqual(StackPhase.Repair.start.commands(for: .maintree), [["stack", "start"]])
        XCTAssertEqual(StackPhase.Repair.restart.commands(for: .worktree), [["worktree", "restart"]])
        XCTAssertEqual(StackPhase.Repair.restart.commands(for: .maintree), [["stack", "restart"]])
    }

    /// Alles andere läuft ohnehin relativ zum Arbeitsverzeichnis und ist deshalb wortgleich.
    func testEveryOtherRepairIsIdentical() {
        for repair in [StackPhase.Repair.build, .cert, .composer, .symfonyAssets, .frontend,
                       .frontendSub("apps/web"), .viteStart, .viteStop] {
            XCTAssertEqual(repair.commands(for: .worktree), repair.commands(for: .maintree),
                           "\(repair) darf sich nicht je Ziel unterscheiden")
        }
    }

    /// Destroy und DB-Seed hängen an dieser einen Eigenschaft: `iwf stack destroy` nähme aus dem
    /// Haupt-Repo jedes `local/<projekt>-*`-Image mit, ein Seed die Entwicklungsdatenbank.
    func testOnlyTheWorktreeAllowsDestructiveActions() {
        XCTAssertTrue(StackTarget.worktree.allowsDestructiveActions)
        XCTAssertFalse(StackTarget.maintree.allowsDestructiveActions)
    }

    /// Der Stack-Name ist in beiden Fällen der Ordnername — deshalb reicht derselbe Scanner mit
    /// einem anderen Pfad.
    func testStackNameIsTheFolderNameForBoth() {
        XCTAssertEqual(("/Users/x/code/even" as NSString).lastPathComponent, "even")
        XCTAssertEqual(("/Users/x/code/even-worktree/even-3963" as NSString).lastPathComponent,
                       "even-3963")
    }
}
