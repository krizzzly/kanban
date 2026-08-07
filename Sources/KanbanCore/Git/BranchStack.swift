import Foundation

/// One branch in the derived stack forest: its own commits beyond the parent, and its children.
public struct BranchStackNode: Sendable, Hashable, Identifiable {
    public let name: String
    /// Own commits beyond the parent (0 for the root and for branches sitting exactly on it).
    public let ahead: Int
    public let children: [BranchStackNode]

    public var id: String { name }

    public init(name: String, ahead: Int, children: [BranchStackNode]) {
        self.name = name
        self.ahead = ahead
        self.children = children
    }

    /// Root → … → the named node, or nil when it is not in the tree.
    public func path(to name: String) -> [BranchStackNode]? {
        if self.name == name { return [self] }
        for child in children {
            if let rest = child.path(to: name) { return [self] + rest }
        }
        return nil
    }
}

/// Derives the hierarchy of all worktree feature branches down to the long-lived base.
///
/// The same idea as `BranchParent`, applied to the whole forest at once: every branch owns the set
/// of commits it has beyond the base, and its parent is the branch whose set is the **largest
/// strict subset** — for a stacked branch that is the level below, for everything else the base.
/// Strict-subset ordering cannot cycle, and one `rev-list` per branch suffices, where pairwise
/// comparison (as `BranchParent` does for a single branch) would need N² git calls.
public enum BranchStack {
    /// Builds the forest under `base`. `commits` maps branch name → commits beyond the base.
    public static func tree(base: String, commits: [String: Set<String>]) -> BranchStackNode {
        let names = commits.keys.sorted()
        var childrenOf: [String: [String]] = [:]
        for name in names {
            let own = commits[name] ?? []
            // A branch without own commits (empty set — merged into the base, or fresh) sits *on*
            // the base; as the empty subset of everything it must not adopt the whole forest.
            let parent = names
                .filter { $0 != name && (commits[$0]?.isEmpty == false)
                          && (commits[$0] ?? []).isStrictSubset(of: own) }
                .max { lhs, rhs in
                    let (l, r) = (commits[lhs]?.count ?? 0, commits[rhs]?.count ?? 0)
                    return l != r ? l < r : lhs > rhs
                }
            childrenOf[parent ?? base, default: []].append(name)
        }
        func node(_ name: String, parentCount: Int) -> BranchStackNode {
            let own = commits[name]?.count ?? 0
            return BranchStackNode(name: name, ahead: own - parentCount,
                                   children: (childrenOf[name] ?? []).map { node($0, parentCount: own) })
        }
        return BranchStackNode(name: base, ahead: 0,
                               children: (childrenOf[base] ?? []).map { node($0, parentCount: 0) })
    }
}


/// Reads the forest out of a git repository: one commit set per worktree branch.
public struct BranchStackScanner: Sendable {
    public init() {}

    /// The forest under the first long-lived branch, or nil when there is none to hang it on.
    public func scan(worktreePath: String) -> BranchStackNode? {
        let existing = Set(GitRun.lines(["for-each-ref", "--format=%(refname:short)",
                                         "refs/heads", "refs/remotes/origin"], cwd: worktreePath))
        guard let baseName = BranchParent.preferredOrder.first(where: {
            existing.contains($0) || existing.contains("origin/\($0)")
        }) else { return nil }
        // The remote copy is the truth for the base — the local checkout is often behind.
        let baseRef = existing.contains("origin/\(baseName)") ? "origin/\(baseName)" : baseName

        var commits: [String: Set<String>] = [:]
        for worktree in WorktreeScanner.run(repoDir: worktreePath) {
            guard let name = worktree.branch, commits[name] == nil,
                  !BranchParent.preferredOrder.contains(name), BranchParent.isCandidate(name),
                  existing.contains(name) else { continue }
            commits[name] = Set(GitRun.lines(["rev-list", "\(baseRef)..\(name)"], cwd: worktreePath))
        }
        guard !commits.isEmpty else { return nil }
        return BranchStack.tree(base: baseName, commits: commits)
    }
}
