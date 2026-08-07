import Foundation

/// Lightweight validation hint for a field; never blocks saving (a config may be partial), only
/// surfaces an inline warning when the entered value is clearly malformed.
public enum FieldValidation: Sendable {
    case none, url, email, phoneE164

    public func error(for value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return nil }   // empty = unset, not invalid
        switch self {
        case .none:
            return nil
        case .url:
            return (v.hasPrefix("http://") || v.hasPrefix("https://"))
                ? nil : "Sollte mit http:// oder https:// beginnen."
        case .email:
            return (v.contains("@") && v.contains(".")) ? nil : "Keine gültige E-Mail-Adresse."
        case .phoneE164:
            return (v.hasPrefix("+") && v.dropFirst().allSatisfy(\.isNumber) && v.count >= 8)
                ? nil : "Erwartet E.164-Format, z. B. +41791234567."
        }
    }
}

/// One editable field in the settings UI, addressed by its JSON key path.
public struct ConfigFieldSpec: Identifiable, Sendable {
    public enum Kind: Sendable {
        case string
        case secret            // rendered as SecureField with reveal toggle
        case bool(defaultOn: Bool)
        case path              // string that is a filesystem path (gets a "Wählen…" button)
        case stringList        // JSON string array, edited comma-separated
        case choice([String])  // enum; empty selection removes the key (= module default)
    }

    public let path: [String]
    public let label: String
    public let help: String?
    public let placeholder: String?
    public let kind: Kind
    public let validation: FieldValidation

    public var id: String { path.joined(separator: ".") }

    public init(_ path: [String], _ label: String, kind: Kind,
                placeholder: String? = nil, help: String? = nil,
                validation: FieldValidation = .none) {
        self.path = path
        self.label = label
        self.kind = kind
        self.placeholder = placeholder
        self.help = help
        self.validation = validation
    }
}

/// A sub-field of one entry in a project map (`modules.<m>.projects.<key>.<field>`).
public struct ProjectFieldSpec: Identifiable, Sendable {
    public enum Kind: Sendable { case string, secret, stringList }

    public let key: String
    public let label: String
    public let kind: Kind
    public let placeholder: String?
    public let required: Bool
    public let help: String?

    public var id: String { key }

    public init(_ key: String, _ label: String, kind: Kind = .string, required: Bool,
                placeholder: String? = nil, help: String? = nil) {
        self.key = key
        self.label = label
        self.kind = kind
        self.placeholder = placeholder
        self.required = required
        self.help = help
    }
}

/// A map of per-project objects with user-defined keys (add/remove projects in the UI).
public struct ProjectMapSpec: Sendable {
    public let path: [String]
    public let title: String
    public let keyPlaceholder: String
    public let fields: [ProjectFieldSpec]

    public init(path: [String], title: String = "Projekte",
                keyPlaceholder: String = "projekt-key", fields: [ProjectFieldSpec]) {
        self.path = path
        self.title = title
        self.keyPlaceholder = keyPlaceholder
        self.fields = fields
    }
}

/// A list of presence blocks (`modules.vertec.presence[].{from,to,text?}`).
public struct PresenceListSpec: Sendable {
    public let path: [String]
    public init(path: [String]) { self.path = path }
}

/// A list of auto-reply contacts (`modules.{whatsapp,telegram}.people[]`). The identifier field
/// differs per module (WhatsApp uses `number`, Telegram `username`).
public struct PersonListSpec: Sendable {
    public let path: [String]
    public let identifierKey: String
    public let identifierLabel: String
    public let identifierPlaceholder: String

    public init(path: [String], identifierKey: String,
                identifierLabel: String, identifierPlaceholder: String) {
        self.path = path
        self.identifierKey = identifierKey
        self.identifierLabel = identifierLabel
        self.identifierPlaceholder = identifierPlaceholder
    }
}

