import Foundation

/// Art eines Claude-Assets; der Rohwert ist der Unterordner im kanonischen Bestand.
public enum ClaudeAssetKind: String, CaseIterable, Sendable {
    /// **Altbestand.** Kanban liefert nichts mehr als Command aus (siehe `ClaudeAssetMigration`) —
    /// die Gattung bleibt, damit ein von Hand angelegter Command sichtbar und editierbar bleibt.
    /// Codex kennt sie nicht.
    case command = "commands"   // einzelne .md-Datei
    case skill   = "skills"     // Ordner (SKILL.md + Beiwerk) — die Gattung, die beide Agents lesen
    case rule    = "rules"      // einzelne .md-Datei; kein nativer Mechanismus, nur referenziert
}

/// Ein Asset im kanonischen Bestand (`~/Library/Application Support/Kanban/claude/…`).
public struct ClaudeAsset: Sendable, Hashable, Identifiable {
    public let kind: ClaudeAssetKind
    public let name: String   // Dateiname ohne .md bzw. Skill-Ordnername
    public let url: URL       // kanonischer Ort

    public var id: String { "\(kind.rawValue)/\(name)" }

    public init(kind: ClaudeAssetKind, name: String, url: URL) {
        self.kind = kind
        self.name = name
        self.url = url
    }
}

/// Zustand des Symlinks in der User-Ebene eines Agents (`~/.claude/skills`, `~/.codex/skills`).
public enum ClaudeSymlinkState: Sendable, Equatable {
    /// Symlink existiert und zeigt auf unseren kanonischen Bestand.
    case linked
    /// Am Zielort liegt nichts.
    case notInstalled
    /// Am Zielort liegt etwas Fremdes (echte Datei oder Symlink woandershin) — wird nie überschrieben.
    case foreign(String)
}

