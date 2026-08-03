import Foundation

/// Runs a one-shot script in the user's login shell (so PATH entries like `~/.local/bin` resolve).
/// Blocking — call from a background task.
public enum LoginShell {
    public static func run(_ script: String) -> (status: Int32, output: String) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do { try proc.run() }
        catch { return (-1, "Fehler beim Start: \(error.localizedDescription)") }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (proc.terminationStatus, output)
    }
}
