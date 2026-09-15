import Foundation

/// Ein Jira-Kommentar, wie ihn `comments.json` neben dem Task-File führt.
public struct TaskComment: Sendable, Equatable, Decodable {
    /// Jiras Kommentar-Id. Optional, weil ältere Exporte sie nicht mitschreiben.
    public let id: String?
    /// Die Id des Kommentars, auf den dieser antwortet — Jiras Antwort-Funktion.
    public let parentId: String?
    public let author: String
    public let created: String       // ISO-8601 mit Offset, roh wie in der Datei
    public let body: String          // bereits Markdown (ADF wurde beim Export übersetzt)
    /// Profilbild, relativ zum Task-Ordner (`<TICKET>/avatars/<datei>`) — nur vorhanden, wenn der
    /// Export es mitgespeichert hat. Ohne Bild stehen die Initialen.
    public let avatar: String?

    public init(id: String? = nil, parentId: String? = nil,
                author: String, created: String, body: String, avatar: String? = nil) {
        self.id = id
        self.parentId = parentId
        self.avatar = avatar
        self.author = author
        self.created = created
        self.body = body
    }

    /// `id` kommt als String (`"115483"`), `parentId` als **Zahl** (`115217`) — dieselbe API, zwei
    /// Typen. Beide werden deshalb tolerant gelesen; ein Feld, das keins von beidem ist, gilt als
    /// nicht vorhanden statt die ganze Datei scheitern zu lassen.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decode(String.self, forKey: .author)
        created = try container.decode(String.self, forKey: .created)
        body = try container.decode(String.self, forKey: .body)
        id = Self.identifier(container, .id)
        parentId = Self.identifier(container, .parentId)
        avatar = try? container.decodeIfPresent(String.self, forKey: .avatar)
    }

    private static func identifier(_ container: KeyedDecodingContainer<CodingKeys>,
                                   _ key: CodingKeys) -> String? {
        if let text = try? container.decode(String.self, forKey: key) { return text }
        if let number = try? container.decode(Int.self, forKey: key) { return String(number) }
        return nil
    }

    private enum CodingKeys: String, CodingKey { case id, parentId, author, created, body, avatar }
}

/// Die Kommentar-Diskussion eines Tickets, als Markdown für die Detailansicht.
///
/// Vorher stand dort die **rohe JSON-Datei** in einem ```json-Block — technisch ehrlich und
/// unlesbar. Jetzt: eine Karte je Beitrag mit Kürzel-Avatar, Autor und Zeitpunkt, **Antworten
/// eingerückt unter ihrem Bezug** — so, wie Jira die Diskussion selbst zeigt.
public enum CommentThread {
    /// nil, wenn der Inhalt keine Kommentar-Liste ist — dann bleibt es beim rohen JSON-Block,
    /// statt eine fremde Datei zu verstümmeln.
    public static func parse(_ json: String) -> [TaskComment]? {
        guard let data = json.data(using: .utf8),
              let comments = try? JSONDecoder().decode([TaskComment].self, from: data),
              !comments.isEmpty
        else { return nil }
        return comments
    }

    /// Die Liste in Lesereihenfolge: jede Wurzel, direkt gefolgt von ihren Antworten (Tiefe 1, 2, …).
    ///
    /// Eine Antwort, deren Bezug fehlt (Kommentar gelöscht, älterer Export ohne Ids), wird zur
    /// Wurzel — sie verschwinden zu lassen wäre schlimmer als sie flach zu zeigen.
    public static func ordered(_ comments: [TaskComment]) -> [(comment: TaskComment, depth: Int)] {
        let known = Set(comments.compactMap(\.id))
        var childrenByParent: [String: [TaskComment]] = [:]
        var roots: [TaskComment] = []
        for comment in comments {
            if let parent = comment.parentId, known.contains(parent) {
                childrenByParent[parent, default: []].append(comment)
            } else {
                roots.append(comment)
            }
        }

        var result: [(TaskComment, Int)] = []
        func append(_ comment: TaskComment, depth: Int) {
            result.append((comment, depth))
            guard let id = comment.id, depth < 4 else { return }   // Schutz gegen Zyklen
            for child in childrenByParent[id] ?? [] { append(child, depth: depth + 1) }
        }
        for root in roots { append(root, depth: 0) }
        return result
    }

