import Foundation

/// Wohin ein angeklickter Link in der Knowledgebase führt.
public enum KBLinkTarget: Equatable, Sendable {
    /// Eine Datei **in** der Knowledgebase — die Ansicht springt dorthin, statt den Finder zu rufen.
    case file(path: String, fragment: String?)
    /// Eine lokale Datei **ausserhalb** der Knowledgebase: die KB verweist mit
    /// `../../core/docs/business-case-structure.md` oder `../../../../core/config/packages/…yaml`
    /// bis ins Projekt-Repo. Auch die wird gezeigt statt weggereicht — nur eben als Quelltext.
    case outsideFile(path: String)
    /// Sprungmarke im selben Dokument — die Web-Ansicht scrollt selbst.
    case fragment(String)
    /// Alles, was keine lokale Datei ist: http(s), mailto, …
    case external(URL)
}

/// Auflösung der Links, die in den Markdown-Dateien stehen.
///
/// Die Knowledgebase ist ein Geflecht: `README.md`, `../Common/HistoryEntry.md`,
/// `../../ueberblick/architektur.md#zwei-cqrs-generationen`. Ohne diese Auflösung landete jeder
/// Klick über `NSWorkspace.open` beim Finder — man verlässt beim Lesen die Ansicht, in der man liest.
public enum KBLink {
    /// `url` ist bereits absolut: WKWebView löst den relativen Link gegen die `baseURL` des
    /// Dokuments auf, bevor der Klick hier ankommt.
    ///
    /// - Parameters:
    ///   - currentFile: die gerade angezeigte Datei — nur so ist „Sprungmarke im selben Dokument"
    ///     von „andere Datei" zu unterscheiden.
    ///   - root: Wurzel der Knowledgebase. Was darunter liegt, bleibt in der Ansicht; was darüber
    ///     hinausführt, geht nach draussen.
    public static func resolve(_ url: URL, currentFile: String, root: String) -> KBLinkTarget {
        guard url.isFileURL else { return .external(url) }

        let path = url.standardizedFileURL.path
        let fragment = url.fragment?.removingPercentEncoding.flatMap { $0.isEmpty ? nil : $0 }

        if path == standardized(currentFile), let fragment {
            return .fragment(fragment)
        }

        let rootPath = standardized(root)
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return .outsideFile(path: path) }

        return .file(path: path, fragment: fragment)
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
