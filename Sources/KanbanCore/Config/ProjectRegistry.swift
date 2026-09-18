import Foundation

/// Ein Projekt, an **einem** Ort beschrieben (HERMES-043).
///
/// Bisher war dieselbe Projektliste vier Mal in `~/.hermes/config.json` gepflegt — je einmal unter
/// `modules.{jira,gitlab,confluence,vertec}.projects`. Ein Record bündelt das: die gemeinsamen
/// Werte oben, die Modul-Zugehörigkeiten als optionale Blöcke.
///
/// **Alles ausser dem Key ist optional**, und das ist fachlich nötig, nicht bequem: `tech` ist ein
/// reiner Confluence-Space ohne Jira-Projekt, `zvmsupport` ein Jira-Projekt ohne eigenes Repo und
/// mit fremdem Host. Ein Record mit Pflichtfeldern würde diese Fälle kaputt-normalisieren.
public struct ProjectRecord: Codable, Sendable, Equatable {
    /// Jira-Präfix (`EVEN`). Nil = Projekt ohne Jira (z.B. reiner Confluence-Space).
    public var prefix: String?
    /// Task-File-Ordner, relativ zu `basePath` oder absolut. Bewusst ein **expliziter** Wert und
    /// kein Konventions-Derivat: sonst würde die erste Projektion die Task-Files stillschweigend
    /// umziehen (das bleibt HERMES-034 Schritt 5, pro Projekt einzeln).
    public var tasksPath: String?
    /// Haupt-Repo, relativ zu `basePath` oder absolut. Nil = Ableitung wie bisher (erstes Segment
    /// von `tasksPath`). Gesetzt bei Support-Projekten, die im Repo eines anderen Projekts leben.
    public var repoDir: String?
    /// Nur bei Abweichung vom Default-Host (`zvmsupport`).
    public var jiraBaseUrl: String?
    /// `false` = Projekt **ohne Jira-Anbindung**: kein Board, keine Sprints, keine Worklogs, nur
    /// freier Modus. nil oder `true` = wie bisher.
    ///
    /// Nicht zu verwechseln mit `prefix == nil`: der Präfix benennt Task-Files und Branches und
    /// bleibt auch ohne Jira gesetzt. Ein Projekt ohne Präfix wäre eins, das Kanban gar nicht als
    /// Ticketquelle führt — das hier ist eins, dessen Tickets nur nirgends in Jira stehen.
    public var usesJira: Bool?
    /// `false` = Projekt **ohne Docker-Stack**: der Worktree ist ein reiner Git-Worktree, es gibt
    /// keine Stack-Oberfläche, keine Snapshots, keinen Sweep und keinen `iwf`-Aufruf. nil oder
    /// `true` = wie bisher.
    ///
    /// Betrifft **nur** die Docker-Hälfte: Worktrees, Branches und Task-Files gibt es weiterhin.
    /// Kanban selbst ist der Anlass — ein Swift-Paket ohne `.iwf.yml`, das bisher wie eine
    /// Web-Applikation konfiguriert aussah.
    ///
    /// Liegt in einer **eigenen** Section (`modules.docker.projects.<key>.stack`), nicht im
    /// Jira-Eintrag: gleiche Form wie `usesJira`, andere Sache. Und in `kanbanOnlySections` statt
    /// `moduleNames` — Hermes kennt keinen Stack-Schalter (siehe `applyKanbanOnly`).
    public var usesDockerStack: Bool?

    public var gitlab: GitlabInfo?
    public var confluence: ConfluenceInfo?
    public var vertec: VertecInfo?
    public var jenkins: JenkinsInfo?
    public var dockerhub: DockerHubInfo?

    public struct GitlabInfo: Codable, Sendable, Equatable {
        public var path: String          // Namespace-Pfad, z.B. "applications/even"
        public init(path: String) { self.path = path }
    }

    public struct ConfluenceInfo: Codable, Sendable, Equatable {
        public var space: String?
        public var path: String?         // Ablageort der generierten Seiten
        public init(space: String? = nil, path: String? = nil) {
            self.space = space
            self.path = path
        }
    }

    public struct VertecInfo: Codable, Sendable, Equatable {
        public var project: String?
        public var phase: String?
        public var task: String?
        /// Weitere GitLab-Keys, deren Aktivität auf dieses Vertec-Projekt gebucht wird.
        public var additionalKeys: [String]?
        public init(project: String? = nil, phase: String? = nil, task: String? = nil,
                    additionalKeys: [String]? = nil) {
            self.project = project
            self.phase = phase
            self.task = task
            self.additionalKeys = additionalKeys
        }
    }

