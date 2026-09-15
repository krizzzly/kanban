import Foundation

/// Welcher Stack gemeint ist — der eines Ticket-Worktrees oder der des Haupt-Repos.
///
/// Beide werden identisch **abgeleitet** (`DockerStatusScanner` bekommt schlicht den anderen Pfad;
/// der Stack-Name ist so oder so der Ordnername). Sie unterscheiden sich nur darin, wie man sie
/// bedient — und darin, was man **nicht** anbieten darf: `iwf stack destroy` aus dem Haupt-Repo
/// nähme wegen des Substring-Filters jedes `local/<projekt>-*`-Image mit, und ein DB-Seed träfe die
/// Haupt-Entwicklungsdatenbank.
public enum StackTarget: String, Sendable, CaseIterable {
    case worktree
    case maintree

    /// Ob dieser Stack zerstörende Eingriffe anbieten darf (Destroy, DB-Seed).
    public var allowsDestructiveActions: Bool { self == .worktree }
}

/// One container of a worktree stack, as `docker ps -a` reports it.
public struct StackService: Sendable, Hashable, Identifiable {
    public enum Health: Sendable, Hashable { case healthy, unhealthy, starting, none }

    /// Service name without the stack prefix (`even-3602-nginx` → `nginx`).
    public let name: String
    /// Full container name.
    public let container: String
    /// docker's own state: running / exited / created / restarting / paused / dead.
    public let state: String
    /// Human status line (`Up 13 minutes`, `Exited (134) 10 hours ago`).
    public let status: String
    /// Exit code for a stopped container — the piece that makes a silent failure visible.
    public let exitCode: Int?
    public let health: Health

    public var id: String { container }
    public var isRunning: Bool { state == "running" }
    /// A container that stopped with a non-zero code — broken, not merely stopped.
    public var isFailed: Bool { (exitCode ?? 0) != 0 }
    /// One-shot helpers (`*-setup`) are expected to exit; only a non-zero code is a problem.
    public var isOneShot: Bool { name.hasSuffix("-setup") || name.hasSuffix("-init") }

    public init(name: String, container: String, state: String, status: String,
                exitCode: Int?, health: Health) {
        self.name = name
        self.container = container
        self.state = state
        self.status = status
        self.exitCode = exitCode
        self.health = health
    }
}

/// A phase of the stack pipeline and whether its artefact is there. Derived from Docker and the file
/// system — never from what a log or a task file once claimed.
public struct StackPhase: Sendable, Hashable, Identifiable {
    public enum State: Sendable, Hashable {
        case ok(String)        // detail, e.g. "vor 12 h · 1.51 GB"
        case missing(String)   // what is missing, in words
        case warning(String)
        case unknown
    }

    /// The `iwf` command that repairs this phase — offered as a button on the row itself, so the fix
    /// sits where the problem is stated instead of in a manual somewhere.
    public enum Repair: Sendable, Hashable {
        case build          // iwf stack build
        case cert           // iwf cert create
        case composer       // iwf composer install
        case symfonyAssets  // php bin/console assets:install
        case frontend       // iwf yarn build (App)
        /// `yarn build` in einem Unterprojekt (`teilnachweis-*-renderer`) — dieselben Schritte wie
        /// `Dockerfile.app`, das dort `cd <dir> && yarn install && yarn build` ausführt.
        case frontendSub(String)
        /// Vite-Dev-Server mit HMR starten. Läuft dauerhaft — der Aufrufer darf nicht auf das Ende
        /// warten, sonst blockiert die UI bis zum Abschuss.
        case viteStart
        case viteStop
        case start          // iwf worktree start
        case restart        // iwf worktree restart (re-runs the postStart hooks)
        /// Dump holen und im Init-Ordner ablegen (Import beim nächsten Start). Braucht eine Quelle,
        /// wird deshalb als Menü angeboten, nicht als einfacher Knopf.
        case seedStage
        /// Dump direkt in die laufende DB importieren.
        case seedImport

