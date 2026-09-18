import Foundation

/// A single project resolved from the config, with everything the app needs precomputed.
public struct ProjectConfig: Identifiable, Sendable, Hashable {
    public let key: String                 // config key, e.g. "even"
    public let prefix: String              // Jira project prefix, e.g. "EVEN"
    public let jiraBaseUrl: String         // project baseUrl, falling back to the jira default
    public let tasksPathAbsolute: String   // absolute path to the task-file directory
    /// Absoluter Ordner der Projekt-Dokumentation (exportierte Confluence-Seiten). Immer gesetzt:
    /// ohne eigenen Eintrag gilt `~/Library/Application Support/Kanban/docs/<key>` — wie die
    /// Task-Files gehört Doku nicht ins Repo, sie wird dort ja nie mitcommittet.
    public let docsPathAbsolute: String
    /// Absoluter Ordner der Knowledgebase dieses Projekts — **nil, wenn keiner konfiguriert ist**.
    /// Anders als `docsPathAbsolute` gibt es hier bewusst keinen erfundenen Default: eine
    /// Knowledgebase ist eine Entscheidung, kein Nebenprodukt. Ohne Eintrag fehlt `kbPath` in
    /// `.claude/project.json`, und ein Skill weiss damit, dass es keine gibt.
    public let kbPathAbsolute: String?
    public let repoDir: String             // local git repo root (for `git worktree list`)
    /// Auf welcher Forge das Repo liegt und unter welchem Pfad — `applications/even` bei GitLab,
    /// `owner/repo` bei GitHub. **nil** heisst: keine Forge zugeordnet; dann bleibt das Board bei
    /// den lokalen Artefakten, genau wie früher ohne GitLab-Eintrag.
    public let forge: ForgeRef?
    /// Welcher Coding-Agent dieses Projekt bedient (`agent` in der Config, Default Claude).
    /// Entscheidet über Startbefehl, Asset-Ort und das Präfix, mit dem Kanban Commands tippt.
    public let agent: AgentKind
    /// Welches Skill-Set dieses Projekt sieht (`skillSet` in der Config) — **nil = Standard-Set**.
    /// Aufgelöst wird der Name erst gegen den Bestand (`ClaudeAssetStore.resolve`): ein Set, das es
    /// nicht mehr gibt, darf ein Projekt nicht ohne Skills dastehen lassen.
    public let skillSet: String?
    /// Bild und Farben der Kopfzeile. Im Regelfall `.none` — dann sieht die Zeile aus wie immer.
    public let appearance: ProjectAppearance
    /// Hängt dieses Projekt an Jira? `false` heisst: es gibt kein Board und keine Sprints, die
    /// Karten kommen ausschliesslich aus dem, was lokal existiert — also **nur freier Modus**.
    ///
    /// Der `prefix` bleibt auch dann gesetzt: er ist die Ticket-Nummerierung (Task-File-Namen,
    /// Branchnamen), nicht die Jira-Anbindung. Beides zu verwechseln hiesse, einem Projekt ohne
    /// Jira auch seine Task-Files zu nehmen.
    public let usesJira: Bool
    /// Hat dieses Projekt einen eigenen Docker-Stack? `false` heisst: Worktrees sind reine
    /// Git-Worktrees (`git worktree add`), es gibt kein `iwf`, keine Stack-Oberflaeche, keine
    /// Snapshots und keinen Stack-Sweep.
    ///
    /// Fehlt der Schluessel, gilt `true` — jedes bestehende Projekt bleibt damit unveraendert eine
    /// Web-Applikation mit Stack. Worktrees und Branches gibt es in **beiden** Faellen; abgeschaltet
    /// wird nur die Docker-Haelfte.
    public let usesDockerStack: Bool

    public var id: String { key }

    /// Der GitLab-Pfad, **wenn** das Projekt auf GitLab liegt. Für die Stellen, die es wörtlich so
    /// weitergeben — `.claude/project.json` führt den Schlüssel für die Übergangszeit weiter.
    public var gitlabProjectPath: String? {
        forge?.kind == .gitlab ? forge?.path : nil
    }