    public struct JenkinsInfo: Codable, Sendable, Equatable {
        public var jobs: [String]        // Job-Namen exakt wie in Jenkins
        public init(jobs: [String]) { self.jobs = jobs }
    }

    public struct DockerHubInfo: Codable, Sendable, Equatable {
        public var namespace: String?
        public var repository: String?
        public init(namespace: String? = nil, repository: String? = nil) {
            self.namespace = namespace
            self.repository = repository
        }
    }

    public init(prefix: String? = nil,
                tasksPath: String? = nil,
                repoDir: String? = nil,
                jiraBaseUrl: String? = nil,
                gitlab: GitlabInfo? = nil,
                confluence: ConfluenceInfo? = nil,
                vertec: VertecInfo? = nil,
                jenkins: JenkinsInfo? = nil,
                dockerhub: DockerHubInfo? = nil) {
        self.prefix = prefix
        self.tasksPath = tasksPath
        self.repoDir = repoDir
        self.jiraBaseUrl = jiraBaseUrl
        self.gitlab = gitlab
        self.confluence = confluence
        self.vertec = vertec
        self.jenkins = jenkins
        self.dockerhub = dockerhub
    }

    /// Ein Record ohne jeden Inhalt beschreibt kein Projekt — die UI verhindert das, der Import
    /// überspringt solche Einträge.
    public var isEmpty: Bool {
        prefix == nil && tasksPath == nil && repoDir == nil && jiraBaseUrl == nil
            && gitlab == nil && confluence == nil && vertec == nil
            && jenkins == nil && dockerhub == nil
    }

    /// Wirft Modulblöcke weg, die zwar **da**, aber leer sind.
    ///
    /// Im Anlege-Formular entscheidet ein Schalter, ob es einen Block gibt — nicht mehr die Frage,
    /// ob zufällig ein Feld ausgefüllt ist. Damit kann ein eingeschalteter Block leer bleiben, und
    /// genau der darf nicht in die Config: ein GitLab-Eintrag mit leerem Pfad würde später gegen
    /// ein Projekt „" abgefragt, ein leerer Confluence-Block stünde nur als Rauschen da.
    ///
    /// Bewusst erst beim Anlegen und nicht bei jedem Tastendruck: sonst verschwände der Block
    /// mitten im Tippen unter dem Schalter weg, sobald man ein Feld einmal leert.
    public func strippingEmptyModules() -> ProjectRecord {
        var record = self
        if record.gitlab?.path.trimmingCharacters(in: .whitespaces).isEmpty ?? false {
            record.gitlab = nil
        }
        if record.confluence == ConfluenceInfo() { record.confluence = nil }
        if record.vertec == VertecInfo() { record.vertec = nil }
        if record.dockerhub == DockerHubInfo() { record.dockerhub = nil }
        if record.jenkins?.jobs.isEmpty ?? false { record.jenkins = nil }
        return record
    }
}

/// Die Projektliste, wie Kanban sie besitzt: Key → Record.
public struct ProjectRegistry: Codable, Sendable, Equatable {
    public var projects: [String: ProjectRecord]

    public init(projects: [String: ProjectRecord] = [:]) {
        self.projects = projects
    }

    public var keys: [String] { projects.keys.sorted() }

    public subscript(key: String) -> ProjectRecord? {
        get { projects[key] }
        set { projects[key] = newValue }
    }

    /// Flaches JSON (`{"even": {…}}`) statt `{"projects": {…}}` — die Datei wird von Menschen
    /// gelesen und gelegentlich von Hand editiert.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        projects = try container.decode([String: ProjectRecord].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(projects)
    }
}

// Bewusst **ohne** eigene Speicherdatei: die Wahrheit bleibt `~/.hermes/config.json`. Eine
// persistierte `projects.json` neben den weiterhin handeditierbaren Modul-Sections wären zwei
// Wahrheiten, die auseinanderlaufen — zentral ist nur das *Anlegen* (und Entfernen), nicht die
// Pflege. `ProjectRegistry` ist deshalb eine Sicht, die live aus der Config gelesen wird
// (`ProjectProjection.importing`), kein gespeicherter Zustand.
