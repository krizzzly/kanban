import Foundation

/// Stages a database seed for a worktree stack — the GUI equivalent of
/// `iwf worktree create --dbdump <env|file>`, which otherwise only exists at create time.
///
/// Mirrors iwf's own `_seed_db`:
///   1. clear stale dumps from the worktree's MySQL init dir,
///   2. put the new dump there as `00_dev-dump.sql[.gz]`,
///   3. drop the `<name>_dbdata` volume, because MySQL only auto-imports into an **empty** data
///      directory — with the volume in place the new dump is simply ignored.
///
/// Step 3 is why seeding needs the stack to be down: Docker refuses to remove a volume that is in
/// use, and iwf swallows that error, which is exactly how a "seeded" worktree ends up with the old
/// database.
public struct StackSeeder: Sendable {
    public enum Source: Sendable, Hashable {
        case remote(String)   // dev / qa / prod
        case file(String)     // path to a .sql or .sql.gz

        public var label: String {
            switch self {
            case .remote(let env): return env
            case .file(let path): return (path as NSString).lastPathComponent
            }
        }
    }

    public enum SeedError: Error, LocalizedError {
        case stackRunning
        case stackNotRunning
        case fileMissing(String)
        case downloadFailed(String)
        case copyFailed(String)
        case importFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case .stackRunning:
                return "Der Stack läuft — Docker gibt das DB-Volume nicht frei. Bitte zuerst stoppen."
            case .stackNotRunning:
                return "Für den Direktimport muss der Stack laufen. Bitte zuerst starten."
            case .fileMissing(let path):
                return "Dump-Datei nicht gefunden: \(path)"
            case .downloadFailed(let message):
                return "Download fehlgeschlagen: \(message)"
            case .copyFailed(let message):
                return "Dump konnte nicht abgelegt werden: \(message)"
            case .importFailed(let code):
                return "Import fehlgeschlagen (Exit \(code))"
            }
        }
    }

    public init() {}

    /// Stages `source` into the worktree and drops the data volume so the next start imports it.
    /// `onOutput` receives progress lines (the remote download can take minutes).
    public func seed(source: Source,
                     worktreePath: String,
                     projectName: String,
                     dbInitDir: String = WorktreeDbSeed.defaultInitSubdir,
                     runningContainers: Int,
                     onOutput: @Sendable (String) -> Void) throws {
        guard runningContainers == 0 else { throw SeedError.stackRunning }

        let name = (worktreePath as NSString).lastPathComponent
        let initDir = (worktreePath as NSString).appendingPathComponent(dbInitDir)
        try? FileManager.default.createDirectory(atPath: initDir, withIntermediateDirectories: true)
        clearStaleDumps(in: initDir, onOutput: onOutput)

        switch source {
        case .file(let path):
            try stageFile(path, into: initDir, onOutput: onOutput)
        case .remote(let environment):
            try download(environment: environment, projectName: projectName,
                         into: initDir, worktreePath: worktreePath, onOutput: onOutput)
        }

        dropVolume(named: "\(name)_dbdata", onOutput: onOutput)
        onOutput("\n✅ Seed bereit — beim nächsten Start importiert MySQL ihn automatisch.\n")
    }

    /// Setzt die Datenbank **jetzt** neu auf, statt den Dump für den nächsten Start abzulegen.
    ///
    /// „Direktimport" heisst nicht „in den laufenden Stack hinein": `iwf db import-dump` legt den
    /// Dump in den Init-Ordner (vorhandene wandern nach `backup/`), fährt den Stack mit
    /// `compose down` **herunter**, **löscht das `<projekt>_dbdata`-Volume** und startet neu — MySQL
    /// importiert dann beim Hochlaufen aus dem Init-Ordner. Nachgelesen in
    /// `project_compose.db_import_dump`, nicht aus dem Hilfetext geschlossen.
    ///
    /// Zwei Folgen, die im Text an den Nutzer gehören müssen:
    ///  - **Der alte Stand ist weg**, unwiderruflich. Einen Snapshot legt iwf dabei *nicht* an
    ///    (`iwf db snapshot create` ist ein eigener Befehl, und niemand ruft ihn hier).
    ///  - **Fertig ist der Import nicht**, wenn der Befehl zurückkommt: er läuft im Container weiter,
    ///    und nur dessen Log sagt, ob er durchlief.
    ///
    /// `iwf` löst das Projekt aus dem Arbeitsverzeichnis auf — im Worktree trifft es also dessen
    /// Datenbank, nicht die des Haupt-Repos.
    public func importNow(source: Source,
                          worktreePath: String,
                          projectName: String,
                          runningContainers: Int,
                          onOutput: @Sendable (String) -> Void) throws {
        guard runningContainers > 0 else { throw SeedError.stackNotRunning }

        let code: Int32
        switch source {
        case .remote(let environment):
            onOutput("• hole Dump von \(environment), setze die DB damit neu auf…\n")
            code = runIwf(["server", "dbdump", environment, projectName,
                           "--service", "db", "--import", "--compress", "--yes"],
                          cwd: worktreePath, onOutput: onOutput)
        case .file(let path):
            let expanded = (path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                throw SeedError.fileMissing(expanded)
            }
            onOutput("• \((expanded as NSString).lastPathComponent) → Stack neu aufsetzen und importieren…\n")
            // `import-dump`, nicht `import`: der Befehl heisst so, seit es ihn gibt — `iwf db import`
            // gab es nie, und iwf antwortete mit „No such command 'import'. Did you mean
            // 'import-dump'?" (Exit 2), also ohne dass irgendetwas passierte.
            code = runIwf(["db", "import-dump", "-f", expanded, "--service", "db", "-y"],
                          cwd: worktreePath, onOutput: onOutput)
        }
        guard code == 0 else { throw SeedError.importFailed(code) }
        // Nicht „abgeschlossen": `compose up` kommt zurück, sobald die Container laufen — MySQL liest
        // den Dump danach ein, und bei mehreren hundert MB dauert das. Ein „✅ fertig" hier hätte
        // einen halb importierten Stand als fertig ausgegeben.
        onOutput("""

        ✅ Stack neu aufgesetzt, Dump liegt im Init-Ordner.
        Der Import läuft **im Container weiter** — Fortschritt im Log der db-Container.
        Der vorherige Datenbestand wurde dabei gelöscht (iwf legt keinen Snapshot an).

        """)
    }

    // MARK: - Steps

    private func clearStaleDumps(in initDir: String, onOutput: @Sendable (String) -> Void) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: initDir)) ?? []
        for file in files where file.hasSuffix(".sql") || file.hasSuffix(".sql.gz") {
            let path = (initDir as NSString).appendingPathComponent(file)
            try? FileManager.default.removeItem(atPath: path)
            onOutput("• alten Dump entfernt: \(file)\n")
        }
    }

    private func stageFile(_ path: String, into initDir: String,
                           onOutput: @Sendable (String) -> Void) throws {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw SeedError.fileMissing(expanded)
        }
        // Keep the original format — the MySQL entrypoint reads .sql and .sql.gz, and re-packing
        // would only risk corrupting a multi-hundred-MB dump.
        let suffix = expanded.hasSuffix(".gz") ? ".sql.gz" : ".sql"
        let destination = (initDir as NSString).appendingPathComponent("00_dev-dump\(suffix)")
        onOutput("• kopiere \((expanded as NSString).lastPathComponent) → \(destination)\n")
        do {
            try FileManager.default.copyItem(atPath: expanded, toPath: destination)
        } catch {
            throw SeedError.copyFailed(error.localizedDescription)
        }
    }

    /// Fetches the dump through `iwf server dbdump`, gzipped — gzip runs in the remote container, so
    /// only the compressed stream crosses the connection. iwf documents that an uncompressed
    /// multi-hundred-MB dump can truncate silently over that transport and then crash the import.
    private func download(environment: String, projectName: String, into initDir: String,
                          worktreePath: String, onOutput: @Sendable (String) -> Void) throws {
        let destination = (initDir as NSString).appendingPathComponent("00_dev-dump.sql.gz")
        onOutput("• lade Dump von \(environment) (\(projectName))…\n")
        let code = runIwf(["server", "dbdump", environment, projectName,
                           "--service", "db", "--dumpfile", destination, "--compress", "--yes"],
                          cwd: worktreePath, onOutput: onOutput)
        guard code == 0, FileManager.default.fileExists(atPath: destination) else {
            throw SeedError.downloadFailed("iwf server dbdump endete mit Code \(code)")
        }
    }

    private func dropVolume(named volume: String, onOutput: @Sendable (String) -> Void) {
        let code = run("/usr/bin/env", ["docker", "volume", "rm", volume], onOutput: { _ in })
        onOutput(code == 0
                 ? "• DB-Volume \(volume) entfernt — Seed wird beim Start importiert\n"
                 : "• kein DB-Volume \(volume) vorhanden (nichts zu entfernen)\n")
    }

    // MARK: - Process plumbing

    private func runIwf(_ args: [String], cwd: String,
                        onOutput: @Sendable (String) -> Void) -> Int32 {
        // Through a login shell, like `WorktreeStackController`: `iwf` lives in ~/.local/bin and
        // needs the user's PATH.
        let script = "cd \(Self.quote(cwd)) && iwf \(args.map(Self.quote).joined(separator: " "))"
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return run(shell, ["-lc", script], onOutput: onOutput)
    }

    private func run(_ executable: String, _ args: [String],
                     onOutput: @Sendable (String) -> Void) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return -1 }
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            onOutput(String(decoding: chunk, as: UTF8.self))
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
