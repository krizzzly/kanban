import SwiftUI
import KanbanCore

/// The "Worktree" tab: controls the ticket's per-worktree docker stack via the `iwf worktree` /
/// `iwf stack` commands — a status badge (from `iwf stack ps`), a row of lifecycle commands, and the
/// live stdout of both the status query and the running command.
struct WorktreeStackView: View {
    @Bindable var model: AppModel
    @State private var confirmDestroy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.currentWorktree != nil {
                commandBar
                Divider()
                panes
            } else {
                noWorktree
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: model.selectedTicketKey) {
            if model.currentWorktree != nil, model.worktreeStatusText.isEmpty {
                model.refreshWorktreeStatus()
            }
        }
    }

    private var worktreeName: String {
        model.currentWorktree.map { ($0.path as NSString).lastPathComponent } ?? (model.selectedTicketKey ?? "")
    }

    // MARK: Header + status badge

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                Text(worktreeName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                statusBadge
                Spacer()
                if model.worktreeBusy { ProgressView().controlSize(.small) }
                Button { model.refreshWorktreeStatus() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(model.worktreeBusy || model.currentWorktree == nil)
                    .help("Status aktualisieren (iwf stack ps)")
            }
            dbDumpLine
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    /// The staged DB seed as a freshness hint (file · size · age). The source (dev/qa/main-repo)
    /// is not recoverable from the file, so only these are shown.
    @ViewBuilder
    private var dbDumpLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "cylinder.split.1x2").font(.system(size: 10)).foregroundStyle(.secondary)
            if let d = model.worktreeDbDump {
                Text("DB-Dump: \(d.fileName) · \(byteText(d.sizeBytes)) · gestaged \(ageText(d.modified))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("kein DB-Dump gestaged")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .help("Der gestagete DB-Seed. Die Quelle (dev/qa/Haupt-Repo) lässt sich aus der Datei nicht ablesen — nur Alter/Größe.")
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func ageText(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var statusBadge: some View {
        let (label, color) = derivedStatus
        return Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    /// Derives a coarse up/down state from the `iwf stack ps` output (container rows show "Up …").
    private var derivedStatus: (String, Color) {
        let ps = model.worktreeStatusText
        if ps.isEmpty || ps.hasPrefix("Lade") { return ("—", .secondary) }
        let up = ps.split(separator: "\n").filter { $0.contains("Up ") }.count
        if up > 0 { return ("● läuft · \(up)", .green) }
        return ("○ gestoppt", .secondary)
    }

    // MARK: Command bar

    private var commandBar: some View {
        HStack(spacing: 8) {
            cmd("Start", "play.fill") { model.worktreeStart() }
            cmd("Stop", "stop.fill") { model.worktreeStop() }
            cmd("Restart", "arrow.triangle.2.circlepath") { model.worktreeRestart() }
            Spacer()
            cmd("Destroy", "trash", role: .destructive) { confirmDestroy = true }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .disabled(model.worktreeBusy)
        .confirmationDialog("Worktree + Stack „\(worktreeName)“ wirklich zerstören?",
                            isPresented: $confirmDestroy, titleVisibility: .visible) {
            Button("Destroy", role: .destructive) { model.worktreeDestroy() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("iwf worktree destroy -f — reißt Container, Volume und Worktree-Verzeichnis ab (Branch bleibt).")
        }
    }

    private func cmd(_ title: String, _ icon: String, role: ButtonRole? = nil,
                     _ action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon).font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: Output panes

    private var panes: some View {
        VStack(spacing: 0) {
            outputBox(title: "STACK-STATUS", text: model.worktreeStatusText, minHeight: 84, maxHeight: 190)
            Divider()
            outputBox(title: "COMMAND-AUSGABE", text: model.worktreeCommandOutput, minHeight: 120, maxHeight: .infinity)
        }
    }

    private func outputBox(title: String, text: String, minHeight: CGFloat, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "—" : text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.bottom, 8)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: text) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
    }

    // MARK: No worktree

    private var noWorktree: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kein Worktree für \(model.selectedTicketKey ?? "diesen Task").")
                .foregroundStyle(.secondary)
            Button { model.worktreeCreate() } label: {
                Label("Worktree + Stack anlegen", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.worktreeBusy)
            if !model.worktreeCommandOutput.isEmpty {
                Divider()
                outputBox(title: "COMMAND-AUSGABE", text: model.worktreeCommandOutput, minHeight: 120, maxHeight: .infinity)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
