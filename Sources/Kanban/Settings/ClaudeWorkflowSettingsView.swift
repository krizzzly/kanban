import SwiftUI
import KanbanCore

/// Einstellungs-Bereich „Claude-Workflow": Markdown-Editor über den kanonischen Bestand an
/// Commands/Skills/Rules (Application Support), mit Symlink-Verwaltung in `~/.claude` und
/// „Auf Auslieferungsstand zurücksetzen" aus den Bundle-Resources.
@Observable
final class ClaudeWorkflowModel {
    struct FileEntry: Identifiable, Hashable {
        let asset: ClaudeAsset
        let url: URL
        let title: String
        var id: String { url.path }
    }

    private let store = ClaudeAssetStore()

    private(set) var sections: [(kind: ClaudeAssetKind, entries: [FileEntry])] = []
    private(set) var selected: FileEntry?
    var text: String = ""
    private(set) var savedText: String = ""
    private(set) var reloadToken = 0
    private(set) var message: String?
    private(set) var linkStates: [String: ClaudeSymlinkState] = [:]   // ClaudeAsset.id → Zustand

    var dirty: Bool { text != savedText }

    func load() {
        ClaudeAssetFactory.seedAtLaunch()   // falls das Sheet vor dem ersten Seeding geöffnet wird
        sections = ClaudeAssetKind.allCases.compactMap { kind in
            let entries = store.assets(kind).flatMap(files(for:))
            return entries.isEmpty ? nil : (kind, entries)
        }
        refreshLinkStates()
        if let current = selected {
            selected = sections.flatMap(\.entries).first { $0.id == current.id }
        }
        if selected == nil { select(sections.first?.entries.first) }
    }

    /// Auswahlwechsel speichert Ungespeichertes — verlustfrei und billiger als eine Rückfrage.
    func select(_ entry: FileEntry?) {
        if dirty { save() }
        selected = entry
        savedText = entry.flatMap { try? String(contentsOf: $0.url, encoding: .utf8) } ?? ""
        text = savedText
        reloadToken += 1
        message = nil
    }

