import Foundation

/// Übersetzt zwischen der Projekt-Registry (Kanbans Wahrheit) und den vier `projects`-Sections der
/// Hermes-Config (dem generierten Artefakt).
///
/// Die Richtung ist bewusst asymmetrisch:
/// - `importing(from:)` liest den Ist-Zustand ein — einmalig beim Bootstrap, **werterhaltend**.
/// - `apply(_:to:)` schreibt zurück, und zwar **additiv**: angefasst werden nur die Felder, die die
///   Registry besitzt. Tokens, `backend`, `baseUrl`, `anonymization` und jeder unbekannte Schlüssel
///   bleiben unberührt — auch innerhalb eines Projekt-Eintrags.
///
/// Ein Projekt-Key, den die Registry nicht kennt, wird **nicht** gelöscht: von Hand ergänzte
/// Einträge sollen nicht stillschweigend verschwinden. Umgekehrt gilt für Keys, die die Registry
/// kennt: fehlt dort ein Modul-Block, verschwindet der zugehörige Eintrag — dafür ist sie ja Owner.
public enum ProjectProjection {
    private static let jiraOwnedKeys = ["prefix", "tasksPath", "repoDir", "baseUrl", "useJira",
                                        "skillSet"]
    private static let gitlabOwnedKeys = ["path"]
    private static let githubOwnedKeys = ["path"]
    private static let confluenceOwnedKeys = ["space", "path"]
    private static let vertecOwnedKeys = ["project", "phase", "task", "additionalKeys"]
    private static let jenkinsOwnedKeys = ["jobs"]
    private static let dockerhubOwnedKeys = ["namespace", "repository"]
    /// Der lokale Docker-Stack — **nicht** DockerHub darüber. Zwei Sections, zwei Fragen: ob das
    /// Projekt lokal als Stack läuft gegen die Registry, in der sein Image liegt.
    private static let dockerOwnedKeys = ["stack"]

    /// Die Module, deren `projects`-Section dieselben Projekt-Keys benutzt. (Argo CDs `instances`
    /// sieht ähnlich aus, meint aber Umgebungen — bewusst nicht dabei.)
    public static let moduleNames = ["jira", "gitlab", "github", "confluence", "vertec",
                                     "jenkins", "dockerhub"]

    private static func projectsPath(_ module: String) -> [String] {
        ["modules", module, "projects"]
    }

    /// Sections, die **nur Kanban** kennt: sie stehen nicht in `moduleNames`, weil die Registry sie
    /// nicht besitzt — `apply` würde sie sonst bei jeder Projektion löschen. Beim ausdrücklichen
    /// Entfernen eines Projekts müssen sie aber mit weg, sonst bliebe ein verwaister Eintrag stehen.
    static let kanbanOnlySections = ["knowledgebase", "docker"]

    /// Sections ausserhalb von `modules` — ihr Pfad lässt sich nicht aus einem Modulnamen bauen.
    /// Bisher nur `appearance.projects` (Bild und Kopfzeilenfarben): reine Oberfläche, die in
    /// Hermes' Config nichts zu suchen hat und deshalb nie unter `modules` stand.
    static let topLevelProjectMaps = [["appearance", "projects"]]

    /// Löscht ein Projekt aus **allen** Sections. Bewusst getrennt von `apply(_:to:)`: das Entfernen
    /// ist eine ausdrückliche Nutzeraktion, während die Projektion selbst nie löscht.
    public static func remove(_ key: String, from config: JSONValue) -> JSONValue {
        var result = config
        let pfade = (moduleNames + kanbanOnlySections).map(projectsPath) + topLevelProjectMaps
        for pfad in pfade {
            let path = pfad + [key]
            if result.value(at: path) != nil { result.set(nil, at: path) }
        }
        return result
    }

    // MARK: - Import

