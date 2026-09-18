import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KanbanCore

/// Einstellungs-Bereich „Claude-Workflow": Markdown-Editor über den kanonischen Bestand an
/// Skills/Rules (Application Support), mit Symlink-Verwaltung in `~/.claude` **und** `~/.codex` und
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
    private let versionStore = ClaudeAssetVersionStore()

    /// Ein Asset als Baumknoten: der Ordner (bzw. die Datei) mit allem, was darin liegt.
    struct AssetKnoten: Identifiable {
        let asset: ClaudeAsset
        let dateien: [FileEntry]

        var id: String { asset.id }
        /// Die Datei, die das Asset **ist** — bei einem Skill sein `SKILL.md`.
        var hauptdatei: FileEntry { dateien.first { $0.url.lastPathComponent.uppercased() == "SKILL.MD" }
            ?? dateien[0] }
        /// Liegt neben der Hauptdatei noch etwas? Nur dann lohnt ein Aufklapp-Dreieck.
        var hatBeiwerk: Bool { dateien.count > 1 }
    }

    private(set) var sections: [(kind: ClaudeAssetKind, entries: [FileEntry])] = []
    /// Dieselben Assets als Baum je Gattung — `skills/` und `rules/` sind zwei Ordner, und so
    /// stehen sie auch da. Die flache `sections` bleibt daneben: über sie laufen alle Nachschläge.
    private(set) var trees: [(kind: ClaudeAssetKind, knoten: [AssetKnoten])] = []
    private(set) var selected: FileEntry?
    var text: String = ""
    private(set) var savedText: String = ""
    private(set) var reloadToken = 0
    private(set) var message: String?
    /// ClaudeAsset.id → Zustand je Agent. Ein Skill liegt in beiden Homes, also gibt es zwei
    /// Zustände; die Anzeige fasst sie zusammen (siehe `linkSummary`).
    private(set) var linkStates: [String: [AgentKind: ClaudeSymlinkState]] = [:]

    var dirty: Bool { text != savedText }

    func load() {
        ClaudeAssetFactory.seedAtLaunch()   // falls das Sheet vor dem ersten Seeding geöffnet wird
        sections = ClaudeAssetKind.allCases.compactMap { kind in
            let entries = store.assets(kind).flatMap(files(for:))
            return entries.isEmpty ? nil : (kind, entries)
        }
        trees = ClaudeAssetKind.allCases.compactMap { kind in
            let knoten = store.assets(kind)
                .map { AssetKnoten(asset: $0, dateien: files(for: $0)) }
                .filter { !$0.dateien.isEmpty }
            return knoten.isEmpty ? nil : (kind, knoten)
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
        refreshVersions()
    }

    /// Speichern legt zugleich eine **Fassung** an: bis dahin gab es nur die eine Datei, und wer
    /// einen Skill umbaute, konnte den alten Wortlaut nur über den Auslieferungsstand zurückholen —
    /// und warf damit alle anderen eigenen Änderungen mit weg.
    func save(bezeichnung: String? = nil) {
        guard let selected else { return }
        guard dirty || bezeichnung != nil else { return }
        do {
            if dirty {
                try text.write(to: selected.url, atomically: true, encoding: .utf8)
                savedText = text
            }
            try versionStore.sichern(selected.url, bezeichnung: bezeichnung)
            refreshVersions()
            message = bezeichnung.map { "Als Fassung „\($0)“ gesichert." }
        } catch {
            message = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: Fassungen

    private(set) var versions: [ClaudeAssetVersion] = []

    func refreshVersions() {
        versions = selected.map { versionStore.versionen(von: $0.url) } ?? []
    }

    func isActive(_ version: ClaudeAssetVersion) -> Bool {
        guard let selected else { return false }
        return versionStore.istAktiv(version, in: selected.url)
    }

    /// Eine ältere Fassung wieder in die Datei schreiben. Der bisherige Stand wird dabei gesichert —
    /// aktivieren muss selbst rückgängig zu machen sein.
    func activate(_ version: ClaudeAssetVersion) {
        guard let selected else { return }
        do {
            if dirty { try text.write(to: selected.url, atomically: true, encoding: .utf8) }
            try versionStore.aktivieren(version, in: selected.url)
            savedText = (try? String(contentsOf: selected.url, encoding: .utf8)) ?? ""
            text = savedText
            reloadToken += 1
            refreshVersions()
            message = "Fassung vom \(Self.datum(version.datum)) aktiviert."
        } catch {
            message = "Aktivieren fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func deleteVersion(_ version: ClaudeAssetVersion) {
        do {
            try versionStore.loeschen(version)
            refreshVersions()
        } catch {
            message = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    static func datum(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Einlesen

    /// Übernimmt den Inhalt einer Markdown-Datei von der Platte in das gewählte Asset.
    ///
    /// **Gesichert, nicht gespeichert**: der bisherige Stand wandert vorher in die Fassungen (dort
    /// steht er auch, wenn diese Datei noch nie über den Editor gespeichert wurde), der eingelesene
    /// Text landet nur im Editor. Gelesen wird erst, geprüft, dann gespeichert — und der Rückweg
    /// steht bereit.
    func importieren(_ url: URL) {
        guard let selected else { return }
        do {
            if dirty {
                try text.write(to: selected.url, atomically: true, encoding: .utf8)
                savedText = text
            }
            try versionStore.sichern(selected.url)
            text = try ClaudeAssetImport.lesen(url, bisher: savedText)
            reloadToken += 1
            refreshVersions()
            message = "Aus „\(url.lastPathComponent)“ eingelesen — noch nicht gespeichert."
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Anlegen

    /// Legt ein Asset an, wählt es aus und verlinkt einen Skill gleich — ein neuer Skill, der in
    /// keinem Home hängt, wäre nur eine Datei im Bestand und in keinem Projekt zu gebrauchen.
    func create(kind: ClaudeAssetKind, name: String, beschreibung: String,
                inhalt: String? = nil) -> Bool {
        do {
            let asset = try store.create(kind: kind, name: name, beschreibung: beschreibung,
                                         inhalt: inhalt)
            if asset.kind != .rule {
                for agent in store.linkableAgents(for: asset) {
                    try? store.installSymlink(for: asset, agent: agent)
                }
            }
            selected = nil
            load()
            select(sections.flatMap(\.entries).first { $0.asset.id == asset.id })
            message = asset.kind == .rule
                ? "Rule „\(asset.name)“ angelegt — Rules werden per Pfad referenziert, nicht verlinkt."
                : "Skill „\(asset.name)“ angelegt und in beide Homes verlinkt."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    /// Ob dieser Name jetzt gerade frei und brauchbar ist — für die Rückmeldung im Anlegen-Dialog,
    /// bevor jemand auf „Anlegen" drückt.
    func createError(kind: ClaudeAssetKind, name roh: String) -> String? {
        let name = ClaudeAssetName.normalisiert(roh)
        guard !name.isEmpty else { return nil }   // noch nichts getippt: keine Meldung
        do { try ClaudeAssetName.pruefen(name) } catch { return error.localizedDescription }
        if store.assets(kind).contains(where: { $0.name == name }) {
            return ClaudeAssetName.Fehler.belegt(name).errorDescription
        }
        return nil
    }

    func deleteSelectedAsset() {
        guard let asset = selected?.asset else { return }
        do {
            try store.delete(asset)
            selected = nil
            load()
            message = "„\(asset.name)“ gelöscht."
        } catch {
            message = "Löschen fehlgeschlagen: \(error.localizedDescription)"
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

    /// Zusammenfassung für das Badge: verlinkt nur, wenn **jeder** mögliche Zielort verlinkt ist —
    /// ein Skill, der nur in `~/.claude` hängt, ist für ein Codex-Projekt nicht da.
    func linkSummary(for asset: ClaudeAsset) -> ClaudeSymlinkState? {
        guard let states = linkStates[asset.id], !states.isEmpty else { return nil }
        if let foreign = states.values.first(where: { if case .foreign = $0 { return true }; return false }) {
            return foreign
        }
        return states.values.allSatisfy { $0 == .linked } ? .linked : .notInstalled
    }

    /// Welche Agents dieses Asset erreicht (für den Tooltip: „~/.claude, ~/.codex").
    func linkedAgents(for asset: ClaudeAsset) -> [AgentKind] {
        (linkStates[asset.id] ?? [:]).filter { $0.value == .linked }.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Dieselbe Liste als Text — Swift erlaubt keine mehrzeilige Interpolation im Tooltip.
    func linkedHomes(for asset: ClaudeAsset) -> String {
        linkedAgents(for: asset).map { "~/.\($0.rawValue)" }.joined(separator: ", ")
    }

    func toggleLink(for asset: ClaudeAsset) {
        let agents = store.linkableAgents(for: asset)
        let allLinked = linkSummary(for: asset) == .linked
        for agent in agents {
            do {
                if allLinked { try store.removeSymlink(for: asset, agent: agent) }
                else { try store.installSymlink(for: asset, agent: agent) }
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
        refreshLinkStates()
    }

    func installAllLinks() {
        store.installAllSymlinks()
        refreshLinkStates()
        let foreign = linkStates.values.flatMap(\.values)
            .filter { if case .foreign = $0 { return true }; return false }
        message = foreign.isEmpty
            ? "Alle Skills nach ~/.claude und ~/.codex verlinkt."
            : "Verlinkt — \(foreign.count) Zielort(e) übersprungen (fremde Datei liegt dort)."
    }

    private func refreshLinkStates() {
        linkStates = Dictionary(uniqueKeysWithValues: store.allAssets()
            .filter { $0.kind != .rule }
            .map { ($0.id, store.symlinkStates(for: $0)) })
    }

    /// Alt-Commands/Rules sind die Datei selbst; ein Skill zeigt seine .md-Dateien einzeln.
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
    @State private var confirmDelete = false
    @State private var neuesAsset = false
    @State private var zeigeFassungen = false
    /// Lesen oder bearbeiten. Gilt für das Fenster, nicht je Asset — beim Durchklicken will man
    /// nicht bei jeder Datei neu umschalten.
    @State private var bearbeiten = false
    /// Von Hand aufgeklappte Ordner (der gewählte klappt ohnehin auf).
    @State private var expandiert: Set<String> = []
    @State private var suche = MarkdownFind()
    @FocusState private var sucheFokussiert: Bool

    var body: some View {
        HStack(spacing: 0) {
            assetList
            Divider()
            editorPane
        }
        .onAppear { model.load() }
        .onKeyPress(keys: ["f"], phases: .down) { druck in
            guard druck.modifiers.contains(.command) else { return .ignored }
            bearbeiten = false          // gesucht wird in der gerenderten Ansicht
            sucheFokussiert = true
            return .handled
        }
        .sheet(isPresented: $neuesAsset) {
            NeuesAssetSheet(model: model) { neuesAsset = false }
        }
        .sheet(isPresented: $zeigeFassungen) {
            FassungenSheet(model: model) { zeigeFassungen = false }
        }
        .confirmationDialog("„\(model.selected?.asset.name ?? "")“ auf den Auslieferungsstand zurücksetzen?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) { model.resetSelectedToFactory() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Überschreibt deine Änderungen an diesem Asset mit der Fassung aus der App. "
                 + "Die gespeicherten Fassungen bleiben — von dort kommst du zurück.")
        }
        .confirmationDialog("„\(model.selected?.asset.name ?? "")“ löschen?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { model.deleteSelectedAsset() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Asset und seine Verknüpfungen in ~/.claude und ~/.codex werden entfernt.")
        }
    }

    private var assetList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { model.selected?.id },
                set: { id in model.select(model.sections.flatMap(\.entries).first { $0.id == id }) }
            )) {
                // Ein Baum je Gattung — `skills/` und `rules/` sind zwei Ordner im Bestand, und die
                // Liste zeigt sie als solche statt als eine durchgehende Aufzählung.
                ForEach(model.trees, id: \.kind) { baum in
                    Section(ordnerTitel(baum.kind, anzahl: baum.knoten.count)) {
                        ForEach(baum.knoten) { knoten in
                            if knoten.hatBeiwerk { ordnerZeile(knoten) } else { blattZeile(knoten) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            listenFuss
        }
        .frame(width: 230)
    }

    /// Anlegen und Löschen unter der Liste — dort, wo man es von einer Liste erwartet.
    private var listenFuss: some View {
        HStack(spacing: 2) {
            Button { neuesAsset = true } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Skill oder Rule anlegen")
            Button { confirmDelete = true } label: { Image(systemName: "minus") }
                .buttonStyle(.borderless)
                .disabled(model.selected == nil)
                .help("Gewähltes Asset löschen")
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    /// Ein Asset, das aus **einer** Datei besteht — bei einem Skill heisst das: nur `SKILL.md`.
    /// Dort ist der Ordner die Datei, und ein Dreieck, hinter dem genau eine Zeile steckt, wäre ein
    /// Klick für nichts (11 der 14 Skills hier).
    private func blattZeile(_ knoten: ClaudeWorkflowModel.AssetKnoten) -> some View {
        zeile(titel: knoten.asset.name, asset: knoten.asset,
              symbol: knoten.asset.kind == .skill ? "doc.text" : "text.justify.left")
            .tag(knoten.hauptdatei.id)
    }

    /// Ein Asset mit Beiwerk (`methodology.md` neben dem Skill) — aufklappbar, mit seinen Dateien
    /// darunter. Der Ordner selbst ist nicht wählbar: gewählt wird immer eine Datei.
    private func ordnerZeile(_ knoten: ClaudeWorkflowModel.AssetKnoten) -> some View {
        DisclosureGroup(isExpanded: aufgeklappt(knoten)) {
            ForEach(knoten.dateien) { datei in
                zeile(titel: datei.url.lastPathComponent, asset: nil, symbol: "doc.text")
                    .tag(datei.id)
            }
        } label: {
            zeile(titel: knoten.asset.name, asset: knoten.asset, symbol: "folder")
        }
    }

    /// Aufgeklappt, solange eine Datei daraus gewählt ist — sonst zeigte die rechte Seite einen
    /// Inhalt, dessen Zeile links hinter einem Dreieck steckt (dieselbe Regel wie im
    /// Knowledgebase-Baum).
    private func aufgeklappt(_ knoten: ClaudeWorkflowModel.AssetKnoten) -> Binding<Bool> {
        Binding(
            get: { expandiert.contains(knoten.id)
                   || knoten.dateien.contains { $0.id == model.selected?.id } },
            set: { auf in
                if auf { expandiert.insert(knoten.id) } else { expandiert.remove(knoten.id) }
            })
    }

    private func zeile(titel: String, asset: ClaudeAsset?, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(titel)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if let asset { linkBadge(for: asset) }
        }
    }

    /// Kettenglied = in allen möglichen Homes verlinkt, offenes Glied = (noch) nicht überall,
    /// ⚠ = fremde Datei an einem Zielort.
    @ViewBuilder
    private func linkBadge(for asset: ClaudeAsset) -> some View {
        switch model.linkSummary(for: asset) {
        case .linked:
            Image(systemName: "link").font(.system(size: 9)).foregroundStyle(.green)
                .help("Verlinkt in \(model.linkedHomes(for: asset)) — gilt in jedem Projekt")
        case .notInstalled:
            Image(systemName: "link").font(.system(size: 9)).foregroundStyle(.quaternary)
                .help(model.linkedAgents(for: asset).isEmpty
                      ? "Nicht verlinkt"
                      : "Nur in \(model.linkedHomes(for: asset)) verlinkt")
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
                ansichtsWahl
                Divider()
                inhalt
            } else {
                Text("Kein Asset gewählt").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
    }

    /// Ganz oben: lesen oder bearbeiten.
    ///
    /// Gelesen wird hier mehr als geschrieben — ein `SKILL.md` hat bis zu 49 KB, und als Rohtext
    /// mit Sternchen und Tabellen-Pipes ist das mühsam. Vorgabe ist deshalb **gerendert**, wie im
    /// Commit-Dialog (Diff vor Editor) und im Dokumentfenster; ein Klick weiter steht der Editor,
    /// und die Wahl bleibt, während man durch die Assets klickt.
    private var ansichtsWahl: some View {
        HStack(spacing: 10) {
            finderKnopf
            Picker("", selection: $bearbeiten) {
                Text("Gerendert").tag(false)
                Text("Bearbeiten").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            if let selected = model.selected {
                Text(selected.title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 0)
            if model.dirty {
                Text(bearbeiten ? "ungespeichert" : "ungespeicherte Änderungen — hier zu sehen")
                    .font(.caption).foregroundStyle(.orange)
            }
            // Ein `SKILL.md` hat bis zu 49 KB — gelesen wird hier gesucht, nicht gescrollt.
            if !bearbeiten {
                MarkdownFindBar(query: $suche.query, treffer: suche.treffer, aktuell: suche.index,
                                zaehlbar: suche.zaehlbar, weiter: { suche.weiter($0) },
                                fokussiert: $sucheFokussiert, breite: 110)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .onChange(of: suche.query) { suche.eingabeGeaendert(model.text) }
        .onChange(of: model.text) { suche.inhaltGeaendert(model.text) }
    }

    /// Zeigt die gewählte Datei im Finder — also den Ordner, **mit ihr ausgewählt**. Bei einem
    /// Skill ist das sein eigener Ordner (dort liegt auch das Beiwerk), bei einer Rule der
    /// `rules/`-Ordner. Der Bestand steht in Application Support und ist von Hand kaum zu finden;
    /// derselbe Knopf steht aus demselben Grund in der Knowledgebase und im Dokumentfenster.
    @ViewBuilder
    private var finderKnopf: some View {
        if let selected = model.selected {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([selected.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Im Finder zeigen: \(abbreviateHome(selected.url.deletingLastPathComponent().path))")
        }
    }

    @ViewBuilder
    private var inhalt: some View {
        if bearbeiten {
            CodeEditorView(text: $model.text,
                           highlight: DiffHighlight(addedLines: [], deletionMarkers: []),
                           language: .markdown,
                           reloadToken: model.reloadToken)
        } else if let selected = model.selected {
            // **Der Editor-Text**, nicht die Datei: wer etwas geändert und noch nicht gespeichert
            // hat, soll sehen, was er gleich speichert — und nicht den Stand von vorher.
            MarkdownWebView(
                markdown: TaskFileLoader.rewriteImagePaths(
                    model.text, directory: selected.url.deletingLastPathComponent()),
                baseURL: selected.url.deletingLastPathComponent(),
                onLinkClick: sprungInDenBestand,
                search: suche.suche)
        }
    }

    /// Ein Link auf eine Nachbardatei desselben Skills (`[methodology.md](methodology.md)` — genau
    /// die Schreibweise, die der Bestand benutzt) springt **in der Ansicht** dorthin, statt den
    /// Finder zu rufen. Alles andere geht den gewohnten Weg nach draussen.
    private func sprungInDenBestand(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ziel = url.standardizedFileURL.path
        guard let treffer = model.sections.flatMap(\.entries).first(where: {
            $0.url.standardizedFileURL.path == ziel
        }) else { return false }
        model.select(treffer)
        return true
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
                    .help("Symlinkt alle Skills nach ~/.claude und ~/.codex — Rules werden per Pfad "
                        + "referenziert")
                if let asset = model.selected?.asset, asset.kind != .rule {
                    Button(model.linkSummary(for: asset) == .linked ? "Link entfernen" : "Verlinken") {
                        model.toggleLink(for: asset)
                    }
                }
                Button("Einlesen…") {
                    guard let url = MarkdownDateiwahl.waehlen(titel: "Inhalt einlesen") else { return }
                    model.importieren(url)
                    // Eingelesenes ist ungespeichert und will angesehen werden — gerendert zeigt
                    // die Ansicht ohnehin den Editor-Text, also bleibt die Wahl, wie sie ist.
                }
                .disabled(model.selected == nil)
                .help("Inhalt aus einer Markdown-Datei übernehmen — der bisherige Stand wandert "
                      + "vorher in die Fassungen")
                Button("Zurücksetzen") { confirmReset = true }
                    .disabled(!model.selectedHasFactoryVersion)
                    .help("Auf Auslieferungsstand zurücksetzen")
                Button {
                    zeigeFassungen = true
                } label: {
                    Label("\(model.versions.count) Fassungen", systemImage: "clock.arrow.circlepath")
                }
                .disabled(model.selected == nil)
                .help("Frühere Fassungen ansehen und wieder aktivieren")
                Button("Speichern") { model.save() }
                    .disabled(!model.dirty)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Speichert und legt eine Fassung an")
            }
        }
        .padding(10)
    }

    /// Überschrift eines Baums: der **Ordnername** im Bestand plus die Anzahl — so heisst es auf
    /// der Platte, und darum geht es hier.
    private func ordnerTitel(_ kind: ClaudeAssetKind, anzahl: Int) -> String {
        let zusatz = kind == .command ? " · Altbestand" : ""
        return "\(kind.rawValue)/ · \(anzahl)\(zusatz)"
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Der Dateidialog fürs Einlesen. Eine Stelle für beide Wege (bestehendes Asset füllen und neues
/// daraus anlegen) — dieselben Typen, dieselbe Beschriftung.
enum MarkdownDateiwahl {
    static func waehlen(titel: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = titel
        panel.message = "Markdown- oder Textdatei wählen"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // `net.daringfireball.markdown` ist der Typ, den Kanban selbst importiert (siehe
        // „Markdown-Dateien öffnen"); Text ist mit dabei, weil ein Skill auch als `.txt` herumliegen
        // kann.
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown"), .plainText].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// „Skill oder Rule anlegen" — die beiden Gattungen, die Kanban kanonisch besitzt.
///
/// Commands fehlen mit Absicht: sie sind Altbestand (`ClaudeAssetMigration` hat sie zu Skills
/// gemacht), Codex kennt sie gar nicht, und ein neu angelegter wäre von Anfang an ein Sonderfall.
private struct NeuesAssetSheet: View {
    let model: ClaudeWorkflowModel
    let onClose: () -> Void

    @State private var kind: ClaudeAssetKind = .skill
    @State private var name = ""
    @State private var beschreibung = ""
    /// Inhalt aus einer Datei statt der Vorlage — nil heisst „Vorlage".
    @State private var inhalt: String?
    @State private var quelle: URL?
    @State private var fehlerBeimLesen: String?

    private var normalisiert: String { ClaudeAssetName.normalisiert(name) }
    private var fehler: String? { model.createError(kind: kind, name: name) }
    private var bereit: Bool { !normalisiert.isEmpty && fehler == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Neues Asset").font(.headline)

            Picker("", selection: $kind) {
                Text("Skill").tag(ClaudeAssetKind.skill)
                Text("Rule").tag(ClaudeAssetKind.rule)
            }
            .pickerStyle(.segmented).labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                TextField("name-in-kebab-case", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit { if bereit { anlegen() } }
                // Der Name ist Dateiname, Symlink-Ziel und Aufruf zugleich — was daraus wird, steht
                // hier, bevor jemand auf „Anlegen" drückt.
                if let fehler {
                    Text(fehler).font(.caption).foregroundStyle(.orange)
                } else if !normalisiert.isEmpty {
                    Text(kind == .skill
                         ? "wird zu `skills/\(normalisiert)/SKILL.md`, aufrufbar als /\(normalisiert)"
                         : "wird zu `rules/\(normalisiert).md`")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Kleinbuchstaben, Ziffern, Bindestriche — wie `create-task`.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField(kind == .skill ? "Beschreibung (steht im Frontmatter)" : "Wofür gilt die Regel?",
                          text: $beschreibung, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                if let fehlerBeimLesen {
                    Text(fehlerBeimLesen).font(.caption).foregroundStyle(.orange)
                } else if quelle != nil {
                    Text(kind == .skill
                         ? "Inhalt kommt aus der Datei; fehlt ihr das Frontmatter, wird es ergänzt."
                         : "Inhalt kommt aus der Datei.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if kind == .rule {
                    Text("Rules werden nicht verlinkt — die Skills verweisen per Pfad auf sie.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Button("Aus Datei…", action: ausDatei)
                    .help("Eine vorhandene Markdown-Datei als Inhalt übernehmen")
                if let quelle {
                    Text(quelle.lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button {
                        self.quelle = nil
                        inhalt = nil
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Doch die Vorlage benutzen")
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Anlegen") { anlegen() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!bereit)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    /// Datei wählen, Inhalt merken und den Namen daraus vorschlagen — solange noch keiner getippt
    /// wurde. Wer schon einen Namen hat, soll ihn nicht verlieren.
    private func ausDatei() {
        guard let url = MarkdownDateiwahl.waehlen(titel: "Asset aus Datei anlegen") else { return }
        do {
            inhalt = try ClaudeAssetImport.lesen(url, bisher: "")
            quelle = url
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                let stamm = url.deletingPathExtension().lastPathComponent
                // `SKILL.md` als Dateiname sagt nichts — dann zählt der Ordner darüber.
                name = stamm.uppercased() == "SKILL"
                    ? url.deletingLastPathComponent().lastPathComponent
                    : stamm
            }
            fehlerBeimLesen = nil
        } catch {
            fehlerBeimLesen = error.localizedDescription
        }
    }

    private func anlegen() {
        if model.create(kind: kind, name: name, beschreibung: beschreibung, inhalt: inhalt) {
            onClose()
        }
    }
}

/// Die Fassungen einer Datei: ansehen, wieder aktivieren, wegwerfen.
private struct FassungenSheet: View {
    let model: ClaudeWorkflowModel
    let onClose: () -> Void

    @State private var bezeichnung = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fassungen von \(model.selected?.title ?? "")")
                .font(.headline).lineLimit(1)

            // Den aktuellen Stand benennen: genau so findet man ihn später wieder. Unbenannte
            // Fassungen entstehen bei jedem Speichern von selbst.
            HStack(spacing: 8) {
                TextField("Diesen Stand sichern als…", text: $bezeichnung)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sichern)
                Button("Sichern", action: sichern)
                    .disabled(bezeichnung.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if model.versions.isEmpty {
                Text("Noch keine Fassung. Jedes Speichern legt eine an.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.versions) { version in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(version.bezeichnung ?? ClaudeWorkflowModel.datum(version.datum))
                                    .font(.system(size: 12, weight: version.bezeichnung == nil ? .regular : .semibold))
                                if model.isActive(version) {
                                    Text("aktiv")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.green.opacity(0.2), in: Capsule())
                                }
                            }
                            Text(version.bezeichnung == nil
                                 ? "\(version.bytes) Bytes"
                                 : "\(ClaudeWorkflowModel.datum(version.datum)) · \(version.bytes) Bytes")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Aktivieren") { model.activate(version) }
                            .disabled(model.isActive(version))
                        Button {
                            model.deleteVersion(version)
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Diese Fassung löschen")
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 240)
            }

            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text("Unbenannte Fassungen werden nach \(ClaudeAssetVersionStore.maxAutomatisch) "
                     + "aufgeräumt; benannte bleiben.")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Fertig") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 560, height: 460)
        .onAppear { model.refreshVersions() }
    }

    private func sichern() {
        let name = bezeichnung.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.save(bezeichnung: name)
        bezeichnung = ""
    }
}
