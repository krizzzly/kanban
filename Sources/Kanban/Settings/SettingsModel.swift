import Foundation
import Observation
import SwiftUI
import KanbanCore

/// State behind the settings sheet: a round-trip-safe `ConfigDocument` plus bindings the
/// schema-driven form edits by JSON key path. Deliberately independent of `HermesConfigLoader`
/// so the sheet also works with a broken or missing config (first-run).
@MainActor
@Observable
final class SettingsModel {
    private let store: ConfigStore

    private(set) var document: ConfigDocument?
    private(set) var loadError: String?
    private(set) var dirty = false
    private(set) var saveError: String?
    private(set) var conflict = false
    /// Was der Rückweg in die Hermes-Config beim letzten Speichern getan hat (nil = noch nichts).
    private(set) var syncResult: HermesSync.Result?

    var configPath: String { store.path }

    /// Nur wenn es überhaupt eine Hermes-Config gibt, ist die Sync-Sektion sinnvoll.
    var hermesAvailable: Bool { HermesSync.isAvailable() }

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
    }

    func load() {
        do {
            document = try store.load()
            loadError = nil
        } catch {
            document = nil
            loadError = error.localizedDescription
        }
        dirty = false
        saveError = nil
        conflict = false
    }

    @discardableResult
    func save(force: Bool = false) -> Bool {
        guard let doc = document else { return false }
        do {
            document = try store.save(doc, force: force)
            dirty = false
            saveError = nil
            conflict = false
            // Rückweg: die Projekte additiv in eine vorhandene Hermes-Config schreiben, damit CLI
            // und MCP-Tools dieselben Projekte kennen. Ohne Hermes ein stiller No-Op.
            syncResult = HermesSync.run(kanban: doc.root)
            return true
        } catch ConfigStoreError.conflict {
            conflict = true
            saveError = ConfigStoreError.conflict.errorDescription
            return false
        } catch {
            conflict = false
            saveError = error.localizedDescription
            return false
        }
    }

    /// Was nach dem Speichern unter dem Formular steht — nil, wenn es nichts zu sagen gibt.
    var syncMessage: String? {
        switch syncResult {
        case .synced(let count):
            return "✓ Gespeichert. \(count) Projekt\(count == 1 ? "" : "e") in die Hermes-Config "
                 + "übertragen (\(abbreviate(HermesImport.defaultPath)))."
        case .unchanged:
            return "✓ Gespeichert. Die Hermes-Config war schon auf demselben Stand."
        case .skipped(let reason) where reason == "keine Hermes-Config":
            return "✓ Gespeichert."
        case .skipped(let reason):
            return "✓ Gespeichert. Hermes-Abgleich übersprungen: \(reason)."
        case nil:
            return nil
        }
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Mutation

    private func mutate(_ change: (inout JSONValue) -> Void) {
        guard var doc = document else { return }
        change(&doc.root)
        document = doc
        dirty = true
    }

    // MARK: - Bindings (empty string / empty list removes the key)

    func stringBinding(_ path: [String]) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.document?.root.value(at: path)?.stringValue ?? "" },
            set: { [weak self] newValue in
                guard let self, self.string(at: path) != newValue else { return }
                self.mutate { $0.set(newValue.isEmpty ? nil : .string(newValue), at: path) }
            })
    }

    func boolBinding(_ path: [String], defaultOn: Bool) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.document?.root.value(at: path)?.boolValue ?? defaultOn },
            set: { [weak self] newValue in self?.mutate { $0.set(.bool(newValue), at: path) } })
    }

    private func string(at path: [String]) -> String {
        document?.root.value(at: path)?.stringValue ?? ""
    }

    /// Public read for validation display (SchemaFieldView).
    func stringValue(at path: [String]) -> String { string(at: path) }

    // MARK: - String lists (comma-separated in the UI, JSON array on disk)

    func stringListText(_ path: [String]) -> String {
        (document?.root.value(at: path)?.arrayValue ?? [])
            .compactMap(\.stringValue)
            .joined(separator: ", ")
    }

    func setStringList(_ path: [String], from text: String) {
        let items = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let current = (document?.root.value(at: path)?.arrayValue ?? []).compactMap(\.stringValue)
        guard items != current else { return }
        mutate { $0.set(items.isEmpty ? nil : .array(items.map { .string($0) }), at: path) }
    }

    // MARK: - Project maps (dynamic keys)

    func projectKeys(at mapPath: [String]) -> [String] {
        (document?.root.value(at: mapPath)?.objectValue ?? [:]).keys.sorted()
    }

    func addProject(at mapPath: [String], key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              document?.root.value(at: mapPath + [trimmed]) == nil else { return }
        mutate { $0.set(.object([:]), at: mapPath + [trimmed]) }
    }

    func removeProject(at mapPath: [String], key: String) {
        mutate { $0.set(nil, at: mapPath + [key]) }
    }

    // MARK: - Projekte (HERMES-043: zentral anlegen, in den Modulen pflegen)

    /// Übersicht über alle Projekte — **live aus der Config gelesen**, nicht gespeichert. Damit
    /// gibt es keine zweite Wahrheit neben den Modul-Sections, die weiterhin editierbar bleiben.
    var projectOverview: ProjectRegistry {
        ProjectProjection.importing(from: document?.root ?? .object([:]))
    }

    func projectSuggestion(for key: String) -> ProjectRecord {
        ProjectSuggestion.record(for: key, from: document?.root ?? .object([:]))
    }

    func isProjectKeyTaken(_ key: String) -> Bool {
        ProjectSuggestion.isTaken(key, in: document?.root ?? .object([:]))
    }

    /// Legt ein Projekt in allen betroffenen Modul-Sections an (nur im Dokument — geschrieben wird
    /// wie bei jeder anderen Änderung erst beim Speichern).
    func createProject(key: String, record: ProjectRecord) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !record.isEmpty else { return }
        mutate { $0 = ProjectProjection.apply(record, key: trimmed, to: $0) }
    }

    /// Entfernt ein Projekt aus allen Sections auf einmal — samt seinem Kopfzeilen-Bild, das sonst
    /// als Datei im Datenordner zurückbliebe, auf die keine Einstellung mehr zeigt.
    func removeProjectEverywhere(key: String) {
        mutate { $0 = ProjectProjection.remove(key, from: $0) }
        ProjectImageStore.remove(projectKey: key)
    }

    // MARK: - Raw JSON escape hatch

    func rawJSON() -> String {
        guard let doc = document else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(doc.root)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Replaces the whole document from edited raw JSON. Returns an error string, or nil on success.
    func applyRawJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return "Text ist nicht UTF-8-kodierbar." }
        let root: JSONValue
        do { root = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { return "Kein gültiges JSON: \(error.localizedDescription)" }
        guard case .object = root else { return "Wurzel muss ein JSON-Objekt sein." }
        mutate { $0 = root }
        return nil
    }
}
