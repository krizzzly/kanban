import AppKit
import SwiftUI
import KanbanCore

/// Das Stack-Panel — **ein** View für zwei Ziele (`StackTarget`): den Worktree des Tickets und das
/// Haupt-Repo. Statusabzeichen (aus `iwf stack ps`), Lebenszyklus-Knöpfe und die laufende Ausgabe
/// sind identisch; die Herleitung sowieso, denn `DockerStatusScanner` bekommt nur einen anderen Pfad.
///
/// Zwei Dinge gibt es im Maintree **nicht**, und beide mit Grund: **Destroy** nähme aus dem
/// Haupt-Repo wegen des Substring-Filters jedes `local/<projekt>-*`-Image mit, und ein **DB-Seed**
/// träfe die Haupt-Entwicklungsdatenbank. Eine Kopie des Views hätte diese Regel nur einmal
/// gekannt — deshalb ein Parameter statt zweier Dateien.
struct WorktreeStackView: View {
    @Bindable var model: AppModel
    var target: StackTarget = .worktree
    @State private var confirmDestroy = false
    /// Welcher Teil des Panels zu sehen ist. Der Stack und seine Snapshots gehören zusammen, sind
    /// aber zwei Arbeitsweisen — Zustand ansehen und reparieren gegen sichern und zurückspielen.
    @State private var section: Section = .stack

