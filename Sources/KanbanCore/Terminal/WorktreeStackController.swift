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
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe   // merge stderr into the stream

        let handle = pipe.fileHandleForReading
        let eof = DispatchSemaphore(value: 0)
        handle.readabilityHandler = { h in
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
            onChunk("Fehler beim Start: \(error.localizedDescription)\n")
            return -1
        }
        proc.waitUntilExit()
        eof.wait()   // make sure the final chunk was delivered before returning
        return proc.terminationStatus
    }

    /// Single-quote a string for safe interpolation into the shell command.
    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