/// A sidebar section of the settings sheet.
public struct ConfigSectionSpec: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let intro: String?
    public let fields: [ConfigFieldSpec]
    public let projectMap: ProjectMapSpec?
    public let presenceList: PresenceListSpec?
    public let personList: PersonListSpec?

    public init(id: String, title: String, icon: String, intro: String? = nil,
                fields: [ConfigFieldSpec], projectMap: ProjectMapSpec? = nil,
                presenceList: PresenceListSpec? = nil, personList: PersonListSpec? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.intro = intro
        self.fields = fields
        self.projectMap = projectMap
        self.presenceList = presenceList
        self.personList = personList
    }
}

/// Declarative schema of `~/.hermes/config.json` — the single source of truth the settings UI
/// renders from. Inventory erhoben aus `~/code/hermes` (siehe Task HERMES-037).
public enum HermesConfigSchema {
    public static let sections: [ConfigSectionSpec] = [
        general, anonymization, jira, gitlab, confluence,
        vertec, jenkins, argocd, dockerhub, whatsapp, telegram, downloads, other,
    ]

    // MARK: General

    static let general = ConfigSectionSpec(
        id: "general", title: "Allgemein", icon: "gearshape",
        fields: [
            ConfigFieldSpec(["basePath"], "Basis-Pfad", kind: .path, placeholder: "~/code",
                            help: "Basisordner der Projekte; tasksPath u. a. werden relativ dazu aufgelöst."),
            ConfigFieldSpec(["daemon", "autoStart"], "Daemon automatisch starten",
                            kind: .bool(defaultOn: true),
                            help: "Startet den Hermes-Daemon automatisch beim CLI-Aufruf."),
        ])

    static let anonymization = ConfigSectionSpec(
        id: "anonymization", title: "Anonymisierung", icon: "eye.slash",
        intro: "Globale Redaktions-Einstellungen; einzelne Module können sie mit ‹anonymize› übersteuern.",
        fields: [
            ConfigFieldSpec(["anonymization", "allowlist"], "Allowlist", kind: .stringList,
                            placeholder: "IWF, Christian Hiller",
                            help: "Identitäten, die NICHT redigiert werden (kommagetrennt)."),
            ConfigFieldSpec(["anonymization", "countries"], "Länder", kind: .stringList,
                            placeholder: "CH",
                            help: "ISO-Ländercodes für lokale Telefon-/Adress-Muster (Default: CH)."),
            ConfigFieldSpec(["anonymization", "images"], "Bilder anonymisieren (OCR)",
                            kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["anonymization", "ocrLang"], "OCR-Sprache", kind: .string,
                            placeholder: "deu",
                            help: "Erzwingt die OCR-Sprache (z. B. deu, fra, ita); leer = Auto-Erkennung."),
            ConfigFieldSpec(["anonymization", "ner"], "Named Entity Recognition",
                            kind: .bool(defaultOn: true),
                            help: "Personen-/Firmennamen in Freitext erkennen (lädt ~250 MB Modell)."),
        ])

    // MARK: Atlassian + GitLab

