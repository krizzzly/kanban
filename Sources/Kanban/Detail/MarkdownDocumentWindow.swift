import AppKit
import SwiftUI
import KanbanCore

/// Eine Markdown-Datei in einem eigenen Fenster — der Weg, über den Kanban aus dem Finder heraus
/// als Betrachter für `.md` dient („Öffnen mit › Kanban", `CFBundleDocumentTypes` in der
/// `Info.plist`).
///
/// Bewusst ein **eigenes** Fenster und kein Tab im Board: die Datei gehört zu keinem Ticket, und
/// das Board hat für sie keinen Platz, an dem sie nicht etwas anderes verdrängen würde.
@MainActor
final class MarkdownDocumentWindow {
    static let shared = MarkdownDocumentWindow()

    /// Offene Fenster nach **aufgelöstem** Pfad. Dieselbe Datei zweimal zu öffnen holt das
    /// vorhandene Fenster nach vorn, statt ein zweites danebenzustellen — genau das tut der Finder
    /// beim wiederholten „Öffnen mit" ständig.
    private var windows: [String: NSWindow] = [:]
    /// Die Beobachter-Tokens dazu. Ein block-basierter `NotificationCenter`-Beobachter bleibt
    /// registriert, bis man ihn abmeldet — sonst sammelt sich je geöffneter Datei einer an.
    private var beobachter: [String: NSObjectProtocol] = [:]

    private init() {}

    /// Öffnet (oder aktiviert) das Fenster für `url`. Verzeichnisse und Unlesbares werden
    /// abgewiesen, statt ein leeres Fenster zu zeigen.
    func show(url: URL) {
        let pfad = url.resolvingSymlinksInPath().standardizedFileURL.path
        if let vorhanden = windows[pfad] {
            vorhanden.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var istOrdner: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pfad, isDirectory: &istOrdner),
              !istOrdner.boolValue else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        // Das Proxy-Symbol in der Titelleiste: damit lässt sich die Datei aus dem Fenster heraus
        // ziehen und ⌘-Klick auf den Titel zeigt ihren Ort — beides erwartet man von einem Fenster,
        // das eine Datei zeigt.
        window.representedURL = url
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MarkdownDocumentView(url: url))
        window.minSize = NSSize(width: 480, height: 320)
        // Nicht stapeln: mehrere geöffnete Dateien sollen nebeneinander liegen, nicht deckungsgleich.
        if windows.isEmpty { window.center() } else { window.cascadeTopLeft(from: NSPoint(x: 40, y: 40)) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        beobachter[pfad] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.aufraeumen(pfad) }
            }
        windows[pfad] = window
    }

    /// Fenster vergessen und den Beobachter abmelden — danach öffnet dieselbe Datei wieder ein
    /// frisches Fenster, statt auf ein geschlossenes zu zeigen.
    private func aufraeumen(_ pfad: String) {
        if let token = beobachter.removeValue(forKey: pfad) {
            NotificationCenter.default.removeObserver(token)
        }
        windows[pfad] = nil
    }
}

/// Der Inhalt des Dokumentfensters: gerendert wie ein Task-File, auf Knopfdruck der Quelltext.
///
/// Es ist derselbe Weg wie in der Knowledgebase (`MarkdownWebView` bzw. `CodeEditorView`), aus
/// demselben Grund: ein Markdown-Betrachter, der anders aussieht als die gerenderten Task-Files
/// derselben App, wäre eine zweite Darstellung für dieselbe Sache.
struct MarkdownDocumentView: View {
    let url: URL

    @State private var markdown = ""
    @State private var fehler: String?
    @State private var zeigeQuelltext = false
    @State private var suche = MarkdownFind()
    @FocusState private var sucheFokussiert: Bool
    /// Steigt bei jedem Neuladen — der Quelltext-Editor liest nur dann neu ein.
    @State private var neuladeToken = 0

    /// Grenze fürs Einlesen, wie in der Knowledgebase: eine mehrere Megabyte grosse Datei durch
    /// WKWebView zu schicken hängt das Fenster auf.
    private static let maxBytes = 4 * 1024 * 1024