    private enum Section: String, CaseIterable, Identifiable {
        case stack = "Stack"
        case snapshots = "Snapshots"
        var id: String { rawValue }
    }
    @State private var showBranchStack = false
    /// Gewählte Quelle + ob direkt importiert wird, solange die Bestätigung offen ist.
    @State private var pending: (source: StackSeeder.Source, importNow: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.directory(for: target) != nil {
                sectionPicker
                Divider()
                // Ausgabe nach rechts: links bleibt so Platz für Status und Aktionen, ohne dass
                // beides um dieselbe Höhe konkurriert. Sie gilt für beide Abschnitte — ein
                // `iwf db snapshot restore` will man genauso mitlesen wie ein `stack build`.
                HSplitView {
                    Group {
                        switch section {
                        case .stack: leftColumn
                        case .snapshots: StackSnapshotsView(model: model, target: target)
                        }
                    }
                    .frame(minWidth: 320, idealWidth: 420, maxHeight: .infinity)
                    outputBox(title: "COMMAND-AUSGABE", text: model.commandOutput(for: target),
                              minHeight: 0, maxHeight: .infinity)
                        .frame(minWidth: 300)
                }
            } else {
                noWorktree
            }
        }
        // Volle Höhe beanspruchen, egal was im Panel steht: `VSplitView` richtet sich nach der
        // Wunschgrösse des Inhalts, und ohne das fiel die untere Zone auf ihr Minimum, sobald der
        // Abschnitt wenig hergab (Snapshots ohne Einträge, kein Worktree).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .task(id: taskKey) {
            guard model.directory(for: target) != nil else { return }
            await model.refreshDerivedStatus(for: target)   // read-only, deshalb bei jedem Wechsel
            if model.statusText(for: target).isEmpty { model.refreshStatus(for: target) }
        }
    }

    private var sectionPicker: some View {
        Picker("", selection: $section) {
            ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(.horizontal, 12).padding(.bottom, 7)
    }

    /// Der Stack-Name ist in beiden Fällen der Ordnername — beim Haupt-Repo der des Repos.
    private var stackName: String {
        model.directory(for: target).map { ($0 as NSString).lastPathComponent }
            ?? (target == .worktree ? (model.selectedTicketKey ?? "") : "")
    }

    /// Der Worktree hängt am Ticket, das Haupt-Repo am Projekt — danach richtet sich, wann der
    /// Status neu gelesen wird.
    private var taskKey: String {
        target == .worktree ? (model.selectedTicketKey ?? "") : (model.selectedProject?.key ?? "")
    }

    // MARK: Header + status badge

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                Text(stackName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                statusBadge
                Spacer()
                if model.isBusy(target) { ProgressView().controlSize(.small) }
                Button { model.refreshStatus(for: target) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy(target) || model.directory(for: target) == nil)
                    .help("Status aktualisieren (iwf stack ps)")
            }
            linkBar
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    /// Die drei Sprungmarken des Worktrees: Branch → Forge, Ordner → PhpStorm, URL → Browser.
    /// Bewusst kräftig statt hellgrau — das sind die Dinge, die man von hier aus ständig öffnet.
    private var linkBar: some View {
        HStack(spacing: 8) {
            if let branch = model.branch(for: target) {
                linkChip(branch, icon: "arrow.triangle.branch", tint: .purple,
                         help: "Branch auf \(model.forgeKind.label) öffnen") {
                    if let url = model.branchURL(for: branch) { StatusLinkOpener.open(url) }
                }
                .disabled(model.branchURL(for: branch) == nil)
            }
            // Abzweig-Basis und Branch-Hierarchie sind Worktree-Fragen: das Haupt-Repo *ist* die Basis.
            if target == .worktree, let parent = model.worktreeParentBranch {
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
            if let path = model.directory(for: target) {
                linkChip((path as NSString).lastPathComponent, icon: "folder", tint: .blue,
                         help: "In PhpStorm öffnen: \(path)") {
                    StatusLinkOpener.open(URL(string: StatusLinks.ideURL(forPath: path))!)
                }
            }
            if let url = model.stackURL(for: target) {
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
    ///
    /// Über `stackStatus(for:)`, wie das Panel darunter: `model.stackStatus` ist immer der
    /// Worktree-Stack, im Maintree-Tab stand deshalb dessen Zahl über den Diensten des Haupt-Repos.
    @ViewBuilder
    private var statusBadge: some View {
        if let status = model.stackStatus(for: target) {
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
            cmd("Start", "play.fill") { model.lifecycle(.start, for: target) }
            cmd("Stop", "stop.fill") { model.lifecycle(.stop, for: target) }
            cmd("Restart", "arrow.triangle.2.circlepath") { model.lifecycle(.restart, for: target) }
            Spacer()
            if target.allowsDestructiveActions {
                cmd("Destroy", "trash", role: .destructive) { confirmDestroy = true }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .disabled(model.isBusy(target))
        .confirmationDialog("Worktree + Stack „\(stackName)“ wirklich zerstören?",
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
            ? "Datenbank mit „\(pending.source.label)“ jetzt neu aufsetzen?"
            : "Datenbank mit „\(pending.source.label)“ neu seeden?"
    }

    /// Sagt, was `iwf` wirklich tut — nachgelesen in `project_compose.db_import_dump`.
    ///
    /// Hier stand vorher „iwf legt vorher automatisch einen Snapshot an (Wiederherstellung mit
    /// `iwf db snapshot restore`)". Das war falsch: `import-dump` legt **keinen** Snapshot an. Und es
    /// war genau der Satz, auf dessen Zusicherung hin man den destruktiven Knopf drückt.
    private var confirmMessage: String {
        guard let pending else { return "" }
        return pending.importNow
            ? "Der Stack wird heruntergefahren, das DB-Volume \(stackName)_dbdata **gelöscht** und "
              + "neu gestartet; MySQL importiert den Dump beim Hochlaufen. Der bisherige "
              + "Datenbestand ist damit weg — einen Snapshot legt iwf dabei nicht an "
              + "(vorher selbst: iwf db snapshot create)."
            : "Der bisherige Dump und das DB-Volume \(stackName)_dbdata werden entfernt; beim "
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
                    if let status = model.stackStatus(for: target) {
                        StackStatusView(status: status,
                                        isLoading: model.isLoadingStatus(for: target),
                                        onRepair: model.isBusy(target) ? nil
                                            : { model.repairStack($0, for: target) },
                                        // Seed nur im Worktree: im Haupt-Repo träfe er die
                                        // Entwicklungsdatenbank, an der alles hängt.
                                        onSeed: (model.isBusy(target)
                                                 || !target.allowsDestructiveActions) ? nil
                                            : { source, importNow in
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
            // `LogTextView` statt `Text`: die Ausgabe wächst im Sekundentakt, und ein SwiftUI-`Text`
            // baute dafür jedes Mal den ganzen `AttributedString` neu (40 ms bei vollem Puffer) und
            // brach ihn bei jeder Breitenänderung neu um. Hier wird angehängt.
            LogTextView(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CodeTheme.background)
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
