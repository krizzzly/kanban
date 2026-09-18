import Foundation

/// Art eines Claude-Assets; der Rohwert ist der Unterordner innerhalb eines Sets.
///
/// Die Gattung `commands` ist mit den Sets weggefallen: Kanban lieferte schon vorher nichts mehr
/// als Command aus (der Umzug nach `skills/` war einmalig und ist erledigt), Codex kennt sie gar
/// nicht, und ein von Hand angelegter Projekt-Command bleibt als Datei liegen — Kanban verwaltet
/// ihn nur nicht mehr.
public enum ClaudeAssetKind: String, CaseIterable, Sendable {
    case skill = "skills"     // Ordner (SKILL.md + Beiwerk) — die Gattung, die beide Agents lesen
    case rule  = "rules"      // einzelne .md-Datei; kein nativer Mechanismus, nur referenziert
}

/// Ein Asset innerhalb eines Sets.
public struct ClaudeAsset: Sendable, Hashable, Identifiable {
    /// Name des Sets, aus dem es stammt — zwei Sets dürfen denselben Skill-Namen führen.
    public let set: String
    public let kind: ClaudeAssetKind
    public let name: String   // Dateiname ohne .md bzw. Skill-Ordnername
    public let url: URL       // Ort im Bestand

    public var id: String { "\(set)/\(kind.rawValue)/\(name)" }

    public init(set: String, kind: ClaudeAssetKind, name: String, url: URL) {
        self.set = set
        self.kind = kind
        self.name = name
        self.url = url
    }
}

/// Eine benannte Zusammenstellung von Skills und Rules — das, was ein Projekt auswählt.
///
/// Ein Set ist ein Ordner unter `sets/`; `set.json` gibt ihm Anzeigename und eine Zeile
/// Beschreibung. Beides ist optional: ohne Datei heisst das Set wie sein Ordner, und die Übersicht
/// zeigt dann eben nur den Namen.
public struct ClaudeAssetSet: Sendable, Hashable, Identifiable {
    public let name: String          // Ordnername — der Wert, der in der Config steht
    public let displayName: String
    public let description: String
    public let url: URL

    public var id: String { name }

    public init(name: String, displayName: String? = nil, description: String = "", url: URL) {
        self.name = name
        self.displayName = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? name
        self.description = description
        self.url = url
    }
}

/// Wohin ein Set verlinkt wird.
///
/// Die Projekt-Ebene ist der Regelfall und der eigentliche Punkt der Sets: ein Agent-Home kann
/// nicht zwei Sets gleichzeitig tragen, und Kanban fährt regelmässig mehrere Projekte parallel.
/// Das Home bekommt nur das Standard-Set — damit eine Sitzung ausserhalb eines Projekts nicht leer
/// dasteht.
public enum ClaudeLinkScope: Sendable, Hashable {
    case home(AgentKind)
    case project(repoDir: String, agent: AgentKind)
}

/// Zustand eines Zielorts (`<repo>/.claude/skills/<name>`, `~/.claude/skills/<name>`, …).
public enum ClaudeSymlinkState: Sendable, Equatable {
    /// Symlink existiert und zeigt genau auf dieses Asset.
    case linked
    /// Am Zielort liegt nichts.
    case notInstalled
    /// **Unser** Symlink, aber auf etwas anderes im Bestand: ein anderes Set oder der alte flache
    /// Bestand aus dem Modell vor den Sets. Wird beim Verlinken umgehängt, nicht gemeldet — sonst
    /// bliebe nach jedem Set-Wechsel ein Zielort für immer belegt.
    case otherSet(String)
    /// Am Zielort liegt etwas Fremdes (echte Datei oder Symlink ausserhalb des Bestands) — wird nie
    /// überschrieben.
    case foreign(String)
}

/// Was beim Verlinken eines Sets passiert ist — die Grundlage der Übersicht.
public struct ClaudeLinkReport: Sendable, Equatable {
    /// Asset-Ids, die jetzt verlinkt sind.
    public var linked: [String] = []
    /// Aufgeräumte Symlinks eines vorher verlinkten Sets (bzw. des alten flachen Bestands).
    public var removed: [String] = []
    /// Zielort → Grund. Fremdes wird nie angefasst, sondern hier gemeldet.
    public var foreign: [String: String] = [:]

    public var isComplete: Bool { foreign.isEmpty }

    public init() {}
}

public struct ClaudeAssetError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    public init(message: String) { self.message = message }
}

