import Foundation

/// Der Pfad, den die Kopier-Knöpfe in die Zwischenablage legen — für das Task-File wie für jede
/// Datei im Task-Ordner.
///
/// **Relativ zum Repo**, solange die Datei darin liegt: das ist, was man in Claudes Console tippen
/// würde (`docs/tasks/EVEN-3530_foo.md`; Claudes cwd *ist* das Repo). Liegt sie ausserhalb,
/// **absolut** — seit dem Umzug nach Application Support gilt das für Task-File und Task-Ordner
/// fast jedes Projekts. Ein blosser Dateiname wäre dort die schlechteste Antwort von allen: weder
/// Claude noch der Finder noch eine Shell findet damit etwas, und sichtbar falsch ist er auch nicht.
public enum ClipboardPath {
    /// - Parameter repoDir: absoluter Pfad des Haupt-Repos (`ProjectConfig.repoDir`), oder nil.
    public static func forCopying(_ url: URL, repoDir: String?) -> String {
        let full = url.standardizedFileURL.path
        guard let repoDir, !repoDir.isEmpty else { return full }
        let root = URL(fileURLWithPath: repoDir).standardizedFileURL.path
        let base = root.hasSuffix("/") ? root : root + "/"
        return full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
    }
}