    /// Baut die Registry aus einer bestehenden Hermes-Config (Vereinigung aller vier Sections).
    public static func importing(from config: JSONValue) -> ProjectRegistry {
        let jira = section(config, "jira")
        let gitlab = section(config, "gitlab")
        let github = section(config, "github")
        let confluence = section(config, "confluence")
        let vertec = section(config, "vertec")
        let jenkins = section(config, "jenkins")
        let dockerhub = section(config, "dockerhub")
        let docker = section(config, "docker")

        var registry = ProjectRegistry()
        let keys = Set(jira.keys).union(gitlab.keys).union(github.keys).union(confluence.keys)
            .union(vertec.keys).union(jenkins.keys).union(dockerhub.keys)

        for key in keys {
            var record = ProjectRecord()

            if let entry = jira[key]?.objectValue {
                record.prefix = entry["prefix"]?.stringValue
                record.tasksPath = entry["tasksPath"]?.stringValue
                record.repoDir = entry["repoDir"]?.stringValue
                record.jiraBaseUrl = entry["baseUrl"]?.stringValue
                record.usesJira = entry["useJira"]?.boolValue
                record.skillSet = entry["skillSet"]?.stringValue
            }
            // Eigene Section, bewusst **nicht** in der Key-Vereinigung oben: ein Eintrag, der nur
            // sagt „kein Stack", beschreibt kein Projekt.
            record.usesDockerStack = docker[key]?.objectValue?["stack"]?.boolValue
            if let path = gitlab[key]?.objectValue?["path"]?.stringValue {
                record.gitlab = .init(path: path)
            }
            if let path = github[key]?.objectValue?["path"]?.stringValue {
                record.github = .init(path: path)
            }
            if let entry = confluence[key]?.objectValue {
                let info = ProjectRecord.ConfluenceInfo(space: entry["space"]?.stringValue,
                                                        path: entry["path"]?.stringValue)
                if info != ProjectRecord.ConfluenceInfo() { record.confluence = info }
            }
            if let entry = vertec[key]?.objectValue {
                let info = ProjectRecord.VertecInfo(
                    project: entry["project"]?.stringValue,
                    phase: entry["phase"]?.stringValue,
                    task: entry["task"]?.stringValue,
                    additionalKeys: entry["additionalKeys"]?.arrayValue?.compactMap(\.stringValue))
                if info != ProjectRecord.VertecInfo() { record.vertec = info }
            }
            if let jobs = jenkins[key]?.objectValue?["jobs"]?.arrayValue?.compactMap(\.stringValue) {
                record.jenkins = .init(jobs: jobs)
            }
            if let entry = dockerhub[key]?.objectValue {
                let info = ProjectRecord.DockerHubInfo(namespace: entry["namespace"]?.stringValue,
                                                       repository: entry["repository"]?.stringValue)
                if info != ProjectRecord.DockerHubInfo() { record.dockerhub = info }
            }

            if !record.isEmpty { registry[key] = record }
        }
        return registry
    }

    private static func section(_ config: JSONValue, _ module: String) -> [String: JSONValue] {
        config.value(at: projectsPath(module))?.objectValue ?? [:]
    }

    // MARK: - Projektion

    /// Schreibt ein einzelnes Projekt in alle Sections — der Weg fürs zentrale Anlegen.
    public static func apply(_ record: ProjectRecord, key: String, to config: JSONValue) -> JSONValue {
        var result = config
        apply(record, key: key, to: &result)
        return result
    }

    /// Schreibt die Sections, die **nur Kanban** kennt — und zwar **nur in Kanbans eigene Config**.
    ///
    /// Bewusst getrennt von `apply(_:key:to:)`: das läuft über `HermesSync` auch gegen
    /// `~/.hermes/config.json`, und `modules.docker` hätte dort nichts zu suchen — Hermes kennt
    /// keinen Stack-Schalter und würde einen Schlüssel geschenkt bekommen, den es nie liest. Genau
    /// deshalb steht `docker` in `kanbanOnlySections` und nicht in `moduleNames`.
    public static func applyKanbanOnly(_ record: ProjectRecord, key: String,
                                       to config: JSONValue) -> JSONValue {
        var result = config
        // Nur die Abschaltung wird geschrieben — `true` ist die Vorgabe, und ein Schlüssel, der nur
        // den Normalfall wiederholt, stünde in jedem Projekt herum. Beim Wiedereinschalten
        // verschwindet der ganze Eintrag (`write` mit nil).
        write(record.usesDockerStack == false ? ["stack": .bool(false)] : nil,
              ownedKeys: dockerOwnedKeys, at: projectsPath("docker") + [key], in: &result)
        return result
    }

