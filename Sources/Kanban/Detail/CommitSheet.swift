import SwiftUI
import KanbanCore

/// Commit dialog for a finished (🟢 Abgeschlossen) task: the message `solve-task` proposed under
/// `## Lösung`, still editable, plus the amend path — amending keeps HEAD's message, so no text is
/// needed there, but the push must then be forced (always `--force-with-lease`).
///
/// Layout follows GitLab: changed files on the left, the selected file's diff on the right, additions
/// on light green and deletions on light red with old/new line-number gutters.
struct CommitSheet: View {
    @Bindable var model: AppModel
    /// Called when the dialog should go away — the owning window closes itself (see `CommitWindow`).
    let onClose: () -> Void

    /// Die drei Reiter. „Diff" committet nichts — er zeigt, was der Branch gegenüber seiner
    /// Abzweig-Basis geändert hat, und ist damit das, was nach dem Commit noch übrig bleibt: die
    /// Arbeitsverzeichnis-Liste ist dann leer, der Branch aber nicht.
    private enum Mode: Hashable { case commit, amend, diff }

    @State private var message = ""
    @State private var mode: Mode = .commit
    @State private var push = true
    @State private var loaded = false

    private var amend: Bool { mode == .amend }
    /// Dateiliste flach oder als Ordnerbaum.
    @AppStorage("commitFileTreeMode") private var treeMode = false