/// Die Skill-Sets, die Kanban ausliefert — gepflegt im Kanban-Repo, verlinkt ins Projekt.
///
/// Drei Orte spielen zusammen:
/// 1. **Auslieferungsstand** (`Sources/Kanban/Resources/ClaudeAssets/sets/…` im App-Bundle) — die
///    Quelle. Dort wird gearbeitet, mit Diff, Historie und Review.
/// 2. **Bestand** (`~/Library/Application Support/Kanban/claude/sets/…`) — eine überschreibende
///    Kopie davon. Er existiert nur, weil das App-Bundle bei einem Update ersetzt wird und
///    Symlinks dorthin brechen würden; editiert wird hier nichts mehr.
/// 3. **Zielorte**: `<repo>/.claude/skills/<name>` bzw. `<repo>/.codex/skills/<name>` je Projekt,
///    und die Agent-Homes für das Standard-Set.
///
/// Rules reisen mit ins Projekt (`<repo>/.claude/rules/<name>.md`) — **immer** nach `.claude/`,
/// auch bei `agent: codex`: die Skills verweisen im Text auf `.claude/rules/…`, und dieser Pfad
/// muss unter beiden Agents aufgehen. Dieselbe Überlegung wie bei `.claude/project.json`. In den
/// Agent-Homes bekommen Rules keinen Zielort — dort gibt es keinen Ordner, auf den ein Skill
/// zeigen könnte.
public struct ClaudeAssetStore: Sendable {
    public let canonicalRoot: URL
    public let userClaudeDir: URL
    public let userCodexDir: URL

