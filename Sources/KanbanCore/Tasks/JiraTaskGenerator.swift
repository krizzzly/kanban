import Foundation

/// Erzeugt aus einem Jira-Ticket den vollständigen Task-Ordner — `<tasksDir>/<TICKET>.md` plus
/// `<tasksDir>/<TICKET>/` mit Bildern, Anhängen, `comments.json` und `avatars/`.
///
/// Der Ablauf ist der von Hermes' `generate-claude-task`, und das Ergebnis ist strukturgleich:
/// dieselbe Abschnittsfolge, dieselben Dateinamen, dieselbe `comments.json`. Damit lesen
/// `CommentThread`, `TaskAttachments` und die bestehenden Skills den erzeugten Ordner unverändert.
///
/// Geschrieben wird `<TICKET>.md` **ohne** `### Status`-Block — beides ist Nachbearbeitung der
/// Skill `get-task` und bleibt es. Wer den Generator aus der App aufruft, holt den Status-Marker
/// selbst nach; der Generator bleibt dadurch gegen einen Hermes-Export prüfbar.
public struct JiraTaskGenerator: Sendable {
    public enum Failure: Error, LocalizedError, Equatable {
        case alreadyExists(filename: String)
        case busy(ticket: String)
        case fetchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyExists(let filename): return "Datei \(filename) existiert bereits"
            case .busy(let ticket): return "Für \(ticket) läuft bereits ein Export"
            case .fetchFailed(let message): return message
            }
        }
    }

    public struct Output: Sendable, Equatable {
        public let path: URL
        public let imageCount: Int
        public let commentCount: Int
    }

    private let client: JiraClient
    private let assets: TaskAssetDownloader
    private let smartLinks: SmartLinks?
    private let scrubber: TextScrubber

    public init(client: JiraClient, assets: TaskAssetDownloader,
                smartLinks: SmartLinks? = nil, scrubber: TextScrubber = .passthrough) {
        self.client = client
        self.assets = assets
        self.smartLinks = smartLinks
        self.scrubber = scrubber
    }

    /// Liefert den geschriebenen Pfad **oder** einen Fehlergrund — nie das ganze Markdown: der
    /// Aufrufer kann die Datei lesen, und in einer MCP-Antwort blähte der Inhalt nur den Kontext.
    public func generate(ticketKey: String, baseUrl: String, tasksDirectory: URL) async throws -> Output {
        // Pre-Flight **vor** dem Abruf: sonst wartet man zehn Sekunden, um zu erfahren, dass die
        // Datei längst da ist.
        if let existing = Self.existingTaskFile(ticketKey: ticketKey, in: tasksDirectory) {
            throw Failure.alreadyExists(filename: existing)
        }

        guard let lock = ExportLock(ticketKey: ticketKey) else { throw Failure.busy(ticket: ticketKey) }
        defer { lock.release() }

        // ── Reihenfolge ist Contract, nicht Zufall ──────────────────────────────────────────────
        // Kommentare werden **vor** den Downloads geholt. Der Anonymizer, der in diese Naht kommt,
        // muss jede Identität kennen, bevor er Bilder verarbeitet — eine Person, die nur in einem
        // Kommentar vorkommt, wäre sonst auf einem Screenshot noch lesbar. Solange der Scrubber
        // unverändert durchreicht, ändert ein Umsortieren nichts, und genau deshalb fiele es
        // niemandem auf: der Schaden entstünde hier und zeigte sich erst dort.
        guard let rawIssue = try? await client.rawIssue(key: ticketKey, baseUrl: baseUrl) else {
            throw Failure.fetchFailed("Ticket \(ticketKey) konnte nicht geladen werden")
        }
        let subtaskKeys = (rawIssue.value(at: ["fields", "subtasks"])?.arrayValue ?? [])
            .compactMap { $0.value(at: ["key"])?.stringValue }
        var rawSubtasks: [(key: String, raw: JSONValue)] = []
        for key in subtaskKeys {
            if let raw = await client.rawSubtask(key: key, baseUrl: baseUrl) {
                rawSubtasks.append((key, raw))
            }
        }
        let rawComments = (try? await client.rawComments(key: ticketKey, baseUrl: baseUrl)) ?? []

        // Ein Smart-Link-Durchgang über **alles**, was dieser Export übersetzt: derselbe Link in
        // Beschreibung und Kommentar kostet damit eine Anfrage statt zweier.
        let links = await resolveSmartLinks(issue: rawIssue, subtasks: rawSubtasks.map(\.raw),
                                            comments: rawComments)

        let issue = scrubbed(JiraClient.parseIssue(key: ticketKey, raw: rawIssue, smartLinks: links))
        var imageIndex = issue.images.count
        var subtaskContents: [JiraSubtaskContent] = []
        var images = issue.images
        for entry in rawSubtasks {
            let content = JiraClient.parseSubtask(key: entry.key, raw: entry.raw,
                                                  imageStartIndex: imageIndex, smartLinks: links)
            images.append(contentsOf: content.images)
            imageIndex = content.nextImageIndex
            subtaskContents.append(scrubbed(content))
        }
        let comments = JiraClient.parseComments(rawComments, smartLinks: links).map(scrubbed)

        // ── Ab hier wird geschrieben ────────────────────────────────────────────────────────────
        let savedImages = await assets.saveImages(images, ticketKey: ticketKey, tasksDirectory: tasksDirectory)

        var commentsLink: CommentsLink?
        if !comments.isEmpty {
            let avatarPaths = await assets.saveAvatars(for: comments, ticketKey: ticketKey,
                                                       tasksDirectory: tasksDirectory)
            let records = comments.map { comment in
                TaskComment(id: comment.id, parentId: comment.parentId, author: comment.author,
                            created: comment.created ?? "", body: comment.body,
                            avatar: comment.avatarUrl.flatMap { avatarPaths[$0] })
            }
            let file = tasksDirectory.appendingPathComponent(ticketKey, isDirectory: true)
                .appendingPathComponent("comments.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            if let data = try? encoder.encode(records) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: file)
                commentsLink = CommentsLink(path: "\(ticketKey)/comments.json", count: comments.count)
            }
        }

        let markdown = JiraTaskMarkdown.format(issue: issue, savedImages: savedImages,
                                               subtaskContents: subtaskContents,
                                               commentsLink: commentsLink)

        // Zweiter Existenzcheck gegen das Rennen mit einem Lauf, der ausserhalb dieses Prozesses
        // gestartet wurde — die Sperre deckt nur unsere Seite ab.
        if let existing = Self.existingTaskFile(ticketKey: ticketKey, in: tasksDirectory) {
            throw Failure.alreadyExists(filename: existing)
        }
        let target = tasksDirectory.appendingPathComponent("\(ticketKey).md")
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        // Atomar und **zuletzt**: der Ticket-Ordner ist zu diesem Zeitpunkt vollständig, und
        // `TaskFileWatcher` beobachtet genau dieses Verzeichnis. Ein `rename` ist entweder passiert
        // oder nicht — ein halb geschriebenes Task-File sieht damit niemand.
        try Data(markdown.utf8).write(to: target, options: .atomic)

        return Output(path: target, imageCount: savedImages.count, commentCount: comments.count)
    }

    // MARK: - Pre-Flight

    /// Exakt `<KEY>.md` oder `<KEY>_<titel>.md` — **kein** `contains`: `EVEN-2` darf sich
    /// `EVEN-2591` nicht einverleiben.
    public static func existingTaskFile(ticketKey: String, in directory: URL) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        return names.sorted().first {
            $0.hasSuffix(".md") && ($0 == "\(ticketKey).md" || $0.hasPrefix("\(ticketKey)_"))
        }
    }

    // MARK: - Scrubber-Stellen

    /// Genau die Stellen, an denen das Original `rescrub` anwendet. Der Default reicht unverändert
    /// durch; erst der Anonymizer-Folge-Task füllt die Naht.
    private func scrubbed(_ issue: JiraIssue) -> JiraIssue {
        JiraIssue(key: issue.key,
                  summary: scrubber(issue.summary),
                  issueType: issue.issueType,
                  reporter: issue.reporter, assignee: issue.assignee, creator: issue.creator,
                  meta: issue.meta,
                  description: scrubber(issue.description),
                  environment: scrubber(issue.environment),
                  ausgangslage: scrubber(issue.ausgangslage),
                  erwartetesErgebnis: scrubber(issue.erwartetesErgebnis),
                  erweiterteBeschreibung: scrubber(issue.erweiterteBeschreibung),
                  akzeptanzkriterien: scrubber(issue.akzeptanzkriterien),
                  customFields: issue.customFields.map {
                      JiraCustomField(id: $0.id, name: $0.name, value: scrubber($0.value))
                  },
                  extraFields: issue.extraFields.map {
                      JiraExtraField(id: $0.id, name: $0.name, value: scrubber($0.value))
                  },
                  subtasks: issue.subtasks.map {
                      JiraSubtaskRef(key: $0.key, summary: scrubber($0.summary))
                  },
                  linkedIssues: issue.linkedIssues.map {
                      JiraLinkedIssue(key: $0.key, summary: scrubber($0.summary),
                                      status: $0.status, relation: $0.relation)
                  },
                  attachments: issue.attachments,
                  images: issue.images)
    }

    private func scrubbed(_ content: JiraSubtaskContent) -> JiraSubtaskContent {
        JiraSubtaskContent(key: content.key,
                           summary: scrubber(content.summary),
                           description: scrubber(content.description),
                           akzeptanzkriterien: scrubber(content.akzeptanzkriterien),
                           customFields: content.customFields.map {
                               JiraCustomField(id: $0.id, name: $0.name, value: scrubber($0.value))
                           },
                           images: content.images,
                           nextImageIndex: content.nextImageIndex)
    }

    private func scrubbed(_ comment: JiraComment) -> JiraComment {
        JiraComment(id: comment.id, parentId: comment.parentId, author: comment.author,
                    authorAccountId: comment.authorAccountId, avatarUrl: comment.avatarUrl,
                    created: comment.created, updated: comment.updated,
                    body: scrubber(comment.body))
    }

    private func resolveSmartLinks(issue: JSONValue, subtasks: [JSONValue],
                                   comments: [JSONValue]) async -> [String: SmartLinkTarget]? {
        guard let smartLinks else { return nil }
        var documents: [JSONValue] = []
        for raw in [issue] + subtasks {
            documents += JiraFieldExtraction.adfDocuments(in: raw.value(at: ["fields"])?.objectValue ?? [:])
        }
        documents += comments.compactMap { $0.value(at: ["body"]) }
        return await smartLinks.resolve(documents: documents)
    }
}