        /// Der Befehl selbst ist die Beschriftung — so steht auf dem Knopf, was er ausführt, und
        /// Label und Aktion können nicht auseinanderlaufen.
        public var label: String {
            switch self {
            case .seedStage: return "Bereitstellen"
            case .viteStop: return "Dev-Server stoppen"
            case .seedImport: return "Importieren"
            default: return "iwf " + arguments.joined(separator: " ")
            }
        }

        /// True für die beiden Seed-Aktionen, die erst noch eine Quelle brauchen (dev/qa/prod/Datei).
        /// Dauerläufer: starten und nicht auf das Ende warten.
        public var isLongRunning: Bool { self == .viteStart }

        public var needsSource: Bool {
            if case .seedStage = self { return true }
            if case .seedImport = self { return true }
            return false
        }

        /// The `iwf` invocations this repair runs, in order — stopping at the first failure.
        ///
        /// A chain, not a single command, because `Dockerfile.app` needs one too: a renderer is built
        /// with `yarn install --production=false && yarn build`. The image throws its `node_modules`
        /// away afterwards (`rm -rf node_modules`), so in a worktree they are simply absent and a bare
        /// `yarn build` dies with `vite: not found`.
        /// Für welchen Stack die Reparatur gilt. Der Unterschied ist genau **einer**: ein Worktree
        /// wird über `iwf worktree start|restart` hoch- und runtergefahren (iwf findet ihn über
        /// seine Nummer), das Haupt-Repo über `iwf stack start|restart` im eigenen Verzeichnis.
        /// Alles andere — build, cert, composer, yarn, vite — ist wortgleich, es läuft ohnehin
        /// relativ zum cwd. Gegen `iwf stack --help` geprüft (build/destroy/logs/ps/restart/start/
        /// stop/update).
        public func commands(for target: StackTarget) -> [[String]] {
            switch (self, target) {
            case (.start, .maintree): return [["stack", "start"]]
            case (.restart, .maintree): return [["stack", "restart"]]
            default: return commands
            }
        }

        public var commands: [[String]] {
            switch self {
            case .build: return [["stack", "build"]]
            case .cert: return [["cert", "create"]]
            case .composer: return [["composer", "install"]]
            case .symfonyAssets: return [["symfony", "console", "assets:install"]]
            case .frontend: return [["yarn", "install", "--production=false"], ["yarn", "build"]]
            case .frontendSub(let directory):
                return [["yarn", "--cwd", directory, "install", "--production=false"],
                        ["yarn", "--cwd", directory, "build"]]
            case .viteStart: return [["yarn", "dev"]]
            // Zwei Fallen, die ein blosses `pkill -f yarn` stellt:
            //  1. Die ausführende Shell heisst selbst `sh -c "pkill -f yarn"`, enthält also das
            //     Muster — pkill erschiesst sich selbst und liefert Exit 143.
            //  2. Der eigentliche Server ist `node .bin/vite`; seine Kommandozeile enthält kein
            //     „yarn". Wurde er ohne yarn-Wrapper gestartet, überlebt er das pkill unbeschadet.
            // Deshalb: Klammer-Muster gegen den Selbsttreffer, alle drei Prozessarten, `exit 0`.
            case .viteStop:
                return [["run", "pkill -f '[n]ode_modules/.bin/vite'; pkill -f '[c]ross-env'; "
                                + "pkill -f '[y]arn dev'; exit 0"]]
            case .start: return [["worktree", "start"]]
            case .restart: return [["worktree", "restart"]]
            case .seedStage, .seedImport: return []   // laufen über StackSeeder, nicht über iwf
            }
        }

        /// Kurzform für Beschriftung und Tooltip — bei Ketten der letzte, sprechende Schritt.
        public var arguments: [String] { commands.last ?? [] }
    }

    public let title: String
    public let state: State
    public let repair: Repair?
    public var id: String { title }

    public init(title: String, state: State, repair: Repair? = nil) {
        self.title = title
        self.state = state
        self.repair = repair
    }

    public var isOK: Bool { if case .ok = state { return true }; return false }
}

/// The full derived state of one worktree stack.
public struct WorktreeStackStatus: Sendable, Hashable {
    /// Stack name = the worktree directory name (`even-3602`), which is also the container prefix
    /// and the image tag.
    public let name: String
    public let phases: [StackPhase]
    public let services: [StackService]