    /// `~/Library/Application Support/Kanban/claude`
    public static var defaultRoot: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban/claude", isDirectory: true)
    }

    /// Der Ordner, unter dem die Sets liegen — unter beiden Wurzeln derselbe Name.
    public static let setsDirName = "sets"

    public init(canonicalRoot: URL = ClaudeAssetStore.defaultRoot,
                userClaudeDir: URL = AgentKind.claude.homeDir,
                userCodexDir: URL = AgentKind.codex.homeDir) {
        self.canonicalRoot = canonicalRoot
        self.userClaudeDir = userClaudeDir
        self.userCodexDir = userCodexDir
    }

    public var setsRoot: URL {
        canonicalRoot.appendingPathComponent(Self.setsDirName, isDirectory: true)
    }

    /// Home des Agents — in Tests umgebogen, im Betrieb `~/.claude` bzw. `~/.codex`.
    public func homeDir(_ agent: AgentKind) -> URL {
        switch agent {
        case .claude: return userClaudeDir
        case .codex:  return userCodexDir
        }
    }

    // MARK: - Inventar

    public func sets() -> [ClaudeAssetSet] {
        Self.sets(under: canonicalRoot)
    }

    public func set(named name: String?) -> ClaudeAssetSet? {
        guard let name, !name.isEmpty else { return nil }
        return sets().first { $0.name == name }
    }

    /// Liest die Sets unter einer beliebigen Wurzel — dieselbe Struktur gilt für Bundle und Bestand.
    ///
    /// Ein Ordner unter `sets/` ist erst ein Set, wenn er auch `skills/` oder `rules/` hat. Neben
    /// dem Bestand liegt historisch allerlei (`skills-backup-2026-08-20`, `projektkopien-backup-*`,
    /// `.versions`, ein ZIP) — nichts davon darf als Set durchgehen, nur weil es ein Ordner ist.
    public static func sets(under root: URL) -> [ClaudeAssetSet] {
        let dir = root.appendingPathComponent(setsDirName, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles) else { return [] }
        return entries.compactMap { url -> ClaudeAssetSet? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = url.lastPathComponent
            guard isDir, ClaudeAssetName.istGueltig(name), hasAnyKindDir(url) else { return nil }
            let info = SetInfo.read(url.appendingPathComponent("set.json"))
            return ClaudeAssetSet(name: name, displayName: info?.displayName,
                                  description: info?.description ?? "", url: url)
        }
        .sorted { $0.name < $1.name }
    }

    private static func hasAnyKindDir(_ setURL: URL) -> Bool {
        ClaudeAssetKind.allCases.contains {
            FileManager.default.fileExists(atPath: setURL.appendingPathComponent($0.rawValue).path)
        }
    }

    /// Anzeigename und Beschreibung eines Sets. Fehlt die Datei oder ist sie unlesbar, heisst das
    /// Set wie sein Ordner — eine kaputte `set.json` darf ein Set nicht verschwinden lassen.
    private struct SetInfo: Decodable {
        let displayName: String?
        let description: String?

        static func read(_ url: URL) -> SetInfo? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SetInfo.self, from: data)
        }
    }

    public func assets(_ kind: ClaudeAssetKind, in set: ClaudeAssetSet) -> [ClaudeAsset] {
        Self.assets(kind, in: set)
    }

    public func allAssets(in set: ClaudeAssetSet) -> [ClaudeAsset] {
        ClaudeAssetKind.allCases.flatMap { Self.assets($0, in: set) }
    }

    public static func assets(_ kind: ClaudeAssetKind, in set: ClaudeAssetSet) -> [ClaudeAsset] {
        let dir = set.url.appendingPathComponent(kind.rawValue, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles) else { return [] }
        return entries.compactMap { url -> ClaudeAsset? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            switch kind {
            case .skill:
                guard isDir else { return nil }
                return ClaudeAsset(set: set.name, kind: kind, name: url.lastPathComponent, url: url)
            case .rule:
                guard !isDir, url.pathExtension == "md" else { return nil }
                return ClaudeAsset(set: set.name, kind: kind,
                                   name: url.deletingPathExtension().lastPathComponent, url: url)
            }
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: - Auflösung: welches Set gilt für ein Projekt?

    /// Welches Set gilt — und ob dabei etwas nicht aufging.
    public struct Resolution: Sendable, Equatable {
        public let set: ClaudeAssetSet?
        /// Gesetzt, wenn das ausdrücklich gewählte Set nicht (mehr) existiert und deshalb das
        /// Standard-Set eingesprungen ist. Gehört in die Übersicht — sonst arbeitet ein Projekt
        /// stillschweigend mit fremden Skills.
        public let missingName: String?

        public init(set: ClaudeAssetSet?, missingName: String? = nil) {
            self.set = set
            self.missingName = missingName
        }
    }

    /// Das Set, das gilt, wenn ein Projekt keins wählt.
    ///
    /// Ohne Eintrag in der Config gilt das einzige vorhandene Set. Gibt es mehrere und ist keins
    /// bestimmt, fällt die Wahl auf das erste — ein Projekt ganz ohne Skills wäre die schlechtere
    /// Antwort; die Übersicht sagt dann, dass hier nichts entschieden ist.
    public func defaultSet(configured: String?) -> ClaudeAssetSet? {
        let alle = sets()
        if let configured, let treffer = alle.first(where: { $0.name == configured }) { return treffer }
        return alle.first
    }

    /// Das Set eines Projekts: seine eigene Wahl, sonst das Standard-Set.
    public func resolve(skillSet: String?, default defaultName: String?) -> Resolution {
        let standard = defaultSet(configured: defaultName)
        guard let skillSet, !skillSet.isEmpty else { return Resolution(set: standard) }
        if let treffer = set(named: skillSet) { return Resolution(set: treffer) }
        return Resolution(set: standard, missingName: skillSet)
    }

    // MARK: - Sync aus dem Auslieferungsstand

    /// Spiegelt die Sets aus dem Auslieferungsstand in den Bestand — **überschreibend**.
    ///
    /// Das ist die bewusste Umkehr des früheren `seedMissing`: gepflegt wird ab jetzt im Repo, und
    /// der Bestand ist nur noch die Stelle, auf die Symlinks zeigen dürfen. Ein Set, das nur im
    /// Bestand liegt (von Hand dazugelegt), bleibt stehen — überschrieben wird, was wir liefern,
    /// gelöscht wird nichts Fremdes.
    ///
    /// Inhaltsgleiche Sets werden übersprungen, damit nicht bei jedem App-Start ein paar Megabyte
    /// neu geschrieben werden.
    @discardableResult
    public func syncSets(from factoryRoot: URL) throws -> [ClaudeAssetSet] {
        let fm = FileManager.default
        try fm.createDirectory(at: setsRoot, withIntermediateDirectories: true)
        for factory in Self.sets(under: factoryRoot) {
            let target = setsRoot.appendingPathComponent(factory.name, isDirectory: true)
            if Self.contentsEqual(factory.url, target) { continue }
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: factory.url, to: target)
        }
        return sets()
    }

    /// Zwei Ordner Datei für Datei vergleichen. Bewusst ein voller Vergleich und kein Blick auf die
    /// Zeitstempel: der Bestand wird kopiert, nicht gebaut — mtimes sagen hier nichts.
    static func contentsEqual(_ a: URL, _ b: URL) -> Bool {
        guard let left = relativeFiles(a), let right = relativeFiles(b), left == right else {
            return false
        }
        return left.allSatisfy { relative in
            let x = try? Data(contentsOf: a.appendingPathComponent(relative))
            let y = try? Data(contentsOf: b.appendingPathComponent(relative))
            return x != nil && x == y
        }
    }

    private static func relativeFiles(_ root: URL) -> Set<String>? {
        guard FileManager.default.fileExists(atPath: root.path),
              let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]) else { return nil }
        var result: Set<String> = []
        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in walker {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            result.insert(String(path.dropFirst(prefix.count)))
        }
        return result
    }

    // MARK: - Zielorte

    /// Wohin dieses Asset in diesem Bereich gehört — nil, wo es keinen Ort gibt.
    ///
    /// Rules haben im Agent-Home keinen: dort existiert kein Rules-Mechanismus, und die Skills
    /// verweisen ohnehin repo-relativ auf `.claude/rules/…`. Im Projekt haben sie einen, und zwar
    /// immer unter `.claude/` — siehe Typ-Kommentar.
    public func symlinkTarget(for asset: ClaudeAsset, scope: ClaudeLinkScope) -> URL? {
        switch (asset.kind, scope) {
        case (.skill, .home(let agent)):
            return homeDir(agent).appendingPathComponent("skills/\(asset.name)", isDirectory: true)
        case (.skill, .project(let repoDir, let agent)):
            return URL(fileURLWithPath: repoDir)
                .appendingPathComponent("\(agent.projectDirName)/skills/\(asset.name)",
                                        isDirectory: true)
        case (.rule, .home):
            return nil
        case (.rule, .project(let repoDir, _)):
            return URL(fileURLWithPath: repoDir)
                .appendingPathComponent("\(AgentKind.claude.projectDirName)/rules/\(asset.name).md")
        }
    }

    public func symlinkState(for asset: ClaudeAsset, scope: ClaudeLinkScope) -> ClaudeSymlinkState {
        guard let target = symlinkTarget(for: asset, scope: scope) else { return .notInstalled }
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) else {
            // Kein Symlink: entweder nichts, oder eine echte Datei/Ordner (fremd).
            return FileManager.default.fileExists(atPath: target.path)
                ? .foreign("keine Verknüpfung, sondern eine eigene Datei")
                : .notInstalled
        }
        let resolved = URL(fileURLWithPath: dest, relativeTo: target.deletingLastPathComponent())
            .standardizedFileURL.path
        if resolved == asset.url.standardizedFileURL.path { return .linked }
        return isOurs(resolved) ? .otherSet(dest) : .foreign("Verknüpfung zeigt auf \(dest)")
    }

    /// Zeigt ein Pfad in unseren Bestand? Das entscheidet, ob ein vorgefundener Symlink umgehängt
    /// werden darf. Geprüft wird gegen die **ganze** Wurzel, nicht nur gegen `sets/`: die Links des
    /// alten flachen Modells (`claude/skills/<name>`) sind ebenfalls unsere und sollen sich beim
    /// ersten Start auf das Standard-Set umhängen lassen.
    private func isOurs(_ path: String) -> Bool {
        path.hasPrefix(canonicalRoot.standardizedFileURL.path + "/")
    }

    /// Legt den Symlink an. Fremde Zielorte werden nie überschrieben, sondern gemeldet.
    public func installSymlink(for asset: ClaudeAsset, scope: ClaudeLinkScope) throws {
        guard let target = symlinkTarget(for: asset, scope: scope) else {
            throw ClaudeAssetError(message:
                "Für \(asset.id) gibt es hier keinen Zielort — Rules werden nur ins Projekt gelegt.")
        }
        switch symlinkState(for: asset, scope: scope) {
        case .linked:
            return
        case .foreign(let what):
            throw ClaudeAssetError(message: "\(target.path): \(what) — bitte manuell auflösen.")
        case .otherSet:
            try FileManager.default.removeItem(at: target)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: asset.url)
        case .notInstalled:
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: asset.url)
        }
    }

    /// Entfernt unseren Symlink; Fremdes bleibt liegen.
    public func removeSymlink(for asset: ClaudeAsset, scope: ClaudeLinkScope) throws {
        guard let target = symlinkTarget(for: asset, scope: scope) else { return }
        switch symlinkState(for: asset, scope: scope) {
        case .linked, .otherSet:
            try FileManager.default.removeItem(at: target)
        case .notInstalled, .foreign:
            return
        }
    }

    // MARK: - Ein ganzes Set verlinken

    /// Verlinkt ein Set ins Projekt und räumt auf, was von einem vorher verlinkten Set übrig ist.
    ///
    /// Aufgeräumt wird auch das Skills-Verzeichnis des **anderen** Agents: ein Projekt hat genau
    /// einen, ein Link im Ordner des anderen ist damit per Definition ein Überbleibsel. Fremdes
    /// bleibt überall liegen.
    @discardableResult
    public func link(_ set: ClaudeAssetSet, toProject repoDir: String,
                     agent: AgentKind) -> ClaudeLinkReport {
        var report = ClaudeLinkReport()
        let repo = URL(fileURLWithPath: repoDir)
        let skills = assets(.skill, in: set)
        let rules = assets(.rule, in: set)

        for other in AgentKind.allCases where other != agent {
            report.removed += cleanUp(
                in: repo.appendingPathComponent("\(other.projectDirName)/skills", isDirectory: true),
                keeping: [])
        }
        report.removed += cleanUp(
            in: repo.appendingPathComponent("\(agent.projectDirName)/skills", isDirectory: true),
            keeping: Set(skills.map(\.name)))
        report.removed += cleanUp(
            in: repo.appendingPathComponent("\(AgentKind.claude.projectDirName)/rules",
                                            isDirectory: true),
            keeping: Set(rules.map { "\($0.name).md" }))

        for asset in skills + rules {
            install(asset, scope: .project(repoDir: repoDir, agent: agent), into: &report)
        }
        return report
    }

    /// Verlinkt das Standard-Set in beide Agent-Homes — für Sitzungen ausserhalb eines Projekts.
    /// Rules bleiben aussen vor: im Home gibt es keinen Ort, auf den ein Skill zeigen könnte.
    @discardableResult
    public func link(_ set: ClaudeAssetSet, toHomes agents: [AgentKind] = AgentKind.allCases)
        -> [AgentKind: ClaudeLinkReport] {
        let skills = assets(.skill, in: set)
        var result: [AgentKind: ClaudeLinkReport] = [:]
        for agent in agents {
            var report = ClaudeLinkReport()
            report.removed += cleanUp(in: homeDir(agent).appendingPathComponent("skills",
                                                                               isDirectory: true),
                                      keeping: Set(skills.map(\.name)))
            for skill in skills { install(skill, scope: .home(agent), into: &report) }
            result[agent] = report
        }
        return result
    }

    private func install(_ asset: ClaudeAsset, scope: ClaudeLinkScope,
                         into report: inout ClaudeLinkReport) {
        guard let target = symlinkTarget(for: asset, scope: scope) else { return }
        do {
            try installSymlink(for: asset, scope: scope)
            report.linked.append(asset.id)
        } catch {
            report.foreign[target.path] = error.localizedDescription
        }
    }

    /// Entfernt **unsere** Symlinks in `dir`, die nicht in `keeping` stehen. Alles andere — echte
    /// Dateien, fremde Symlinks — bleibt unangetastet.
    private func cleanUp(in dir: URL, keeping: Set<String>) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: []) else { return [] }
        var removed: [String] = []
        for url in entries where !keeping.contains(url.lastPathComponent) {
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            else { continue }
            let resolved = URL(fileURLWithPath: dest, relativeTo: dir).standardizedFileURL.path
            guard isOurs(resolved) else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed.append(url.path)
            }
        }
        return removed.sorted()
    }

    // MARK: - Zustand für die Übersicht

    /// Zustand des ganzen Sets an einem Zielort: verlinkt nur, wenn **jedes** Asset verlinkt ist.
    /// Ein halb verlinktes Projekt ist keins — ein fehlender Skill fällt erst im Betrieb auf.
    public func state(of set: ClaudeAssetSet, scope: ClaudeLinkScope) -> ClaudeSymlinkState {
        let ziele = allAssets(in: set).filter { symlinkTarget(for: $0, scope: scope) != nil }
        guard !ziele.isEmpty else { return .notInstalled }
        let zustaende = ziele.map { symlinkState(for: $0, scope: scope) }
        if let fremd = zustaende.first(where: { if case .foreign = $0 { return true }; return false }) {
            return fremd
        }
        if let anderes = zustaende.first(where: { if case .otherSet = $0 { return true }; return false }) {
            return anderes
        }
        return zustaende.allSatisfy { $0 == .linked } ? .linked : .notInstalled
    }
}
