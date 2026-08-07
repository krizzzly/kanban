import Foundation

/// Runs `iwf` worktree/stack lifecycle commands for a worktree, streaming their combined
/// stdout+stderr. Blocking — call from a background task. Uses a **login shell** so the user's PATH
/// (`~/.local/bin/iwf`, OrbStack/docker) resolves, and `cd`s into the target directory first.
public struct WorktreeStackController: Sendable {
    public init() {}

    /// Runs `iwf <args>` with working directory `cwd`, streaming output chunks to `onChunk` as they
    /// arrive. Returns the exit code (-1 if the process couldn't be launched).
    @discardableResult
    public func run(iwfArgs: [String], cwd: String,
                    onChunk: @escaping @Sendable (String) -> Void) -> Int32 {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let script = "cd \(Self.quote(cwd)) && iwf \(iwfArgs.map(Self.quote).joined(separator: " "))"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", script]

        // A **pseudo-terminal**, not a pipe: `iwf` colours its output via `click.secho(fg:…)`, and
        // click drops all styling when stdout is not a tty. With a plain pipe the stream arrives
        // completely colourless — verified: the same command yields `\e[32m…` on a pty and nothing
        // through a pipe. TERM is set for the same reason.
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            onChunk("Fehler: kein Pseudo-Terminal verfügbar\n")
            return -1
        }
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle   // merge stderr into the stream
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        proc.environment = environment

        let handle = FileHandle(fileDescriptor: master, closeOnDealloc: false)
        let eof = DispatchSemaphore(value: 0)
        handle.readabilityHandler = { h in
            // On a pty the read fails with EIO once the child closed the slave — that is the normal
            // end of stream here, not an error.
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                eof.signal()
                return
            }
            if let s = String(data: data, encoding: .utf8), !s.isEmpty { onChunk(s) }
        }

        do {
            try proc.run()
        } catch {
            handle.readabilityHandler = nil
            close(master); close(slave)
            onChunk("Fehler beim Start: \(error.localizedDescription)\n")
            return -1
        }
        proc.waitUntilExit()
        close(slave)          // let the master see EOF
        _ = eof.wait(timeout: .now() + 2)
        handle.readabilityHandler = nil
        close(master)
        return proc.terminationStatus
    }

    /// Single-quote a string for safe interpolation into the shell command.
    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
