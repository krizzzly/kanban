import SwiftUI
import KanbanCore

/// Der Reiter „Snapshots" des Stack-Panels: die Liste aus `~/.iwf-dev/snapshots/<stack>`, ein
/// Wiederherstellen je Zeile und zwei Wege, einen neuen anzulegen.
///
/// Was `iwf db snapshot` wirklich kann (am Quelltext von iwf-local-dev gelesen, nicht geraten):
/// `create` überschreibt `<volume>-latest.tar` oder legt mit `-t` einen mit Zeitstempel an — einen
/// **Namen** kennt es nicht. Den macht Kanban selbst: mit `-t` erzeugen, dann umbenennen. Das ist
/// gefahrlos, weil `restore -f` jeden Basename aus dem Ordner annimmt und `list` alles globt.
struct StackSnapshotsView: View {
    @Bindable var model: AppModel
    let target: StackTarget

    @State private var newName = ""
    @State private var pendingRestore: DbSnapshot?
    @State private var confirmOverwriteLatest = false

    private var stack: String { model.stackName(for: target) ?? "" }
    private var volume: String { DbSnapshots.defaultVolume(stack: stack) }
    private var snapshots: [DbSnapshot] { model.snapshots(for: target) }
    private var busy: Bool { model.isBusy(target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            createBar
            Divider()
            if snapshots.isEmpty {
                empty
            } else {
                ScrollView { LazyVStack(spacing: 0) { ForEach(snapshots) { row($0) } } }
            }
            Spacer(minLength: 0)
        }
        // Auch leer die volle Höhe halten — sonst schrumpft die untere Fensterzone beim Umschalten
        // (siehe `WorktreeStackView`).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: stack) { model.refreshSnapshots(for: target) }
        .confirmationDialog("Snapshot „\(pendingRestore?.label(volume: volume) ?? "")“ wiederherstellen?",
                            isPresented: restoreConfirmation, titleVisibility: .visible) {
            Button("Wiederherstellen", role: .destructive) {
                if let pendingRestore { model.restoreSnapshot(pendingRestore, for: target) }
                pendingRestore = nil
            }
            Button("Abbrechen", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Der aktuelle Datenbestand von \(volume) wird dabei ersetzt. iwf hält die "
                 + "Datenbank dafür an und startet sie danach wieder.")
        }
        .confirmationDialog("Bestehenden „latest“-Snapshot überschreiben?",
                            isPresented: $confirmOverwriteLatest, titleVisibility: .visible) {
            Button("Überschreiben", role: .destructive) { model.createSnapshot(label: nil, for: target) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("`iwf db snapshot create` schreibt immer \(volume)-latest.tar — der bisherige "
                 + "Stand dieser Datei ist danach weg. Ein benannter Snapshot lässt ihn stehen.")
        }
    }

    private var restoreConfirmation: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    // MARK: Anlegen

    private var createBar: some View {
        HStack(spacing: 8) {
            Button {
                if snapshots.contains(where: \.isLatest) { confirmOverwriteLatest = true }
                else { model.createSnapshot(label: nil, for: target) }
            } label: {
                Label("Snapshot (latest)", systemImage: "camera")
            }
            .help("iwf db snapshot create — überschreibt \(volume)-latest.tar")

            Divider().frame(height: 16)

            TextField("Name", text: $newName, prompt: Text("z. B. vor-migration"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                .onSubmit(createNamed)
            Button("Anlegen", action: createNamed)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("iwf db snapshot create -t, danach umbenannt auf "
                      + "\(DbSnapshots.fileName(volume: volume, label: newName.isEmpty ? "name" : newName))")

            Spacer()
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .disabled(busy || stack.isEmpty)
    }

    private func createNamed() {
        let label = newName.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        model.createSnapshot(label: label, for: target)
        newName = ""
    }

    // MARK: Liste

    private func row(_ snapshot: DbSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.isLatest ? "clock.arrow.circlepath" : "camera")
                .foregroundStyle(snapshot.isLatest ? Color.accentColor : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.label(volume: volume))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text("\(byteText(snapshot.bytes)) · \(ageText(snapshot.modified))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Wiederherstellen") { pendingRestore = snapshot }
                .disabled(busy)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .help(snapshot.path)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keine Snapshots für \(stack).")
                .foregroundStyle(.secondary)
            Text("Sie liegen unter \(DbSnapshots.directory(stack: stack)) — ein Ordner je Stack, "
                 + "also getrennt für Haupt-Repo und jeden Worktree.")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func ageText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