    /// Ein `<div>` je Kommentar, Kopfzeile mit Kürzel, Autor und Zeitpunkt, darunter der Body **als
    /// Markdown**. Die Leerzeilen um den Body sind Pflicht: cmark behandelt einen Block bis zur
    /// nächsten Leerzeile als rohes HTML — ohne sie bliebe `**fett**` im Kommentar stehen.
    /// `directory` ist der Task-Ordner: relativ dazu liegen die Profilbilder. Sie werden **inline
    /// als data-URI** eingebettet, weil WKWebViews `loadHTMLString` keinen Dateizugriff hat — ein
    /// `file://`-Bild bliebe ein kaputtes Symbol (dieselbe Regel wie bei den Task-Bildern). Sie sind
    /// ~5 KB gross, das fällt nicht ins Gewicht.
    public static func markdown(_ comments: [TaskComment], directory: URL? = nil,
                                now: Date = Date()) -> String {
        let names = Set(comments.map(\.author))
        return ordered(comments).map { entry in
            let comment = entry.comment
            let depth = min(entry.depth, 3)
            return """
            <div class="comment\(depth > 0 ? " reply depth-\(depth)" : "")">
            <div class="comment-head">\(avatarTag(comment, directory: directory))\
            <span class="comment-author">\(escape(comment.author))</span>\
            <span class="comment-date" title="\(escape(absolute(comment.created)))">\
            \(relative(comment.created, now: now))</span></div>

            \(mentions(in: comment.body.trimmingCharacters(in: .whitespacesAndNewlines), names: names))

            </div>
            """
        }.joined(separator: "\n\n")
    }

    /// Das Profilbild, wenn der Export eins mitgespeichert hat — sonst die Initialen. Ein fehlendes
    /// oder unlesbares Bild fällt still auf die Buchstaben zurück; eine kaputte Bildmarke im
    /// Kommentarkopf wäre schlechter als zwei ehrliche Zeichen.
    static func avatarTag(_ comment: TaskComment, directory: URL?) -> String {
        if let relative = comment.avatar, let directory,
           let data = try? Data(contentsOf: directory.appendingPathComponent(relative)),
           !data.isEmpty {
            let mime = relative.lowercased().hasSuffix(".svg") ? "image/svg+xml"
                : relative.lowercased().hasSuffix(".jpg") ? "image/jpeg" : "image/png"
            return "<img class=\"comment-avatar\" src=\"data:\(mime);base64,\(data.base64EncodedString())\" "
                 + "alt=\"\(escape(initials(comment.author)))\">"
        }
        return "<span class=\"comment-avatar\">\(escape(initials(comment.author)))</span>"
    }

    /// „PA", „SX" — dasselbe Kürzel, das Jira zeigt, wenn es kein Profilbild hat.
    public static func initials(_ author: String) -> String {
        let parts = author.split(separator: " ").filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// `@Name` wird zur Erwähnung — aber **nur** für Namen, die in dieser Diskussion als Autor
    /// vorkommen. Ein Muster wie „@ + Grossbuchstabe" träfe auch Handles, E-Mails und Code.
    static func mentions(in body: String, names: Set<String>) -> String {
        var text = body
        for name in names.sorted(by: { $0.count > $1.count }) {   // längster zuerst, sonst Teiltreffer
            text = text.replacingOccurrences(
                of: "@\(name)", with: "<span class=\"mention\">@\(escape(name))</span>")
        }
        return text
    }

    /// `2026-09-02T08:22` → „gestern", „vor 3 Tagen" — wie in Jira. Das genaue Datum steht im
    /// Tooltip, damit die Kürze nichts verdeckt.
    public static func relative(_ raw: String, now: Date = Date()) -> String {
        guard let date = parse(date: raw) else { return raw }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.unitsStyle = .full
        // `.named` sagt „gestern" statt „vor 1 Tag" — genau die Sprache, die Jira selbst benutzt.
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    public static func absolute(_ raw: String) -> String {
        guard let date = parse(date: raw) else { return raw }
        return display.string(from: date)
    }

    static func parse(date raw: String) -> Date? {
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds],
                                                      [.withInternetDateTime]] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        return formatter
    }()

    /// Autornamen landen in HTML — ein `&` oder `<` darf die Kopfzeile nicht zerlegen.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
