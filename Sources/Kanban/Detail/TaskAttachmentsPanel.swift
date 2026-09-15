import AppKit
import Quartz
import SwiftUI
import KanbanCore

/// Der Task-Ordner des Tickets: Dateibaum links, Vorschau rechts (an der Stelle, an der sonst der
/// gewählte Task-Tab steht).
///
/// Das Task-File zeigt nur, was es selbst einbettet — ein Video wird dort zu einem Link, eine
/// `.xlsx` taucht gar nicht auf, und `avatars/` sieht niemand. Der Ordner ist die einzige Stelle,
/// an der **alles** steht, was zu dem Ticket geholt wurde; siehe `TaskAttachments`.
struct TaskAttachmentsTree: View {
    @Bindable var model: AppModel
    @Binding var expanded: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: $model.taskAttachmentSelection) {
                KBRows(nodes: model.taskAttachments, expanded: $expanded, icon: Self.icon)
            }
            .listStyle(.sidebar)
        }
        .frame(maxHeight: .infinity)
        .onAppear { expandFolders() }
        .onChange(of: model.taskAttachments) { _, _ in expandFolders() }
    }

    /// Ein Task-Ordner hat eine Handvoll Dateien und höchstens die Ebene `avatars/` — hier wird
    /// deshalb **alles** aufgeklappt (wie im Commit-Dialog), nicht nur der Weg zur Auswahl wie in
    /// der Knowledgebase mit ihren 365 Dateien.
    private func expandFolders() {
        expanded.formUnion(folderIDs(model.taskAttachments))
    }

    private func folderIDs(_ nodes: [KBNode]) -> Set<String> {
        nodes.reduce(into: Set<String>()) { ids, node in
            guard node.isDirectory else { return }
            ids.insert(node.id)
            ids.formUnion(folderIDs(node.children))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip").font(.app(.caption))
            Text("Dateien").font(.app(.caption, weight: .medium))
            Text("\(TaskAttachments.fileCount(model.taskAttachments))")
                .font(.app(.caption)).foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            Button {
                model.reloadTaskAttachments()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Task-Ordner neu einlesen")

            if let folder = model.taskAttachments.first.map(folderOf) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Task-Ordner im Finder öffnen: \(folder)")
            }
        }
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    /// Der Ordner, in dem der Baum wurzelt — bei einem einzigen Task-Ordner steht dessen Inhalt auf
    /// oberster Ebene, also ist es der Elternordner des ersten Eintrags.
    private func folderOf(_ node: KBNode) -> String {
        node.isDirectory && model.taskAttachments.count > 1
            ? node.path
            : (node.path as NSString).deletingLastPathComponent
    }

    /// Symbole für einen Task-Ordner: er besteht aus Anhängen, nicht aus Text. Ein Bild als
    /// generisches Blatt zu zeigen, wäre die Zeile, die man am häufigsten sieht — 231 von 382
    /// Dateien auf dieser Maschine sind PNGs.
    static func icon(_ node: KBNode) -> String {
        switch (node.path as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "svg": "photo"
        case "mp4", "mov", "avi", "mkv", "webm", "m4v": "film"
        case "pdf": "doc.richtext"
        case "xlsx", "xls", "csv", "numbers": "tablecells"
        case "docx", "doc", "pages": "doc.text.image"
        case "msg", "eml": "envelope"
        case "zip", "gz", "tgz", "7z", "rar": "shippingbox"
        case "json": node.name.lowercased() == "comments.json" ? "bubble.left.and.bubble.right" : "curlybraces"
        default: KBRows.kbIcon(node)
        }
    }
}

/// Eine Datei aus dem Task-Ordner. Kopfzeile mit Name und Grösse, darunter der Inhalt **nach
/// Dateiart** — dieselbe Aufteilung wie in der Knowledgebase, nur mit einem zusätzlichen Fall, der
/// hier den Normalfall trägt: Bilder, Videos, PDFs und Tabellen gehen an **Quick Look**.
///
/// Ohne den wäre die Vorschau für 70 % der Dateien der Satz „kein Textformat" — genau die Dateien,
/// derentwegen man den Ordner aufmacht.
struct TaskAttachmentPreview: View {
    let node: KBNode
    /// Bezugspunkt relativer Pfade in den Dateien: das **Tasks-Verzeichnis**, nicht der Ticket-
    /// Ordner. `comments.json` verweist auf seine Profilbilder als `<KEY>/avatars/…`.
    let baseDirectory: URL?
    /// Zurück zu den Task-Tabs — die Vorschau steht an deren Platz.
    let onClose: () -> Void

    /// Wie in der Knowledgebase: darüber wird nicht gerendert, sondern die Grösse genannt. Gilt nur
    /// für den Text-Weg — Quick Look bringt sein eigenes Nachladen mit.
    private static let maxBytes = 4 * 1024 * 1024

    @State private var text: String?
    @State private var loadError: String?
    @State private var showSource = false
    /// Die gelesene Outlook-Nachricht, wenn die Datei eine `.msg` ist.
    @State private var message: OutlookMessage?

    private var url: URL { URL(fileURLWithPath: node.path) }

    /// Eine Outlook-Nachricht wird gelesen, nicht an Quick Look gereicht: das hängt an `.msg`
    /// (zwei Minuten ohne Ergebnis gemessen), und die Endung fällt ausserdem nicht unter
    /// `KBFileKind.binary` — ohne diesen Weg landete sie im Text-Pfad und meldete „Binärdatei".
    private var isMessage: Bool { OutlookMessageReader.isMessageFile(node.path) }