    public init(key: String, prefix: String, jiraBaseUrl: String, tasksPathAbsolute: String,
                docsPathAbsolute: String = "", kbPathAbsolute: String? = nil,
                repoDir: String, forge: ForgeRef?,
                agent: AgentKind = .claude,
                skillSet: String? = nil,
                appearance: ProjectAppearance = .none,
                usesJira: Bool = true,
                usesDockerStack: Bool = true) {
        self.key = key
        self.prefix = prefix
        self.jiraBaseUrl = jiraBaseUrl
        self.tasksPathAbsolute = tasksPathAbsolute
        self.docsPathAbsolute = docsPathAbsolute
        self.kbPathAbsolute = kbPathAbsolute
        self.repoDir = repoDir
        self.forge = forge
        self.agent = agent
        self.skillSet = skillSet
        self.appearance = appearance
        self.usesJira = usesJira
        self.usesDockerStack = usesDockerStack
    }
}

/// Everything the app needs from its config, resolved and validated.
///
/// The shape mirrors Hermes' (`modules.<name>.…`) on purpose — Kanban grew out of it, the adoption
/// (`HermesImport`) is then a plain value copy, and anyone who knows one file knows the other. What
/// changed is **ownership**: this is read from Kanban's own config, and Hermes is optional.
public struct AppConfig: Sendable {
    public let basePath: String
    public let jiraEmail: String
    public let jiraApiToken: String
    public let jiraDefaultBaseUrl: String
    public let gitlabBaseUrl: String?
    public let gitlabApiToken: String?
    /// GitHubs **API**-Basis. Leer = `https://api.github.com`; bei GitHub Enterprise steht hier
    /// `https://<host>/api/v3`, und die Web-Adressen werden daraus abgeleitet (`githubWebBaseUrl`).
    public let githubBaseUrl: String?
    public let githubApiToken: String?
    public let projects: [ProjectConfig]
    /// Der Session-Watchdog (`watchdog.*`) — aus, solange niemand ihn einschaltet.
    public let watchdog: WatchdogSettings

    /// Das Skill-Set für alles, was keins gewählt hat (`claude.defaultSkillSet`). Fehlt der
    /// Eintrag, gilt das einzige vorhandene Set — bei mehreren entscheidet der Sets-Ordner
    /// (`ClaudeAssetStore.defaultSet`), und die Übersicht sagt, dass hier nichts bestimmt ist.
    public let defaultSkillSet: String?

    /// Die einzeln registrierten Skill-Sets (`claude.sets.<name>.path`) — Name plus Ordner, und der
    /// Ordner darf überall liegen. Das ist der Normalfall: ein Set ist nichts als ein Ordner mit
    /// `skills/` und/oder `rules/`, den jemand angelegt hat.
    public let skillSets: [SkillSetEntry]

    /// Sammelordner für Sets, die **nicht** einzeln registriert sind (`claude.setsPath`). Nur noch
    /// Rückfallebene: wer mehrere Sets nebeneinander liegen hat, muss sie nicht einzeln eintragen.
    public let skillSetsPath: String

    /// Ein registriertes Set, wie es in der Config steht.
    public struct SkillSetEntry: Sendable, Hashable, Identifiable {
        public let name: String
        public let path: String    // absolut, aufgelöst
        public var id: String { name }

        public init(name: String, path: String) {
            self.name = name
            self.path = path
        }

        /// Name und Ordner zusammen mit dem, was die `set.json` des Ordners sagt.
        public var asset: ClaudeAssetSet {
            ClaudeAssetStore.describe(name: name, at: URL(fileURLWithPath: path))
        }
    }

    /// `.claude/project.json` im Commit-Fenster vorab abwählen (`commit.excludeClaudeProjectFile`).
    /// Vorgabe **an**: die Datei erzeugt Kanban selbst, und wo `.claude/` nicht gitignored ist
    /// (hier: `core`) stünde sie sonst in jedem Commit.
    public let excludeClaudeProjectFileFromCommit: Bool

    /// Der Pfad, den dieser Schalter meint — relativ zum Repo-Wurzelverzeichnis, wie `git status`
    /// ihn meldet.
    public static let claudeProjectFilePath = ".claude/project.json"

