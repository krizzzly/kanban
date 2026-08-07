import Foundation

/// Art eines Claude-Assets; der Rohwert ist der Unterordner im kanonischen Bestand.
public enum ClaudeAssetKind: String, CaseIterable, Sendable {
    case command = "commands"   // einzelne .md-Datei
    case skill   = "skills"     // Ordner (SKILL.md + Beiwerk)
    case rule    = "rules"      // einzelne .md-Datei; kein nativer Claude-Mechanismus, nur referenziert
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

/// Zustand des Symlinks in der Claude-User-Ebene (`~/.claude/commands|skills`).
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
/// Bestand** (Application Support — editierbar, überlebt Updates) und die **Claude-User-Ebene**
/// (`~/.claude/…` — Symlinks auf den Bestand, gelten damit in jedem Projekt). Rules bekommen keinen
/// Symlink: Claude kennt keinen Rules-Mechanismus, sie werden aus den Commands per absolutem Pfad
/// referenziert.
public struct ClaudeAssetStore: Sendable {
    public let canonicalRoot: URL
    public let userClaudeDir: URL

    /// `~/Library/Application Support/Kanban/claude`
    public static var defaultRoot: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban/claude", isDirectory: true)
    }

    public init(canonicalRoot: URL = ClaudeAssetStore.defaultRoot,
                userClaudeDir: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude", isDirectory: true)) {
        self.canonicalRoot = canonicalRoot
        self.userClaudeDir = userClaudeDir
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

    /// Wohin der Symlink für dieses Asset gehört — nil für Rules (kein nativer Mechanismus).
    public func symlinkTarget(for asset: ClaudeAsset) -> URL? {
        switch asset.kind {
        case .command: return userClaudeDir.appendingPathComponent("commands/\(asset.name).md")
        case .skill:   return userClaudeDir.appendingPathComponent("skills/\(asset.name)", isDirectory: true)
        case .rule:    return nil
        }
    }

    public func symlinkState(for asset: ClaudeAsset) -> ClaudeSymlinkState {
        guard let target = symlinkTarget(for: asset) else { return .notInstalled }
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
    public func installSymlink(for asset: ClaudeAsset) throws {
        guard let target = symlinkTarget(for: asset) else {
            throw ClaudeAssetError(message: "Rules werden nicht verlinkt — sie werden per Pfad referenziert.")
        }
        switch symlinkState(for: asset) {
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
    public func removeSymlink(for asset: ClaudeAsset) throws {
        guard let target = symlinkTarget(for: asset), symlinkState(for: asset) == .linked else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Verlinkt alle Commands + Skills; fremde Zielorte werden übersprungen. Liefert den Zustand danach.
    @discardableResult
    public func installAllSymlinks() -> [ClaudeAsset: ClaudeSymlinkState] {
        var result: [ClaudeAsset: ClaudeSymlinkState] = [:]
        for asset in allAssets() where asset.kind != .rule {
            try? installSymlink(for: asset)
            result[asset] = symlinkState(for: asset)
        }
        return result
    }
}