    static let jira = ConfigSectionSpec(
        id: "jira", title: "Jira", icon: "checklist",
        fields: [
            ConfigFieldSpec(["modules", "jira", "enabled"], "Aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "jira", "anonymize"], "Anonymisieren", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "jira", "baseUrl"], "Base-URL", kind: .string,
                            placeholder: "https://firma.atlassian.net", validation: .url),
            ConfigFieldSpec(["modules", "jira", "email"], "E-Mail", kind: .string,
                            placeholder: "ich@firma.ch", validation: .email),
            ConfigFieldSpec(["modules", "jira", "apiToken"], "API-Token", kind: .secret,
                            help: "Erstellen unter id.atlassian.com → Security → API tokens."),
            ConfigFieldSpec(["modules", "jira", "backend"], "Backend", kind: .choice(["api", "extension"]),
                            help: "api = direkte REST-Calls, extension = via Daemon + Browser (Default)."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "jira", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("prefix", "Ticket-Präfix", required: true, placeholder: "EVEN"),
                ProjectFieldSpec("tasksPath", "Tasks-Pfad", required: true,
                                 placeholder: "even/docs/tasks", help: "Relativ zum Basis-Pfad."),
                ProjectFieldSpec("repoDir", "Repo-Ordner (Override)", required: false,
                                 placeholder: "even",
                                 help: "Lokales Git-Repo; absolut, ~ oder relativ zum Basis-Pfad. "
                                     + "Leer = erstes Segment des Tasks-Pfads (bisheriges Verhalten). "
                                     + "Nötig, sobald die Task-Files ausserhalb des Repos liegen."),
                ProjectFieldSpec("baseUrl", "Base-URL (Override)", required: false,
                                 placeholder: "https://andere-instanz.atlassian.net"),
            ]))

    static let gitlab = ConfigSectionSpec(
        id: "gitlab", title: "GitLab", icon: "arrow.triangle.branch",
        intro: "Gleicher Projekt-Key wie bei Jira → Zuordnung fürs Kanban-Board (Review/Done).",
        fields: [
            ConfigFieldSpec(["modules", "gitlab", "baseUrl"], "Base-URL", kind: .string,
                            placeholder: "https://git.firma.io", validation: .url),
            ConfigFieldSpec(["modules", "gitlab", "apiToken"], "API-Token", kind: .secret,
                            help: "Personal Access Token (Settings → Access Tokens), Header PRIVATE-TOKEN."),
            ConfigFieldSpec(["modules", "gitlab", "backend"], "Backend", kind: .choice(["api", "extension"]),
                            help: "api = direkter REST-Zugriff mit Token (braucht read_api-Scope); "
                                + "extension = über den Hermes-Daemon/Browser (Default)."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "gitlab", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("path", "Projekt-Pfad", required: true, placeholder: "applications/even"),
            ]))