    public init(name: String, phases: [StackPhase], services: [StackService]) {
        self.name = name
        self.phases = phases
        self.services = services
    }

    public var running: [StackService] { services.filter(\.isRunning) }
    /// Containers that stopped with a non-zero exit code — what today's raw `stack ps` text buries.
    public var failed: [StackService] { services.filter { !$0.isRunning && $0.isFailed } }
    public var unhealthy: [StackService] { services.filter { $0.health == .unhealthy } }

    /// Short verdict for the badge.
    public enum Verdict: Sendable, Hashable { case notCreated, stopped, degraded, running }

    public var verdict: Verdict {
        if services.isEmpty { return .notCreated }
        if running.isEmpty { return .stopped }
        if !failed.isEmpty || !unhealthy.isEmpty { return .degraded }
        return .running
    }
}

/// Parsers for the docker output the scanner collects. Pure, so the shape of every line is pinned
/// down by tests rather than discovered in production.
public enum StackStatusParser {
    /// `name<TAB>state<TAB>status<TAB>compose-project` from `docker ps -a --format`.
    ///
    /// Die Zugehörigkeit entscheidet das **Compose-Label**, nicht der Name. Über den Namen ging es
    /// so lange gut, wie nur Worktrees verglichen wurden (`even-3602-` fängt kein `even-3518-`) —
    /// im Haupt-Repo heisst der Stack aber `even` und ist damit Präfix **jedes** Worktree-Stacks:
    /// `even-3602-db` bestand den Test und tauchte, um das Präfix gekürzt, als Dienst „3602-db" des
    /// Haupt-Repos auf. Das Label ist die Auskunft von Docker selbst und trennt sauber
    /// (`com.docker.compose.project` = `even` vs. `even-3602`).
    ///
    /// Zeilen ohne Label gehören keinem Compose-Projekt — also auch keinem Stack — und fallen weg.
    public static func services(from output: String, stackName: String) -> [StackService] {
        output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { return nil }
            let container = parts[0].trimmingCharacters(in: .whitespaces)
            guard parts[3].trimmingCharacters(in: .whitespaces) == stackName else { return nil }
            // Anzeigename ohne Stack-Präfix. Ein Container mit eigenem `container_name` trägt es
            // nicht — dann ist der volle Name der beste Name, den es gibt.
            let prefix = stackName + "-"
            let short = container.hasPrefix(prefix)
                ? String(container.dropFirst(prefix.count))
                : container
            let status = parts[2].trimmingCharacters(in: .whitespaces)
            return StackService(name: short,
                                container: container,
                                state: parts[1].trimmingCharacters(in: .whitespaces),
                                status: status,
                                exitCode: exitCode(in: status),
                                health: health(in: status))
        }
        .sorted { $0.name < $1.name }
    }

    /// `Exited (134) 10 hours ago` → 134. Nil while running.
    static func exitCode(in status: String) -> Int? {
        guard let open = status.range(of: "Exited (") else { return nil }
        let rest = status[open.upperBound...]
        guard let close = rest.firstIndex(of: ")") else { return nil }
        return Int(rest[..<close])
    }

    static func health(in status: String) -> StackService.Health {
        let lower = status.lowercased()
        if lower.contains("(unhealthy)") { return .unhealthy }
        if lower.contains("(healthy)") { return .healthy }
        if lower.contains("health: starting") { return .starting }
        return .none
    }
}

/// Die drei umkehrbaren Lebenszyklus-Aktionen, die ein Stack-Panel anbietet. Destroy steht
/// bewusst **nicht** hier — es ist kein Lebenszyklus, sondern ein Abriss, und für das Haupt-Repo
/// gar nicht erlaubt (siehe `StackTarget`).
public enum StackLifecycle: String, Sendable, CaseIterable {
    case start, stop, restart

    public var label: String {
        switch self {
        case .start: return "Start"
        case .stop: return "Stop"
        case .restart: return "Neustart"
        }
    }
}