    /// A config that has never been filled in — what a fresh install starts from.
    public static let empty = AppConfig(basePath: ("~/code" as NSString).expandingTildeInPath,
                                        jiraEmail: "", jiraApiToken: "", jiraDefaultBaseUrl: "",
                                        gitlabBaseUrl: nil, gitlabApiToken: nil,
                                        githubBaseUrl: nil, githubApiToken: nil, projects: [],
                                        watchdog: WatchdogSettings(),
                                        defaultSkillSet: nil,
                                        skillSets: [],
                                        skillSetsPath: ClaudeAssetStore
                                            .defaultSetsRoot(basePath: ("~/code" as NSString)
                                                .expandingTildeInPath).path,
                                        excludeClaudeProjectFileFromCommit: true)

    public var hasJira: Bool {
        !jiraEmail.isEmpty && !jiraApiToken.isEmpty && !jiraDefaultBaseUrl.isEmpty
    }

    public var hasGitlab: Bool { gitlabBaseUrl != nil && (gitlabApiToken?.isEmpty == false) }
    public var gitlabApiUrl: String? { gitlabBaseUrl.map { "\($0)/api/v4" } }

    /// Anders als bei GitLab reicht das **Token** — die Base-URL hat eine sinnvolle Vorgabe, und
    /// niemand soll `https://api.github.com` abtippen müssen, um GitHub zu benutzen.
    public var hasGithub: Bool { githubApiToken?.isEmpty == false }

    public var githubApiUrl: String {
        let configured = githubBaseUrl?.trimmingCharacters(in: .whitespaces) ?? ""
        return configured.isEmpty ? GitHubClient.defaultApiBaseUrl : configured
    }

    /// Die Web-Basis für Branch- und PR-Links (`https://github.com`), abgeleitet aus der API-Basis.
    public var githubWebBaseUrl: String { GitHubClient.webBaseURL(forApiBase: githubApiUrl) }

    /// Die Web-Basis der Forge eines Projekts — was `ForgeLocation` braucht.
    public func webBaseUrl(for kind: ForgeKind) -> String? {
        switch kind {
        case .gitlab: return gitlabBaseUrl
        case .github: return githubWebBaseUrl
        }
    }

    /// Plattform, Web-Basis und Pfad eines Projekts in einem Wert — nil, wenn dem Projekt keine
    /// Forge zugeordnet ist oder deren Basis fehlt.
    public func forgeLocation(for project: ProjectConfig?) -> ForgeLocation? {
        guard let forge = project?.forge else { return nil }
        return ForgeLocation(kind: forge.kind, webBaseUrl: webBaseUrl(for: forge.kind),
                             projectPath: forge.path)
    }

    /// Whether the app can show a board at all. Deliberately **not** an error state: a fresh install
    /// has no credentials and no projects, and lands on the setup screen instead of a red triangle.
    public var isConfigured: Bool { hasJira && !projects.isEmpty }
}

public enum KanbanConfigError: Error, LocalizedError {
    case decode(String)
    /// Ein Projekt steht in **beiden** Forge-Abschnitten. Kein Raten: welche der beiden gemeint
    /// ist, weiss nur der Mensch, und die falsche Wahl zeigte stillschweigend fremde Requests.
    case ambiguousForge(project: String)

    public var errorDescription: String? {
        switch self {
        case .decode(let m): return "Kanban-Config konnte nicht gelesen werden: \(m)"
        case .ambiguousForge(let project):
            return "Projekt „\(project)“ steht sowohl unter modules.gitlab.projects als auch unter "
                 + "modules.github.projects. Ein Projekt liegt auf einer Forge — bitte den "
                 + "falschen Eintrag entfernen."
        }
    }
}

/// Reads `~/Library/Application Support/Kanban/config.json` — Kanban's **own** config and the single
/// source of truth for the Jira and GitLab modules.
///
/// A missing file is not an error: the app is usable without Hermes and without any config, it just
/// opens its setup screen. Only a file that exists and is not valid JSON throws — that one is worth
/// a message, because silently ignoring it would look like data loss.
public enum KanbanConfig {
    public static var fileURL: URL {
        try? FileManager.default.createDirectory(at: KanbanPaths.root,
                                                 withIntermediateDirectories: true)
        return KanbanPaths.configFile
    }

    public static var path: String { fileURL.path }

    /// Der Datenordner des **aktiven Profils** — reine Pfad-Rechnung, legt nichts an (anders als
    /// `fileURL`, das die Config schreiben können muss). Woher er kommt, sagt `KanbanPaths`.
    public static var supportDirectory: String { KanbanPaths.root.path }

