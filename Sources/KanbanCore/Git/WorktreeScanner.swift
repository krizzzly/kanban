import Foundation

/// Scans a git repo for worktrees via `git worktree list --porcelain`.
/// Fail-open: any error (no git, not a repo) yields an empty list.
public enum WorktreeScanner {
    public static func scan(repoDir: String) async -> [Worktree] {
        await Task.detached(priority: .utility) { run(repoDir: repoDir) }.value
    }

    /// Runs git synchronously off the main actor. `nonisolated` by virtue of being a
    /// plain static function invoked from a detached task.
    static func run(repoDir: String) -> [Worktree] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repoDir, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoDir, "worktree", "list", "--porcelain"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return parse(text)
    }

    /// Parses porcelain output: blank-line-separated blocks of `worktree <path>` / `branch refs/heads/<b>`.
    static func parse(_ text: String) -> [Worktree] {
        var worktrees: [Worktree] = []
        var path: String?
        var branch: String?

        func flush() {
            if let p = path { worktrees.append(Worktree(path: p, branch: branch)) }
            path = nil; branch = nil
        }

        for line in text.components(separatedBy: "\n") {
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            }
        }
        flush()
        return worktrees
    }

    /// First worktree whose branch references the ticket key as a whole token.
    public static func worktree(for ticketKey: String, in worktrees: [Worktree],
                                branch: String? = nil) -> Worktree? {
        worktrees.first { TicketMatching.matches($0, ticketKey: ticketKey, branch: branch) }
    }
}
