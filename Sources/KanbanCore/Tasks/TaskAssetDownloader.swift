import Foundation
import CryptoKit

/// Lädt, was neben dem Task-File liegt: die Bilder und Anhänge des Tickets nach
/// `<tasksDir>/<TICKET>/`, die Profilbilder der Kommentar-Autoren nach `<TICKET>/avatars/`.
///
/// Heruntergeladen statt verlinkt, obwohl die Avatar-URLs öffentlich sind: die Kommentar-Ansicht
/// rendert mit `loadHTMLString` und bettet die Bytes als data-URI ein. Ein `https`-Verweis würde
/// dort bei **jedem** Rendern nachladen — bei Gravatar-Autoren über einen Dritten, also mit
/// IP-Abfluss je Ansicht.
public struct TaskAssetDownloader: Sendable {
    private let jira: ModuleHTTPClient
    private let avatars: ModuleHTTPClient

    public init(jira: ModuleHTTPClient, avatars: ModuleHTTPClient = .avatars()) {
        self.jira = jira
        self.avatars = avatars
    }

    // MARK: - Bilder und Anhänge

    /// Ein Bild ohne `content`-URL wird übersprungen, und ein fehlgeschlagener Download nimmt nur
    /// sich selbst mit — der Rest des Exports wird trotzdem geschrieben.
    public func saveImages(_ images: [JiraIssueImage], ticketKey: String,
                           tasksDirectory: URL) async -> [SavedImage] {
        guard !images.isEmpty else { return [] }
        let targetDirectory = tasksDirectory.appendingPathComponent(ticketKey, isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        var saved: [SavedImage] = []
        for image in images {
            guard let url = image.url, !url.isEmpty else { continue }
            guard let response = try? await jira.getBinary(url) else { continue }
            let file = targetDirectory.appendingPathComponent(image.filename)
            guard (try? response.data.write(to: file)) != nil else { continue }
            saved.append(SavedImage(filename: image.filename,
                                    relativePath: "\(ticketKey)/\(Self.pathEncoded(image.filename))",
                                    index: image.index,
                                    unreferenced: image.unreferenced))
        }
        return saved
    }

    // MARK: - Profilbilder

    /// Je Autor **ein** Download, auch wenn er zehnmal geschrieben hat. Gibt die Kommentare mit
    /// lokalem `avatar`-Pfad statt der Fernadresse zurück; ein Autor ohne brauchbares Bild behält
    /// keins und die Anzeige fällt auf ihr eigenes Kürzel zurück.
    public func saveAvatars(for comments: [JiraComment], ticketKey: String,
                            tasksDirectory: URL) async -> [String: String] {
        let urls = comments.compactMap(\.avatarUrl).filter { !$0.isEmpty }
        guard !urls.isEmpty else { return [:] }

        let avatarDirectory = tasksDirectory
            .appendingPathComponent(ticketKey, isDirectory: true)
            .appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)

        var localPathByURL: [String: String] = [:]
        // Der Dateiname kommt aus dem Anzeigenamen und ist damit nicht eindeutig: zwei Autoren
        // „Michael Meier" schrieben sonst in dieselbe Datei und einer bekäme das Gesicht des
        // anderen. Wer den Namen zuerst belegt, behält ihn; jeder weitere bekommt ein Kürzel seiner
        // Bild-URL angehängt.
        var ownerOfName: [String: String] = [:]

        for comment in comments {
            guard let url = comment.avatarUrl, !url.isEmpty, localPathByURL[url] == nil else { continue }
            guard AvatarHosts.isAllowed(url), !AvatarHosts.isInitialsFallback(url) else { continue }
            guard let response = try? await avatars.getBinary(url,
                                                              maxBytes: AvatarHosts.maxBytes,
                                                              maxRedirects: AvatarHosts.maxRedirects),
                  !AvatarHosts.isInitialsFallback(response.finalURL)
            else { continue }

            let safe = Self.safeName(comment.author)
            let owner = ownerOfName[safe]
            let stem = (owner == nil || owner == url) ? safe : "\(safe)-\(Self.shortHash(url))"
            if owner == nil { ownerOfName[safe] = url }

            let filename = "\(stem).\(Self.fileExtension(for: response.contentType))"
            let file = avatarDirectory.appendingPathComponent(filename)
            guard (try? response.data.write(to: file)) != nil else { continue }
            localPathByURL[url] = "\(ticketKey)/avatars/\(filename)"
        }

        // Ein leerer `avatars/`-Ordner wäre eine Zeile im Anhang-Baum, hinter der nichts steht.
        if (try? FileManager.default.contentsOfDirectory(atPath: avatarDirectory.path))?.isEmpty ?? false {
            try? FileManager.default.removeItem(at: avatarDirectory)
        }
        return localPathByURL
    }

    // MARK: - Namen

    /// Der Anzeigename aus Jira ist **nicht** vertrauenswürdig: er kommt aus einem fremden Feld und
    /// wird hier zu einem Pfad. Auf `[A-Za-z0-9_-]` reduziert kann er das Verzeichnis nicht mehr
    /// verlassen — und nebenbei löst das den `:` in Jiras accountId, an dem das Original die Regel
    /// festmacht.
    static func safeName(_ author: String) -> String {
        let reduced = author.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
                ? character : "-"
        }
        let collapsed = String(reduced).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let trimmed = String(collapsed.prefix(40))
        return trimmed.isEmpty || trimmed.allSatisfy { $0 == "-" } ? "autor" : trimmed
    }

    static func shortHash(_ text: String) -> String {
        Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    static func fileExtension(for contentType: String?) -> String {
        let type = (contentType ?? "").lowercased()
        if type.contains("svg") { return "svg" }
        if type.contains("jpeg") || type.contains("jpg") { return "jpg" }
        return "png"
    }

    /// Wie `encodeURIComponent`: der Dateiname bleibt auf der Platte im Original, im Markdown steht
    /// er kodiert — sonst zerbricht ein Leerzeichen den Link.
    static func pathEncoded(_ filename: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? filename
    }
}
