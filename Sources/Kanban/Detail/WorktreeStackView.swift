import AppKit
import SwiftUI
import KanbanCore

/// The "Worktree" tab: controls the ticket's per-worktree docker stack via the `iwf worktree` /
/// `iwf stack` commands — a status badge (from `iwf stack ps`), a row of lifecycle commands, and the
/// live stdout of both the status query and the running command.
struct WorktreeStackView: View {
    @Bindable var model: AppModel
    @State private var confirmDestroy = false
    @State private var showBranchStack = false
    /// Gewählte Quelle + ob direkt importiert wird, solange die Bestätigung offen ist.
    @State private var pending: (source: StackSeeder.Source, importNow: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.currentWorktree != nil {
                // Ausgabe nach rechts: links bleibt so Platz für Status und Aktionen, ohne dass
                // beides um dieselbe Höhe konkurriert.
                HSplitView {
                    leftColumn.frame(minWidth: 320, idealWidth: 420)
                    outputBox(title: "COMMAND-AUSGABE", text: model.worktreeCommandOutput,
                              minHeight: 0, maxHeight: .infinity)
                        .frame(minWidth: 300)
                }
            } else {
                noWorktree
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        // Am Wurzel-View, nicht am Menü: das Menü liegt inzwischen in der Status-Zeile, und ein
        // Dialog an einer nicht gerenderten View erscheint nie.
        .confirmationDialog(confirmTitle, isPresented: seedConfirmation, titleVisibility: .visible) {
            Button(pending?.importNow == true ? "Importieren" : "Bereitstellen", role: .destructive) {
                if let pending { model.seedDatabase(from: pending.source, importNow: pending.importNow) }
                pending = nil
            }
            Button("Abbrechen", role: .cancel) { pending = nil }
        } message: {
            Text(confirmMessage)
        }
        .task(id: model.selectedTicketKey) {
            guard model.currentWorktree != nil else { return }
            await model.refreshStackStatus()          // read-only, deshalb bei jedem Ticketwechsel
            if model.worktreeStatusText.isEmpty { model.refreshWorktreeStatus() }
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
            linkBar
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    /// Die drei Sprungmarken des Worktrees: Branch → GitLab, Ordner → PhpStorm, URL → Browser.
    /// Bewusst kräftig statt hellgrau — das sind die Dinge, die man von hier aus ständig öffnet.
    private var linkBar: some View {
        HStack(spacing: 8) {
            if let branch = model.currentWorktree?.branch {
                linkChip(branch, icon: "arrow.triangle.branch", tint: .purple,
                         help: "Branch auf GitLab öffnen") {
                    if let url = model.worktreeBranchURL { StatusLinkOpener.open(url) }
                }
                .disabled(model.worktreeBranchURL == nil)
            }
            if let parent = model.worktreeParentBranch {
                linkChip("← \(parent.name)", icon: "arrow.triangle.pull", tint: .orange,
                         help: "Abzweig-Basis (abgeleitet): \(parent.ref) · "
                               + "\(parent.ahead) Commits voraus, Basis +\(parent.behind) seither · "
                               + "Klick: Hierarchie aller Feature-Branches") {
                    showBranchStack = true
                }
                .popover(isPresented: $showBranchStack, arrowEdge: .bottom) {
                    BranchStackPopover(model: model)
                }
            }
            if let path = model.currentWorktree?.path {
                linkChip((path as NSString).lastPathComponent, icon: "folder", tint: .blue,
                         help: "In PhpStorm öffnen: \(path)") {
                    StatusLinkOpener.open(URL(string: StatusLinks.ideURL(forPath: path))!)
                }
            }
            if let url = model.worktreeStackURL {
                linkChip(url.host ?? url.absoluteString, icon: "safari", tint: .green,
                         help: "Im Browser öffnen: \(url.absoluteString)") {
                    StatusLinkOpener.open(url)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func linkChip(_ title: String, icon: String, tint: Color, help: String,
                          _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
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

    /// Verdict from the derived status — no longer counted out of the `stack ps` text, which cannot
    /// distinguish "läuft" from "läuft, aber keycloak ist mit Exit 134 weg".
    @ViewBuilder
    private var statusBadge: some View {
        if let status = model.stackStatus {
            let verdict = status.verdict
            Text("\(verdict.label) · \(status.running.count)/\(status.services.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(verdict.color)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(verdict.color.opacity(0.15), in: Capsule())
        } else {
            Text("—")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        }
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

    private var seedConfirmation: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var confirmTitle: String {
        guard let pending else { return "" }
        return pending.importNow
            ? "„\(pending.source.label)“ jetzt in die laufende DB importieren?"
            : "Datenbank mit „\(pending.source.label)“ neu seeden?"
    }

    private var confirmMessage: String {
        guard let pending else { return "" }
        return pending.importNow
            ? "Der aktuelle Datenbestand wird ersetzt. iwf legt vorher automatisch einen Snapshot an "
              + "(Wiederherstellung mit `iwf db snapshot restore`). Der Stack muss laufen."
            : "Der bisherige Dump und das DB-Volume \(worktreeName)_dbdata werden entfernt; beim "
              + "nächsten Start importiert MySQL den neuen Dump. Der Stack muss gestoppt sein."
    }

    /// Dateiauswahl für einen lokalen Dump (.sql / .sql.gz).
    private func chooseSeedFile(importNow: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "DB-Dump wählen"
        panel.message = "Wähle einen .sql- oder .sql.gz-Dump."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pending = (.file(url.path), importNow)
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

    /// Links: Aktionen oben, Status darunter — beides scrollt gemeinsam.
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            commandBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let status = model.stackStatus {
                        StackStatusView(status: status,
                                        isLoading: model.stackStatusLoading,
                                        onRepair: model.worktreeBusy ? nil : { model.repairStack($0) },
                                        onSeed: model.worktreeBusy ? nil : { source, importNow in
                                            if let source { pending = (source, importNow) }
                                            else { chooseSeedFile(importNow: importNow) }
                                        })
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            }
        }
    }

    private func outputBox(title: String, text: String, minHeight: CGFloat, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Titelleiste bleibt im App-Look — nur die Ausgabefläche darunter ist Terminal.
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? AttributedString("—") : CodeTheme.ansiText(text))
                        .font(CodeTheme.font)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: text) { proxy.scrollTo("bottom", anchor: .bottom) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CodeTheme.background)
                .environment(\.colorScheme, .dark)   // gleiche Anmutung wie die eingebettete Console
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