/// Eine Sperre je Ticket für die Dauer eines Exports.
///
/// Sie liegt **weder** im Ticket-Ordner **noch** im Tasks-Verzeichnis: im Ticket-Ordner erschiene
/// sie im Anhang-Baum, der keine Dotfiles filtert, und im Tasks-Verzeichnis hielte
/// `TaskFile.belongsToTicket` sie für eine Datei des Tickets — die Regel dort akzeptiert nach dem
/// Schlüssel ausdrücklich auch einen Punkt.
///
/// Der Pre-Flight schützt nur die `.md`; Bilder und Avatare landen vorher auf der Platte, und zwei
/// gleichzeitige Läufe mischten sich dort.
final class ExportLock {
    private let file: URL
    /// Ein abgestürzter Lauf darf das Ticket nicht dauerhaft aussperren.
    private static let staleAfter: TimeInterval = 600

    init?(ticketKey: String) {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban/.locks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("\(ticketKey).lock")

        if let modified = try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > Self.staleAfter {
            try? FileManager.default.removeItem(at: file)
        }
        // `O_EXCL` ist der eigentliche Test: anlegen gelingt genau einmal.
        let descriptor = open(file.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        guard descriptor >= 0 else { return nil }
        close(descriptor)
    }

    func release() { try? FileManager.default.removeItem(at: file) }
}

public extension JiraClient {
    /// Der Generator zu diesem Client.
    ///
    /// Zusammengebaut wird er **hier**, weil der Transport (`http`) modulintern ist und bleiben
    /// soll: die App braucht den Generator, nicht den Client darunter. `baseUrls` sind die
    /// Jira-Instanzen, gegen die Smart-Links aufgelöst werden dürfen — ein Link auf eine fremde
    /// Instanz behält sein Label.
    func taskGenerator(baseUrls: [String], scrubber: TextScrubber = .passthrough) -> JiraTaskGenerator {
        JiraTaskGenerator(client: self,
                          assets: TaskAssetDownloader(jira: http),
                          smartLinks: SmartLinks(http: http, baseUrls: baseUrls),
                          scrubber: scrubber)
    }
}