    /// Eine Kommentar-Diskussion wird als solche gezeigt, nicht als JSON — dieselbe Entscheidung wie
    /// im Task-File (`TaskFile.embedJsonLinks`). Eine beliebige `.json` zu deuten, weil sie so
    /// heisst, ginge daneben, deshalb entscheidet `CommentThread.parse` und nicht der Dateiname.
    private var comments: [TaskComment]? {
        guard node.kind == .text, (node.path as NSString).pathExtension.lowercased() == "json",
              let text else { return nil }
        return CommentThread.parse(text)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        // `id:` statt `onAppear`: bei einem Wechsel der Auswahl bleibt der View stehen und würde
        // sonst den alten Inhalt behalten (wie `KBFileView`).
        .task(id: node.path) { load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: TaskAttachmentsTree.icon(node)).font(.app(.caption))
            Text(node.name)
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(node.path)
            if let size = fileSize {
                Text(size).font(.app(.caption)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if comments != nil || message?.text != nil || node.kind == .markdown || node.kind == .html {
                Button {
                    showSource.toggle()
                } label: {
                    Image(systemName: showSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.plain)
                .help(showSource ? "Gerendert anzeigen" : "Quelltext anzeigen")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Im Finder zeigen")
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Vorschau schliessen — zurück zum Task-Tab")
        }
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var fileSize: String? {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: node.path))?[.size] as? Int
        else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @ViewBuilder
    private var content: some View {
        if isMessage {
            if let message {
                // Der Quelltext-Schalter zeigt hier den **Text-Körper** der Mail: die Fassung ohne
                // Outlooks HTML, oft die lesbarere — und die einzige, die eine Mail immer hat.
                if showSource, let raw = message.text {
                    sourceEditor(raw)
                } else {
                    MarkdownWebView(markdown: message.markdown, baseURL: url)
                }
            } else {
                placeholder
            }
        } else if node.kind == .binary {
            // Bilder, Videos, PDFs, Office-Dateien — alles, was macOS selbst darstellen kann.
            QuickLookView(url: url)
        } else if let text, showSource {
            sourceEditor(text)
        } else if let comments {
            MarkdownWebView(markdown: CommentThread.markdown(comments, directory: baseDirectory),
                            baseURL: url)
        } else {
            switch node.kind {
            case .html:
                // Datei-URL statt HTML-String: eine exportierte Seite lädt ihr CSS und ihre Bilder
                // relativ und braucht dafür echten Dateizugriff.
                FileWebView(url: url,
                            readAccessRoot: baseDirectory ?? url.deletingLastPathComponent())
            case .markdown:
                if let text {
                    MarkdownWebView(
                        markdown: TaskFileLoader.rewriteImagePaths(
                            text, directory: url.deletingLastPathComponent()),
                        baseURL: url)
                } else { placeholder }
            case .text, .binary:
                if let text { sourceEditor(text) } else { placeholder }
            }
        }
    }

    /// Derselbe Editor wie im Commit-Dialog und in der Knowledgebase. **Nicht** schreibbar: hier
    /// wird gelesen, und ein Feld, das Tippen annimmt und die Änderung wegwirft, wäre schlimmer als
    /// ein sichtbar gesperrtes.
    private func sourceEditor(_ text: String) -> some View {
        CodeEditorView(text: .constant(text),
                       highlight: DiffHighlight(addedLines: [], deletionMarkers: []),
                       language: CodeLanguage.detect(path: node.path),
                       reloadToken: node.path.hashValue,
                       isEditable: false)
    }

    @ViewBuilder
    private var placeholder: some View {
        if let loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24)).foregroundStyle(.secondary)
                Text(loadError)
                    .font(.app(.callout)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() {
        text = nil
        loadError = nil
        showSource = false
        message = nil
        if isMessage {
            message = OutlookMessageReader.read(url)
            if message == nil {
                loadError = "Keine lesbare Outlook-Nachricht."
            }
            return
        }
        guard node.kind != .binary else { return }

        let size = (try? FileManager.default.attributesOfItem(atPath: node.path))?[.size] as? Int
        if let size, size > Self.maxBytes {
            let readable = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            loadError = "Datei ist \(readable) gross — zu gross für die Vorschau."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // Null-Byte = binär, egal was die Endung sagt (dieselbe Prüfung wie in der KB).
            if data.prefix(8192).contains(0) {
                loadError = "Binärdatei — im Finder öffnen"
                return
            }
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            if text == nil { loadError = "Datei ist in keiner bekannten Kodierung lesbar" }
        } catch {
            loadError = "Datei kann nicht gelesen werden: \(error.localizedDescription)"
        }
    }
}

/// macOS' eigene Vorschau (`QLPreviewView`) für alles, was kein Text ist.
///
/// Bewusst Quick Look statt eigener Darstellungen je Format: ein Task-Ordner enthält Bilder, Videos,
/// PDFs, Tabellen und exportierte Mails, und für jedes davon eine eigene Ansicht zu bauen hiesse,
/// nachzubauen, was das System schon kann — inklusive Abspielen und Blättern.
struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        // `style: .normal` zeigt nur den Inhalt; `.compact` blendet zusätzlich eine Titelleiste ein,
        // und die Kopfzeile steht hier schon darüber.
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = false   // ein Video, das beim Anklicken der Datei losläuft, will niemand
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard (view.previewItem as? URL) != url else { return }
        view.previewItem = url as QLPreviewItem
        view.refreshPreviewItem()
    }

    /// Quick Look hält bis zum `close()` Ressourcen (u. a. laufende Medien) fest.
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
