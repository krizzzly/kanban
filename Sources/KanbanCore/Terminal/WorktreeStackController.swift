import Foundation

/// Runs `iwf` worktree/stack lifecycle commands for a worktree, streaming their combined
/// stdout+stderr. Blocking — call from a background task. Uses a **login shell** so the user's PATH
/// (`~/.local/bin/iwf`, OrbStack/docker) resolves, and `cd`s into the target directory first.
public struct WorktreeStackController: Sendable {
    public init() {}

    /// Wie oft die gesammelte Ausgabe weitergereicht wird. Ein pty liefert in winzigen Häppchen —
    /// gemessen an 1500 Zeilen: **1407 Aufrufe, Ø 47 Byte**, alle innerhalb von 68 ms. Jeder davon
    /// war bisher ein eigener Sprung auf den Main-Actor samt SwiftUI-Neuzeichnen; gebündelt sind es
    /// ~10 je Sekunde. Die Bündelung sitzt hier statt bei den sechs Aufrufern: die Häppchen
    /// entstehen hier, und „höchstens 10 Rückrufe je Sekunde" ist eine Eigenschaft des Stroms.
    public static let flushInterval = 0.1

    /// Runs `iwf <args>` with working directory `cwd`, streaming output chunks to `onChunk` as they
    /// arrive. Returns the exit code (-1 if the process couldn't be launched).
    @discardableResult
    public func run(iwfArgs: [String], cwd: String,
                    onChunk: @escaping @Sendable (String) -> Void) -> Int32 {
        run(shellScript: "iwf \(iwfArgs.map(Self.quote).joined(separator: " "))",
            cwd: cwd, onChunk: onChunk)
    }

    /// Dasselbe für einen beliebigen Befehl — der tiefe Sweep löscht Volumes und Images direkt über
    /// `docker`, weil iwf für „Volume und Image weg, Worktree bleibt" keinen Befehl hat: `stop` lässt
    /// beides stehen, `destroy` nimmt den Worktree mit, und `iwf stack destroy` fragt interaktiv und
    /// nimmt auch Zertifikat und DNS-Eintrag mit.
    ///
    /// Argumente **vorher** mit `quoted(_:)` einpacken: hier geht eine Shell-Zeile durch, kein
    /// Argument-Array.
    @discardableResult
    public func run(shellScript command: String, cwd: String,
                    onChunk: @escaping @Sendable (String) -> Void) -> Int32 {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let script = "cd \(Self.quote(cwd)) && \(command)"

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
        let pending = ChunkBuffer()
        handle.readabilityHandler = { h in
            // On a pty the read fails with EIO once the child closed the slave — that is the normal
            // end of stream here, not an error.
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                eof.signal()
                return
            }
            if let s = String(data: data, encoding: .utf8), !s.isEmpty { pending.add(s) }
        }

        // Der Taktgeber, der das Gesammelte weiterreicht. Eigene Queue: der Rückruf landet beim
        // Aufrufer auf dem Main-Actor, und der darf den Lesevorgang nicht ausbremsen.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "kanban.stack.flush"))
        timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
        timer.setEventHandler {
            let text = pending.take()
            if !text.isEmpty { onChunk(text) }
        }
        timer.resume()
        // Ein abgebrochener Timer feuert nicht mehr — der Rest geht am Ende von Hand raus.
        func stopStreaming() {
            timer.cancel()
            let rest = pending.take()
            if !rest.isEmpty { onChunk(rest) }
        }

        do {
            try proc.run()
        } catch {
            handle.readabilityHandler = nil
            stopStreaming()
            close(master); close(slave)
            onChunk("Fehler beim Start: \(error.localizedDescription)\n")
            return -1
        }
        proc.waitUntilExit()
        close(slave)          // let the master see EOF
        _ = eof.wait(timeout: .now() + 2)
        handle.readabilityHandler = nil
        // Vor der Rückkehr leeren: der Aufrufer schreibt direkt danach seine „— fertig —"-Zeile,
        // und die darf nicht vor dem letzten Stück Ausgabe stehen.
        stopStreaming()
        close(master)
        return proc.terminationStatus
    }

    /// Sammelt die pty-Häppchen zwischen zwei Takten. Eigene Klasse statt eines Actors: der
    /// Lesevorgang läuft synchron in `readabilityHandler`, dort gibt es kein `await`.
    private final class ChunkBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""

        func add(_ chunk: String) {
            lock.lock(); text += chunk; lock.unlock()
        }

        func take() -> String {
            lock.lock()
            defer { text = ""; lock.unlock() }
            return text
        }
    }

    /// Single-quote für Aufrufer, die eine ganze Shell-Zeile bauen (Docker-Namen sind harmlos, aber
    /// derselbe Weg für alles heisst: kein Sonderfall, der es doch nicht ist).
    public static func quoted(_ value: String) -> String { quote(value) }

    /// Single-quote a string for safe interpolation into the shell command.
    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
