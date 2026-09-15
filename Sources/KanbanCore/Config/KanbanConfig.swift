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
    public let gitlabProjectPath: String?  // GitLab namespace path, e.g. "applications/even"
    /// Welcher Coding-Agent dieses Projekt bedient (`agent` in der Config, Default Claude).
    /// Entscheidet über Startbefehl, Asset-Ort und das Präfix, mit dem Kanban Commands tippt.
    public let agent: AgentKind

    public var id: String { key }

    public init(key: String, prefix: String, jiraBaseUrl: String, tasksPathAbsolute: String,
                docsPathAbsolute: String = "", kbPathAbsolute: String? = nil,
                repoDir: String, gitlabProjectPath: String?,
                agent: AgentKind = .claude) {
        self.key = key
        self.prefix = prefix
        self.jiraBaseUrl = jiraBaseUrl
        self.tasksPathAbsolute = tasksPathAbsolute
        self.docsPathAbsolute = docsPathAbsolute
        self.kbPathAbsolute = kbPathAbsolute
        self.repoDir = repoDir
        self.gitlabProjectPath = gitlabProjectPath
        self.agent = agent
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
    public let projects: [ProjectConfig]
    /// Der Session-Watchdog (`watchdog.*`) — aus, solange niemand ihn einschaltet.
    public let watchdog: WatchdogSettings

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
                                        gitlabBaseUrl: nil, gitlabApiToken: nil, projects: [],
                                        watchdog: WatchdogSettings(),
                                        excludeClaudeProjectFileFromCommit: true)

    public var hasJira: Bool {
        !jiraEmail.isEmpty && !jiraApiToken.isEmpty && !jiraDefaultBaseUrl.isEmpty
    }

    public var hasGitlab: Bool { gitlabBaseUrl != nil && (gitlabApiToken?.isEmpty == false) }
    public var gitlabApiUrl: String? { gitlabBaseUrl.map { "\($0)/api/v4" } }

    /// Whether the app can show a board at all. Deliberately **not** an error state: a fresh install
    /// has no credentials and no projects, and lands on the setup screen instead of a red triangle.
    public var isConfigured: Bool { hasJira && !projects.isEmpty }
}

public enum KanbanConfigError: Error, LocalizedError {
    case decode(String)

    public var errorDescription: String? {
        switch self {
        case .decode(let m): return "Kanban-Config konnte nicht gelesen werden: \(m)"
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
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }

    public static var path: String { fileURL.path }

    /// `~/Library/Application Support/Kanban` — reine Pfad-Rechnung, legt nichts an (anders als
    /// `fileURL`, das die Config schreiben können muss).
    public static var supportDirectory: String {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban", isDirectory: true).path
    }

    /// Wo die Doku eines Projekts liegt, das keinen eigenen Pfad nennt: `<support>/docs/<key>`.
    /// Gegenstück zu `<support>/tasks/<…>` — beides gehört Kanban, nicht dem Repo.
    public static var docsRoot: String {
        (supportDirectory as NSString).appendingPathComponent("docs")
    }

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
        let confluence = raw.modules?.confluence
        let knowledgebase = raw.modules?.knowledgebase

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
                gitlabProjectPath: gitlab?.projects?[key]?.path,
                agent: AgentKind(configValue: p.agent) ?? .fallback
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
            projects: projects,
            watchdog: watchdogSettings(raw.watchdog),
            excludeClaudeProjectFileFromCommit: raw.commit?.excludeClaudeProjectFile ?? true
        )
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
            modell: (modell?.isEmpty ?? true) ? vorgabe.modell : modell!)
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
    let modules: RawModules?
    /// Wie `commit` ein Kanban-eigener Abschnitt, kein Hermes-Modul — steht deshalb nicht in
    /// `ProjectProjection.moduleNames` und wandert nie in Hermes' Config.
    let watchdog: RawWatchdog?
}

struct RawWatchdog: Decodable {
    let enabled: Bool?
    let intervalMinutes: String?
    let lookbackHours: String?
    let maxSessions: String?
    let minSignals: String?
    let model: String?
}

/// `commit` — Kanban-eigener Abschnitt, kein Hermes-Modul. Steht deshalb nicht in
/// `ProjectProjection.moduleNames` und wandert nie in Hermes' Config.
private struct RawCommit: Decodable {
    let excludeClaudeProjectFile: Bool?
}

private struct RawModules: Decodable {
    let jira: RawJira?
    let gitlab: RawGitlab?
    /// Kein Modul, das Kanban betreibt — nur der Ablageort der exportierten Seiten (und der Space,
    /// über den Hermes' Export sein Ziel findet). Siehe `KanbanConfigSchema.confluence`.
    let confluence: RawConfluence?
    /// Ebenfalls kein Modul: nur der Ort der Knowledgebase je Projekt, den Kanban als `kbPath` in
    /// `.claude/project.json` durchreicht.
    let knowledgebase: RawKnowledgebase?
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
}

private struct RawGitlab: Decodable {
    let baseUrl: String?
    let apiToken: String?
    let projects: [String: RawGitlabProject]?
}

private struct RawGitlabProject: Decodable {
    let path: String?
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
