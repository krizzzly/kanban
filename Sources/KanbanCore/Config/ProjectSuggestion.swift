import Foundation

/// Füllt das Formular „Neues Projekt" vor, indem es die Muster liest, die in der Config ohnehin
/// schon stehen: `applications/<key>`, `<key>/docs/tasks`, `<key> - DEV - Build`.
///
/// Ohne das wäre zentrales Anlegen nur ein Ortswechsel — man tippt dieselben sechs Muster, bloss in
/// einem anderen Formular. Der Vorschlag ist immer **editierbar**; er soll den Normalfall treffen,
/// nicht die Ausnahme.
///
/// Regel gegen Raten: ein Muster wird nur übernommen, wenn es **eindeutig** in der Mehrheit ist.
/// Bei Gleichstand gilt die dokumentierte Konvention (`<key>/docs/tasks`) bzw. gar kein Vorschlag —
/// ein falsch geratener Pfad ist teurer als ein leeres Feld.
public enum ProjectSuggestion {

    /// Ist der Key in irgendeiner Section schon vergeben? (Auch modul-fremde zählen: `tech` gibt es
    /// nur in Confluence, wäre als Jira-Key aber trotzdem eine Kollision.)
    public static func isTaken(_ key: String, in config: JSONValue) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return ProjectProjection.moduleNames.contains {
            config.value(at: ["modules", $0, "projects", trimmed]) != nil
        }
    }

    /// Liegt an diesem Pfad eine Datei? Injizierbar, damit der `.iwf.yml`-Blick unten im Test
    /// nicht an der Platte dieser Maschine hängt.
    public typealias FileCheck = @Sendable (String) -> Bool

    public static let defaultFileCheck: FileCheck = { FileManager.default.fileExists(atPath: $0) }

    public static func record(for rawKey: String, from config: JSONValue,
                              fileExists: FileCheck = ProjectSuggestion.defaultFileCheck) -> ProjectRecord {
        let key = rawKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return ProjectRecord() }

        var record = ProjectRecord(prefix: key.uppercased())
        // Tasks-Pfad ist das einzige Feld mit einer Konvention als Rückfallebene — ohne ihn wäre das
        // Projekt für Kanban unsichtbar (die Board-Spalten hängen an den Task-Files).
        record.tasksPath = pattern(config, "jira", "tasksPath", key) ?? "\(key)/docs/tasks"

        if let path = pattern(config, "gitlab", "path", key) {
            record.gitlab = .init(path: path)
        }
        if !section(config, "confluence").isEmpty {
            // Space-Keys folgen keinem Pfad-Muster, sind aber konventionell der Key in Grossbuchstaben.
            record.confluence = .init(space: key.uppercased(),
                                      path: pattern(config, "confluence", "path", key))
        }
        if let jobs = jobsTemplate(config, key) {
            record.jenkins = .init(jobs: jobs)
        }
        if !section(config, "dockerhub").isEmpty {
            record.dockerhub = .init(namespace: literal(config, "dockerhub", "namespace"),
                                     repository: pattern(config, "dockerhub", "repository", key) ?? key)
        }
        // Docker-Stack: das einzige Feld, das nicht aus der Config, sondern aus dem **Repo** kommt.
        // Eine `.iwf.yml` dort ist die Stack-Definition selbst — fehlt sie, gibt es keinen Stack.
        // Geraten wird nur der Vorschlag: entschieden wird im Editor.
        if !hasIwfConfig(record, key: key, in: config, fileExists: fileExists) {
            record.usesDockerStack = false
        }
        // Vertec (Projekt/Phase/Task), `repoDir` und ein abweichender Jira-Host folgen keinem
        // ableitbaren Muster — bewusst leer.
        return record
    }

    /// Liegt im (vorgeschlagenen) Repo-Ordner eine `.iwf.yml`?
    ///
    /// Der Ordner wird genauso abgeleitet wie in `KanbanConfig.resolve`: `repoDir`, sonst das erste
    /// Segment des Tasks-Pfads, beides relativ zu `basePath`. Lässt sich kein Ordner bestimmen,
    /// lautet die Antwort **nein** — ein Vorschlag „mit Stack" ohne jeden Beleg wäre geraten, und
    /// die teurere Richtung: ein abgeschalteter Schalter nimmt nur die Docker-Hälfte weg.
    private static func hasIwfConfig(_ record: ProjectRecord, key: String, in config: JSONValue,
                                     fileExists: FileCheck) -> Bool {
        let basePath = (config.value(at: ["basePath"])?.stringValue ?? "~/code" as String)
        let expandedBase = (basePath as NSString).expandingTildeInPath
        let candidate = record.repoDir
            ?? record.tasksPath?.split(separator: "/").first.map(String.init)
            ?? key
        let expanded = (candidate as NSString).expandingTildeInPath
        let repoDir = expanded.hasPrefix("/") ? expanded
            : (expandedBase as NSString).appendingPathComponent(expanded)
        return fileExists((repoDir as NSString).appendingPathComponent(".iwf.yml"))
    }

    // MARK: - Musterableitung

    private static func section(_ config: JSONValue, _ module: String) -> [String: JSONValue] {
        config.value(at: ["modules", module, "projects"])?.objectValue ?? [:]
    }

    /// Sucht Werte, die den Key ihres eigenen Projekts enthalten, und setzt den neuen Key ein.
    /// Der Key kann überall stehen — vorne (`even/docs/tasks`) wie hinten (`applications/even`).
    private static func pattern(_ config: JSONValue, _ module: String, _ field: String,
                                _ newKey: String) -> String? {
        let candidates = section(config, module).compactMap { existingKey, entry -> String? in
            guard let value = entry.objectValue?[field]?.stringValue else { return nil }
            return substitute(existingKey, with: newKey, in: value)
        }
        return strictWinner(candidates)
    }

    /// Häufigster wörtlicher Wert (für Felder, die kein Muster sind — etwa der DockerHub-Namespace,
    /// der für alle Projekte derselbe ist).
    private static func literal(_ config: JSONValue, _ module: String, _ field: String) -> String? {
        strictWinner(section(config, module).values.compactMap {
            $0.objectValue?[field]?.stringValue
        })
    }

    /// Jobs sind eine Liste: hier gewinnt nicht die Mehrheit, sondern das **reichhaltigste**
    /// Vorbild — eine Job-Liste mit fünf Einträgen ist die bessere Schablone als eine mit einem.
    private static func jobsTemplate(_ config: JSONValue, _ newKey: String) -> [String]? {
        let candidates = section(config, "jenkins").compactMap { existingKey, entry -> [String]? in
            guard let jobs = entry.objectValue?["jobs"]?.arrayValue?.compactMap(\.stringValue),
                  !jobs.isEmpty else { return nil }
            let substituted = jobs.map { substitute(existingKey, with: newKey, in: $0) ?? $0 }
            return substituted == jobs ? nil : substituted   // ohne Key-Bezug keine Schablone
        }
        let ranked = candidates.sorted {
            $0.count == $1.count ? $0.joined() < $1.joined() : $0.count > $1.count
        }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, ranked[1].count == best.count { return nil }   // kein eindeutiges Vorbild
        return best
    }

    /// Ersetzt jedes Vorkommen von `key` (Gross-/Kleinschreibung egal) und behält die Schreibweise
    /// bei: aus `EVEN` wird `NEU`, aus `even/docs/kb` wird `neu/docs/kb`. Nil, wenn der Wert den Key
    /// gar nicht enthält — dann ist er keine Schablone, sondern eine Konstante.
    ///
    /// Das Vorkommen muss an Wortgrenzen liegen (Anfang/Ende oder ein Zeichen, das weder Buchstabe
    /// noch Ziffer ist), damit ein Key nicht mitten in einem längeren Wort ersetzt wird.
    private static func substitute(_ key: String, with newKey: String, in value: String) -> String? {
        guard !key.isEmpty else { return nil }
        var result = ""
        var rest = Substring(value)
        var replaced = false

        while let range = rest.range(of: key, options: .caseInsensitive) {
            let before = rest[..<range.lowerBound].last
            let after = rest[range.upperBound...].first
            let atBoundary = !(before?.isLetter ?? false) && !(before?.isNumber ?? false)
                && !(after?.isLetter ?? false) && !(after?.isNumber ?? false)

            let matched = String(rest[range])
            let isUppercased = matched == matched.uppercased() && matched != matched.lowercased()
            result += rest[..<range.lowerBound]
            result += atBoundary ? (isUppercased ? newKey.uppercased() : newKey) : matched
            replaced = replaced || atBoundary
            rest = rest[range.upperBound...]
        }
        result += rest
        return replaced ? result : nil
    }

    /// Nur ein **eindeutiger** Sieger zählt — bei Gleichstand lieber kein Vorschlag.
    private static func strictWinner(_ candidates: [String]) -> String? {
        guard !candidates.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for candidate in candidates { counts[candidate, default: 0] += 1 }
        let ranked = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, ranked[1].value == best.value { return nil }
        return best.key
    }
}
