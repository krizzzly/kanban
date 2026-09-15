import AppKit
import SwiftUI
import WebKit
import KanbanCore

/// Die Knowledgebase des Projekts: Ordnerbaum links, Inhalt rechts.
///
/// Sie **ersetzt** Board und Detail, solange sie offen ist (📚 in der Leiste schaltet um). Ein
/// Sheet wäre der falsche Rahmen — die Knowledgebase ist selbst ein Zwei-Spalten-Bild und wird
/// gelesen, nicht in einem Arbeitsschritt beantwortet.
///
/// Angezeigt wird nach Dateiart, nicht nach Vermutung: Markdown durch denselben Renderer wie die
/// Task-Files, die generierten HTML-Artefakte in einer echten Web-Ansicht (sie bringen ihr eigenes
/// Layout mit, durch den Markdown-Renderer käme ihr Quelltext heraus), Textdateien monospaced.
///
/// **Der Baum steht zu, wenn die Ansicht aufgeht** — gelesen wird rechts, und ein Artefakt bringt
/// sein eigenes Layout mit, das die Fläche braucht. Eingeschaltet wird er über den Knopf in der
/// Kopfzeile der Datei (⌘⌥S, wie im Finder); der Zustand gilt für die geöffnete Ansicht, beim
/// nächsten 📚 steht er wieder zu.
struct KnowledgebaseView: View {
    var model: AppModel
    @State private var expanded: Set<String> = []
    /// Baum eingeblendet? Vorgabe **aus** (Platz). `@State` und nicht gemerkt: die Ansicht wird bei
    /// jedem 📚 neu gebaut, also fängt sie zugeklappt an.
    @State private var showTree = false
    /// Sprungmarke aus einem angeklickten Link (`architektur.md#zwei-cqrs-generationen`). Sie gilt
    /// **einer** Datei, deshalb steht der Pfad daneben: eine Marke, die zur gerade angezeigten Datei
    /// nicht passt, wird nicht angewandt.
    @State private var pendingJump: KBJump?
    /// Woher man kam. Nötig, seit ein Link auch aus der Knowledgebase **hinaus** führen kann (eine
    /// Datei aus dem Repo, gezeigt als Quelltext): die steht in keinem Baum, über den man
    /// zurückfände.
    @State private var back: [KBJump] = []

    private var root: String? { model.selectedProject?.kbPathAbsolute }

    /// Ohne Auswahl steht rechts nur ein Hinweis — und der Knopf, der den Baum zurückholt, sitzt in
    /// der Kopfzeile der Datei. Also steht der Baum dann da, egal was der Schalter sagt: eine
    /// Ansicht ohne Weg zum Baum wäre eine Sackgasse (leere/fehlende Knowledgebase).
    private var treeVisible: Bool { showTree || model.kbSelection == nil }

    var body: some View {
        HSplitView {
            if treeVisible {
                sidebar
                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 460)
            }
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { revealSelection() }
        .onChange(of: model.kbNodes) { _, _ in revealSelection() }
        .onChange(of: model.kbSelection) { _, _ in revealSelection() }
    }

    /// Die oberste Ebene steht offen — sie ist das Inhaltsverzeichnis. Tiefere Ordner bleiben zu,
    /// bis jemand sie öffnet; nur der Weg zur **gewählten** Datei wird aufgeklappt, sonst zeigte die
    /// rechte Seite einen Inhalt, dessen Zeile links hinter einem Dreieck steckt.
    private func revealSelection() {
        expanded.formUnion(model.kbNodes.filter(\.isDirectory).map(\.id))
        if let selection = model.kbSelection {
            expanded.formUnion(KnowledgebaseTree.ancestorFolderIDs(of: selection, in: model.kbNodes))
        }
    }

