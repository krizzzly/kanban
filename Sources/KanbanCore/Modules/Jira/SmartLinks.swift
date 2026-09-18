import Foundation

/// Smart-Links — Jira- und Confluence-Karten mit echtem Titel. Port von Hermes' `lib/smart-links.js`.
///
/// In Jira und Confluence ist ein Link auf ein Ticket oder eine Seite keine URL, sondern eine Karte:
/// Ticket-Key + Summary + Status-Lozenge, bzw. Seitentitel. Der ADF-Konverter sieht davon nur
/// `inlineCard.attrs.url`, und was darin steht, ist verlustbehaftet:
///
///     /pages/1702625281/NonEHS+ab+2025+Verf+gung+erstellen+und+senden   ← Umlaut ist weg
///     /browse/CORETEST-4207                                             ← Titel war nie drin
///
/// Aufgelöst wird **vor** dem Konverter, damit der synchron bleibt; das Ergebnis geht als
/// `smartLinks`-Map in `ADFToMarkdown.convert`.
///
/// **Confluence läuft über denselben Client wie Jira.** Beide Produkte liegen auf derselben
/// Atlassian-Site, der Host steht damit schon in der Allowlist des Transports, und ein
/// Cloud-API-Token ist kontogebunden statt produktgebunden. Ein eigenes Confluence-Modul, das
/// Kanban gar nicht betreibt, wäre dafür nicht nötig — und wenn die Annahme doch nicht trägt,
/// kostet das nur das alte Label.
///
/// Fail-open an jeder Stelle: ein nicht erreichbares Ticket, eine fremde Site oder ein fehlendes
/// Recht führen auf den Slug aus der URL zurück, nie auf einen Fehler.
public struct SmartLinks: Sendable {
    /// Obergrenze je Export. Hermes deckelt bei 40 **pro Dokument**; ein Export hat aber viele
    /// Dokumente (Beschreibung, jedes Custom Field, jeder Subtask, alle Kommentare), und ein
    /// gemeinsames 40er-Budget löste weniger auf als der Vergleichsexport. Deshalb hier ein
    /// **Runaway-Guard statt einer funktionalen Grenze**: bei realistischen Tickets bindet er nie,
    /// ein pathologisches Dokument fängt er trotzdem. Die Ersparnis kommt aus der Deduplizierung
    /// über alle Dokumente, und die ändert nur die Anzahl Anfragen, nicht das Ergebnis.
    public static let defaultLimit = 200

    public enum Kind: Sendable, Equatable {
        case jiraIssue(key: String)
        case confluencePage(pageId: String)
        case confluenceComment(pageId: String, commentId: String)
    }

    private let http: ModuleHTTPClient
    /// Die konfigurierten Jira-Basis-URLs. Angefragt wird nur, was auf einer davon liegt — ein Link
    /// auf eine fremde Atlassian-Instanz behält sein Fallback-Label (der Host-Guard des Transports
    /// lehnte ihn ohnehin ab).
    private let baseUrls: [String]

    public init(http: ModuleHTTPClient, baseUrls: [String]) {
        self.http = http
        self.baseUrls = baseUrls
    }

    // MARK: - Klassifikation

