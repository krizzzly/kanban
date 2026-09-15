import SwiftUI
import KanbanCore

/// Editor für das Jira-Feld „Lösung" des offenen Tickets.
///
/// Vorbelegt wird mit dem, was in Jira steht; ist das Feld leer, mit `## JIRA Lösungsfeld` →
/// `### Für Kunde` aus dem Task-File (`SolutionDraft`) — dort schreibt `solve-task` genau den Text
/// hin, der in Jira gehört. Geschrieben wird **Markdown**, umgewandelt nach ADF (`MarkdownToADF`).
///
/// Bearbeitet wird **formatiert** (`RichTextEditor`): Überschriften, Listen und Marks stehen so da,
/// wie sie in Jira ankommen, statt als `**Sternchen**`. Markdown bleibt darunter die gespeicherte
/// Wahrheit — die Umschaltung „Markdown" zeigt (und bearbeitet) sie direkt, damit nichts hinter dem
/// Editor verschwindet und ein Konverter-Fehler von Hand korrigierbar bleibt.
struct SolutionSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case formatted = "Formatiert"
        case markdown = "Markdown"
        var id: String { rawValue }
    }

    /// Markdown — das, was gespeichert wird, in beiden Ansichten.
    @State private var text = ""
    @State private var mode: Mode = .formatted
    /// Hochzählen lädt den formatierten Editor neu aus `text` (Öffnen, Zurückschalten).
    @State private var reloadToken = 0
    @State private var loaded = false
    /// Woher die Vorbelegung kam — beim Öffnen **einmal** festgehalten. Frisch aus dem Model gelesen
    /// wäre es ein Task-File-Lesevorgang pro Tastendruck, weil der Header mit jedem Render neu rechnet.
    @State private var draftSource: SolutionDraft.Source?
    @State private var editor = RichTextEditorController()
    @State private var linkPopover = false
    @State private var linkURL = ""
    @FocusState private var markdownFocused: Bool

    private var ticketKey: String { model.selectedTicketKey ?? "" }
    private var wasEmpty: Bool { model.solution?.isEmpty ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            modeBar
            editorArea

            if let error = model.solutionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption)).foregroundStyle(.orange).lineLimit(3)
            }

            footer
        }
        .padding(16)
        .frame(width: 780, height: 680)
        .onAppear {
            guard !loaded else { return }
            draftSource = model.taskFileSolutionSuggestion?.source
            text = model.solutionDraft
            loaded = true
            // `onAppear` läuft **nach** dem ersten Aufbau der WebView, die also mit leerem Text
            // geladen wurde. Ohne dieses Hochzählen bliebe der Editor leer, obwohl der Entwurf steht.
            reloadToken += 1
        }
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Lösung").font(.app(.headline))
                Text(ticketKey).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                if let column = model.solutionMissingColumn {
                    Label("in \(column.rawValue), Feld leer", systemImage: "exclamationmark.bubble.fill")
                        .font(.app(.caption)).foregroundStyle(.red)
                }
            }
            Text(source)
                .font(.app(.callout)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Woher der Vorschlag kommt — sonst rätselt man, warum da schon Text steht. Bei einem Task-File
    /// ohne `### Für Kunde` wird das gesagt: dann steht hier der ganze Abschnitt, inklusive der
    /// Test-Ingenieur-Teile, die im Jira-Feld nichts zu suchen haben.
    private var source: String {
        if !wasEmpty { return "Aktueller Inhalt des Jira-Felds. Formatierung wird als ADF geschrieben." }
        switch draftSource {
        case .customerPart:
            return "Vorbelegt aus „## JIRA Lösungsfeld“ → „### Für Kunde“ des Task-Files — bitte gegenlesen."
        case .wholeSection:
            return "Vorbelegt aus „## JIRA Lösungsfeld“ des Task-Files — es hat keinen Unterabschnitt "
                 + "„### Für Kunde“, deshalb steht hier der ganze Abschnitt. Bitte kürzen und gegenlesen."
        case nil:
            return "Das Feld ist leer und das Task-File hat keinen Abschnitt „## JIRA Lösungsfeld“."
        }
    }

    // MARK: - Umschalter + Toolbar

    private var modeBar: some View {
        HStack(spacing: 10) {
            Picker("Ansicht", selection: Binding(get: { mode }, set: { switchMode(to: $0) })) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            if mode == .formatted {
                Divider().frame(height: 16)
                toolbar
            }
            Spacer()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            button("bold", "Fett (⌘B)", .bold)
            button("italic", "Kursiv (⌘I)", .italic)
            button("strikethrough", "Durchgestrichen", .strike)
            button("chevron.left.forwardslash.chevron.right", "Code im Text", .inlineCode)
            separator
            textButton("H2", "Überschrift 2", .heading2)
            textButton("H3", "Überschrift 3", .heading3)
            button("text.alignleft", "Normaler Absatz", .paragraph)
            separator
            button("list.bullet", "Punkteliste", .bulletList)
            button("list.number", "Nummerierte Liste", .orderedList)
            button("increase.indent", "Tiefer einrücken (Tab)", .indent)
            button("decrease.indent", "Ausrücken (⇧Tab)", .outdent)
            separator
            button("text.quote", "Zitat", .quote)
            button("curlybraces", "Codeblock", .codeBlock)
            linkButton
            separator
            button("arrow.uturn.backward", "Widerrufen (⌘Z)", .undo)
            button("arrow.uturn.forward", "Wiederholen (⇧⌘Z)", .redo)
        }
    }

    private var separator: some View {
        Divider().frame(height: 14).padding(.horizontal, 3)
    }

    private func button(_ symbol: String, _ help: String, _ command: RichTextCommand) -> some View {
        Button { editor.apply(command) } label: {
            Image(systemName: symbol).frame(width: 20, height: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    /// „H2"/„H3" als Text: es gibt kein SF-Symbol, das Überschriftenebenen unterscheidet, und ein
    /// geratenes Symbol für beide wäre nicht auseinanderzuhalten.
    private func textButton(_ label: String, _ help: String, _ command: RichTextCommand) -> some View {
        Button { editor.apply(command) } label: {
            Text(label).font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var linkButton: some View {
        Button { linkURL = ""; linkPopover = true } label: {
            Image(systemName: "link").frame(width: 20, height: 18)
        }
        .buttonStyle(.borderless)
        .help("Auswahl zu einem Link machen")
        .popover(isPresented: $linkPopover) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Link-Ziel").font(.app(.callout))
                TextField("https://…", text: $linkURL)
                    .textFieldStyle(.roundedBorder).frame(width: 260)
                    .onSubmit(applyLink)
                HStack {
                    Spacer()
                    Button("Einfügen", action: applyLink)
                        .disabled(linkURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
        }
    }

    private func applyLink() {
        let url = linkURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        editor.apply(.link(url))
        linkPopover = false
    }

    // MARK: - Fläche

    private var editorArea: some View {
        Group {
            switch mode {
            case .formatted:
                RichTextEditor(markdown: text,
                               reloadToken: reloadToken,
                               placeholder: "Was wurde gemacht?",
                               onChange: { text = $0 },
                               controller: editor)
            case .markdown:
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($markdownFocused)
                    .padding(6)
                    .onAppear { markdownFocused = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    /// Beim Wechsel **aus** dem formatierten Editor den Stand abholen, bevor die Ansicht wechselt —
    /// die letzten getippten Zeichen hängen sonst noch im Entprell-Timer und wären weg.
    private func switchMode(to newMode: Mode) {
        guard newMode != mode else { return }
        if mode == .formatted {
            Task {
                if let markdown = await editor.currentMarkdown() { text = markdown }
                mode = newMode
            }
        } else {
            reloadToken += 1        // formatierte Ansicht aus dem (ggf. handgeschriebenen) Markdown
            mode = newMode
        }
    }

    // MARK: - Fuss

    private var footer: some View {
        HStack {
            if model.solutionSaving { ProgressView().controlSize(.small) }
            Text(mode == .formatted
                 ? "Formatierung wird als Markdown gespeichert und als ADF nach Jira geschrieben."
                 : "Markdown — dieselbe Quelle, die der formatierte Editor anzeigt.")
                .font(.app(.caption)).foregroundStyle(.tertiary)
            Spacer()
            Button("Abbrechen") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(wasEmpty ? "In Jira schreiben" : "Feld ersetzen", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(model.solutionSaving || isEmptyText)
        }
    }

    private var isEmptyText: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Erst den Editor-Stand holen, dann schreiben. Ohne das Abholen fehlt alles, was in den letzten
    /// 400 ms getippt wurde — der häufigste Ablauf ist ja „letztes Wort tippen, dann Speichern".
    private func save() {
        Task {
            if mode == .formatted, let markdown = await editor.currentMarkdown() {
                text = markdown
            }
            guard !isEmptyText else { return }
            await model.saveSolution(text)
        }
    }
}
