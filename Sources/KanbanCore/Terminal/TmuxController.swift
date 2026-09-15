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

    /// Scrollback kept per Kanban pane. tmux's default of 2000 lines is nothing next to Claude: one
    /// measured answer alone filled ~900 of them, so a console held its last two prompts and the
    /// prompt timeline could jump to almost nothing. ~20 prompts fit in 20 000 lines, at roughly
    /// 2 MB per pane in the worst case.
    public static let historyLimit = 20_000

    /// Creates a detached session with a shell in `cwd`, then sends `command` + Enter so the shell
    /// survives if the command exits. No-op if the session already exists (never clobbers a live one).
    @discardableResult
    public func createSession(name: String, cwd: String, command: String?) -> Bool {
        if hasSession(name) { return true }
        ensureServerUTF8Locale()
        let created = withHistoryLimit(Self.historyLimit) {
            run(["new-session", "-d", "-s", name, "-c", cwd])?.exitCode == 0
        }
        guard created else { return false }
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

    /// The whole pane including its scrollback, one entry per **physical** line.
    ///
    /// No `-J`: joining wrapped lines would collapse them into one entry and the array index would
    /// stop being the pane's line number, which the jump arithmetic depends on. Verified against
    /// tmux's own accounting — the count equals `history_size + pane_height`.
    public func capturePaneLines(_ session: String) -> [String]? {
        guard let result = run(["capture-pane", "-p", "-S", "-", "-t", session]),
              result.exitCode == 0 else { return nil }
        var lines = result.stdout.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }   // trailing newline, not a pane line
        return lines
    }

    public func paneHeight(_ session: String) -> Int? {
        guard let raw = run(["display-message", "-p", "-t", session, "#{pane_height}"])?.stdout else {
            return nil
        }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Rows kept above the target line. Two purposes: a line of context reads better than a line
    /// glued to the top edge, and it absorbs the one or two lines a busy console appends between
    /// measuring and scrolling — without it, the prompt lands just *above* the edge and is invisible
    /// (measured against a pane writing 33 lines/s).
    public static let scrollTopMargin = 2

    /// How far to scroll up so pane line `line` sits near the **top** of the view, or nil when it is
    /// already on screen (nothing to scroll).
    ///
    /// tmux's `goto-line` is not usable for this: it counts from the bottom and always parks the
    /// cursor in the last row, so the prompt would stick to the bottom edge with its answer out of
    /// sight — and a following `scroll-down` drags the cursor along. Scrolling the view is exact.
    public static func scrollDistance(toLine line: Int, totalLines: Int, paneHeight: Int) -> Int? {
        let distance = totalLines - paneHeight - line + scrollTopMargin
        return distance > 0 ? distance : nil
    }

    /// Sends literal keystrokes (e.g. after exiting copy-mode on a keypress).
    public func sendKeys(_ session: String, _ keys: String) { _ = run(["send-keys", "-t", session, keys]) }

    /// Types literal text into the session's input line — no Enter, the user confirms manually.
    /// `-l` keeps tmux from interpreting the text as key names.
    public func sendText(_ session: String, _ text: String) {
        _ = run(["send-keys", "-t", session, "-l", text])
    }

    /// Fügt Text als **Paste** ein statt als Tastendrücke: `load-buffer` + `paste-buffer -p` klammert
    /// ihn in Bracketed-Paste-Marker. Nötig, sobald der Text Zeilenumbrüche hat — als Tastendruck
    /// wäre das erste `\n` ein Enter und schickte die halbe Beschreibung ab.
    public func pasteText(_ session: String, _ text: String) {
        let buffer = "kanban-paste"
        guard run(["load-buffer", "-b", buffer, "-"], stdin: text) != nil else { return }
        _ = run(["paste-buffer", "-b", buffer, "-p", "-t", session])
        _ = run(["delete-buffer", "-b", buffer])
    }

    /// tmux `#{scroll_position}` — "0" means scrolled to the bottom (copy-mode should exit).
    public func scrollPosition(_ session: String) -> String? {
        run(["display-message", "-p", "-t", session, "#{scroll_position}"])?
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs `body` with the server's global `history-limit` temporarily raised, then puts the old
    /// value back.
    ///
    /// A pane takes its scrollback size at creation and keeps it — verified: `set-option -t <session>`
    /// on a live session leaves its pane at the old limit, only `-g` *before* `new-session` counts.
    /// The global option is therefore raised for the moment of creation and restored right after, so
    /// panes the user opens in their own terminal keep their own setting.
    private func withHistoryLimit<T>(_ limit: Int, _ body: () -> T) -> T {
        let previous = run(["show-options", "-gv", "history-limit"])?
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = run(["set-option", "-g", "history-limit", "\(limit)"])
        defer {
            if let previous, !previous.isEmpty {
                _ = run(["set-option", "-g", "history-limit", previous])
            }
        }
        return body()
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

    private func run(_ args: [String], stdin: String? = nil) -> ProcResult? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmuxPath)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        if env["LANG"]?.uppercased().contains("UTF") != true { env["LANG"] = Self.utf8Lang }
        proc.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        if let stdin {
            let inPipe = Pipe()
            proc.standardInput = inPipe
            do { try proc.run() } catch { return nil }
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return ProcResult(stdout: String(decoding: outData, as: UTF8.self),
                              stderr: String(decoding: errData, as: UTF8.self),
                              exitCode: proc.terminationStatus)
        }
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
