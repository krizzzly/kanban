import Foundation

/// Reads the real state of a worktree stack from Docker and the worktree directory.
///
/// Everything here is derived on demand — the same principle as the board columns. A phase is "done"
/// because its artefact exists (an image, a cert, a staged dump, a running container), never because
/// a log line once said so. That is what the task file's stale
/// "⚠️ Image-Build fehlgeschlagen … bei Bedarf `iwf worktree start`" got wrong: `iwf worktree start`
/// does not build, so the advice could not work, and the claim outlived the fact.
public struct DockerStatusScanner: Sendable {
    public init() {}

    /// Collects the status of the stack belonging to `worktreePath`.
    /// `dbInitDir` is the project's MySQL init directory (relative to the worktree).
    public func scan(worktreePath: String, projectName: String,
                     dbInitDir: String = WorktreeDbSeed.defaultInitSubdir) -> WorktreeStackStatus {
        let name = (worktreePath as NSString).lastPathComponent
        let services = StackStatusParser.services(
            from: run(["ps", "-a", "--format", "{{.Names}}\t{{.State}}\t{{.Status}}"]),
            stackName: name)

        var phases: [StackPhase] = []
        phases.append(imagePhase(name: name, projectName: projectName, worktreePath: worktreePath))
        phases.append(domainPhase(name: name))
        phases.append(seedPhase(worktreePath: worktreePath, dbInitDir: dbInitDir))
        if let importPhase = importPhase(services: services) { phases.append(importPhase) }
        phases.append(volumePhase(name: name))
        // composer / yarn / bin/console laufen via `exec` **im fpm-Container** — ohne den kann
        // keine dieser Reparaturen greifen, also muss der Status das sagen statt es zu versuchen.
        let appRunning = services.contains { $0.name == "fpm" && $0.isRunning }
        phases.append(backendPhase(worktreePath: worktreePath, appRunning: appRunning))
        phases.append(symfonyAssetsPhase(worktreePath: worktreePath, appRunning: appRunning))
        phases.append(frontendPhase(worktreePath: worktreePath, appRunning: appRunning))
        phases.append(contentsOf: rendererPhases(worktreePath: worktreePath, appRunning: appRunning))
        phases.append(vitePhase(name: name, appRunning: appRunning))
        phases.append(containerPhase(services: services))
        phases.append(routerPhase())

        return WorktreeStackStatus(name: name, phases: phases, services: services)
    }

    /// The domain: mkcert leaves `<name>.crt` + `<name>.key` in Traefik's cert folder, and a
    /// `<name>.yml` in certs-conf that tells Traefik to actually serve them.
    ///
    /// All three are created by `_create_cert`, which `_launch_stack` skips entirely when the image
    /// build fails — so a stack can be up and reachable while `https://<name>.test` has no
    /// certificate at all. The cert and its Traefik entry are checked separately, because a cert
    /// without the `.yml` is served by Traefik's default certificate: the browser shows a warning
    /// while everything else looks healthy.
    private func domainPhase(name: String, tld: String = "test") -> StackPhase {
        let certs = (Self.iwfConfigDir as NSString).appendingPathComponent("traefik/certs")
        let conf = (Self.iwfConfigDir as NSString).appendingPathComponent("traefik/certs-conf")
        let fm = FileManager.default
        let hasCert = fm.fileExists(atPath: (certs as NSString).appendingPathComponent("\(name).crt"))
            && fm.fileExists(atPath: (certs as NSString).appendingPathComponent("\(name).key"))
        let hasConf = fm.fileExists(atPath: (conf as NSString).appendingPathComponent("\(name).yml"))

        switch (hasCert, hasConf) {
        case (true, true):
            return StackPhase(title: "Domain/TLS", state: .ok("https://\(name).\(tld)"), repair: .cert)
        case (true, false):
            return StackPhase(title: "Domain/TLS",
                              state: .warning("Zertifikat da, aber nicht in Traefik eingetragen — Browser warnt"),
                              repair: .cert)
        case (false, _):
            return StackPhase(title: "Domain/TLS",
                              state: .missing("kein Zertifikat für \(name).\(tld)"), repair: .cert)
        }
    }

