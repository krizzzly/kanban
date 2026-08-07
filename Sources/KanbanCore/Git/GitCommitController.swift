import Foundation

/// One file with uncommitted changes, as `git status --porcelain` reports it (`XY path`).
public struct GitChangedFile: Sendable, Hashable, Identifiable {
    public let path: String
    /// The two status columns: index (staged) and worktree. `??` = untracked.
    public let index: Character
    public let worktree: Character

    public var id: String { path }
    public var isUntracked: Bool { index == "?" }

    /// Short marker for the list: `A` added · `M` modified · `D` deleted · `R` renamed · `?` new file.
    public var marker: String {
        if isUntracked { return "?" }
        let code = index != " " ? index : worktree
        return String(code)
    }

    public init(path: String, index: Character, worktree: Character) {
        self.path = path
        self.index = index
        self.worktree = worktree
    }
}

/// The state of a working tree, as the commit dialog needs it.
public struct GitWorkingState: Sendable, Hashable {
    public let branch: String?
    /// Files with uncommitted changes (staged or not).
    public let changedFiles: [GitChangedFile]
    /// Subject of HEAD — shown when amending, so it is visible what gets rewritten.
    public let headSubject: String?
    /// True when HEAD exists on the remote — an amend then needs a force push.
    public let hasUpstream: Bool

    public var isClean: Bool { changedFiles.isEmpty }

    public init(branch: String?, changedFiles: [GitChangedFile], headSubject: String?, hasUpstream: Bool) {
        self.branch = branch
        self.changedFiles = changedFiles
        self.headSubject = headSubject
        self.hasUpstream = hasUpstream
    }
}

/// Runs the git commands behind the Commit button. Every call is synchronous and meant to run off the
/// main actor (like `WorktreeScanner`); the caller reports stdout/stderr back to the user.
public struct GitCommitController: Sendable {
    public enum GitError: Error, LocalizedError {
        case failed(command: String, output: String)

        public var errorDescription: String? {
            switch self {
            case .failed(let command, let output):
                return output.isEmpty ? "git \(command) fehlgeschlagen" : output
            }
        }
    }

    private let git = "/usr/bin/git"

    public init() {}

    // MARK: - Reading

    /// Branch, pending changes and HEAD subject of `dir`. Fail-open: a non-repo yields an empty state.
    public func state(dir: String) -> GitWorkingState {
        let branch = run(["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"], dir: dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = run(["-C", dir, "status", "--porcelain"], dir: dir).output
        let files = status.components(separatedBy: .newlines).compactMap(Self.parseStatusLine)
        let subject = run(["-C", dir, "log", "-1", "--pretty=%s"], dir: dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `@{upstream}` resolves only when the branch is tracked — that decides push vs force-push.
        let upstream = run(["-C", dir, "rev-parse", "--abbrev-ref", "@{upstream}"], dir: dir)
        return GitWorkingState(branch: branch.isEmpty ? nil : branch,
                               changedFiles: files,
                               headSubject: subject.isEmpty ? nil : subject,
                               hasUpstream: upstream.status == 0)
    }

    /// `XY path` → a changed file. A rename reads `R  old -> new`; the new path is what we show.
    static func parseStatusLine(_ line: String) -> GitChangedFile? {
        guard line.count > 3 else { return nil }
        let chars = Array(line)
        let path = String(chars[3...]).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        let target = path.components(separatedBy: " -> ").last ?? path
        return GitChangedFile(path: target.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                              index: chars[0], worktree: chars[1])
    }

    /// The unified diff of one file against HEAD — what the dialog renders. An untracked file has no
    /// HEAD side, so it is diffed against /dev/null and shows up as all-additions.
    /// git exits non-zero when differences exist, so the status is deliberately ignored here.
    public func diff(dir: String, file: GitChangedFile) -> String {
        if file.isUntracked {
            return run(["-C", dir, "diff", "--no-index", "--", "/dev/null", file.path], dir: dir).output
        }
        return run(["-C", dir, "diff", "HEAD", "--", file.path], dir: dir).output
    }

    // MARK: - Writing

    /// Stages everything and commits with `message`. Returns git's output for the log pane.
    @discardableResult
    public func commit(dir: String, message: String) throws -> String {
        var log = try stageAll(dir: dir)
        log += try expect(["-C", dir, "commit", "-m", message], dir: dir, name: "commit")
        return log
    }

    /// Stages everything and folds it into HEAD, keeping the existing message (`--no-edit`) — which is
    /// why amending needs no message from the user.
    @discardableResult
    public func amend(dir: String) throws -> String {
        var log = try stageAll(dir: dir)
        log += try expect(["-C", dir, "commit", "--amend", "--no-edit"], dir: dir, name: "commit --amend")
        return log
    }

    /// Pushes the current branch. `force` uses **--force-with-lease**, never a bare --force: it refuses
    /// when the remote moved since we last fetched, so a colleague's push cannot be overwritten blindly.
    @discardableResult
    public func push(dir: String, force: Bool, setUpstream: Bool) throws -> String {
        var args = ["-C", dir, "push"]
        if force { args.append("--force-with-lease") }
        if setUpstream, let branch = state(dir: dir).branch {
            args += ["--set-upstream", "origin", branch]
        }
        return try expect(args, dir: dir, name: force ? "push --force-with-lease" : "push")
    }

    private func stageAll(dir: String) throws -> String {
        try expect(["-C", dir, "add", "-A"], dir: dir, name: "add -A")
    }

    // MARK: - Process plumbing

    private func expect(_ args: [String], dir: String, name: String) throws -> String {
        let result = run(args, dir: dir)
        guard result.status == 0 else {
            throw GitError.failed(command: name, output: result.output)
        }
        return result.output.isEmpty ? "" : result.output + "\n"
    }

    private func run(_ args: [String], dir: String) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "git nicht ausführbar: \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
