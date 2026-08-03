import Foundation

/// Thin, synchronous wrapper around the `tmux` CLI (create / list / check sessions). Blocking —
/// call it off the main actor. Runs a plan produced by `TerminalSessionResolver`.
public struct TmuxController: Sendable {
    private let tmuxPath: String

    public init(tmuxPath: String? = nil) {
        self.tmuxPath = tmuxPath ?? TmuxController.findTmux() ?? "tmux"
    }

    public var resolvedTmuxPath: String { tmuxPath }
    public var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: tmuxPath) }

    public func listSessions() -> [TmuxSession] {
        guard let result = run(["list-sessions", "-F",
                                "#{session_name}\t#{session_path}\t#{session_attached}"]),
              !result.stdout.isEmpty else { return [] }
        return result.stdout.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { return nil }
            return TmuxSession(name: parts[0], path: parts[1], attached: parts[2] == "1")
        }
    }

    public func hasSession(_ name: String) -> Bool {
        run(["has-session", "-t", name])?.exitCode == 0
    }

    /// Creates a detached session with a shell in `cwd`, then sends `command` + Enter so the shell
    /// survives if the command exits. No-op if the session already exists (never clobbers a live one).
    @discardableResult
    public func createSession(name: String, cwd: String, command: String?) -> Bool {
        if hasSession(name) { return true }
        ensureServerUTF8Locale()
        guard run(["new-session", "-d", "-s", name, "-c", cwd])?.exitCode == 0 else { return false }
        if let command, !command.isEmpty {
            _ = run(["send-keys", "-t", name, command, "Enter"])
        }
        return true
    }

    /// Runs `plan`: creates + launches when `plan.needsCreate`, otherwise a no-op (attach happens
    /// in the terminal view). Returns true on success.
    @discardableResult
    public func run(plan: TerminalSessionPlan) -> Bool {
        guard plan.needsCreate else { return true }
        return createSession(name: plan.name, cwd: plan.cwd, command: plan.launchCommand)
    }

    /// Show/hide the green tmux status bar for a session (off = cleaner embedded look).
    public func setStatusBar(_ session: String, visible: Bool) {
        _ = run(["set-option", "-t", session, "status", visible ? "on" : "off"])
    }

    /// Kills a session (used when the user closes an extra terminal tab).
    public func killSession(_ name: String) {
        _ = run(["kill-session", "-t", name])
    }

    // MARK: - Scroll / copy-mode (used by the scroll-wheel handler)

    public func enterCopyMode(_ session: String) { _ = run(["copy-mode", "-t", session]) }

    /// Scrolls the copy-mode view (not the cursor) — the natural scroll-wheel behavior.
    public func copyScroll(_ session: String, up: Bool, lines: Int) {
        _ = run(["send-keys", "-t", session, "-X", "-N", "\(lines)", up ? "scroll-up" : "scroll-down"])
    }

    public func cancelCopyMode(_ session: String) { _ = run(["send-keys", "-t", session, "-X", "cancel"]) }

    /// Snapshots the visible pane text of a session (used to detect a blocking prompt). nil if the
    /// session is gone. `-p` prints to stdout, `-t` targets the session's active pane.
    public func capturePane(_ session: String) -> String? {
        guard let result = run(["capture-pane", "-p", "-t", session]), result.exitCode == 0 else { return nil }
        return result.stdout
    }

    /// Sends literal keystrokes (e.g. after exiting copy-mode on a keypress).
    public func sendKeys(_ session: String, _ keys: String) { _ = run(["send-keys", "-t", session, keys]) }

    /// Types literal text into the session's input line — no Enter, the user confirms manually.
    /// `-l` keeps tmux from interpreting the text as key names.
    public func sendText(_ session: String, _ text: String) {
        _ = run(["send-keys", "-t", session, "-l", text])
    }

    /// tmux `#{scroll_position}` — "0" means scrolled to the bottom (copy-mode should exit).
    public func scrollPosition(_ session: String) -> String? {
        run(["display-message", "-p", "-t", session, "#{scroll_position}"])?
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Locale

    /// GUI apps inherit no `LANG`/`LC_*`, so a tmux server we spawn runs its panes in the C locale —
    /// zsh prompt themes then fail with "prompt_segment: character not in range" and multibyte
    /// redraws garble. Preferred value: the user's own UTF-8 `LANG`, else `en_US.UTF-8`.
    private static var utf8Lang: String {
        if let lang = ProcessInfo.processInfo.environment["LANG"],
           lang.uppercased().contains("UTF") {
            return lang
        }
        return "en_US.UTF-8"
    }

    /// Sets a UTF-8 `LANG` in the global environment of an already-running tmux server so newly
    /// created sessions get it. (A server we auto-start inherits it from `run`'s environment.)
    private func ensureServerUTF8Locale() {
        if let current = run(["show-environment", "-g", "LANG"]),
           current.exitCode == 0, current.stdout.uppercased().contains("UTF") {
            return
        }
        _ = run(["set-environment", "-g", "LANG", Self.utf8Lang])
    }

    // MARK: - Process plumbing

    private struct ProcResult { let stdout: String; let stderr: String; let exitCode: Int32 }

    private func run(_ args: [String]) -> ProcResult? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmuxPath)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        if env["LANG"]?.uppercased().contains("UTF") != true { env["LANG"] = Self.utf8Lang }
        proc.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do { try proc.run() } catch { return nil }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return ProcResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: proc.terminationStatus)
    }

    private static func findTmux() -> String? {
        for path in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to the login-shell PATH.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        proc.arguments = ["-lc", "command -v tmux"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        return nil
    }
}
