import Foundation

/// Der Ablageort der Projektbilder: `~/Library/Application Support/Kanban/images/<key>.<ext>`.
///
/// Das gewählte Bild wird **kopiert**, nicht verlinkt. Ein Pfad in den Download-Ordner hielte genau
/// so lange, bis dort jemand aufräumt, und die Kopfzeile stünde ohne Bild da, ohne dass etwas an
/// der Einstellung falsch wäre. Der Ordner gehört Kanban, wie `tasks/` und `docs/` daneben.
///
/// Ein Projekt hat höchstens **ein** Bild: der Dateiname ist der Projekt-Key. Ein neues Bild ersetzt
/// das alte, auch wenn es eine andere Endung hat — sonst blieben Leichen liegen, auf die nichts mehr
/// zeigt.
public enum ProjectImageStore {
    /// Was `NSImage` lesen kann und in einer Kopfzeile Sinn ergibt.
    ///
    /// `svg` und `pdf` sind die beiden **Vektor**-Formate darin: AppKit lädt SVG seit macOS 13 von
    /// sich aus (`_NSSVGImageRep`, nachgemessen unter 15.2 — Grösse kommt aus dem viewBox-Attribut,
    /// Pixelmasse bleiben 0, weil es keine gibt). Sie skalieren auf Zeilenhöhe verlustfrei, während
    /// ein PNG dort weich wird; deshalb sind sie hier die bessere Wahl, nicht bloss eine weitere.
    public static let allowedExtensions = ["svg", "pdf", "png", "jpg", "jpeg",
                                           "gif", "heic", "tiff", "bmp"]

    public static var directory: String {
        (KanbanConfig.supportDirectory as NSString).appendingPathComponent("images")
    }

    /// Kopiert `source` als Bild des Projekts und gibt den neuen absoluten Pfad zurück.
    ///
    /// Vorhandene Bilder desselben Projekts werden vorher entfernt — auch die mit anderer Endung,
    /// siehe oben. Wirft, wenn die Datei nicht lesbar oder der Ordner nicht schreibbar ist; der
    /// Aufrufer zeigt das an, statt still nichts zu tun.
    @discardableResult
    public static func store(source: URL, projectKey: String) throws -> String {
        let fm = FileManager.default
        let ext = source.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw ProjectImageError.unsupportedType(ext)
        }
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        remove(projectKey: projectKey)

        let ziel = (directory as NSString)
            .appendingPathComponent("\(projectKey).\(ext)")
        try fm.copyItem(at: source, to: URL(fileURLWithPath: ziel))
        return ziel
    }

    /// Entfernt jedes gespeicherte Bild des Projekts. Still: es aufzurufen, wo keins liegt, ist der
    /// Normalfall (jedes `store` tut es zuerst).
    public static func remove(projectKey: String) {
        let fm = FileManager.default
        for ext in allowedExtensions {
            let pfad = (directory as NSString).appendingPathComponent("\(projectKey).\(ext)")
            if fm.fileExists(atPath: pfad) { try? fm.removeItem(atPath: pfad) }
        }
    }
}

public enum ProjectImageError: LocalizedError, Sendable {
    case unsupportedType(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext):
            let liste = ProjectImageStore.allowedExtensions.joined(separator: ", ")
            return ext.isEmpty
                ? "Datei ohne Endung — möglich sind: \(liste)."
                : "„\(ext)“ kann nicht als Bild gelesen werden — möglich sind: \(liste)."
        }
    }
}
