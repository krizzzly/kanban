import Foundation

/// The parsed config file plus the mtime it was loaded at (for conflict detection on save).
public struct ConfigDocument: Sendable, Equatable {
    public var root: JSONValue
    public let loadedModificationDate: Date?

    public init(root: JSONValue, loadedModificationDate: Date? = nil) {
        self.root = root
        self.loadedModificationDate = loadedModificationDate
    }
}

public enum ConfigStoreError: Error, LocalizedError, Equatable {
    case read(String)
    case parse(String)
    case conflict
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .read(let m): return "Config konnte nicht gelesen werden: \(m)"
        case .parse(let m): return "Config ist kein gültiges JSON: \(m)"
        case .conflict: return "Die Datei wurde seit dem Öffnen extern geändert."
        case .write(let m): return "Config konnte nicht gespeichert werden: \(m)"
        }
    }
}

/// Round-trip-safe reader/writer for a JSON config file — by default Kanban's own
/// (`~/Library/Application Support/Kanban/config.json`), with the Hermes config as the other caller.
/// Unlike `KanbanConfig` it parses lax (any valid JSON object, no required fields) so the settings UI
/// stays usable with a broken or missing config. Saving normalizes formatting (pretty-printed, sorted
/// keys), writes a `.bak` backup of the previous content first, and writes atomically.
public struct ConfigStore: Sendable {
    public let path: String

    public init(path: String = KanbanConfig.path) {
        self.path = path
    }

    public var backupPath: String { path + ".bak" }

    /// Loads the config; a missing file yields an empty document (first-run).
    public func load() throws -> ConfigDocument {
        guard FileManager.default.fileExists(atPath: path) else {
            return ConfigDocument(root: .object([:]), loadedModificationDate: nil)
        }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: path)) }
        catch { throw ConfigStoreError.read(error.localizedDescription) }

        let root: JSONValue
        do { root = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw ConfigStoreError.parse(error.localizedDescription) }

        return ConfigDocument(root: root, loadedModificationDate: modificationDate())
    }

    /// Saves the document. Throws `.conflict` if the file changed on disk since `load()` —
    /// unless `force` is set. Returns a fresh document (new mtime baseline).
    @discardableResult
    public func save(_ document: ConfigDocument, force: Bool = false) throws -> ConfigDocument {
        if !force,
           let onDisk = modificationDate(),
           onDisk != document.loadedModificationDate {
            throw ConfigStoreError.conflict
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do { data = try encoder.encode(document.root) }
        catch { throw ConfigStoreError.write(error.localizedDescription) }

        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: path) {
                if fm.fileExists(atPath: backupPath) { try fm.removeItem(atPath: backupPath) }
                try fm.copyItem(atPath: path, toPath: backupPath)
            } else {
                let dir = (path as NSString).deletingLastPathComponent
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch let error as ConfigStoreError {
            throw error
        } catch {
            throw ConfigStoreError.write(error.localizedDescription)
        }
        return ConfigDocument(root: document.root, loadedModificationDate: modificationDate())
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
