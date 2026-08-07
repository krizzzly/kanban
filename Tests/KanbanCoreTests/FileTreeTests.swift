import XCTest
@testable import KanbanCore

final class FileTreeTests: XCTestCase {
    private func file(_ path: String) -> GitChangedFile {
        GitChangedFile(path: path, index: " ", worktree: "M")
    }

    func testFilesAreGroupedByFolder() {
        let tree = FileTreeBuilder.build([
            file("assets/ui-components/layout/AppMenu.jsx"),
            file("assets/ui-components/layout/MobileMenu.jsx"),
            file("config/services.yaml"),
        ])
        XCTAssertEqual(tree.map(\.name), ["assets/ui-components/layout", "config"])
        XCTAssertEqual(tree[0].children?.map(\.name), ["AppMenu.jsx", "MobileMenu.jsx"])
        XCTAssertEqual(tree[1].children?.map(\.name), ["services.yaml"])
    }

    func testSingleChildFolderChainsCollapse() {
        // src/Controller/Api/Pendenz/Pendenz/Foo.php would otherwise cost five nested rows.
        let tree = FileTreeBuilder.build([file("src/Controller/Api/Pendenz/ListPendenzenController.php")])
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].name, "src/Controller/Api/Pendenz")
        XCTAssertEqual(tree[0].children?.map(\.name), ["ListPendenzenController.php"])
    }

    func testCollapsingStopsWhereTheTreeBranches() {
        let tree = FileTreeBuilder.build([
            file("src/Model/Pendenz/PendenzList.php"),
            file("src/Entity/Pendenz.php"),
        ])
        // src holds two different folders → src stays its own level.
        XCTAssertEqual(tree.map(\.name), ["src"])
        XCTAssertEqual(tree[0].children?.map(\.name).sorted(), ["Entity", "Model/Pendenz"])
    }

    func testFoldersComeBeforeFilesAtTheSameLevel() {
        let tree = FileTreeBuilder.build([file("zz.txt"), file("aa/deep.txt")])
        XCTAssertEqual(tree.map(\.name), ["aa", "zz.txt"])
    }

    func testRootLevelFilesStayAtTheRoot() {
        let tree = FileTreeBuilder.build([file("README.md")])
        XCTAssertEqual(tree.count, 1)
        XCTAssertFalse(tree[0].isFolder)
        XCTAssertEqual(tree[0].file?.path, "README.md")
    }

    func testFileCountAggregatesUpTheTree() {
        let tree = FileTreeBuilder.build([
            file("a/b/one.php"), file("a/b/two.php"), file("a/c/three.php"),
        ])
        XCTAssertEqual(tree.first?.fileCount, 3)
    }

    func testFolderIDsCoverEveryFolder() {
        let tree = FileTreeBuilder.build([file("a/b/one.php"), file("a/c/two.php")])
        let ids = FileTreeBuilder.folderIDs(tree)
        XCTAssertTrue(ids.contains("a"))
        XCTAssertTrue(ids.contains("a/b"))
        XCTAssertTrue(ids.contains("a/c"))
        XCTAssertFalse(ids.contains("a/b/one.php"), "Dateien sind keine Ordner")
    }

    func testEmptyInputYieldsEmptyTree() {
        XCTAssertTrue(FileTreeBuilder.build([]).isEmpty)
    }
}
