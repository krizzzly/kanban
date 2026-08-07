import XCTest
@testable import KanbanCore

final class BranchParentTests: XCTestCase {
    private func base(_ ref: String, ahead: Int = 0, behind: Int = 0) -> BranchBase {
        BranchBase(ref: ref, ahead: ahead, behind: behind)
    }

    /// The real shape from the EVEN repo: everything comes off develop, qa forked further back —
    /// the branch misses less against develop.
    func testFewestMissingCommitsWin() {
        let parent = BranchParent.best(from: [
            base("origin/qa", ahead: 8),
            base("origin/develop", ahead: 4),
        ])
        XCTAssertEqual(parent?.name, "develop")
    }

    func testBranchOffQaIsRecognised() {
        // Against develop the branch also carries all the qa commits since the fork.
        let parent = BranchParent.best(from: [
            base("origin/develop", ahead: 20),
            base("origin/qa", ahead: 3),
        ])
        XCTAssertEqual(parent?.name, "qa")
    }

    func testTieOnDistancePrefersConventionThenFresher() {
        // develop and a sibling that merged develop after the fork miss the same commits —
        // the conventional name is the answer.
        let conventional = BranchParent.best(from: [
            base("feature/EVEN-3600_sibling", ahead: 2, behind: 1),
            base("origin/develop", ahead: 2, behind: 9),
        ])
        XCTAssertEqual(conventional?.name, "develop")

        // Fully identical rank → the twin that moved on less is the closer base.
        let fresher = BranchParent.best(from: [
            base("feature/EVEN-3518_stale", ahead: 2, behind: 7),
            base("origin/feature/EVEN-3518_fresh", ahead: 2, behind: 0),
        ])
        XCTAssertEqual(fresher?.ref, "origin/feature/EVEN-3518_fresh")
    }

    func testEmptyInputYieldsNothing() {
        XCTAssertNil(BranchParent.best(from: []))
    }

    // MARK: - Stacked branches

    /// The real EVEN-3517 shape: stacked on EVEN-3518, only its own commit is missing there —
    /// against develop the whole stack (5 commits) is missing.
    func testStackedFeatureBranchWins() {
        let parent = BranchParent.best(from: [
            base("origin/develop", ahead: 5),
            base("origin/feature/EVEN-3518_show_teilnachweis_label", ahead: 1),
        ])
        XCTAssertEqual(parent?.name, "feature/EVEN-3518_show_teilnachweis_label")
    }

    /// Seen from EVEN-3518: the child EVEN-3517 stacked on top misses nothing (ahead == 0) —
    /// it holds the tip itself, yet is not where 3518 came from.
    func testChildStackedOnTopIsNotTheParent() {
        let parent = BranchParent.best(from: [
            base("feature/EVEN-3517_role_switch", ahead: 0, behind: 1),
            base("origin/develop", ahead: 4),
        ])
        XCTAssertEqual(parent?.name, "develop")
    }

    /// A stray copy at the tip (ahead == 0, behind == 0) is a pointer to us, not a base.
    func testCopyAtTheTipIsNotTheParent() {
        let parent = BranchParent.best(from: [
            base("feature/EVEN-3519_fresh_child"),
            base("origin/feature/EVEN-3518_show_teilnachweis_label", ahead: 2),
        ])
        XCTAssertEqual(parent?.name, "feature/EVEN-3518_show_teilnachweis_label")
    }

    /// A fresh branch with no own commits sits exactly on its base — the long-lived branch
    /// survives the ahead == 0 filter, an old sibling must not win instead.
    func testFreshBranchSitsOnItsBase() {
        let parent = BranchParent.best(from: [
            base("origin/develop"),
            base("origin/feature/EVEN-3400_old_sibling", ahead: 40),
        ])
        XCTAssertEqual(parent?.name, "develop")
    }

    // MARK: - Candidates

    func testFeatureBranchesAreCandidates() {
        // Branches stack — a sibling feature branch can be the base.
        XCTAssertTrue(BranchParent.isCandidate("origin/feature/EVEN-3518_show_teilnachweis_label"))
        XCTAssertTrue(BranchParent.isCandidate("bugfix/EVEN-1"))
        XCTAssertFalse(BranchParent.isCandidate("origin/HEAD"))
    }

    func testSnapshotBranchesAreNoCandidates() {
        // Both real backups from the EVEN repo — a rebase snapshot misses at most the rebase's
        // reshuffling and would undercut every real base.
        XCTAssertFalse(BranchParent.isCandidate("backup/EVEN-3517-pre-rebase"))
        XCTAssertFalse(BranchParent.isCandidate("backup/EVEN-3286_pre_rebase"))
        XCTAssertFalse(BranchParent.isCandidate("feature/EVEN-3517_pre_rebase"))
        XCTAssertFalse(BranchParent.isCandidate("EVEN-3517-backup"))
    }

    func testLongLivedBranchesAreCandidates() {
        XCTAssertTrue(BranchParent.isCandidate("origin/develop"))
        XCTAssertTrue(BranchParent.isCandidate("origin/qa"))
        XCTAssertTrue(BranchParent.isCandidate("release/2.8"))
    }

    func testNameStripsTheRemote() {
        XCTAssertEqual(base("origin/develop").name, "develop")
        XCTAssertEqual(base("develop").name, "develop")
    }
}
