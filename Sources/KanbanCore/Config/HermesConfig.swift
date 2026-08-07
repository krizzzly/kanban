import Foundation

/// A single project resolved from the Hermes config, with everything the app needs precomputed.
public struct ProjectConfig: Identifiable, Sendable, Hashable {
    public let key: String                 // config key, e.g. "even"
    public let prefix: String              // Jira project prefix, e.g. "EVEN"
    public let jiraBaseUrl: String         // project baseUrl, falling back to the jira default
    public let tasksPathAbsolute: String   // absolute path to the task-file directory
    public let repoDir: String             // local git repo root (for `git worktree list`)
    public let gitlabProjectPath: String?  // GitLab namespace path, e.g. "applications/even"

    public var id: String { key }
}

/// The slice of `~/.hermes/config.json` the Kanban app reads (read-only).
public struct HermesConfig: Sendable {
    public let basePath: String
    public let jiraEmail: String
    public let jiraApiToken: String
    public let jiraDefaultBaseUrl: String
    public let gitlabBaseUrl: String?
    public let gitlabApiToken: String?
    public let gitlabBackend: String?     // "api" = direct REST with token; else via Hermes daemon
    public let projects: [ProjectConfig]

    public var hasGitlab: Bool { gitlabBaseUrl != nil && (gitlabApiToken?.isEmpty == false) }
    public var gitlabApiUrl: String? { gitlabBaseUrl.map { "\($0)/api/v4" } }
}

public enum HermesConfigError: Error, LocalizedError {
    case fileNotFound(String)
    case decode(String)
    case missingJiraCredentials

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "Hermes-Config nicht gefunden: \(p)"
        case .decode(let m): return "Hermes-Config konnte nicht gelesen werden: \(m)"
        case .missingJiraCredentials: return "modules.jira.{email,apiToken,baseUrl} fehlen in der Hermes-Config."
        }
    }
}

public enum HermesConfigLoader {
    public static var defaultPath: String {
        ("~/.hermes/config.json" as NSString).expandingTildeInPath
    }

    public static func load(path: String? = nil) throws -> HermesConfig {
        let resolved = path ?? defaultPath
        guard FileManager.default.fileExists(atPath: resolved) else {
            throw HermesConfigError.fileNotFound(resolved)
        }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: resolved)) }
        catch { throw HermesConfigError.decode(error.localizedDescription) }

        let raw: RawConfig
        do { raw = try JSONDecoder().decode(RawConfig.self, from: data) }
        catch { throw HermesConfigError.decode(error.localizedDescription) }

        guard let jira = raw.modules.jira,
              let email = jira.email, !email.isEmpty,
              let token = jira.apiToken, !token.isEmpty,
              let jiraBase = jira.baseUrl, !jiraBase.isEmpty else {
            throw HermesConfigError.missingJiraCredentials
        }

        let basePathExpanded = expand(raw.basePath ?? "~/code")
        let gitlab = raw.modules.gitlab

        var projects: [ProjectConfig] = []
        for (key, p) in (jira.projects ?? [:]) {
            guard let prefix = p.prefix, let tasksPath = p.tasksPath else { continue }
            let tasksAbsolute = resolve(tasksPath, against: basePathExpanded)
            // Eigener `repoDir` je Projekt (HERMES-034): entkoppelt das Repo vom Tasks-Pfad, damit
            // die Task-Files umziehen können. Ohne Override gilt die bisherige Ableitung.
            let firstSegment = tasksPath.split(separator: "/").first.map(String.init) ?? key
            let repoDir = p.repoDir.map { resolve($0, against: basePathExpanded) }
                ?? (basePathExpanded as NSString).appendingPathComponent(firstSegment)
            projects.append(ProjectConfig(
                key: key,
                prefix: prefix,
                jiraBaseUrl: p.baseUrl ?? jiraBase,
                tasksPathAbsolute: tasksAbsolute,
                repoDir: repoDir,
                gitlabProjectPath: gitlab?.projects?[key]?.path
            ))
        }
        projects.sort { $0.key < $1.key }

        return HermesConfig(
            basePath: basePathExpanded,
            jiraEmail: email,
            jiraApiToken: token,
            jiraDefaultBaseUrl: jiraBase,
            gitlabBaseUrl: gitlab?.baseUrl,
            gitlabApiToken: gitlab?.apiToken,
            gitlabBackend: gitlab?.backend,
            projects: projects
        )
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Absolut oder `~…` bleibt, alles andere ist relativ zum Basis-Pfad.
    private static func resolve(_ path: String, against basePath: String) -> String {
        let expanded = expand(path)
        return expanded.hasPrefix("/") ? expanded
            : (basePath as NSString).appendingPathComponent(expanded)
    }
}

// MARK: - Raw decoding shapes

private struct RawConfig: Decodable {
    let basePath: String?
    let modules: RawModules
}

private struct RawModules: Decodable {
    let jira: RawJira?
    let gitlab: RawGitlab?
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
}

private struct RawGitlab: Decodable {
    let baseUrl: String?
    let apiToken: String?
    let backend: String?
    let projects: [String: RawGitlabProject]?
}

private struct RawGitlabProject: Decodable {
    let path: String?
}