    var body: some View {
        VStack(spacing: 0) {
            kopf
            Divider()
            inhalt
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: suche.query) { suche.eingabeGeaendert(markdown) }
        .onChange(of: markdown) { suche.inhaltGeaendert(markdown) }
        // ⌘F wie überall auf dem System — „immer durchsuchbar" heisst auch: ohne Mausweg dorthin.
        .onKeyPress(keys: ["f"], phases: .down) { druck in
            guard druck.modifiers.contains(.command) else { return .ignored }
            zeigeQuelltext = false
            sucheFokussiert = true
            return .handled
        }
        // Erst laden, dann die Datei im Auge behalten: sie ändert sich unter dem Fenster (beim
        // Task-File ist das der Normalfall, und für eine Datei, die jemand nebenher offen hat,
        // gilt dasselbe). Der Watcher wird beim Schliessen abgeräumt — ohne das bliebe eine
        // DispatchSource je geöffnetem Fenster stehen.
        .task(id: url) {
            laden()
            let watcher = TaskFileWatcher(path: url.path)
            await withTaskCancellationHandler {
                for await _ in watcher.events {
                    try? await Task.sleep(nanoseconds: 150_000_000)   // Entprellen, wie beim Task-File
                    guard !Task.isCancelled else { break }
                    laden()
                }
            } onCancel: {
                watcher.cancel()
            }
        }
    }

    private var kopf: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1).truncationMode(.head)
            // Suchen gilt der gerenderten Ansicht — im Quelltext sucht der Code-Editor selbst.
            if !zeigeQuelltext {
                MarkdownFindBar(query: $suche.query, treffer: suche.treffer, aktuell: suche.index,
                                zaehlbar: suche.zaehlbar, weiter: { suche.weiter($0) },
                                fokussiert: $sucheFokussiert)
            }
            Spacer()
            Button {
                zeigeQuelltext.toggle()
            } label: {
                Label(zeigeQuelltext ? "Gerendert" : "Quelltext",
                      systemImage: zeigeQuelltext ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .help(zeigeQuelltext ? "Gerendert anzeigen" : "Markdown-Quelltext anzeigen")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Im Finder zeigen")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private var inhalt: some View {
        if let fehler {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28)).foregroundStyle(.tertiary)
                Text(fehler)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if zeigeQuelltext {
            CodeEditorView(text: .constant(markdown),
                           highlight: DiffHighlight(addedLines: [], deletionMarkers: []),
                           language: .markdown, reloadToken: neuladeToken, isEditable: false)
                .environment(\.colorScheme, .dark)
        } else {
            // Bilder als data-URI einbetten, wie beim Task-File: `loadHTMLString` gibt dem Dokument
            // keinen Lesezugriff aufs Dateisystem, ein `<img src="bild.png">` bliebe also leer.
            MarkdownWebView(
                markdown: TaskFileLoader.rewriteImagePaths(markdown, directory: url.deletingLastPathComponent()),
                baseURL: url.deletingLastPathComponent(),
                search: suche.suche)
        }
    }

    private func laden() {
        let werte = FileManager.default.attributesOfItemSafe(atPath: url.path)
        if let groesse = werte?[.size] as? Int, groesse > Self.maxBytes {
            fehler = "Die Datei ist \(ByteCountFormatter.string(fromByteCount: Int64(groesse), countStyle: .file)) gross — "
                   + "zu viel für die Vorschau."
            markdown = ""
            return
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            fehler = "\(url.lastPathComponent) lässt sich nicht als Text lesen."
            markdown = ""
            return
        }
        fehler = nil
        markdown = text
        neuladeToken += 1
    }
}

private extension FileManager {
    /// Attribute ohne `throws` — eine Datei, die zwischen Watcher-Tick und Lesen verschwindet, ist
    /// hier kein Fehlerfall, sondern nur „keine Grösse bekannt".
    func attributesOfItemSafe(atPath path: String) -> [FileAttributeKey: Any]? {
        try? attributesOfItem(atPath: path)
    }
}