    private var state: GitWorkingState? { model.commitState }
    private var canSubmit: Bool {
        guard mode != .diff, !model.commitBusy, let state else { return false }
        if state.isClean && !amend { return false }              // nothing to commit
        // Alles abgewählt heisst: es bleibt nichts zu committen. Beim Amend schon — dort wird HEAD
        // ohnehin neu geschrieben und gepusht, auch ohne neue Änderung.
        if model.commitIncludedCount == 0 && !amend { return false }
        return amend || !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HSplitView {
                leftPane.frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
                diffPane.frame(minWidth: 520)
            }
            Divider()
            footer
        }
        .frame(minWidth: 1100, minHeight: 700)
        .task {
            guard !loaded else { return }
            loaded = true
            await model.prepareCommitDialog()
            message = model.suggestedCommitMessage
        }
        .onChange(of: mode) { _, new in
            Task { await model.setCommitDiffSource(new == .diff ? .branch : .working) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal").foregroundStyle(.secondary)
            Text("Commit").font(.app(.headline))
            if let key = model.selectedTicketKey {
                Text(key).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }
            Divider().frame(height: 14)
            Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(state?.branch ?? "—").font(.system(size: 12, weight: .medium, design: .monospaced))
            if state?.hasUpstream == false {
                Text("kein Upstream").font(.app(.caption)).foregroundStyle(.orange)
            }
            Spacer()
            // Kein eigenes (X) mehr — das Fenster hat einen echten Schliessen-Knopf.
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Left: message + file list

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            modePicker
            switch mode {
            case .commit: messageEditor
            case .amend:  amendInfo
            case .diff:   branchInfo
            }
            fileList
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text("Neuer Commit").tag(Mode.commit)
            Text("Amend").tag(Mode.amend)
            Text("Diff").tag(Mode.diff)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Commit-Message").font(.app(.subheadline, weight: .medium)).foregroundStyle(.secondary)
            TextEditor(text: $message)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 84)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            Text("Vorschlag aus dem Task-File (`## Lösung`) — editierbar.")
                .font(.app(.subheadline)).foregroundStyle(.secondary)
        }
    }

    private var amendInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Wird in HEAD gefaltet").font(.app(.subheadline, weight: .medium)).foregroundStyle(.secondary)
            Text(state?.headSubject ?? "—")
                .font(.system(size: 13, design: .monospaced)).lineLimit(3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            Text("Die bestehende Message bleibt (`--amend --no-edit`) — keine Eingabe nötig.")
                .font(.app(.subheadline)).foregroundStyle(.secondary)
        }
    }

    /// Wogegen verglichen wird. Die Basis ist **abgeleitet**, nicht konfiguriert (`BranchParent`) —
    /// also wird sie genannt, samt der Zahl eigener Commits: nur so ist zu sehen, ob der Vergleich
    /// den Branch meint, den man im Kopf hat.
    private var branchInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Verglichen mit").font(.app(.subheadline, weight: .medium)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if model.branchDiffLoading { ProgressView().controlSize(.small) }
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(model.branchDiff?.baseRef ?? "—")
                    .font(.system(size: 13, design: .monospaced))
                if let commits = model.branchDiff?.commits, commits > 0 {
                    Text("· \(commits) Commit\(commits == 1 ? "" : "s")")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            if let error = model.branchDiffError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption)).foregroundStyle(.orange)
            } else {
                // Ab dem Merge-Base, nicht ab der Spitze der Basis — sonst stünden fremde Commits
                // als Rücknahmen im eigenen Diff. Derselbe Vergleich, den der MR zeigt.
                Text("Ab dem gemeinsamen Vorfahren (`\(model.branchDiff?.baseRef ?? "…")...HEAD`) — "
                     + "was der Branch geändert hat, wie im Merge Request.")
                    .font(.app(.subheadline)).foregroundStyle(.secondary)
            }
            // Committet ist nicht alles: was noch im Arbeitsverzeichnis liegt, steht hier nicht
            // drin. Das schweigend wegzulassen wäre genau die Lücke, die diesen Reiter nötig macht.
            if let pending = state?.changedFiles.count, pending > 0 {
                Text("Dazu \(pending) ungespeicherte Änderung\(pending == 1 ? "" : "en") — "
                     + "die stehen unter „Neuer Commit“.")
                    .font(.app(.caption)).foregroundStyle(.orange)
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(fileListTitle)
                    .font(.app(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $treeMode) {
                    Image(systemName: "list.bullet").tag(false)
                    Image(systemName: "folder").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("Flache Liste oder Ordnerstruktur")
            }
            if !files.isEmpty {
                if treeMode {
                    FileTreeView(files: files, selection: fileSelection(in: files),
                                 inclusion: inclusionBinding)
                        .frame(minHeight: 200)
                } else {
                    List(files, selection: fileSelection(in: files)) { file in
                        ChangedFileRow(file: file, included: inclusionBinding?(file.path))
                            .tag(file.path)
                    }
                    .listStyle(.plain)   // keine Zebrastreifen, keine Phantom-Zeilen unter der Liste
                    .frame(minHeight: 200)
                }
            } else {
                Text(emptyListMessage)
                    .font(.app(.callout)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Die Liste des aktiven Reiters — Arbeitsverzeichnis oder Branch.
    private var files: [GitChangedFile] { model.commitFiles }

    /// Der Haken je Zeile — nur dort, wo auch wirklich committet wird. Im Reiter „Diff" wird
    /// gelesen; ein Kästchen ohne Wirkung wäre schlimmer als keins.
    private var inclusionBinding: ((String) -> Binding<Bool>)? {
        guard mode != .diff else { return nil }
        return { path in
            Binding(get: { model.isCommitIncluded(path) },
                    set: { model.setCommitInclusion($0, path: path) })
        }
    }

    /// Sagt die Abwahl mit, sobald es eine gibt — sonst übersieht man sie und wundert sich über
    /// einen halben Commit.
    private var fileListTitle: String {
        guard mode != .diff else { return "Geänderte Dateien (\(files.count))" }
        let excluded = files.count - model.commitIncludedCount
        return excluded > 0
            ? "Geänderte Dateien (\(model.commitIncludedCount) von \(files.count) — \(excluded) abgewählt)"
            : "Geänderte Dateien (\(files.count))"
    }

    private var emptyListMessage: String {
        switch mode {
        case .diff:
            return model.branchDiffLoading ? "Wird gelesen …"
                 : (model.branchDiffError == nil
                    ? "Der Branch unterscheidet sich nicht von seiner Basis."
                    : "Kein Vergleich möglich.")
        case .amend:  return "Nichts Neues — HEAD wird nur neu gepusht."
        case .commit: return "Keine Änderungen — nichts zu committen."
        }
    }

    /// Auswahl-Binding, geteilt von Liste und Baum.
    private func fileSelection(in files: [GitChangedFile]) -> Binding<String?> {
        Binding(
            get: { model.commitSelectedFile?.path },
            set: { path in
                guard let file = files.first(where: { $0.path == path }) else { return }
                Task { await model.selectCommitFile(file) }
            })
    }



    // MARK: - Right: the diff

    private var diffPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(model.commitSelectedFile?.path ?? "Keine Datei gewählt")
                    .font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.head)
                    .textSelection(.enabled)
                // Der Editor gilt in **beiden** Reitern, auch im Branch-Diff: man liest, was der
                // Branch geändert hat, sieht dabei etwas und bessert es an Ort und Stelle nach.
                // Gespeichert landet es im Arbeitsverzeichnis und damit in „Neuer Commit"/„Amend".
                // Eine vom Branch **gelöschte** Datei bleibt aussen vor — dort gäbe es nichts zu
                // bearbeiten, und ein Speichern legte sie wieder an.
                if model.commitSelectedFile != nil, model.commitFileExists {
                    Picker("", selection: $model.commitEditorMode) {
                        Text("Diff").tag(false)
                        Text("Editor").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help(mode == .diff
                          ? "Im Editor geänderte Dateien stehen danach unter „Neuer Commit“/„Amend“"
                          : "Datei bearbeiten statt nur ansehen")
                }
                Spacer()
                if model.commitDiffLoading { ProgressView().controlSize(.small) }
                if model.commitEditorMode {
                    editorActions
                } else {
                    let added = model.commitDiff.filter { $0.kind == .addition }.count
                    let removed = model.commitDiff.filter { $0.kind == .deletion }.count
                    if added > 0 { Text("+\(added)").font(.app(.caption)).foregroundStyle(.green).monospacedDigit() }
                    if removed > 0 { Text("−\(removed)").font(.app(.caption)).foregroundStyle(.red).monospacedDigit() }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diffAsText, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Ganzes Diff dieser Datei kopieren")
                        .disabled(model.commitDiff.isEmpty)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))   // Kopfzeile bleibt hell
            Divider()
            codeArea
                .environment(\.colorScheme, .dark)   // nur die Code-Fläche ist dunkel
        }
    }

    /// Diff oder Editor — die dunkle Fläche unter der hellen Kopfzeile.
    @ViewBuilder
    private var codeArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.commitEditorMode {
                // Editor: der Datei-Inhalt mit demselben Diff-Muster (grün = neu, rot = hier wurde
                // gelöscht) — und native Text-Selektion, also echtes Copy-Paste über Zeilen hinweg.
                CodeEditorView(text: $model.commitFileText,
                               highlight: model.commitFileHighlight,
                               language: language,
                               reloadToken: model.commitEditorReloadToken)
                if let error = model.commitSaveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.caption)).foregroundStyle(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                } else if mode == .diff {
                    // Im Branch-Reiter ist nicht selbstverständlich, wohin eine Änderung geht: der
                    // Diff daneben zeigt Commits, das Gespeicherte ist erst mal nur Arbeitsstand.
                    Label("Gespeichertes steht danach unter „Neuer Commit“ / „Amend“ —"
                          + " das Branch-Diff daneben zeigt weiterhin die Commits.",
                          systemImage: "info.circle")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
            } else if model.commitDiff.isEmpty {
                Text(model.commitDiffLoading ? "Lade Diff…" : "Keine Änderungen in dieser Datei.")
                    .font(.app(.callout)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // GeometryReader statt `maxWidth: .infinity`: in einem ScrollView mit horizontaler
                // Achse ist die vorgeschlagene Breite unbegrenzt, „infinity" bleibt dort wirkungslos
                // und der Inhalt wurde weiter zentriert. Mit `minWidth/minHeight` auf die echte
                // Viewport-Grösse füllt der Inhalt die Fläche und sitzt oben links; längere Zeilen
                // dürfen darüber hinauswachsen und scrollen.
                GeometryReader { viewport in
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(model.commitDiff) { line in diffRow(line) }
                        }
                        .padding(.vertical, 4)
                        .frame(minWidth: viewport.size.width,
                               minHeight: viewport.size.height,
                               alignment: .topLeading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CodeTheme.background)
    }

    /// Speichern / Verwerfen für den Editor-Modus.
    private var editorActions: some View {
        HStack(spacing: 8) {
            if model.commitEditorDirty {
                Text("geändert").font(.app(.caption)).foregroundStyle(.orange)
                Button("Verwerfen") { Task { await model.revertCommitFile() } }
                    .buttonStyle(.borderless)
            }
            Button("Speichern") { Task { await model.saveCommitFile() } }
                .buttonStyle(.bordered)
                .disabled(!model.commitEditorDirty)
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    /// Das Diff als Text für die Zwischenablage — ohne Zeilennummern, damit es direkt einfügbar ist.
    private var diffAsText: String {
        model.commitDiff.map { line in
            switch line.kind {
            case .addition: return "+" + line.text
            case .deletion: return "-" + line.text
            case .hunk: return line.text
            default: return " " + line.text
            }
        }.joined(separator: "\n")
    }

    private func diffRow(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            gutter(line.oldNumber)
            gutter(line.newNumber)
            Text(prefix(line))
                .font(CodeTheme.font)
                .foregroundStyle(markerColor(line))
                .padding(.leading, 6)
            Text(highlightedText(line))
                .font(CodeTheme.font)
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)   // Zeile markieren + kopieren
            Spacer(minLength: 0)
        }
        // Zeile auf volle Breite ziehen, damit das Grün/Rot wie bei GitLab durchläuft statt am
        // Textende abzubrechen.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(line))
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(CodeTheme.gutterFont)
            .foregroundStyle(CodeTheme.gutter)
            .frame(width: 46, alignment: .trailing)
            .padding(.trailing, 4)
    }

    private func prefix(_ line: DiffLine) -> String {
        switch line.kind {
        case .addition: return "+ "
        case .deletion: return "− "
        case .hunk, .meta: return ""
        case .context: return "  "
        }
    }

    /// `+` grün, `−` rot — die Richtung bleibt so auch dann lesbar, wenn die Flächenfarbe
    /// (z.B. bei Farbfehlsichtigkeit oder auf einem blassen Display) schwer zu unterscheiden ist.
    private func markerColor(_ line: DiffLine) -> Color {
        switch line.kind {
        case .addition: return CodeTheme.additionMarker
        case .deletion: return CodeTheme.deletionMarker
        default: return CodeTheme.gutter
        }
    }

    /// Die aktuelle Sprache, aus dem Dateinamen abgeleitet.
    private var language: CodeLanguage {
        CodeLanguage.detect(path: model.commitSelectedFile?.path ?? "")
    }

    /// Syntax-gefärbte Zeile. Hunk-Köpfe bleiben ungefärbt — sie sind kein Code.
    private func highlightedText(_ line: DiffLine) -> AttributedString {
        guard line.kind != .hunk, line.kind != .meta else {
            var plain = AttributedString(line.text)
            plain.foregroundColor = CodeTheme.gutter
            return plain
        }
        return CodeTheme.highlighted(line.text, language: language)
    }

    /// GitLab-Muster auf dunklem Grund — kräftiger als auf Weiss, sonst verschluckt der Hintergrund
    /// die Tönung.
    private func background(_ line: DiffLine) -> Color {
        switch line.kind {
        case .addition: return CodeTheme.additionBackground
        case .deletion: return CodeTheme.deletionBackground
        case .hunk: return CodeTheme.hunkBackground
        case .meta, .context: return .clear
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.commitError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption)).foregroundStyle(.orange).lineLimit(3)
            }
            HStack(spacing: 10) {
                if mode == .diff {
                    // Ein Ansichts-Reiter. Kein Push-Schalter und kein Knopf, der etwas schreibt —
                    // ein grüner „Commit" neben einem reinen Diff wäre eine Einladung zum Vertippen.
                    Text("Nur Ansicht — hier wird nichts geschrieben.")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                } else {
                    Toggle(amend ? "Force-Push (mit Lease)" : "Pushen", isOn: $push)
                        .toggleStyle(.checkbox)
                    if amend && push {
                        Text("überschreibt die Remote-Historie")
                            .font(.app(.caption)).foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button(mode == .diff ? "Schliessen" : "Abbrechen") { onClose() }
                    .keyboardShortcut(.cancelAction)
                if mode != .diff {
                    Button {
                        Task { await model.performCommit(message: message, amend: amend, push: push) }
                    } label: {
                        HStack(spacing: 6) {
                            if model.commitBusy { ProgressView().controlSize(.small) }
                            Text(amend ? "Amend" : "Commit")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
