import XCTest
@testable import KanbanCore

final class BranchStackTests: XCTestCase {
    /// The real EVEN shape: a four-level stack plus an independent branch, all under develop.
    func testStackChainAndSibling() {
        let tree = BranchStack.tree(base: "develop", commits: [
            "feature/EVEN-3514": ["a"],
            "feature/EVEN-3515": ["a", "b"],
            "feature/EVEN-3518": ["a", "b", "c"],
            "feature/EVEN-3517": ["a", "b", "c", "d"],
            "feature/EVEN-3194": ["x"],
        ])
        XCTAssertEqual(tree.name, "develop")
        XCTAssertEqual(tree.children.map(\.name),
                       ["feature/EVEN-3194", "feature/EVEN-3514"])

        let chain = tree.path(to: "feature/EVEN-3517")?.map(\.name)
        XCTAssertEqual(chain, ["develop", "feature/EVEN-3514", "feature/EVEN-3515",
                               "feature/EVEN-3518", "feature/EVEN-3517"])
    }

    /// Every level counts only its own commits beyond the parent.
    func testAheadIsPerLevel() {
        let tree = BranchStack.tree(base: "develop", commits: [
            "feature/A": ["a", "b", "c"],
            "feature/B": ["a", "b", "c", "d"],
        ])
        let a = tree.children[0], b = a.children[0]
        XCTAssertEqual(a.ahead, 3)
        XCTAssertEqual(b.ahead, 1)
    }

    /// A fresh branch with no own commits sits directly on the base.
    func testFreshBranchHangsUnderBase() {
        let tree = BranchStack.tree(base: "develop", commits: ["feature/FRESH": []])
        XCTAssertEqual(tree.children.map(\.name), ["feature/FRESH"])
        XCTAssertEqual(tree.children[0].ahead, 0)
    }

    /// A merged branch (empty set, like a merged worktree that still exists) is the empty subset
    /// of everything — it must not adopt the whole forest.
    func testMergedBranchAdoptsNothing() {
        let tree = BranchStack.tree(base: "develop", commits: [
            "feature/MERGED": [],
            "feature/A": ["a"],
            "feature/B": ["a", "b"],
        ])
        XCTAssertEqual(tree.children.map(\.name), ["feature/A", "feature/MERGED"])
        XCTAssertEqual(tree.path(to: "feature/B")?.map(\.name),
                       ["develop", "feature/A", "feature/B"])
    }

    /// Identical commit sets are no strict subset of each other — both stay siblings instead of
    /// one arbitrarily becoming the other's parent.
    func testTwinsStaySiblings() {
        let tree = BranchStack.tree(base: "develop", commits: [
            "feature/A": ["a"],
            "feature/A-copy": ["a"],
        ])
        XCTAssertEqual(tree.children.map(\.name), ["feature/A", "feature/A-copy"])
    }

    /// A diverged branch (rebased, shares no subset relation) falls back to the base — honest
    /// rather than guessed.
    func testDivergedBranchFallsToBase() {
        let tree = BranchStack.tree(base: "develop", commits: [
            "feature/A": ["a", "b"],
            "feature/REBASED": ["x", "y", "z"],
        ])
        XCTAssertEqual(tree.children.map(\.name), ["feature/A", "feature/REBASED"])
        XCTAssertEqual(tree.children[1].ahead, 3)
    }

    func testPathToUnknownIsNil() {
        let tree = BranchStack.tree(base: "develop", commits: ["feature/A": ["a"]])
        XCTAssertNil(tree.path(to: "feature/GONE"))
    }
}
