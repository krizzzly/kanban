import Foundation

/// A branch a feature branch could have come from, with how far the two have drifted.
public struct BranchBase: Sendable, Hashable {
    /// Ref as git names it (`origin/develop`).
    public let ref: String
    /// Commits the feature branch has that the candidate lacks (its own work since the divergence).
    public let ahead: Int
    /// Commits the candidate has that the feature branch lacks (moved on since the divergence).
    public let behind: Int

    /// `origin/develop` → `develop`.
    public var name: String {
        ref.hasPrefix("origin/") ? String(ref.dropFirst("origin/".count)) : ref
    }

    public init(ref: String, ahead: Int, behind: Int) {
        self.ref = ref
        self.ahead = ahead
        self.behind = behind
    }
}

/// Works out which branch a feature branch was created from.
///
/// Git records no parent — a branch is just a pointer, and `branch.<name>.merge` names the *upstream*
/// (usually the branch itself on the remote), not the origin. iwf does not help either: its
/// `baseBranch` is a global default (`develop`) and `worktree create --branch` can start anywhere.
///
/// So it is derived: the parent is the candidate missing the **fewest** of the branch's commits.
/// `ahead` counts what the branch has beyond a candidate — against the true base that is its own
/// work only; against everything further away (develop when stacked on a sibling, an unrelated
/// sibling that also carries develop commits since its own fork) the count only grows. Monotone
/// along a stack (EVEN-3517 → EVEN-3518 → develop), so the nearest ancestor wins.
public enum BranchParent {
    /// Long-lived branches in preference order — breaks ties (same commit, e.g. right after a
    /// release) and marks the names a fresh branch may sit on with no commits of its own.
    public static let preferredOrder = ["develop", "main", "master", "qa", "staging"]

    /// The most likely parent, or nil when nothing matched.
    public static func best(from candidates: [BranchBase]) -> BranchBase? {
        // ahead == 0 → the candidate holds the branch tip itself: a copy of it, or a child stacked
        // on top. Missing nothing, it would always win — yet it is exactly not where the branch
        // *came from*. The long-lived branches are the exception: a fresh branch with no own
        // commits legitimately sits on its base.
        let plausible = candidates.filter { $0.ahead > 0 || rank($0.name) < preferredOrder.count }
        return plausible.min { lhs, rhs in
            if lhs.ahead != rhs.ahead { return lhs.ahead < rhs.ahead }
            // Same distance → the conventional order (a sibling that merged develop after the
            // branch forked ties with develop — develop is still the answer); then the fresher one.
            if rank(lhs.name) != rank(rhs.name) { return rank(lhs.name) < rank(rhs.name) }
            return lhs.behind < rhs.behind
        }
    }

    private static func rank(_ name: String) -> Int {
        preferredOrder.firstIndex(of: name) ?? preferredOrder.count
    }

    /// Snapshot branches can never be the parent: a rebase backup (`backup/EVEN-3517-pre-rebase`)
    /// is a copy of the feature branch itself — it misses at most the rebase's own reshuffling and
    /// would undercut every real base.
    public static func isCandidate(_ ref: String) -> Bool {
        let name = ref.hasPrefix("origin/") ? String(ref.dropFirst("origin/".count)) : ref
        guard !name.isEmpty, name != "HEAD" else { return false }
        if name.hasPrefix("backup/") { return false }
        let normalized = name.replacingOccurrences(of: "_", with: "-").lowercased()
        return !normalized.contains("pre-rebase") && !normalized.hasSuffix("-backup")
    }
}


/// Reads the candidates and their divergence out of a git repository.
public struct BranchParentScanner: Sendable {
    public init() {}

    /// The branch `worktreePath`'s checkout most likely came from, or nil when it cannot be told.
    public func parent(worktreePath: String) -> BranchBase? {
        let head = GitRun.run(["rev-parse", "--abbrev-ref", "HEAD"], cwd: worktreePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty, head != "HEAD" else { return nil }

        // Candidate names: the long-lived branches plus what the other worktrees have checked out —
        // a stacked base is practically always an active worktree, and walking all repo branches
        // (~300 here) at one `rev-list` each would take far too long for a tab visit.
        var names = Set(BranchParent.preferredOrder)
        for worktree in WorktreeScanner.run(repoDir: worktreePath) {
            if let branch = worktree.branch { names.insert(branch) }
        }
        names.remove(head)   // drops the branch's own remote twin too — it is looked up by name

        var sha: [String: String] = [:]
        for line in GitRun.lines(["for-each-ref", "--format=%(refname:short) %(objectname)",
                                  "refs/heads", "refs/remotes/origin"], cwd: worktreePath) {
            let parts = line.split(separator: " ")
            if parts.count == 2 { sha[String(parts[0])] = String(parts[1]) }
        }

        // Local and remote twin both compete: whichever is fresher misses less of the branch and
        // wins by itself (long-lived branches are usually current on origin, worktree checkouts
        // locally — a stale twin only loses). Identical twins collapse to the remote one.
        let refs = names.filter(BranchParent.isCandidate).flatMap { name -> [String] in
            let twins = ["origin/\(name)", name].filter { sha[$0] != nil }
            return twins.count == 2 && sha[twins[0]] == sha[twins[1]] ? [twins[0]] : twins
        }

        let candidates: [BranchBase] = refs.compactMap { ref in
            // `<behind>\t<ahead>`: left = commits only in the candidate, right = only in the branch.
            let counts = GitRun.run(["rev-list", "--left-right", "--count", "\(ref)...\(head)"],
                                    cwd: worktreePath)
                .split(whereSeparator: { $0 == "\t" || $0 == "\n" || $0 == " " })
            guard counts.count == 2,
                  let behind = Int(counts[0]), let ahead = Int(counts[1]) else { return nil }
            return BranchBase(ref: ref, ahead: ahead, behind: behind)
        }
        return BranchParent.best(from: candidates)
    }
}