    func save() {
        guard let selected, dirty else { return }
        do {
            try text.write(to: selected.url, atomically: true, encoding: .utf8)
            savedText = text
            message = nil
        } catch {
            message = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: Auslieferungsstand

    var selectedHasFactoryVersion: Bool {
        guard let selected, let factory = ClaudeAssetFactory.bundledRoot else { return false }
        return store.hasFactoryVersion(selected.asset, in: factory)
    }

    /// Setzt das ganze Asset (bei Skills: den Ordner) auf den Auslieferungsstand zurück.
    func resetSelectedToFactory() {
        guard let selected, let factory = ClaudeAssetFactory.bundledRoot else { return }
        do {
            try store.resetToFactory(selected.asset, from: factory)
            let keep = selected
            self.selected = nil     // Auswahl neu aufbauen, damit der Editor den Bestand neu lädt
            load()
            select(sections.flatMap(\.entries).first { $0.id == keep.id })
            message = "Auf Auslieferungsstand zurückgesetzt."
        } catch {
            message = "Zurücksetzen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: Symlinks

    func linkState(for asset: ClaudeAsset) -> ClaudeSymlinkState? {
        asset.kind == .rule ? nil : linkStates[asset.id]
    }

    func toggleLink(for asset: ClaudeAsset) {
        do {
            switch linkStates[asset.id] {
            case .linked: try store.removeSymlink(for: asset)
            default:      try store.installSymlink(for: asset)
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
        refreshLinkStates()
    }

    func installAllLinks() {
        store.installAllSymlinks()
        refreshLinkStates()
        let foreign = linkStates.values.filter { if case .foreign = $0 { return true }; return false }
        message = foreign.isEmpty
            ? "Alle Commands + Skills nach ~/.claude verlinkt."
            : "Verlinkt — \(foreign.count) Zielort(e) übersprungen (fremde Datei liegt dort)."
    }

    private func refreshLinkStates() {
        linkStates = Dictionary(uniqueKeysWithValues: store.allAssets()
            .filter { $0.kind != .rule }
            .map { ($0.id, store.symlinkState(for: $0)) })
    }

    /// Commands/Rules sind die Datei selbst; ein Skill zeigt seine .md-Dateien einzeln.
    private func files(for asset: ClaudeAsset) -> [FileEntry] {
        switch asset.kind {
        case .command, .rule:
            return [FileEntry(asset: asset, url: asset.url, title: asset.name)]
        case .skill:
            let mds = (try? FileManager.default.contentsOfDirectory(
                at: asset.url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))?
                .filter { $0.pathExtension == "md" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            return mds.map { FileEntry(asset: asset, url: $0,
                                       title: "\(asset.name)/\($0.lastPathComponent)") }
        }
    }
}

struct ClaudeWorkflowSettingsView: View {
    @State private var model = ClaudeWorkflowModel()
    @State private var confirmReset = false

    var body: some View {
        HStack(spacing: 0) {
            assetList
            Divider()
            editorPane
        }
        .onAppear { model.load() }
        .confirmationDialog("„\(model.selected?.asset.name ?? "")“ auf den Auslieferungsstand zurücksetzen?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) { model.resetSelectedToFactory() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Überschreibt deine Änderungen an diesem Asset mit der Fassung aus der App.")
        }
    }

    private var assetList: some View {
        List(selection: Binding(
            get: { model.selected?.id },
            set: { id in model.select(model.sections.flatMap(\.entries).first { $0.id == id }) }
        )) {
            ForEach(model.sections, id: \.kind) { section in
                Section(sectionTitle(section.kind)) {
                    ForEach(section.entries) { entry in
                        HStack(spacing: 6) {
                            Text(entry.title)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            linkBadge(for: entry.asset)
                        }
                        .tag(entry.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 230)
    }

    /// Kettenglied = verlinkt, offenes Glied = nicht verlinkt, ⚠ = fremde Datei am Zielort.
    @ViewBuilder
    private func linkBadge(for asset: ClaudeAsset) -> some View {
        switch model.linkState(for: asset) {
        case .linked:
            Image(systemName: "link").font(.system(size: 9)).foregroundStyle(.green)
                .help("In ~/.claude verlinkt — gilt in jedem Projekt")
        case .notInstalled:
            Image(systemName: "link").font(.system(size: 9)).foregroundStyle(.quaternary)
                .help("Nicht verlinkt")
        case .foreign(let what):
            Image(systemName: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(.orange)
                .help("Zielort belegt: \(what)")
        case nil:
            EmptyView()   // Rules werden nicht verlinkt
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            if model.selected != nil {
                CodeEditorView(text: $model.text,
                               highlight: DiffHighlight(addedLines: [], deletionMarkers: []),
                               language: .markdown,
                               reloadToken: model.reloadToken)
            } else {
                Text("Kein Asset gewählt").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                if let selected = model.selected {
                    Text(abbreviateHome(selected.url.path))
                        .font(.caption).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                    if model.dirty {
                        Text("●").font(.caption).foregroundStyle(.orange)
                            .help("Ungespeicherte Änderungen — Speichern-Button oder Bereichswechsel speichert")
                    }
                }
                Spacer()
                Button("Alle verlinken") { model.installAllLinks() }
                    .help("Symlinkt alle Commands + Skills nach ~/.claude — Rules werden per Pfad referenziert")
                if let asset = model.selected?.asset, asset.kind != .rule {
                    Button(model.linkState(for: asset) == .linked ? "Link entfernen" : "Verlinken") {
                        model.toggleLink(for: asset)
                    }
                }
                Button("Zurücksetzen") { confirmReset = true }
                    .disabled(!model.selectedHasFactoryVersion)
                    .help("Auf Auslieferungsstand zurücksetzen")
                Button("Speichern") { model.save() }
                    .disabled(!model.dirty)
            }
        }
        .padding(10)
    }

    private func sectionTitle(_ kind: ClaudeAssetKind) -> String {
        switch kind {
        case .command: return "Commands"
        case .skill:   return "Skills"
        case .rule:    return "Rules"
        }
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