    /// Traefik and the DNS resolver are shared by every stack: without them no worktree domain
    /// resolves, however healthy the stack's own containers look.
    private func routerPhase() -> StackPhase {
        let output = run(["ps", "--format", "{{.Names}}\t{{.State}}"])
        func isRunning(_ name: String) -> Bool {
            output.components(separatedBy: .newlines).contains { line in
                let parts = line.components(separatedBy: "\t")
                return parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces) == name
                    && parts[1].trimmingCharacters(in: .whitespaces) == "running"
            }
        }
        let traefik = isRunning("traefik")
        let dns = isRunning("dns")
        switch (traefik, dns) {
        case (true, true):   return StackPhase(title: "Routing", state: .ok("traefik + dns laufen"))
        case (false, true):  return StackPhase(title: "Routing", state: .missing("traefik läuft nicht"))
        case (true, false):  return StackPhase(title: "Routing", state: .missing("dns läuft nicht"))
        case (false, false): return StackPhase(title: "Routing", state: .missing("traefik und dns laufen nicht"))
        }
    }

    /// `~/.iwf-dev` (iwf's `USER_CONFIG_DIR`).
    static var iwfConfigDir: String { ("~/.iwf-dev" as NSString).expandingTildeInPath }

    // MARK: - Phases

    /// Whether the worktree has an image **of its own**.
    ///
    /// Existence alone proves nothing: when the build never ran, `local/<name>:latest` can still
    /// resolve — to the *main repo's* image under a second tag. That is not a cosmetic difference,
    /// because the frontend assets are compiled into the image: the worktree then serves the main
    /// repo's assets and the branch's changes are silently absent. So the image ID is compared with
    /// the main repo's, and the build date with the branch's newest commit.
    private func imagePhase(name: String, projectName: String, worktreePath: String) -> StackPhase {
        let info = imageInfo("local/\(name):latest")
        guard let info else {
            // The most common silent failure: the build died (disk full) and `_launch_stack` returned
            // early, skipping cert, seed and start. `iwf worktree start` cannot fix this — it does
            // not build; only `iwf stack build` (or a recreate) does.
            return StackPhase(title: "Image", state: .missing("nicht gebaut"), repair: .build)
        }
        if let main = imageInfo("local/\(projectName):latest"), main.id == info.id {
            // Code und Assets kommen aus dem Mount (`../../:/app`), nicht aus dem Image — ein
            // fremdes Image heisst also nicht "falsche Assets", sondern: die Tooling-/PHP-Stände
            // stammen aus dem Haupt-Repo. Relevant, sobald die Branch das Dockerfile anfasst.
            return StackPhase(title: "Image",
                              state: .warning("kein eigener Build — Tag zeigt auf das Image des "
                                              + "Haupt-Repos (\(info.age))"),
                              repair: .build)
        }
        if let commit = lastCommitDate(worktreePath: worktreePath), let built = info.created,
           built < commit {
            return StackPhase(title: "Image",
                              state: .warning("älter als der letzte Commit (\(info.age))"),
                              repair: .build)
        }
        return StackPhase(title: "Image", state: .ok("\(info.age) · \(info.size)"), repair: .build)
    }

    /// Backend build: what `docker/build/Dockerfile.app` does with `composer install` and
    /// `php bin/console assets:install`.
    ///
    /// The **deployment** image bakes these in; the local image (`docker/build-local/Dockerfile`)
    /// does not — compose mounts the whole project over `/app`, so locally the same steps have to
    /// have run inside the worktree. `vendor/` and `public/bundles` are their artefacts.
    /// `composer install` — der erste der beiden Backend-Schritte aus `Dockerfile.app`.
    private func backendPhase(worktreePath: String, appRunning: Bool) -> StackPhase {
        let hasVendor = hasEntries(worktreePath, "vendor")
        return StackPhase(
            title: "Backend",
            state: hasVendor ? .ok("vendor/ vorhanden")
                             : .missing("vendor/ fehlt — composer lief nie"
                                        + (appRunning ? "" : " · fpm-Container nötig")),
            repair: appRunning ? .composer : (hasVendor ? nil : .start))
    }

    /// `php bin/console assets:install` — der zweite Backend-Schritt, eigene Zeile mit eigenem Knopf,
    /// damit er auch dann erreichbar bleibt, wenn `vendor/` längst steht.
    private func symfonyAssetsPhase(worktreePath: String, appRunning: Bool) -> StackPhase {
        let hasBundles = hasEntries(worktreePath, "public/bundles")
        return StackPhase(
            title: "↳ assets:install",
            state: hasBundles ? .ok("public/bundles vorhanden")
                              : .missing("public/bundles fehlt"
                                         + (appRunning ? "" : " · fpm-Container nötig")),
            repair: appRunning ? .symfonyAssets : (hasBundles ? nil : .start))
    }

    /// Frontend build of the app itself (`public/build`). The renderer sub-projects get their own
    /// rows, because each is built separately and one of them failing must not hide the others.
    private func frontendPhase(worktreePath: String, appRunning: Bool) -> StackPhase {
        guard !hasEntries(worktreePath, "public/build") else {
            return StackPhase(title: "Frontend", state: .ok("public/build vorhanden"),
                              repair: appRunning ? .frontend : nil)
        }
        return StackPhase(title: "Frontend",
                          state: .missing("public/build leer"
                                          + (appRunning ? "" : " · braucht laufenden fpm-Container")),
                          repair: appRunning ? .frontend : .start)
    }

    /// Vite dev server with hot module replacement, detected by **its own process** inside the fpm
    /// container.
    ///
    /// Not by `yarn dev`: that wrapper is only there when the server was started through yarn and
    /// the shell stayed alive. A worktree can very well run `node_modules/.bin/vite` with no `yarn`
    /// parent left (observed on even-3602), and looking for the wrapper then reports "not started"
    /// while HMR is serving. The bracket in `[n]ode_modules` keeps `pgrep` from matching the shell
    /// that carries the pattern itself.
    private func vitePhase(name: String, appRunning: Bool) -> StackPhase {
        guard appRunning else {
            return StackPhase(title: "Vite/HMR", state: .missing("fpm-Container nötig"), repair: .start)
        }
        let output = run(["exec", "\(name)-fpm", "sh", "-c",
                          "pgrep -f '[n]ode_modules/.bin/vite' >/dev/null && echo running || echo stopped"])
        let running = output.contains("running")
        return running
            ? StackPhase(title: "Vite/HMR", state: .ok("läuft — HMR aktiv"), repair: .viteStop)
            : StackPhase(title: "Vite/HMR", state: .missing("nicht gestartet"), repair: .viteStart)
    }

    /// One row per renderer sub-project that exists in the worktree, each with its own build button.
    private func rendererPhases(worktreePath: String, appRunning: Bool) -> [StackPhase] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: worktreePath)) ?? []
        let renderers = entries.filter { name in
            name.hasSuffix("-renderer")
                && fm.fileExists(atPath: (worktreePath as NSString)
                    .appendingPathComponent(name + "/package.json"))
        }.sorted()

        return renderers.map { renderer in
            let built = hasEntries(worktreePath, "\(renderer)/build")
            let title = renderer.replacingOccurrences(of: "teilnachweis-", with: "")
            return StackPhase(
                title: "↳ " + title,
                state: built ? .ok("build/ vorhanden")
                             : .missing("nicht gebaut" + (appRunning ? "" : " · fpm-Container nötig")),
                repair: appRunning ? .frontendSub(renderer) : (built ? nil : .start))
        }
    }

    /// True when the directory exists and holds something other than dotfiles — an empty `build/`
    /// left behind by a cleanup is not a build.
    private func hasEntries(_ worktreePath: String, _ subdirectory: String) -> Bool {
        let path = (worktreePath as NSString).appendingPathComponent(subdirectory)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return entries.contains { !$0.hasPrefix(".") }
    }

    private struct ImageInfo {
        let id: String
        let age: String
        let size: String
        let created: Date?
    }

    private func imageInfo(_ tag: String) -> ImageInfo? {
        let output = run(["images", tag, "--format", "{{.ID}}\t{{.CreatedSince}}\t{{.Size}}\t{{.CreatedAt}}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = output.components(separatedBy: "\t")
        guard parts.count >= 3, !parts[0].isEmpty else { return nil }
        return ImageInfo(id: parts[0], age: parts[1], size: parts[2],
                         created: parts.count >= 4 ? Self.dockerDate(parts[3]) : nil)
    }

    /// `2026-08-06 21:47:18 +0200 CEST` — docker's own `CreatedAt` format.
    static func dockerDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        // Trim the trailing zone name ("CEST"), which the format above does not cover.
        let trimmed = text.components(separatedBy: " ").prefix(4).joined(separator: " ")
        return formatter.date(from: trimmed)
    }

    private func lastCommitDate(worktreePath: String) -> Date? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", worktreePath, "log", "-1", "--format=%ct"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let seconds = TimeInterval(String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func seedPhase(worktreePath: String, dbInitDir: String) -> StackPhase {
        let dir = (worktreePath as NSString).appendingPathComponent(dbInitDir)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        guard let dump = files.first(where: { $0.hasSuffix(".sql") || $0.hasSuffix(".sql.gz") }) else {
            return StackPhase(title: "DB-Seed", state: .missing("kein Dump bereitgestellt"),
                              repair: .seedStage)
        }
        let path = (dir as NSString).appendingPathComponent(dump)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let age = (attributes?[.modificationDate] as? Date).map(Self.relativeAge) ?? ""
        return StackPhase(title: "DB-Seed", state: .ok("\(dump) · \(Self.bytes(size))\(age)"),
                          repair: .seedStage)
    }

    /// Direct import into the running database — only offered once the stack actually has a `db`
    /// container, since `iwf db import` / `--import` talk to a live service.
    private func importPhase(services: [StackService]) -> StackPhase? {
        guard let db = services.first(where: { $0.name == "db" }) else { return nil }
        return db.isRunning
            ? StackPhase(title: "DB-Import", state: .ok("db läuft — Direktimport möglich"),
                         repair: .seedImport)
            : StackPhase(title: "DB-Import", state: .missing("db-Container gestoppt"), repair: .start)
    }

    private func volumePhase(name: String) -> StackPhase {
        let volume = "\(name)_dbdata"
        let output = run(["volume", "ls", "--format", "{{.Name}}"])
        let exists = output.components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespaces) == volume }
        // A staged dump only imports into an *empty* volume — so an existing volume means the seed
        // will NOT be re-read on the next start.
        return exists
            ? StackPhase(title: "DB-Volume", state: .ok("\(volume) — Seed wird nicht neu importiert"))
            : StackPhase(title: "DB-Volume", state: .missing("noch keins — Seed importiert beim Start"))
    }

    private func containerPhase(services: [StackService]) -> StackPhase {
        guard !services.isEmpty else {
            return StackPhase(title: "Container", state: .missing("Stack nie gestartet"), repair: .start)
        }
        let running = services.filter(\.isRunning).count
        let failed = services.filter { !$0.isRunning && $0.isFailed }
        if !failed.isEmpty {
            let names = failed.map(\.name).joined(separator: ", ")
            return StackPhase(title: "Container",
                              state: .warning("\(running)/\(services.count) laufen · fehlgeschlagen: \(names)"),
                              repair: .restart)
        }
        if running == 0 {
            return StackPhase(title: "Container", state: .missing("gestoppt (0/\(services.count))"), repair: .start)
        }
        return StackPhase(title: "Container", state: .ok("\(running)/\(services.count) laufen"),
                          repair: .restart)
    }

    // MARK: - Helpers

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    static func relativeAge(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86400)
        if days >= 1 { return " · \(days) T alt" }
        let hours = Int(Date().timeIntervalSince(date) / 3600)
        return hours >= 1 ? " · \(hours) h alt" : " · frisch"
    }

    /// Runs `docker` and returns its combined output. Fail-open: no docker → empty string, which the
    /// phases read as "nothing there".
    private func run(_ args: [String]) -> String {
        for path in ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"] {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do { try process.run() } catch { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        return ""
    }
}