    /// Schreibt die Registry in die Config und gibt die neue Fassung zurück.
    public static func apply(_ registry: ProjectRegistry, to config: JSONValue) -> JSONValue {
        var result = config
        for key in registry.keys {
            guard let record = registry[key] else { continue }
            apply(record, key: key, to: &result)
        }
        return result
    }

    private static func apply(_ record: ProjectRecord, key: String, to config: inout JSONValue) {
        // Jira: der Eintrag entsteht nur mit Präfix — ohne Jira-Projekt gibt es dort nichts zu suchen.
        var jira: [String: JSONValue]? = nil
        if let prefix = record.prefix {
            var fields: [String: JSONValue] = ["prefix": .string(prefix)]
            fields["tasksPath"] = record.tasksPath.map(JSONValue.string)
            fields["repoDir"] = record.repoDir.map(JSONValue.string)
            fields["baseUrl"] = record.jiraBaseUrl.map(JSONValue.string)
            // Nur die Abschaltung wird geschrieben: `true` ist die Vorgabe, und ein Schlüssel,
            // der nur den Normalfall wiederholt, stünde in jedem Projekt herum.
            if record.usesJira == false { fields["useJira"] = .bool(false) }
            // Nur die ausdrückliche Wahl steht da; ohne Eintrag gilt das Standard-Set.
            fields["skillSet"] = record.skillSet.map(JSONValue.string)
            jira = fields
        }
        write(jira, ownedKeys: jiraOwnedKeys, at: projectsPath("jira") + [key], in: &config)

        write(record.gitlab.map { ["path": .string($0.path)] },
              ownedKeys: gitlabOwnedKeys, at: projectsPath("gitlab") + [key], in: &config)

        write(record.github.map { ["path": .string($0.path)] },
              ownedKeys: githubOwnedKeys, at: projectsPath("github") + [key], in: &config)

        write(record.confluence.map {
            var fields: [String: JSONValue] = [:]
            fields["space"] = $0.space.map(JSONValue.string)
            fields["path"] = $0.path.map(JSONValue.string)
            return fields
        }, ownedKeys: confluenceOwnedKeys, at: projectsPath("confluence") + [key], in: &config)

        write(record.vertec.map {
            var fields: [String: JSONValue] = [:]
            fields["project"] = $0.project.map(JSONValue.string)
            fields["phase"] = $0.phase.map(JSONValue.string)
            fields["task"] = $0.task.map(JSONValue.string)
            fields["additionalKeys"] = $0.additionalKeys.map { keys in
                .array(keys.map(JSONValue.string))
            }
            return fields
        }, ownedKeys: vertecOwnedKeys, at: projectsPath("vertec") + [key], in: &config)

        write(record.jenkins.map { ["jobs": .array($0.jobs.map(JSONValue.string))] },
              ownedKeys: jenkinsOwnedKeys, at: projectsPath("jenkins") + [key], in: &config)

        write(record.dockerhub.map {
            var fields: [String: JSONValue] = [:]
            fields["namespace"] = $0.namespace.map(JSONValue.string)
            fields["repository"] = $0.repository.map(JSONValue.string)
            return fields
        }, ownedKeys: dockerhubOwnedKeys, at: projectsPath("dockerhub") + [key], in: &config)
    }

    /// Merged `fields` in den Eintrag an `path`: eigene Felder werden gesetzt bzw. entfernt, fremde
    /// bleiben stehen. `fields == nil` entfernt den ganzen Eintrag — aber nur, wenn er existiert
    /// (sonst entstünden leere `projects`-Objekte für Module, die gar nicht konfiguriert sind).
    private static func write(_ fields: [String: JSONValue]?,
                              ownedKeys: [String],
                              at path: [String],
                              in config: inout JSONValue) {
        let existing = config.value(at: path)?.objectValue

        guard let fields else {
            if existing != nil { config.set(nil, at: path) }
            return
        }

        var entry = existing ?? [:]
        for key in ownedKeys { entry[key] = fields[key] }   // setzen oder (bei nil) entfernen
        config.set(.object(entry), at: path)
    }
}
