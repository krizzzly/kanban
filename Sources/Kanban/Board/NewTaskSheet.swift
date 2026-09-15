import SwiftUI
import KanbanCore

/// „Task erstellen" im freien Modus: eine Beschreibung eintippen, den Rest macht `/create-task` in
/// der Projekt-Console (Ticket-Nummer, Task-File, Worktree).
///
/// Der Text wird nur **eingefügt**, nicht abgeschickt — wie bei jedem anderen Command liest du in der
/// Console gegen und drückst selbst Enter.
struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Neuen Task beschreiben")
                    .font(.app(.headline))
                Text("Geht als `/create-task …` in die Claude-Console von "
                     + "\(model.selectedProject?.key.uppercased() ?? "—"). Abgeschickt wird dort, "
                     + "nicht hier.")
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $text)
                .font(.app(.body, design: .default))
                .focused($focused)
                .frame(minHeight: 180)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("z. B. „Pendenz soll sich auch bei zurückgezogenem Nachtrag auflösen“")
                            .font(.app(.body))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11).padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Erstellen") {
                    model.createTask(description: trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty || model.selectedProject == nil)
            }
        }
        .padding(16)
        .frame(width: 560)
        .onAppear {
            // Aus einer Karte ohne Nummer heraus steht Titel und Branch schon da (siehe
            // `AppModel.startTaskFromBranch`); der Entwurf wird dabei verbraucht, damit das nächste
            // „Task erstellen" wieder leer aufgeht.
            if !model.newTaskDraft.isEmpty {
                text = model.newTaskDraft
                model.newTaskDraft = ""
            }
            focused = true
        }
    }
}
