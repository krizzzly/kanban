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
    private(set) var savedPendingRestart = false
    private(set) var restartBusy = false
    private(set) var restartResult: String?

    var configPath: String { store.path }

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
            savedPendingRestart = true
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

    /// Runs `hermes daemon-restart` in the user's login shell (PATH!) off the main thread.
    func restartDaemon() {
        guard !restartBusy else { return }
        restartBusy = true
        restartResult = nil
        Task.detached {
            let result = LoginShell.run("hermes daemon-restart")
            await MainActor.run {
                self.restartBusy = false
                self.restartResult = result.status == 0
                    ? "✓ Daemon neu gestartet."
                    : "Daemon-Neustart fehlgeschlagen (Exit \(result.status)): \(result.output)"
            }
        }
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

    // MARK: - Arrays of objects (presence blocks, contact people)

    func arrayCount(_ path: [String]) -> Int {
        (document?.root.value(at: path)?.arrayValue ?? []).count
    }

    func appendArrayObject(_ path: [String], _ template: JSONValue = .object([:])) {
        mutate { root in
            var arr = root.value(at: path)?.arrayValue ?? []
            arr.append(template)
            root.set(.array(arr), at: path)
        }
    }

    func removeArrayObject(_ path: [String], at index: Int) {
        mutate { root in
            var arr = root.value(at: path)?.arrayValue ?? []
            guard arr.indices.contains(index) else { return }
            arr.remove(at: index)
            root.set(arr.isEmpty ? nil : .array(arr), at: path)
        }
    }

    private func elementValue(_ path: [String], _ index: Int, _ subPath: [String]) -> JSONValue? {
        guard let arr = document?.root.value(at: path)?.arrayValue,
              arr.indices.contains(index) else { return nil }
        return arr[index].value(at: subPath)
    }

    private func setElementValue(_ path: [String], _ index: Int, _ subPath: [String], _ value: JSONValue?) {
        mutate { root in
            var arr = root.value(at: path)?.arrayValue ?? []
            guard arr.indices.contains(index) else { return }
            var element = arr[index]
            if subPath.isEmpty { if let value { element = value } }
            else { element.set(value, at: subPath) }
            arr[index] = element
            root.set(.array(arr), at: path)
        }
    }

    func elementStringBinding(_ path: [String], _ index: Int, _ subPath: [String]) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.elementValue(path, index, subPath)?.stringValue ?? "" },
            set: { [weak self] newValue in
                guard let self,
                      (self.elementValue(path, index, subPath)?.stringValue ?? "") != newValue else { return }
                self.setElementValue(path, index, subPath, newValue.isEmpty ? nil : .string(newValue))
            })
    }

    func elementBoolBinding(_ path: [String], _ index: Int, _ subPath: [String],
                            defaultOn: Bool) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.elementValue(path, index, subPath)?.boolValue ?? defaultOn },
            set: { [weak self] newValue in self?.setElementValue(path, index, subPath, .bool(newValue)) })
    }

    func elementStringListText(_ path: [String], _ index: Int, _ subPath: [String]) -> String {
        (elementValue(path, index, subPath)?.arrayValue ?? [])
            .compactMap(\.stringValue).joined(separator: ", ")
    }

    func setElementStringList(_ path: [String], _ index: Int, _ subPath: [String], from text: String) {
        let items = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        setElementValue(path, index, subPath, items.isEmpty ? nil : .array(items.map { .string($0) }))
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
