import Foundation

/// A tmux session as reported by `tmux list-sessions`.
public struct TmuxSession: Sendable, Hashable {
    public let name: String
    public let path: String
    public let attached: Bool

    public init(name: String, path: String, attached: Bool) {
        self.name = name
        self.path = path
        self.attached = attached
    }
}

/// What the terminal should do for a ticket: which tmux session to show, in which directory,
/// and — only when the session must be *created* — the command to launch inside it.
public struct TerminalSessionPlan: Sendable, Hashable {
    public let name: String
    public let cwd: String
    /// nil → attach to an existing session (never inject a command into a live session).
    public let launchCommand: String?

    public var needsCreate: Bool { launchCommand != nil }

    public init(name: String, cwd: String, launchCommand: String?) {
        self.name = name
        self.cwd = cwd
        self.launchCommand = launchCommand
    }
}

/// Pure decision logic: given the existing tmux sessions and the ticket's artifacts, decide which
/// session to attach/create. No side effects — the caller runs the resulting plan via `TmuxController`.
public enum TerminalSessionResolver {
    /// Our own deterministic session name for a ticket, e.g. `kanban-BFEZVM-4525`.
    public static func sessionName(forTicket key: String) -> String {
        "kanban-\(key.uppercased())"
    }

    /// The command that starts (or resumes) the ticket's Claude conversation. Deterministic:
    /// `--resume` reuses the stored id; on the very first launch resume fails fast and the
    /// `||` fallback creates the session with exactly that id.
    public static func claudeLaunchCommand(sessionId: String?) -> String {
        guard let id = sessionId, !id.isEmpty else { return "claude" }
        return "claude --resume '\(id)' 2>/dev/null || claude --session-id '\(id)'"
    }

    /// Resolution order (first match wins):
    /// 1. Our own `kanban-<TICKET>` session already exists → attach.
    /// 2. A foreign session matches the worktree (path / dir name / branch) → attach (compat).
    /// 3. Nothing yet → create `kanban-<TICKET>` in the **main tree** and launch Claude.
    public static func resolve(ticketKey: String,
                               repoDir: String,
                               worktree: Worktree?,
                               sessionId: String?,
                               existing: [TmuxSession]) -> TerminalSessionPlan {
        let own = sessionName(forTicket: ticketKey)

        if existing.contains(where: { $0.name == own }) {
            return TerminalSessionPlan(name: own, cwd: repoDir, launchCommand: nil)
        }

        if let worktree, let match = matchWorktree(worktree, in: existing) {
            let cwd = match.path.isEmpty ? repoDir : match.path
            return TerminalSessionPlan(name: match.name, cwd: cwd, launchCommand: nil)
        }

        return TerminalSessionPlan(name: own, cwd: repoDir,
                                   launchCommand: claudeLaunchCommand(sessionId: sessionId))
    }

    /// Mirrors kanban-code's `findSessionForWorktree` matching so we reuse sessions started by
    /// other tools (kanban-code, the `kanban` CLI) instead of spawning a duplicate.
    static func matchWorktree(_ worktree: Worktree, in sessions: [TmuxSession]) -> TmuxSession? {
        if let m = sessions.first(where: { $0.path == worktree.path }) { return m }        // exact path
        let dir = (worktree.path as NSString).lastPathComponent
        if let m = sessions.first(where: { $0.name == dir }) { return m }                   // dir name
        if let branch = worktree.branch {
            if let m = sessions.first(where: { $0.name == branch }) { return m }            // branch
            let dashed = branch.replacingOccurrences(of: "/", with: "-")
            if dashed != branch, let m = sessions.first(where: { $0.name == dashed }) { return m }
        }
        return nil
    }
}