    /// Wo die Doku eines Projekts liegt, das keinen eigenen Pfad nennt: `<support>/docs/<key>`.
    /// Gegenstück zu `<support>/tasks/<…>` — beides gehört Kanban, nicht dem Repo.
    public static var docsRoot: String { KanbanPaths.docsRoot.path }

    public static func load(path: String? = nil) throws -> AppConfig {
        let resolved = path ?? Self.path
        guard FileManager.default.fileExists(atPath: resolved) else { return .empty }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: resolved)) }
        catch { throw KanbanConfigError.decode(error.localizedDescription) }
        return try resolve(data)
    }

    /// Decodes and resolves a config from raw JSON — filesystem-free, so it is unit-testable.
    /// `docsRoot` ist injizierbar, damit der Default-Ordner im Test nicht am Home der Maschine hängt.
    public static func resolve(_ data: Data, docsRoot: String = KanbanConfig.docsRoot) throws -> AppConfig {
        let raw: RawConfig
        do { raw = try JSONDecoder().decode(RawConfig.self, from: data) }
        catch { throw KanbanConfigError.decode(error.localizedDescription) }

        let basePathExpanded = expand(raw.basePath ?? "~/code")
        let jira = raw.modules?.jira
        let gitlab = raw.modules?.gitlab
        let github = raw.modules?.github
        let confluence = raw.modules?.confluence
        let knowledgebase = raw.modules?.knowledgebase
        let docker = raw.modules?.docker
        let appearance = raw.appearance

        // **Vor** dem Aufbau der Projektliste: ein Projekt, das in beiden Forge-Abschnitten steht,
        // ist ein Konfigurationsfehler. Geprüft wird über die Vereinigung beider Abschnitte, nicht
        // nur über die Jira-Projekte — sonst bliebe ein Widerspruch in einem Key ohne Jira stehen,
        // bis ihn jemand dort einträgt.
        try assertSingleForge(gitlab: gitlab?.projects, github: github?.projects)

        var projects: [ProjectConfig] = []
        for (key, p) in (jira?.projects ?? [:]) {
            guard let prefix = p.prefix, let tasksPath = p.tasksPath else { continue }
            let tasksAbsolute = resolve(tasksPath, against: basePathExpanded)
            // Eigener `repoDir` je Projekt (HERMES-034): entkoppelt das Repo vom Tasks-Pfad, damit
            // die Task-Files umziehen können. Ohne Override gilt die bisherige Ableitung.
            let firstSegment = tasksPath.split(separator: "/").first.map(String.init) ?? key
            let repoDir = p.repoDir.map { resolve($0, against: basePathExpanded) }
                ?? (basePathExpanded as NSString).appendingPathComponent(firstSegment)
            // Doku-Ordner: der Confluence-Eintrag desselben Projekt-Keys, sonst der Default unter
            // Application Support. Derselbe Wert steuert (über `HermesSync`) auch, wohin Hermes'
            // `generate-confluence-page` schreibt — ein Ort, keine zwei Wahrheiten.
            let docsAbsolute = confluence?.projects?[key]?.path
                .map { resolve($0, against: basePathExpanded) }
                ?? (docsRoot as NSString).appendingPathComponent(key)
            let kbAbsolute = knowledgebase?.projects?[key]?.path
                .flatMap { $0.isEmpty ? nil : $0 }
                .map { resolve($0, against: basePathExpanded) }
            projects.append(ProjectConfig(
                key: key,
                prefix: prefix,
                jiraBaseUrl: p.baseUrl ?? jira?.baseUrl ?? "",
                tasksPathAbsolute: tasksAbsolute,
                docsPathAbsolute: docsAbsolute,
                kbPathAbsolute: kbAbsolute,
                repoDir: repoDir,
                forge: try forge(for: key, gitlab: gitlab?.projects?[key]?.path,
                                 github: github?.projects?[key]?.path),
                agent: AgentKind(configValue: p.agent) ?? .fallback,
                // Wie `agent` tolerant gelesen: der Name wird erst gegen den Bestand aufgelöst,
                // ein Tippfehler macht ein Projekt also nicht unbenutzbar.
                skillSet: trimmedOrNil(p.skillSet),
                // Fehlt der Abschnitt ganz (der Normalfall), kommt `.none` heraus — kein Bild,
                // keine Farben, Kopfzeile wie immer.
                appearance: appearanceFor(key, appearance),
                // Fehlt der Schlüssel, ist es ein Jira-Projekt — alles Bestehende bleibt, wie es war.
                usesJira: p.useJira ?? true,
                // Der Stack steht in der **eigenen** Sektion, nicht im Jira-Eintrag: er hat mit
                // Jira nichts zu tun. Ohne Eintrag ist es eine Web-Applikation mit Docker-Stack.
                usesDockerStack: docker?.projects?[key]?.stack ?? true
            ))
        }
        projects.sort { $0.key < $1.key }

        return AppConfig(
            basePath: basePathExpanded,
            jiraEmail: jira?.email ?? "",
            jiraApiToken: jira?.apiToken ?? "",
            jiraDefaultBaseUrl: jira?.baseUrl ?? "",
            gitlabBaseUrl: gitlab?.baseUrl,
            gitlabApiToken: gitlab?.apiToken,
            githubBaseUrl: github?.baseUrl,
            githubApiToken: github?.apiToken,
            projects: projects,
            watchdog: watchdogSettings(raw.watchdog),
            defaultSkillSet: trimmedOrNil(raw.claude?.defaultSkillSet),
            skillSets: (raw.claude?.sets ?? [:]).compactMap { name, eintrag in
                guard let pfad = trimmedOrNil(eintrag.path) else { return nil }
                return AppConfig.SkillSetEntry(name: name,
                                               path: resolve(pfad, against: basePathExpanded))
            }.sorted { $0.name < $1.name },
            skillSetsPath: trimmedOrNil(raw.claude?.setsPath)
                .map { resolve($0, against: basePathExpanded) }
                ?? ClaudeAssetStore.defaultSetsRoot(basePath: basePathExpanded).path,
            excludeClaudeProjectFileFromCommit: raw.commit?.excludeClaudeProjectFile ?? true
        )
    }

    /// Wirft beim ersten Projekt, das in beiden Forge-Abschnitten mit nicht-leerem Pfad steht.
    /// Sortiert, damit dieselbe Config immer denselben Namen meldet.
    private static func assertSingleForge(gitlab: [String: RawGitlabProject]?,
                                          github: [String: RawGithubProject]?) throws {
        func filled(_ path: String?) -> Bool {
            !(path?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty
        }
        for key in (gitlab ?? [:]).keys.sorted() where filled(gitlab?[key]?.path) {
            if filled(github?[key]?.path) { throw KanbanConfigError.ambiguousForge(project: key) }
        }
    }

    /// Die Forge-Zuordnung eines Projekts aus den beiden Abschnitten. Ein leerer Pfad zählt als
    /// „nicht gesetzt" — ein GitLab-Eintrag mit leerem `path` wäre später eine Abfrage gegen das
    /// Projekt „" (siehe `ProjectRecord.strippingEmptyModules`).
    static func forge(for key: String, gitlab: String?, github: String?) throws -> ForgeRef? {
        let gitlabPath = gitlab?.trimmingCharacters(in: .whitespaces) ?? ""
        let githubPath = github?.trimmingCharacters(in: .whitespaces) ?? ""
        switch (gitlabPath.isEmpty, githubPath.isEmpty) {
        case (false, false): throw KanbanConfigError.ambiguousForge(project: key)
        case (false, true): return ForgeRef(kind: .gitlab, path: gitlabPath)
        case (true, false): return ForgeRef(kind: .github, path: githubPath)
        case (true, true): return nil
        }
    }

    /// Bild und Farben eines Projekts aus `appearance.projects.<key>`. Der Bildpfad wird **nicht**
    /// gegen `basePath` aufgelöst: er zeigt immer in Kanbans eigenen `images/`-Ordner, weil das Bild
    /// beim Auswählen dorthin kopiert wurde (siehe `ProjectImageStore`).
    static func appearanceFor(_ key: String, _ raw: RawAppearance?) -> ProjectAppearance {
        guard let entry = raw?.projects?[key] else { return .none }
        return ProjectAppearance.make(imagePath: entry.image,
                                      background: entry.headerBackground,
                                      foreground: entry.headerForeground,
                                      borderColor: entry.headerBorderColor,
                                      borderWidth: entry.headerBorderWidth)
    }

    /// Die Zahlenfelder stehen als Text in der Config, weil der Settings-Editor nur Text, Wahrheits-
    /// werte und Auswahllisten kennt. Unlesbares fällt still auf die Vorgabe zurück — eine kaputte
    /// Zahl darf den Watchdog nicht anders einstellen, als der Benutzer denkt, aber auch nicht die
    /// ganze Config zu Fall bringen.
    static func watchdogSettings(_ raw: RawWatchdog?) -> WatchdogSettings {
        let vorgabe = WatchdogSettings()
        guard let raw else { return vorgabe }
        func zahl(_ text: String?, _ fallback: Int, min untergrenze: Int, max obergrenze: Int) -> Int {
            guard let text, let wert = Int(text.trimmingCharacters(in: .whitespaces)) else { return fallback }
            return Swift.min(Swift.max(wert, untergrenze), obergrenze)
        }
        let modell = raw.model?.trimmingCharacters(in: .whitespaces)
        return WatchdogSettings(
            aktiv: raw.enabled ?? false,
            intervallMinuten: zahl(raw.intervalMinutes, vorgabe.intervallMinuten, min: 5, max: 1440),
            rueckblickStunden: zahl(raw.lookbackHours, vorgabe.rueckblickStunden, min: 1, max: 720),
            maxSessions: zahl(raw.maxSessions, vorgabe.maxSessions, min: 1, max: 200),
            minSignale: zahl(raw.minSignals, vorgabe.minSignale, min: 1, max: 100),
            modell: (modell?.isEmpty ?? true) ? vorgabe.modell : modell!,
            // Untergrenze 60 s: darunter schlägt das Limit garantiert zu, bevor irgendein Lauf
            // fertig ist — gemessen braucht einer hier 5½ bis 6 Minuten.
            timeoutSekunden: zahl(raw.timeoutSeconds, vorgabe.timeoutSekunden, min: 60, max: 3600))
    }

    /// Ein leerer Eintrag ist keiner: in der Config steht ein Feld oft nur deshalb da, weil der
    /// Einstellungs-Editor es einmal angelegt hat.
    private static func trimmedOrNil(_ text: String?) -> String? {
        let wert = text?.trimmingCharacters(in: .whitespaces) ?? ""
        return wert.isEmpty ? nil : wert
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Absolut oder `~…` bleibt, alles andere ist relativ zum Basis-Pfad. Normalisiert am Ende
    /// (`standardizingPath`): ein Pfad wie `../Library/…` — die Form, die Hermes' `path.join`
    /// braucht — stünde sonst als `/Users/…/code/../Library/…` im UI und in `.claude/project.json`.
    private static func resolve(_ path: String, against basePath: String) -> String {
        let expanded = expand(path)
        let joined = expanded.hasPrefix("/") ? expanded
            : (basePath as NSString).appendingPathComponent(expanded)
        return (joined as NSString).standardizingPath
    }
}

// MARK: - Raw decoding shapes

private struct RawConfig: Decodable {
    let basePath: String?
    let commit: RawCommit?
    /// Kanban-eigener Abschnitt wie `commit` und `watchdog` — bisher nur das Standard-Skill-Set.
    let claude: RawClaude?
    let modules: RawModules?
    /// Wie `commit` ein Kanban-eigener Abschnitt, kein Hermes-Modul — steht deshalb nicht in
    /// `ProjectProjection.moduleNames` und wandert nie in Hermes' Config.
    let watchdog: RawWatchdog?
    /// Bild und Kopfzeilenfarben je Projekt. Ebenfalls Kanban-eigen: Hermes hat keine Oberfläche,
    /// der Abschnitt hätte dort nichts zu suchen.
    let appearance: RawAppearance?
}

struct RawAppearance: Decodable {
    let projects: [String: RawAppearanceProject]?
}

/// Alle Felder optional — „gar nichts definiert" ist der Normalfall und muss es bleiben.
struct RawAppearanceProject: Decodable {
    let image: String?
    let headerBackground: String?
    let headerForeground: String?
    let headerBorderColor: String?
    /// Als Text, wie die Zahlen des Watchdogs — der Einstellungs-Editor schreibt nur Strings.
    let headerBorderWidth: String?
}

struct RawWatchdog: Decodable {
    let enabled: Bool?
    let intervalMinutes: String?
    let lookbackHours: String?
    let maxSessions: String?
    let minSignals: String?
    let model: String?
    let timeoutSeconds: String?
}

/// `commit` — Kanban-eigener Abschnitt, kein Hermes-Modul. Steht deshalb nicht in
/// `ProjectProjection.moduleNames` und wandert nie in Hermes' Config.
private struct RawCommit: Decodable {
    let excludeClaudeProjectFile: Bool?
}

/// `claude` — ebenfalls Kanban-eigen: wo die Skill-Sets liegen und welches gilt, wo keins gewählt
/// ist.
private struct RawClaude: Decodable {
    let defaultSkillSet: String?
    let setsPath: String?
    /// Name → Ordner. Die Registrierung ist ausdrücklich, deshalb ein Objekt und keine Liste: der
    /// Schlüssel **ist** der Name, unter dem ein Projekt das Set wählt.
    let sets: [String: RawClaudeSet]?
}

private struct RawClaudeSet: Decodable {
    let path: String?
}

private struct RawModules: Decodable {
    let jira: RawJira?
    let gitlab: RawGitlab?
    /// Die zweite Forge. Gleiche Form wie `gitlab`, nur ist `baseUrl` optional mit Vorgabe
    /// (`https://api.github.com`) und `projects.<key>.path` heisst `owner/repo`.
    let github: RawGithub?
    /// Kein Modul, das Kanban betreibt — nur der Ablageort der exportierten Seiten (und der Space,
    /// über den Hermes' Export sein Ziel findet). Siehe `KanbanConfigSchema.confluence`.
    let confluence: RawConfluence?
    /// Ebenfalls kein Modul: nur der Ort der Knowledgebase je Projekt, den Kanban als `kbPath` in
    /// `.claude/project.json` durchreicht.
    let knowledgebase: RawKnowledgebase?
    /// Auch kein Modul, und erst recht keins von Hermes: ob ein Projekt lokal einen Docker-Stack
    /// hat. Kanban wertet das selbst aus und reicht es als `dockerStack` an die Skills durch.
    let docker: RawDocker?
}

private struct RawJira: Decodable {
    let baseUrl: String?
    let email: String?
    let apiToken: String?
    let projects: [String: RawJiraProject]?
}

private struct RawJiraProject: Decodable {
    let prefix: String?
    let tasksPath: String?
    let baseUrl: String?
    let repoDir: String?   // optionaler Override — sonst erstes Segment von tasksPath
    let agent: String?     // "claude" (Default) oder "codex"
    let skillSet: String?  // Name eines Sets im Bestand; leer/fehlend = Standard-Set
    /// `false` = Projekt ohne Jira-Anbindung. Fehlt der Schlüssel, gilt `true` — jedes bestehende
    /// Projekt bleibt damit unverändert ein Jira-Projekt.
    let useJira: Bool?
}

private struct RawGitlab: Decodable {
    let baseUrl: String?
    let apiToken: String?
    let projects: [String: RawGitlabProject]?
}

private struct RawGitlabProject: Decodable {
    let path: String?
}

private struct RawGithub: Decodable {
    let baseUrl: String?
    let apiToken: String?
    let projects: [String: RawGithubProject]?
}

private struct RawGithubProject: Decodable {
    let path: String?      // owner/repo
}

private struct RawConfluence: Decodable {
    let projects: [String: RawConfluenceProject]?
}

private struct RawConfluenceProject: Decodable {
    let space: String?
    let path: String?      // Ablageort der exportierten Seiten (absolut, ~ oder relativ zum Basis-Pfad)
}

private struct RawKnowledgebase: Decodable {
    let projects: [String: RawKnowledgebaseProject]?
}

private struct RawKnowledgebaseProject: Decodable {
    let path: String?      // absolut, ~ oder relativ zum Basis-Pfad
}

private struct RawDocker: Decodable {
    let projects: [String: RawDockerProject]?
}

private struct RawDockerProject: Decodable {
    /// `false` = Projekt ohne Docker-Stack. Fehlt der Schlüssel (der Normalfall — geschrieben wird
    /// nur die Abschaltung), gilt `true`.
    let stack: Bool?
}
