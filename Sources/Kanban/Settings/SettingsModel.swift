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
        migriereMarkdownAltblock()
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

    /// Der flache `markdown`-Altblock zieht beim Speichern einmalig in eine benannte Fassung um
    /// (`MarkdownAltblock` — dort steht auch, warum).
    private func migriereMarkdownAltblock() {
        guard var doc = document else { return }
        guard MarkdownAltblock.migriere(&doc.root) else { return }
        document = doc
        dirty = true
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

    // MARK: - Zahlen (als JSON-Zahl, nicht als Zeichenkette)

    /// Der Wert als Text fürs Feld — leer heisst „nicht gesetzt", also Vorgabe.
    func numberText(at path: [String]) -> String {
        document?.root.value(at: path)?.doubleValue.map(Self.zahlText) ?? ""
    }

    /// Schreibt **ungerundet und ungezogen**, was dasteht: gezogen wird erst beim Verlassen des
    /// Feldes (`clampNumber`). Wer „1" tippt, um „16" zu schreiben, soll nicht nach dem ersten
    /// Zeichen bei der Untergrenze landen. Leer entfernt den Schlüssel; Unlesbares bleibt liegen,
    /// statt eine halbe Eingabe in die Datei zu schreiben.
    func setNumber(_ path: [String], from text: String) {
        let getrimmt = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if getrimmt.isEmpty {
            guard document?.root.value(at: path) != nil else { return }
            mutate { $0.set(nil, at: path) }
            return
        }
        guard let zahl = Double(getrimmt), zahl != document?.root.value(at: path)?.doubleValue else { return }
        mutate { $0.set(Self.jsonZahl(zahl), at: path) }
    }

    /// Beim Verlassen auf die Grenzen ziehen — dieselben, die auch der Decoder anwendet.
    func clampNumber(_ path: [String], min: Double, max: Double) {
        guard let zahl = document?.root.value(at: path)?.doubleValue else { return }
        let gezogen = Swift.min(Swift.max(zahl, min), max)
        guard gezogen != zahl else { return }
        mutate { $0.set(Self.jsonZahl(gezogen), at: path) }
    }

    /// Ganze Zahlen bleiben ganz: `16` statt `16.0` — `JSONValue` hält die beiden auseinander, und
    /// eine Config voller `.0` liest sich schlechter.
    static func jsonZahl(_ wert: Double) -> JSONValue {
        wert == wert.rounded() && abs(wert) < 1e15 ? .int(Int(wert)) : .double(wert)
    }

    static func zahlText(_ wert: Double) -> String {
        wert == wert.rounded() && abs(wert) < 1e15 ? String(Int(wert)) : String(wert)
    }

    // MARK: - Benannte Fassungen (`terminal.themes`, `markdown.themes`)

    /// Die Schlüssel eines Objekts — die Namen der Fassungen, die Auswahl einer `choiceFromKeys`.
    func keys(at path: [String]) -> [String] {
        (document?.root.value(at: path)?.objectValue ?? [:]).keys.sorted()
    }

    func themeValues(_ spec: ThemeMapSpec, key: String) -> JSONValue? {
        document?.root.value(at: spec.path + [key])
    }

    func activeTheme(_ spec: ThemeMapSpec) -> String {
        document?.root.value(at: spec.activePath)?.stringValue ?? ""
    }

    /// Anlegen, Entfernen, Umbenennen und die ANSI-Farben liegen als reine JSON-Operationen in
    /// `ThemeMapEdit` — dort stehen auch die Gründe, und dort sind sie prüfbar.
    func addTheme(_ spec: ThemeMapSpec, key: String) {
        mutate { ThemeMapEdit.add(&$0, spec: spec, name: key) }
    }

    func removeTheme(_ spec: ThemeMapSpec, key: String) {
        mutate { ThemeMapEdit.remove(&$0, spec: spec, name: key) }
    }

    func renameTheme(_ spec: ThemeMapSpec, from: String, to: String) {
        mutate { ThemeMapEdit.rename(&$0, spec: spec, from: from, to: to) }
    }

    func ansiBinding(_ path: [String], index: Int) -> Binding<String> {
        Binding(
            get: { [weak self] in
                let liste = self?.document?.root.value(at: path)?.arrayValue ?? []
                return index < liste.count ? (liste[index].stringValue ?? "") : ""
            },
            set: { [weak self] neu in
                self?.mutate { ThemeMapEdit.setAnsi(&$0, path: path, index: index, hex: neu) }
            })
    }

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

    /// Der Vorschlag — und als erste Quelle der `origin`-Remote des Repos, das unter dem Basis-Pfad
    /// vielleicht schon liegt: er **sagt**, auf welcher Forge das Projekt liegt, während die Muster
    /// der Nachbarprojekte es nur raten. Liegt dort noch nichts, bleibt der bisherige Weg.
    func projectSuggestion(for key: String) -> ProjectRecord {
        let root = document?.root ?? .object([:])
        let origin = candidateRepoDir(for: key).flatMap(ProjectSuggestion.originURL(repoDir:))
        return ProjectSuggestion.record(for: key, from: root, originURL: origin)
    }

    /// Wo das Repo läge, wenn es der Konvention folgt: `<basePath>/<key>` — dieselbe Ableitung, die
    /// `KanbanConfig` ohne `repoDir`-Override benutzt.
    private func candidateRepoDir(for key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let base = document?.root.value(at: ["basePath"])?.stringValue ?? "~/code"
        return ((base as NSString).expandingTildeInPath as NSString).appendingPathComponent(trimmed)
    }

    func isProjectKeyTaken(_ key: String) -> Bool {
        ProjectSuggestion.isTaken(key, in: document?.root ?? .object([:]))
    }

    /// Legt ein Projekt in allen betroffenen Modul-Sections an (nur im Dokument — geschrieben wird
    /// wie bei jeder anderen Änderung erst beim Speichern).
    func createProject(key: String, record: ProjectRecord) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !record.isEmpty else { return }
        mutate {
            $0 = ProjectProjection.apply(record, key: trimmed, to: $0)
            // Getrennter Aufruf, weil es getrennte Ziele sind: `apply` läuft auch gegen Hermes'
            // Config, die Kanban-eigenen Sections (`modules.docker`) gehören nur hierher.
            $0 = ProjectProjection.applyKanbanOnly(record, key: trimmed, to: $0)
        }
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