    /// Was ist das für ein Link? Nur die Formen, die Jira/Confluence als Karte rendern.
    public static func classify(_ url: String) -> Kind? {
        guard !url.isEmpty else { return nil }

        // Jira-Ticket: .../browse/KEY, oder ein Board-Link mit ?selectedIssue=KEY
        if let key = firstGroup(in: url, pattern: #"/browse/([A-Z][A-Z0-9_]*-\d+)"#)
            ?? firstGroup(in: url, pattern: #"[?&]selectedIssue=([A-Z][A-Z0-9_]*-\d+)"#) {
            return .jiraIssue(key: key)
        }

        // Confluence-Kurzlink: /wiki/x/<tiny>
        if let tiny = firstGroup(in: url, pattern: #"/wiki/x/([A-Za-z0-9_-]+)"#),
           let id = pageIdFromTinyLink(tiny) {
            return .confluencePage(pageId: id)
        }

        // Kommentar vor Seite prüfen: die Kommentar-URL erfüllt beide Muster, und der Kommentar
        // ist die genauere Aussage.
        let pageId = firstGroup(in: url, pattern: #"/pages/(\d+)"#)
        let commentId = firstGroup(in: url, pattern: #"[?&]focusedCommentId=(\d+)"#)
        if let pageId, let commentId { return .confluenceComment(pageId: pageId, commentId: commentId) }
        if let pageId { return .confluencePage(pageId: pageId) }

        return nil
    }

    /// Confluence-Kurzlink `/wiki/x/AgDRM` → Page-Id.
    ///
    /// Der Tiny-Code **ist** die Page-Id: Base64 eines Little-Endian-Longs, url-safe (`/`→`-`,
    /// `+`→`_`), und die abschliessenden Null-Bytes sind als `A` weggeschnitten. Deshalb wird mit
    /// `A` aufgefüllt und nicht mit `=`. Kein Request nötig — und ein Kurzlink ist im Markdown
    /// sonst vollkommen nichtssagend.
    public static func pageIdFromTinyLink(_ tiny: String) -> String? {
        guard !tiny.isEmpty, tiny.count <= 12,
              tiny.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }

        var base64 = tiny.replacingOccurrences(of: "-", with: "/")
                         .replacingOccurrences(of: "_", with: "+")
        while base64.count % 4 != 0 { base64 += "A" }
        guard let decoded = Data(base64Encoded: base64) else { return nil }

        var id: UInt64 = 0
        for (offset, byte) in decoded.prefix(8).enumerated() {
            id |= UInt64(byte) << (8 * UInt64(offset))
        }
        // Dieselbe Schranke wie im Original (`Number.MAX_SAFE_INTEGER`): darüber ist die Zahl
        // ohnehin keine gültige Page-Id mehr, sondern verrutschte Bytes.
        guard id > 0, id <= 9_007_199_254_740_991 else { return nil }
        return String(id)
    }

    /// Das Label ohne API — Ticket-Key bzw. Slug aus der URL. Genau das, was der Konverter vor den
    /// Smart-Links gemacht hat, und weiterhin der Rückfallpfad.
    public static func fallbackLabel(_ url: String) -> String { ADFToMarkdown.cardLabel(url) }

    // MARK: - Einsammeln

    /// Alle auflösbaren Karten-/Link-Ziele eines ADF-Dokuments, dedupliziert.
    ///
    /// Neben den Karten auch Text-Links, deren sichtbarer Text die URL selbst ist: dort steht heute
    /// dieselbe nichtssagende URL im Export. Ein Link mit eigenem Text bleibt unangetastet — den
    /// hat jemand bewusst so beschriftet.
    public static func collectURLs(in adf: JSONValue) -> [String] {
        var urls: [String] = []
        var seen = Set<String>()

        func add(_ url: String) {
            guard !url.isEmpty, classify(url) != nil, seen.insert(url).inserted else { return }
            urls.append(url)
        }

        func walk(_ node: JSONValue) {
            if let array = node.arrayValue {
                for child in array { walk(child) }
                return
            }
            guard let object = node.objectValue else { return }

            switch object["type"]?.stringValue {
            case "inlineCard", "blockCard", "embedCard":
                add(node.value(at: ["attrs", "url"])?.stringValue ?? "")
            case "text":
                let text = object["text"]?.stringValue ?? ""
                for mark in object["marks"]?.arrayValue ?? []
                where mark.value(at: ["type"])?.stringValue == "link" {
                    let href = mark.value(at: ["attrs", "href"])?.stringValue ?? ""
                    if text.trimmingCharacters(in: .whitespaces) == href.trimmingCharacters(in: .whitespaces) {
                        add(href)
                    }
                }
            default:
                break
            }

            if let content = object["content"] { walk(content) }
        }

        walk(adf)
        return urls
    }

    // MARK: - Auflösen

    /// Mehrere ADF-Dokumente in **einem** Durchgang, mit einem gemeinsamen Budget — sonst zahlt ein
    /// Ticket mit vierzig Kommentaren das Limit je Kommentar.
    public func resolve(documents: [JSONValue], limit: Int = SmartLinks.defaultLimit) async -> [String: SmartLinkTarget] {
        await resolve(urls: documents.flatMap { Self.collectURLs(in: $0) }, limit: limit)
    }

    public func resolve(urls: [String], limit: Int = SmartLinks.defaultLimit) async -> [String: SmartLinkTarget] {
        var unique: [String] = []
        var seen = Set<String>()
        for url in urls where !url.isEmpty && seen.insert(url).inserted { unique.append(url) }
        guard !unique.isEmpty else { return [:] }

        let todo = Array(unique.prefix(limit))
        var resolved: [String: SmartLinkTarget] = [:]
        await withTaskGroup(of: (String, SmartLinkTarget?).self) { group in
            for url in todo {
                group.addTask { (url, await self.resolveOne(url)) }
            }
            for await (url, target) in group {
                if let target { resolved[url] = target }
            }
        }
        return resolved
    }

    private func resolveOne(_ url: String) async -> SmartLinkTarget? {
        if let cached = await SmartLinkCache.shared.entry(for: url) { return cached }
        guard let kind = Self.classify(url) else {
            return await SmartLinkCache.shared.store(nil, for: url)
        }

        let target: SmartLinkTarget?
        do {
            switch kind {
            case .jiraIssue(let key):
                target = try await jiraIssue(url: url, key: key)
            case .confluenceComment(let pageId, let commentId):
                target = try await confluenceComment(url: url, pageId: pageId, commentId: commentId)
            case .confluencePage(let pageId):
                target = try await confluencePage(url: url, pageId: pageId)
            }
        } catch {
            // Kein Recht auf das Ticket, gelöschte Seite, fremde Instanz — das Label fällt zurück,
            // der Export läuft weiter.
            target = nil
        }
        return await SmartLinkCache.shared.store(target, for: url)
    }

    private func jiraIssue(url: String, key: String) async throws -> SmartLinkTarget? {
        guard let base = base(for: url) else { return nil }
        let data: JSONValue = try await http.getJSON("\(base)/rest/api/3/issue/\(key)?fields=summary,status")
        guard let summary = data.value(at: ["fields", "summary"])?.stringValue else { return nil }
        return SmartLinkTarget(label: "\(key): \(summary)",
                               chip: data.value(at: ["fields", "status", "name"])?.stringValue)
    }

    private func confluencePage(url: String, pageId: String) async throws -> SmartLinkTarget? {
        guard let base = base(for: url) else { return nil }
        let page: JSONValue = try await http.getJSON("\(base)/wiki/api/v2/pages/\(pageId)")
        guard let title = page.value(at: ["title"])?.stringValue else { return nil }
        return SmartLinkTarget(label: title)
    }

    private func confluenceComment(url: String, pageId: String, commentId: String) async throws -> SmartLinkTarget? {
        guard let base = base(for: url) else { return nil }
        // Welcher der beiden Kommentar-Typen es ist, sagt die URL nicht — also beide Ressourcen
        // versuchen. Der Titel ist bei beiden „Re: <Seitentitel>", genau wie in der Karte.
        for resource in ["footer-comments", "inline-comments"] {
            if let comment: JSONValue = try? await http.getJSON("\(base)/wiki/api/v2/\(resource)/\(commentId)"),
               let title = comment.value(at: ["title"])?.stringValue {
                return SmartLinkTarget(label: title, chip: "Kommentar")
            }
        }
        // Kommentar weg oder nicht lesbar: die Seite ist die nächstbeste Aussage.
        guard let page = try await confluencePage(url: url, pageId: pageId) else { return nil }
        return SmartLinkTarget(label: page.label, chip: "Kommentar")
    }

    /// Die konfigurierte Basis-URL, auf der diese URL liegt — oder nil. Der Vergleich ist bewusst
    /// streng: gefragt wird nur, was konfiguriert ist.
    private func base(for url: String) -> String? {
        guard let host = URL(string: url)?.host?.lowercased() else { return nil }
        return baseUrls.first { URL(string: $0)?.host?.lowercased() == host }
    }

    private static func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }
}

/// Auflösungen gelten prozessweit — ein Export verlinkt dieselben Tickets dutzendfach, und ein
/// Summary, das sich während eines Laufs ändert, spielt keine Rolle. Gedeckelt, damit eine lange
/// laufende App nicht unbegrenzt wächst; bei Überlauf wird geleert statt einzeln verdrängt (wie im
/// Original — eine LRU wäre mehr Buchhaltung, als der Fall wert ist).
actor SmartLinkCache {
    static let shared = SmartLinkCache()

    private var entries: [String: SmartLinkTarget?] = [:]
    private let limit = 2000

    /// Das äussere Optional trennt „nicht im Cache" von „im Cache als nicht auflösbar".
    func entry(for url: String) -> SmartLinkTarget?? { entries[url] }

    @discardableResult
    func store(_ target: SmartLinkTarget?, for url: String) -> SmartLinkTarget? {
        if entries.count >= limit { entries.removeAll() }
        entries[url] = target
        return target
    }

    func clear() { entries.removeAll() }
}