    static let confluence = ConfigSectionSpec(
        id: "confluence", title: "Confluence", icon: "book",
        intro: "Base-URL/E-Mail/API-Token fallen auf die Jira-Werte zurück, wenn leer.",
        fields: [
            ConfigFieldSpec(["modules", "confluence", "enabled"], "Aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "confluence", "anonymize"], "Anonymisieren", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "confluence", "baseUrl"], "Base-URL", kind: .string,
                            placeholder: "https://firma.atlassian.net/wiki", validation: .url),
            ConfigFieldSpec(["modules", "confluence", "email"], "E-Mail", kind: .string, validation: .email),
            ConfigFieldSpec(["modules", "confluence", "apiToken"], "API-Token", kind: .secret),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "confluence", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("space", "Space-Key", required: true, placeholder: "EVEN"),
                ProjectFieldSpec("path", "Wissens-Pfad", required: true,
                                 placeholder: "even/docs/knowledge", help: "Relativ zum Basis-Pfad."),
            ]))

    // MARK: Vertec

    static let vertec = ConfigSectionSpec(
        id: "vertec", title: "Vertec", icon: "clock",
        fields: [
            ConfigFieldSpec(["modules", "vertec", "enabled"], "Aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "vertec", "useWebSocket"], "WebSocket-Backend",
                            kind: .bool(defaultOn: false),
                            help: "Schnellere Batch-Eingabe über WebSocket statt der Legacy-CDP-Steuerung."),
            ConfigFieldSpec(["modules", "vertec", "tasks", "calendar"], "Kalender-Task", kind: .string,
                            placeholder: "BESPRECHUNG / MEETING",
                            help: "Vertec-Task, mit dem Kalendertermine geblockt werden."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "vertec", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("project", "Projekt", required: true, placeholder: "8100 - BFE - ZVM-Tool"),
                ProjectFieldSpec("phase", "Phase", required: true, placeholder: "ZVM-TOOL ENTWICKLUNG 2026"),
                ProjectFieldSpec("task", "Task", required: true, placeholder: "PROGRAMMIERUNG"),
                ProjectFieldSpec("additionalKeys", "Zusätzliche Keys", kind: .stringList, required: false,
                                 placeholder: "bfezvm-config",
                                 help: "Weitere GitLab-Keys, die auf dieses Vertec-Projekt zeigen (kommagetrennt)."),
            ]),
        presenceList: PresenceListSpec(path: ["modules", "vertec", "presence"]))

    // MARK: CI / Infra

    static let jenkins = ConfigSectionSpec(
        id: "jenkins", title: "Jenkins", icon: "hammer",
        fields: [
            ConfigFieldSpec(["modules", "jenkins", "enabled"], "Aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "jenkins", "baseUrl"], "Base-URL", kind: .string,
                            placeholder: "https://jenkins.firma.io", validation: .url),
            ConfigFieldSpec(["modules", "jenkins", "backend"], "Backend", kind: .choice(["api", "extension"])),
            ConfigFieldSpec(["modules", "jenkins", "username"], "Benutzername", kind: .string),
            ConfigFieldSpec(["modules", "jenkins", "apiToken"], "API-Token", kind: .secret,
                            help: "Jenkins → Benutzer → Configure → API Token."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "jenkins", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("jobs", "Jobs", kind: .stringList, required: true,
                                 placeholder: "even-build, even-deploy",
                                 help: "Jenkins-Jobnamen für dieses Projekt (kommagetrennt)."),
            ]))

    static let argocd = ConfigSectionSpec(
        id: "argocd", title: "Argo CD", icon: "point.3.filled.connected.trianglepath.dotted",
        intro: "Entweder Single-Instance (Base-URL + Token) ODER Multi-Instance (Instanzen + Default) verwenden.",
        fields: [
            ConfigFieldSpec(["modules", "argocd", "enabled"], "Aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "argocd", "baseUrl"], "Base-URL (Single-Instance)", kind: .string,
                            placeholder: "https://argocd.firma.io", validation: .url),
            ConfigFieldSpec(["modules", "argocd", "token"], "Token (Single-Instance)", kind: .secret,
                            help: "Optional, wenn OIDC/OAuth genutzt wird."),
            ConfigFieldSpec(["modules", "argocd", "defaultInstance"], "Default-Instanz (Multi)", kind: .string,
                            placeholder: "staging",
                            help: "Key aus der Instanzen-Liste, der ohne explizite Angabe genutzt wird."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "argocd", "instances"], title: "Instanzen (Multi-Instance)",
            keyPlaceholder: "staging",
            fields: [
                ProjectFieldSpec("baseUrl", "Base-URL", required: true,
                                 placeholder: "https://staging-argocd.firma.io"),
                ProjectFieldSpec("token", "Token", kind: .secret, required: false),
            ]))

    static let dockerhub = ConfigSectionSpec(
        id: "dockerhub", title: "DockerHub", icon: "shippingbox",
        fields: [
            ConfigFieldSpec(["modules", "dockerhub", "enabled"], "Aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "dockerhub", "baseUrl"], "Base-URL", kind: .string,
                            placeholder: "https://hub.docker.com", validation: .url),
            ConfigFieldSpec(["modules", "dockerhub", "backend"], "Backend", kind: .choice(["api", "extension"])),
            ConfigFieldSpec(["modules", "dockerhub", "username"], "Benutzername", kind: .string),
            ConfigFieldSpec(["modules", "dockerhub", "apiToken"], "API-Token", kind: .secret,
                            help: "Personal Access Token (nicht das Passwort)."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "dockerhub", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("namespace", "Namespace", required: true, placeholder: "iwfwebsolutions"),
                ProjectFieldSpec("repository", "Repository", required: true, placeholder: "even"),
            ]))

    // MARK: Messaging

    static let whatsapp = ConfigSectionSpec(
        id: "whatsapp", title: "WhatsApp", icon: "message",
        fields: [
            ConfigFieldSpec(["modules", "whatsapp", "enabled"], "Aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "whatsapp", "ownNumber"], "Eigene Nummer", kind: .string,
                            placeholder: "+41791234567", validation: .phoneE164),
            ConfigFieldSpec(["modules", "whatsapp", "assistantName"], "Assistent-Name", kind: .string,
                            placeholder: "Claude"),
            ConfigFieldSpec(["modules", "whatsapp", "replyRule"], "Reply-Regel", kind: .string,
                            help: "Prompt-Injection-Warnregel für eingehende Nachrichten."),
            ConfigFieldSpec(["modules", "whatsapp", "bridge", "apiUrl"], "Bridge API-URL", kind: .string,
                            placeholder: "http://localhost:8081", validation: .url),
            ConfigFieldSpec(["modules", "whatsapp", "bridge", "dbPath"], "Bridge DB-Pfad", kind: .path),
        ],
        personList: PersonListSpec(
            path: ["modules", "whatsapp", "people"], identifierKey: "number",
            identifierLabel: "Nummer", identifierPlaceholder: "+41791234567"))

    static let telegram = ConfigSectionSpec(
        id: "telegram", title: "Telegram", icon: "paperplane",
        fields: [
            ConfigFieldSpec(["modules", "telegram", "enabled"], "Aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "telegram", "ownUsername"], "Eigener Username", kind: .string,
                            placeholder: "christian"),
            ConfigFieldSpec(["modules", "telegram", "assistantName"], "Assistent-Name", kind: .string,
                            placeholder: "Claude"),
        ],
        personList: PersonListSpec(
            path: ["modules", "telegram", "people"], identifierKey: "username",
            identifierLabel: "Username", identifierPlaceholder: "max_muster"))

    // MARK: Downloads + simple toggles

    static let downloads = ConfigSectionSpec(
        id: "downloads", title: "Downloads", icon: "arrow.down.circle",
        fields: [
            ConfigFieldSpec(["modules", "youtube-music", "enabled"], "YouTube Music aktiviert",
                            kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "youtube-music", "downloadPath"], "YouTube-Music-Pfad", kind: .path,
                            placeholder: "~/Music/youtube-dl"),
            ConfigFieldSpec(["modules", "youtube-video", "enabled"], "YouTube Video aktiviert",
                            kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "youtube-video", "downloadPath"], "YouTube-Video-Pfad", kind: .path,
                            placeholder: "~/Music/youtube-dl"),
            ConfigFieldSpec(["modules", "instagram", "downloadPath"], "Instagram-Pfad", kind: .path,
                            placeholder: "~/Downloads/hermes-instagram"),
            ConfigFieldSpec(["modules", "facebook", "downloadPath"], "Facebook-Pfad", kind: .path,
                            placeholder: "~/Downloads/hermes-facebook"),
            ConfigFieldSpec(["modules", "facebook", "cookiesFromBrowser"], "Facebook-Cookies aus Browser",
                            kind: .choice(["chrome", "firefox", "edge", "safari", "brave"]),
                            help: "Browser, aus dem yt-dlp Cookies liest."),
        ])

    static let other = ConfigSectionSpec(
        id: "other", title: "Weitere Module", icon: "square.grid.2x2",
        intro: "Module ohne statische Config (Browser-Login) — nur an-/abschaltbar.",
        fields: [
            ConfigFieldSpec(["modules", "browser", "enabled"], "Browser aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "browser", "anonymize"], "Browser anonymisieren", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "office365", "enabled"], "Office 365 aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "spotify", "enabled"], "Spotify aktiviert", kind: .bool(defaultOn: true)),
            ConfigFieldSpec(["modules", "boost", "enabled"], "Boost aktiviert", kind: .bool(defaultOn: true)),
        ])
}