    // MARK: - Links: Baum

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
            treeContent
        }
        .frame(maxHeight: .infinity)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 6) {
            Button {
                model.closeKnowledgebase()
            } label: {
                Label("Board", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.app(.caption))
            }
            .buttonStyle(.plain)
            .help("Zurück zum Board")

            Spacer(minLength: 4)

            if model.kbLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                model.loadKnowledgebase()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Knowledgebase neu einlesen")

            if let root {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root)])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Knowledgebase im Finder öffnen: \(root)")
            }
        }
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var treeContent: some View {
        if let root, !FileManager.default.fileExists(atPath: root) {
            // Der Pfad ist konfiguriert, der Ordner fehlt — das ist der Fall, den man beheben will,
            // also wird er benannt statt versteckt.
            hint("Knowledgebase-Ordner gibt es nicht", detail: root, icon: "questionmark.folder")
        } else if model.kbNodes.isEmpty {
            if model.kbLoading {
                hint("Wird eingelesen …", detail: nil, icon: "hourglass")
            } else {
                hint("Keine Dateien gefunden", detail: root, icon: "tray")
            }
        } else {
            List(selection: Binding(get: { model.kbSelection },
                                    // Aus dem Baum gewählt heisst: an den Anfang der Datei, nicht
                                    // an die Marke, die ein früherer Link-Klick gesetzt hat.
                                    set: { if let path = $0 { show(path, fragment: nil) } })) {
                KBRows(nodes: model.kbNodes, expanded: $expanded)
            }
            .listStyle(.sidebar)
        }
    }

    private func hint(_ title: String, detail: String?, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.secondary)
            Text(title).font(.app(.callout))
            if let detail {
                Text(detail)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rechts: Inhalt

    @ViewBuilder
    private var detail: some View {
        if let path = model.kbSelection, let root, let node = shownNode(path) {
            KBFileView(node: node,
                       root: root,
                       jumpTo: pendingJump?.path == node.path ? pendingJump?.fragment : nil,
                       canGoBack: !back.isEmpty,
                       onBack: goBack,
                       treeVisible: treeVisible,
                       toggleTree: { showTree.toggle() },
                       onLinkClick: { follow($0, from: node, root: root) })
        } else {
            VStack(spacing: 8) {
                Image(systemName: "books.vertical").font(.system(size: 34)).foregroundStyle(.tint)
                Text("Datei links auswählen").font(.app(.callout)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Der Knoten zum angezeigten Pfad. Liegt die Datei **ausserhalb** der Knowledgebase (ein Link
    /// ins Repo), steht sie in keinem Baum — dann wird ein Knoten für sie gebildet, damit die
    /// Anzeige derselbe Code ist. Ordner zeigt niemand an.
    private func shownNode(_ path: String) -> KBNode? {
        if let node = KnowledgebaseTree.node(at: path, in: model.kbNodes) {
            return node.isDirectory ? nil : node
        }
        return KBNode(path: path, name: (path as NSString).lastPathComponent, isDirectory: false)
    }

    /// Ein angeklickter Link. `true` heisst „übernommen" — dann zeigt die Ansicht das Ziel selbst,
    /// statt den Klick nach draussen zu reichen.
    ///
    /// Die Knowledgebase verlinkt sich hunderte Male selbst (`../Common/HistoryEntry.md`,
    /// `README.md`) und daneben ins Projekt-Repo (`../../core/docs/business-case-structure.md`).
    /// Beides bleibt hier: das eine gerendert, das andere als Quelltext. Nach draussen gehen nur
    /// Web-Links, Sprungmarken im selben Dokument (die erledigt WebKit) und Pfade, die es nicht gibt.
    private func follow(_ url: URL, from node: KBNode, root: String) -> Bool {
        switch KBLink.resolve(url, currentFile: node.path, root: root) {
        case .file(let path, let fragment):
            guard let target = KnowledgebaseTree.node(at: path, in: model.kbNodes) else {
                // Im Baum nicht vorhanden: tote Verknüpfung oder gefilterte Datei — dann soll der
                // Klick nach draussen gehen statt still zu verpuffen.
                return false
            }
            // Auf einen Ordner verlinkt (`../Common/`): dessen Einstieg zeigen.
            guard let file = target.isDirectory ? KnowledgebaseTree.landingFile(target.children) : target
            else { return false }
            show(file.path, fragment: fragment)
            return true

        case .outsideFile(let path):
            // Nur was es wirklich gibt: sonst stünde rechts ein leeres Fenster statt eines
            // Hinweises, und die tote Verknüpfung sähe aus wie ein Anzeigefehler.
            guard FileManager.default.fileExists(atPath: path) else { return false }
            show(path, fragment: nil)
            return true

        case .fragment, .external:
            return false
        }
    }

    /// Datei anzeigen und den bisherigen Stand auf den Zurück-Stapel legen.
    private func show(_ path: String, fragment: String?) {
        guard path != model.kbSelection || fragment != nil else { return }
        if let current = model.kbSelection {
            back.append(KBJump(path: current, fragment: pendingJump?.path == current
                               ? pendingJump?.fragment : nil))
        }
        pendingJump = fragment.map { KBJump(path: path, fragment: $0) }
        model.kbSelection = path
    }

    private func goBack() {
        guard let previous = back.popLast() else { return }
        pendingJump = previous.fragment.map { KBJump(path: previous.path, fragment: $0) }
        model.kbSelection = previous.path
    }
}

/// Ein Ziel mit optionaler Sprungmarke — Pfad **und** Marke, damit eine Marke nicht auf der
/// nächsten Datei landet. Dient auch als Eintrag des Zurück-Stapels.
private struct KBJump {
    let path: String
    let fragment: String?

    init(path: String, fragment: String?) {
        self.path = path
        self.fragment = fragment
    }
}

/// Rekursive Zeilen. Eigener View, weil eine `@ViewBuilder`-Funktion sich nicht selbst aufrufen kann
/// — der Rückgabetyp wäre unendlich verschachtelt (dasselbe Muster wie `FileTreeRows`).
///
/// Auch der Task-Ordner eines Tickets wird damit gezeigt (`TaskAttachmentsPanel`) — derselbe Baum,
/// dieselbe Auswahl. Einziger Unterschied sind die Symbole: die Knowledgebase besteht aus Text, ein
/// Task-Ordner aus Bildern, Videos und Tabellen. Deshalb ist das Symbol ein Parameter und nicht
/// zwei Kopien dieses Views.
struct KBRows: View {
    let nodes: [KBNode]
    @Binding var expanded: Set<String>
    var icon: (KBNode) -> String = Self.kbIcon

    var body: some View {
        ForEach(nodes) { node in
            if node.isDirectory {
                DisclosureGroup(isExpanded: binding(for: node.id)) {
                    KBRows(nodes: node.children, expanded: $expanded, icon: icon)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(node.name).font(.app(.callout, weight: .medium)).lineLimit(1)
                        Text("\(node.fileCount)")
                            .font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: icon(node))
                        .font(.system(size: 11))
                        .foregroundStyle(node.kind == .binary ? .tertiary : .secondary)
                        .frame(width: 13)
                    Text(node.name)
                        .font(.app(.callout))
                        .foregroundStyle(node.kind == .binary ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, 1)
                .contentShape(Rectangle())
                .help(node.name)
                .tag(node.path)
            }
        }
    }

    /// Das Symbol der Knowledgebase: sie besteht aus Markdown und generierten HTML-Seiten.
    static func kbIcon(_ node: KBNode) -> String {
        switch node.kind {
        case .markdown: "doc.text"
        case .html: "globe"
        case .text: "doc.plaintext"
        case .binary: "doc"
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { isOpen in
                    if isOpen { expanded.insert(id) } else { expanded.remove(id) }
                })
    }
}

/// Eine Datei der Knowledgebase — Kopfzeile mit dem Pfad relativ zur KB, darunter der Inhalt.
private struct KBFileView: View {
    let node: KBNode
    /// Wurzel der Knowledgebase: Bezugspunkt der Kopfzeile **und** die Leseerlaubnis der
    /// Web-Ansicht, damit ein HTML-Artefakt seine Bilder und Stylesheets daneben findet.
    let root: String
    /// Sprungmarke, mit der diese Datei geöffnet wurde (`…#zwei-cqrs-generationen`).
    let jumpTo: String?
    let canGoBack: Bool
    let onBack: () -> Void
    /// Steht der Baum links? Nur für die Beschriftung des Schalters — entschieden wird oben.
    let treeVisible: Bool
    let toggleTree: () -> Void
    /// Klick auf einen Link — die Ansicht übernimmt Ziele innerhalb der Knowledgebase.
    let onLinkClick: (URL) -> Bool

    /// Grenze fürs Einlesen. Darüber wird nicht gerendert, sondern gesagt, was los ist: eine
    /// mehrere Megabyte grosse Datei als Markdown durch WKWebView zu schicken, hängt das Fenster auf.
    private static let maxBytes = 4 * 1024 * 1024

    @State private var text: String?
    @State private var loadError: String?
    /// Quelltext statt Darstellung. **Ausserhalb** der Knowledgebase die Vorgabe: wer einem Link
    /// ins Repo folgt, will die Datei sehen — nicht eine gerenderte Fassung davon, die aussieht wie
    /// KB-Inhalt. Innerhalb der KB umgekehrt, dort ist die Darstellung der Zweck. Der Knopf in der
    /// Kopfzeile schaltet beides um.
    @State private var showSource = false

    private var url: URL { URL(fileURLWithPath: node.path) }

    /// Liegt die Datei ausserhalb der Knowledgebase? Dann ist sie über einen Link aus der KB
    /// heraus erreicht worden (ins Projekt-Repo) und wird als Quelltext gezeigt.
    private var isOutside: Bool { !node.path.hasPrefix(root + "/") }

    /// In der KB relativ zu ihr, ausserhalb mit `~` gekürzt — beides kurz genug für eine Zeile und
    /// eindeutig genug, um zu wissen, wo man ist.
    private var displayPath: String {
        if !isOutside { return String(node.path.dropFirst(root.count + 1)) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return node.path.hasPrefix(home + "/") ? "~" + node.path.dropFirst(home.count) : node.path
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        // `id:` statt `onAppear`: bei einem Wechsel der Auswahl bleibt der View stehen und würde
        // sonst den alten Inhalt behalten.
        .task(id: node.path) { load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Ganz links, weil er dem Baum links gilt — und weil er der einzige Weg dorthin ist.
            Button(action: toggleTree) {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: [.command, .option])
            .help(treeVisible ? "Baum ausblenden (⌘⌥S)" : "Baum einblenden (⌘⌥S)")

            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .keyboardShortcut("[", modifiers: .command)
            .help("Zurück (⌘[)")

            if isOutside {
                // Ausserhalb der KB gibt es keine Zeile im Baum, an der man sich orientieren
                // könnte — also sagt es die Kopfzeile.
                Text("Repo")
                    .font(.app(.caption2, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            Text(displayPath)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
                .help(node.path)
            Spacer(minLength: 4)
            if node.kind == .markdown || node.kind == .html {
                Button {
                    showSource.toggle()
                } label: {
                    Image(systemName: showSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.plain)
                .help(showSource ? "Gerendert anzeigen" : "Quelltext anzeigen")
            }
            Button {
                StatusLinkOpener.open(URL(string: StatusLinks.ideURL(forPath: node.path))!)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("In PhpStorm öffnen")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Im Finder zeigen")
        }
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if node.kind == .binary {
            notice(loadError ?? "Kein Textformat — im Finder öffnen", icon: "doc")
        } else if showSource {
            if let text { sourceEditor(text) } else { placeholder }
        } else {
            rendered
        }
    }

    /// Derselbe Editor wie im Commit-Dialog — Zeilennummern, Syntaxfarben, dieselbe Schrift wie das
    /// Terminal. **Nicht** schreibbar: hier wird gelesen, und ein Feld, das Tippen annimmt und die
    /// Änderung wegwirft, wäre schlimmer als ein sichtbar gesperrtes. Zum Ändern führt der Stift.
    private func sourceEditor(_ text: String) -> some View {
        CodeEditorView(text: .constant(text),
                       highlight: DiffHighlight(addedLines: [], deletionMarkers: []),
                       language: CodeLanguage.detect(path: node.path),
                       reloadToken: node.path.hashValue,
                       isEditable: false)
    }

    @ViewBuilder
    private var rendered: some View {
        switch node.kind {
        case .html:
            // Datei-URL statt HTML-String: ein Artefakt lädt sein CSS und seine Bilder relativ,
            // und dafür braucht die Web-Ansicht echten Dateizugriff. Ausserhalb der KB reicht der
            // Ordner der Datei — die KB-Wurzel enthält sie ja nicht, die Erlaubnis ginge ins Leere.
            FileWebView(url: url,
                        readAccessRoot: isOutside ? url.deletingLastPathComponent()
                                                  : URL(fileURLWithPath: root))
        case .markdown:
            if let text {
                MarkdownWebView(
                    markdown: TaskFileLoader.rewriteImagePaths(text, directory: url.deletingLastPathComponent()),
                    // Die **Datei** als Basis, nicht ihr Ordner: nur so löst WebKit `../x.md`
                    // richtig auf und ein `#anker` bleibt als Sprung im selben Dokument erkennbar
                    // (gegen den Ordner ergäbe er den Ordner selbst plus Marke).
                    baseURL: url,
                    onLinkClick: onLinkClick,
                    scrollToFragment: jumpTo)
            } else {
                placeholder
            }
        case .text, .binary:
            // `.text` hat keine eigene Darstellung — Quelltext ist die Darstellung.
            if let text { sourceEditor(text) } else { placeholder }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if let loadError {
            notice(loadError, icon: "exclamationmark.triangle")
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func notice(_ message: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.secondary)
            Text(message)
                .font(.app(.callout))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() {
        text = nil
        loadError = nil
        // Ausserhalb der Knowledgebase gilt: die Datei, nicht ihre Darstellung. Ein Link ins Repo
        // führt zum Quelltext — auch bei `.md`, denn dort ist die Datei der Gegenstand.
        showSource = isOutside
        guard node.kind != .binary else { return }

        let size = (try? FileManager.default.attributesOfItem(atPath: node.path))?[.size] as? Int
        if let size, size > Self.maxBytes {
            let readable = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            loadError = "Datei ist \(readable) gross — zu gross für die Vorschau."
            return
        }

        do {
            let data = try Data(contentsOf: url)
            // Null-Byte = binär, egal was die Endung sagt. Ohne diese Prüfung käme über einen Link
            // ins Repo irgendwann eine `.dat` als Zeichensalat in den Editor.
            if data.prefix(8192).contains(0) {
                loadError = "Binärdatei — im Finder öffnen"
                return
            }
            // Latin-1-Altbestand ist kein Fehler, den der Leser beheben muss.
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            if text == nil { loadError = "Datei ist in keiner bekannten Kodierung lesbar" }
        } catch {
            loadError = "Datei kann nicht gelesen werden: \(error.localizedDescription)"
        }
    }
}

/// Eine lokale Datei in einer echten Web-Ansicht — für die generierten HTML-Artefakte.
///
/// `loadFileURL(_:allowingReadAccessTo:)` mit dem KB-Ordner als Wurzel: nur so findet ein Artefakt
/// seine Nachbardateien (Stylesheet, Bilder, verlinkte Seiten). Klicks auf **externe** Links gehen
/// in den Browser, Klicks auf Dateien im KB-Ordner bleiben in der Ansicht — sonst wäre eine
/// verlinkte Artefakt-Seite nur über den Finder erreichbar.
struct FileWebView: NSViewRepresentable {
    let url: URL
    let readAccessRoot: URL

    func makeCoordinator() -> Coordinator { Coordinator(readAccessRoot: readAccessRoot) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.lastURL = url
        webView.loadFileURL(url, allowingReadAccessTo: readAccessRoot)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastURL: URL?
        private let readAccessRoot: URL

        init(readAccessRoot: URL) {
            self.readAccessRoot = readAccessRoot
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let insideKB = target.isFileURL
                && target.standardizedFileURL.path.hasPrefix(readAccessRoot.standardizedFileURL.path)
            if insideKB {
                decisionHandler(.allow)
            } else {
                StatusLinkOpener.open(target)
                decisionHandler(.cancel)
            }
        }
    }
}
