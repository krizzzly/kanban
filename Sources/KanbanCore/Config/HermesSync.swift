import Foundation

/// Schreibt die Projektliste zurück in eine vorhandene `~/.hermes/config.json`.
///
/// Kanban ist der Owner (`HermesImport` hat einmalig übernommen), aber die Hermes-CLI und die
/// MCP-Tools lesen weiter ihre eigene Datei. Ohne diesen Rückweg kennte ein in Kanban angelegtes
/// Projekt dort niemand.
///
/// Die Projektion ist **additiv**: `ProjectProjection.apply` fasst nur die Felder an, die die
/// Registry besitzt (`prefix`, `tasksPath`, `repoDir`, `baseUrl`, Forge-`path`, …). Tokens, URLs,
/// `backend` und jeder unbekannte Schlüssel bleiben stehen, und ein Projekt, das nur Hermes kennt,
/// wird nie gelöscht.
///
/// Ohne Hermes auf der Maschine passiert nichts — kein Fehler, keine Datei.
public enum HermesSync {
    /// Ob überhaupt ein Ziel existiert. Steuert auch, ob die Sektion in den Einstellungen erscheint.
    public static func isAvailable(hermesPath: String? = nil) -> Bool {
        FileManager.default.fileExists(atPath: hermesPath ?? HermesImport.defaultPath)
    }

    /// Ob der Rückweg eingeschaltet ist. Default **an**: wer eine Hermes-Config hat, will die zwei
    /// Dateien in aller Regel beieinander haben.
    public static func isEnabled(in document: JSONValue) -> Bool {
        document.value(at: ["hermes", "syncProjects"])?.boolValue ?? true
    }

    public enum Result: Sendable, Equatable {
        case synced(projects: Int)
        case unchanged
        case skipped(reason: String)
    }

    /// Projiziert die Projekte aus Kanbans Config in die Hermes-Config.
    @discardableResult
    public static func run(kanban document: JSONValue, hermesPath: String? = nil) -> Result {
        let path = hermesPath ?? HermesImport.defaultPath
        guard isEnabled(in: document) else { return .skipped(reason: "abgeschaltet") }
        guard FileManager.default.fileExists(atPath: path) else {
            return .skipped(reason: "keine Hermes-Config")
        }

        let store = ConfigStore(path: path)
        guard var hermes = try? store.load() else {
            return .skipped(reason: "Hermes-Config nicht lesbar")
        }

        let registry = merged(kanban: ProjectProjection.importing(from: document),
                              hermes: ProjectProjection.importing(from: hermes.root))
        guard !registry.keys.isEmpty else { return .skipped(reason: "keine Projekte") }

        let projected = ProjectProjection.apply(
            HermesPath.relativizing(registry, hermesBase: hermes.root.value(at: ["basePath"])?.stringValue),
            to: hermes.root)
        guard projected != hermes.root else { return .unchanged }

        hermes.root = projected
        // `force`: die Hermes-Datei gehört uns nicht, ihr mtime ist ständig in Bewegung (der Daemon
        // schreibt sie auch) — ein Konflikt-Abbruch hier hilft niemandem, die Projektion ist additiv.
        guard (try? store.save(hermes, force: true)) != nil else {
            return .skipped(reason: "Hermes-Config nicht schreibbar")
        }
        return .synced(projects: registry.keys.count)
    }

    /// Der Grund, warum hier überhaupt gemischt wird: `ProjectProjection.apply` betrachtet die
    /// Registry als Owner **aller** Modul-Blöcke und löscht einen Eintrag, dessen Block sie nicht
    /// kennt. Kanbans Config kennt aber nur Jira, GitLab und GitHub — ungemischt würde jeder Sync
    /// Hermes' Confluence-, Vertec-, Jenkins- und DockerHub-Einträge wegräumen.
    ///
    /// Also: Kanbans Werte gewinnen, wo Kanban welche hat (Jira, die Forge und alles, was im
    /// Projekt-Editor eingetragen wurde), und für die übrigen Module bleibt stehen, was in Hermes
    /// steht.
    static func merged(kanban: ProjectRegistry, hermes: ProjectRegistry) -> ProjectRegistry {
        var result = kanban
        for key in kanban.keys {
            guard var record = kanban[key], let existing = hermes[key] else { continue }
            record.confluence = record.confluence ?? existing.confluence
            record.vertec = record.vertec ?? existing.vertec
            record.jenkins = record.jenkins ?? existing.jenkins
            record.dockerhub = record.dockerhub ?? existing.dockerhub
            result[key] = record
        }
        return result
    }
}

/// Pfade so schreiben, dass **Hermes** sie findet.
///
/// Hermes rechnet jeden Ordner als `path.join(basePath, wert)` (`lib/config.js`, `getTasksDir`) —
/// ein absoluter Wert landet dort also **unter** dem Basis-Pfad: aus `/Users/ich/Library/…` wird
/// `~/code/Users/ich/Library/…`, ohne Fehlermeldung. Genau das passiert, sobald Kanbans Task- oder
/// Doku-Ordner aus dem Repo heraus in den eigenen Ordner zieht.
///
/// Deshalb wird beim Rückschreiben aus einem **absoluten** Pfad einer relativ zu Hermes'
/// `basePath` (`../Library/Application Support/Kanban/tasks/even`) — die Form, die `path.join`
/// korrekt auflöst. Kanbans eigene Config behält den absoluten Pfad; sie muss Hermes' Rechnung
/// nicht nachbauen.
///
/// **Relative Werte bleiben unangetastet.** Sie sind entweder ohnehin schon Hermes' Schreibweise
/// (aus dessen Config gelesen) oder gegen Kanbans Basis-Pfad gemeint — und der ist in der Praxis
/// derselbe. Umrechnen hiesse raten, welcher der beiden gemeint war.
enum HermesPath {
    /// Schreibt jeden absoluten Ordner-Wert der Registry (Task-Files und Confluence-Ablage) in
    /// Hermes' Schreibweise um. Ohne bekannten `basePath` bleibt alles, wie es ist.
    static func relativizing(_ registry: ProjectRegistry, hermesBase: String?) -> ProjectRegistry {
        guard let hermesBase, !hermesBase.isEmpty else { return registry }
        let base = (hermesBase as NSString).expandingTildeInPath
        var result = registry
        for key in registry.keys {
            guard var record = registry[key] else { continue }
            record.tasksPath = record.tasksPath.map { relative($0, to: base) }
            if let confluence = record.confluence, let path = confluence.path {
                record.confluence?.path = relative(path, to: base)
            }
            result[key] = record
        }
        return result
    }

    /// Absoluter Pfad → relativ zu `base` (mit `..`, wo nötig). Alles andere bleibt unverändert.
    static func relative(_ path: String, to base: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return path }

        let target = ((expanded as NSString).standardizingPath as NSString).pathComponents
        let root = ((base as NSString).standardizingPath as NSString).pathComponents
        var common = 0
        while common < min(target.count, root.count), target[common] == root[common] { common += 1 }

        let up = Array(repeating: "..", count: root.count - common)
        let down = target[common...]
        let parts = up + down
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
}
