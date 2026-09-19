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
    /// Der Slug des aktiven Profils — **nil beim Vorgabe-Profil**, dessen Sitzungen ihre
    /// gewohnten Namen behalten.
    ///
    /// Die Regel hängt am Profil und bewusst **nicht** an der Anzahl der Profile („Slug, sobald es
    /// mehr als eins gibt"): sonst änderte das Anlegen eines zweiten Profils die Namen des ersten
    /// und liesse jede laufende Sitzung verwaisen.
    public static var profileSlug: String?

    /// `kanban-` bzw. `kanban-<slug>-` — der Namensraum dieses Profils in tmux.
    public static var sessionPrefix: String {
        guard let slug = profileSlug, !slug.isEmpty else { return "kanban-" }
        return "kanban-\(tmuxSafe(slug))-"
    }

    /// Macht aus einem Namensteil einen, den tmux **unverändert** behält.
    ///
    /// `.` und `:` sind in tmux keine gewöhnlichen Zeichen, sondern die Trenner eines Ziels
    /// (`session:window.pane`). tmux nimmt sie beim Anlegen deshalb nicht an, sondern ersetzt sie
    /// still durch `_` — und danach zeigt jedes `-t <name>` ins Leere: aus
    /// `kanban-helge-schneider.de-new` wird die Sitzung `kanban-helge-schneider_de-new`, während
    /// `has-session -t 'kanban-helge-schneider.de-new'` mit „can't find pane: de-new" scheitert.
    /// Die Sitzung existiert, ist aber unerreichbar — die Konsole öffnet nicht, und der
    /// „Task erstellen"-Text landet nirgends.
    ///
    /// Ersetzt wird deshalb **genau so, wie tmux es selbst tut** (`_`, nicht `-`): so findet Kanban
    /// auch die Sitzungen wieder, die vor dieser Korrektur angelegt wurden, statt sie verwaist
    /// stehen zu lassen. Leerzeichen und `/` bleiben — die trägt tmux unverändert (nachgemessen).
    public static func tmuxSafe(_ part: String) -> String {
        part.map { $0 == "." || $0 == ":" ? "_" : $0 }.reduce(into: "") { $0.append($1) }
    }

    /// Our own deterministic session name for a ticket, e.g. `kanban-BFEZVM-4525`.
    public static func sessionName(forTicket key: String) -> String {
        sessionPrefix + tmuxSafe(key.uppercased())
    }

    /// Eine Nebensitzung desselben Tickets bzw. Projekts (`-wt`, `-new`, `-term-<n>`). Läuft über
    /// dieselbe Stelle, damit der Profil-Namensraum nicht an vier Orten nachgebaut wird.
    public static func sessionName(forTicket key: String, suffix: String) -> String {
        "\(sessionPrefix)\(tmuxSafe(key.uppercased()))-\(tmuxSafe(suffix))"
    }

    /// The command that starts (or resumes) the ticket's Claude conversation. The caller checks
    /// via `ClaudeTranscripts` whether a conversation for the id already exists in the cwd:
    /// `--resume` when it does, `--session-id` (create with exactly that id) when it doesn't.
    /// No `||` fallback — its "No conversation found" noise confused every fresh console.
    public static func claudeLaunchCommand(sessionId: String?, hasTranscript: Bool = false) -> String {
        guard let id = sessionId, !id.isEmpty else { return "claude" }
        return hasTranscript ? "claude --resume '\(id)'" : "claude --session-id '\(id)'"
    }

    /// Der Startbefehl für den Agent des Projekts.
    ///
    /// Codex bekommt bewusst **keine** Id mit: `--session-id` gibt es dort nicht, die Id erfindet
    /// Codex selbst und `codex resume <id|name>` greift erst nachträglich. Eine erfundene Id würde
    /// also nur eine Zuordnung vortäuschen, die es nicht gibt — die Wiederaufnahme über die
    /// Rollout-Dateien (`~/.codex/sessions/…`) ist der nächste Schritt.
    public static func launchCommand(agent: AgentKind, sessionId: String?,
                                     hasTranscript: Bool = false) -> String {
        switch agent {
        case .claude:
            return claudeLaunchCommand(sessionId: sessionId, hasTranscript: hasTranscript)
        case .codex:
            // Ohne Rollout scheitert `resume` sichtbar („no rollout found for thread id …",
            // verifiziert gegen 0.147) — deshalb dieselbe Regel wie bei Claude: resume nur, wenn es
            // wirklich etwas fortzusetzen gibt, sonst frisch starten.
            guard let id = sessionId, !id.isEmpty, hasTranscript else { return agent.executable }
            // `tui.resume_cwd=current` unterdrückt die Rückfrage „Session- oder aktuelles
            // Verzeichnis?", die sonst kommt, sobald die aufgezeichnete cwd abweicht. Kanban startet
            // immer im Repo des Projekts, also ist „current" genau das Gewollte.
            return "\(agent.executable) resume '\(id)' -c tui.resume_cwd=current"
        }
    }

    /// Resolution order (first match wins):
    /// 1. Our own `kanban-<TICKET>` session already exists → attach.
    /// 2. A foreign session matches the worktree (path / dir name / branch) → attach (compat).
    /// 3. Nothing yet → create `kanban-<TICKET>` in the **main tree** and launch the project's agent.
    public static func resolve(ticketKey: String,
                               repoDir: String,
                               worktree: Worktree?,
                               sessionId: String?,
                               hasTranscript: Bool = false,
                               agent: AgentKind = .claude,
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
                                   launchCommand: launchCommand(agent: agent, sessionId: sessionId,
                                                                hasTranscript: hasTranscript))
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