public struct ClaudeAssetError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Der kanonische Bestand an Commands/Skills/Rules, den Kanban besitzt und bereitstellt.
///
/// Drei Orte spielen zusammen: der **Auslieferungsstand** (App-Bundle, read-only), der **kanonische
/// Bestand** (Application Support — editierbar, überlebt Updates) und die **User-Ebene der Agents**
/// (`~/.claude/skills` und `~/.codex/skills` — Symlinks auf denselben Bestand, gelten damit in jedem
/// Projekt). Ein Skill wird in **beide** Homes verlinkt: dieselbe Datei bedient Claude und Codex, es
/// gibt keinen zweiten Bestand, der auseinanderlaufen könnte.
///
/// Rules bekommen keinen Symlink: keiner der beiden Agents hat einen Rules-Mechanismus, sie werden
/// aus den Skills per absolutem Pfad referenziert.
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

    public init(canonicalRoot: URL = ClaudeAssetStore.defaultRoot,
                userClaudeDir: URL = AgentKind.claude.homeDir,
                userCodexDir: URL = AgentKind.codex.homeDir) {
        self.canonicalRoot = canonicalRoot
        self.userClaudeDir = userClaudeDir
        self.userCodexDir = userCodexDir
    }

    /// Home des Agents — in Tests umgebogen, im Betrieb `~/.claude` bzw. `~/.codex`.
    public func homeDir(_ agent: AgentKind) -> URL {
        switch agent {
        case .claude: return userClaudeDir
        case .codex:  return userCodexDir
        }
    }

    // MARK: - Inventar

    public func assets(_ kind: ClaudeAssetKind) -> [ClaudeAsset] {
        Self.assets(kind, under: canonicalRoot)
    }

    public func allAssets() -> [ClaudeAsset] {
        ClaudeAssetKind.allCases.flatMap(assets)
    }

    /// Listet Assets unter beliebiger Wurzel — dieselbe Struktur gilt für Bundle und Bestand.
    public static func assets(_ kind: ClaudeAssetKind, under root: URL) -> [ClaudeAsset] {
        let dir = root.appendingPathComponent(kind.rawValue, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles) else { return [] }
        return entries.compactMap { url -> ClaudeAsset? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            switch kind {
            case .skill:
                guard isDir else { return nil }
                return ClaudeAsset(kind: kind, name: url.lastPathComponent, url: url)
            case .command, .rule:
                guard !isDir, url.pathExtension == "md" else { return nil }
                return ClaudeAsset(kind: kind, name: url.deletingPathExtension().lastPathComponent, url: url)
            }
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: - Auslieferungsstand (Seeding + Reset)

    /// Kopiert Assets, die im Bestand fehlen, aus dem Auslieferungsstand. Vorhandene — womöglich
    /// vom User editierte — bleiben unangetastet. Liefert die neu angelegten Assets.
    @discardableResult
    public func seedMissing(from factoryRoot: URL) throws -> [ClaudeAsset] {
        var seeded: [ClaudeAsset] = []
        for kind in ClaudeAssetKind.allCases {
            let targetDir = canonicalRoot.appendingPathComponent(kind.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            for factory in Self.assets(kind, under: factoryRoot) {
                let target = targetDir.appendingPathComponent(factory.url.lastPathComponent)
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                try FileManager.default.copyItem(at: factory.url, to: target)
                seeded.append(ClaudeAsset(kind: kind, name: factory.name, url: target))
            }
        }
        return seeded
    }

    /// Setzt ein Asset auf den Auslieferungsstand zurück (überschreibt den Bestand).
    public func resetToFactory(_ asset: ClaudeAsset, from factoryRoot: URL) throws {
        let factory = factoryRoot
            .appendingPathComponent(asset.kind.rawValue, isDirectory: true)
            .appendingPathComponent(asset.url.lastPathComponent)
        guard FileManager.default.fileExists(atPath: factory.path) else {
            throw ClaudeAssetError(message: "Kein Auslieferungsstand für \(asset.id) — Zurücksetzen unmöglich.")
        }
        if FileManager.default.fileExists(atPath: asset.url.path) {
            try FileManager.default.removeItem(at: asset.url)
        }
        try FileManager.default.copyItem(at: factory, to: asset.url)
    }

    /// Hat ein Asset einen Auslieferungsstand (= ist zurücksetzbar)?
    public func hasFactoryVersion(_ asset: ClaudeAsset, in factoryRoot: URL) -> Bool {
        FileManager.default.fileExists(atPath: factoryRoot
            .appendingPathComponent(asset.kind.rawValue, isDirectory: true)
            .appendingPathComponent(asset.url.lastPathComponent).path)
    }

    // MARK: - Symlinks in die Claude-User-Ebene

    /// Wohin der Symlink für dieses Asset bei diesem Agent gehört — nil, wo es keinen Ort gibt:
    /// Rules (kein Mechanismus) und Commands unter Codex (kennt die Gattung nicht).
    public func symlinkTarget(for asset: ClaudeAsset, agent: AgentKind = .claude) -> URL? {
        switch asset.kind {
        case .command:
            return agent.userCommandsDir == nil ? nil
                : homeDir(agent).appendingPathComponent("commands/\(asset.name).md")
        case .skill:
            return homeDir(agent).appendingPathComponent("skills/\(asset.name)", isDirectory: true)
        case .rule:
            return nil
        }
    }

    /// Die Agents, für die dieses Asset überhaupt einen Zielort hat.
    public func linkableAgents(for asset: ClaudeAsset) -> [AgentKind] {
        AgentKind.allCases.filter { symlinkTarget(for: asset, agent: $0) != nil }
    }

    public func symlinkState(for asset: ClaudeAsset, agent: AgentKind = .claude) -> ClaudeSymlinkState {
        guard let target = symlinkTarget(for: asset, agent: agent) else { return .notInstalled }
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) else {
            // Kein Symlink: entweder nichts, oder eine echte Datei/Ordner (fremd).
            return FileManager.default.fileExists(atPath: target.path)
                ? .foreign("keine Verknüpfung, sondern eine eigene Datei")
                : .notInstalled
        }
        let resolved = URL(fileURLWithPath: dest, relativeTo: target.deletingLastPathComponent())
            .standardizedFileURL.path
        return resolved == asset.url.standardizedFileURL.path
            ? .linked
            : .foreign("Verknüpfung zeigt auf \(dest)")
    }

    /// Legt den Symlink an. Fremde Dateien am Zielort werden nie überschrieben, sondern gemeldet.
    public func installSymlink(for asset: ClaudeAsset, agent: AgentKind = .claude) throws {
        guard let target = symlinkTarget(for: asset, agent: agent) else {
            throw ClaudeAssetError(message: asset.kind == .rule
                ? "Rules werden nicht verlinkt — sie werden per Pfad referenziert."
                : "\(agent.displayName) kennt keine Commands — nur Skills werden dorthin verlinkt.")
        }
        switch symlinkState(for: asset, agent: agent) {
        case .linked:
            return
        case .foreign(let what):
            throw ClaudeAssetError(message: "\(target.path): \(what) — bitte manuell auflösen.")
        case .notInstalled:
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: asset.url)
        }
    }

    /// Entfernt unseren Symlink; Fremdes bleibt liegen.
    public func removeSymlink(for asset: ClaudeAsset, agent: AgentKind = .claude) throws {
        guard let target = symlinkTarget(for: asset, agent: agent),
              symlinkState(for: asset, agent: agent) == .linked else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Zustand je Agent, für den es einen Zielort gibt — die Grundlage der Anzeige im Editor.
    public func symlinkStates(for asset: ClaudeAsset) -> [AgentKind: ClaudeSymlinkState] {
        Dictionary(uniqueKeysWithValues: linkableAgents(for: asset)
            .map { ($0, symlinkState(for: asset, agent: $0)) })
    }

    /// Verlinkt alles Verlinkbare in **jedes** Agent-Home; fremde Zielorte werden übersprungen.
    /// Liefert den Zustand danach, je Asset und Agent.
    @discardableResult
    public func installAllSymlinks() -> [ClaudeAsset: [AgentKind: ClaudeSymlinkState]] {
        var result: [ClaudeAsset: [AgentKind: ClaudeSymlinkState]] = [:]
        for asset in allAssets() where asset.kind != .rule {
            for agent in linkableAgents(for: asset) {
                try? installSymlink(for: asset, agent: agent)
            }
            result[asset] = symlinkStates(for: asset)
        }
        return result
    }
}
