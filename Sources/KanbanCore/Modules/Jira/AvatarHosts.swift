import Foundation

/// Die Hosts, von denen ein Profilbild kommen darf.
///
/// `gravatar.com` steht mit drin, weil Jira für einen Autor **ohne** eigenes Bild gar keine
/// `atl-paas`-URL liefert, sondern eine Gravatar-URL, die Atlassians Initialen-PNG nur als
/// Fallback im `d=`-Parameter mitführt. Ohne diesen Host fiele für jeden solchen Autor das Bild
/// still weg.
public enum AvatarHosts {
    public static let allowed = ["atl-paas.net", "atlassian.com", "atlassian.net", "gravatar.com"]

    /// Höchstens fünf Umleitungen: Gravatars Kette ist zwei Sprünge lang
    /// (`secure.gravatar.com` → `i1.wp.com` → Bild), fünf lassen Luft und binden real nie.
    public static let maxRedirects = 5

    /// Ein Profilbild ist rund zehn Kilobyte; zwei Megabyte sind eine Schranke gegen Unfug,
    /// keine Einschränkung.
    public static let maxBytes = 2 * 1024 * 1024

    /// Nur `https`, und nur ein Host aus der Liste — inklusive Subdomains
    /// (`secure.gravatar.com`, `avatar-management--avatars.eu-west-1.prod.public.atl-paas.net`).
    public static func isAllowed(_ url: String) -> Bool {
        guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https",
              let host = parsed.host?.lowercased() else { return false }
        return allowed.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// Atlassians Initialen-Bild ist **kein** Profilbild, sondern ein Rasterbild derselben zwei
    /// Buchstaben, die die Anzeige ohnehin selbst zeichnet — im fremden Stil und mit ~9 KB je Autor
    /// und Ticket. Ein solches Ergebnis wird verworfen, damit die Kommentar-Ansicht auf ihr eigenes
    /// Kürzel zurückfällt. Erkennbar am Pfad, sowohl direkt als auch als Ziel der Gravatar-Umleitung.
    public static func isInitialsFallback(_ url: String?) -> Bool {
        (url ?? "").contains("/initials/")
    }
}
