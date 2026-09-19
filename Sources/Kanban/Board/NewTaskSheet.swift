import SwiftUI
import KanbanCore

/// „Task erstellen“ im freien Modus: eine Beschreibung schreiben, den Rest macht `/create-task` in der
/// Projekt-Console (Ticket-Nummer, Task-File, Worktree).
///
/// Geschrieben wird in `MarkdownComposer`, demselben Bauteil wie in „Prompt verfassen“ — gerade die
/// Task-Beschreibung braucht Struktur: was strukturiert in der Console ankommt, landet strukturiert im
/// Task-File.
///
/// Der Text wird nur **eingefügt**, nicht abgeschickt — wie bei jedem anderen Command liest du in der
/// Console gegen und drückst selbst Enter.
struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    @State private var text = ""
    @State private var vorschauAn = true

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ComposerKopf(
                titel: "Neuen Task beschreiben",
                untertitel: "Geht als `/create-task …` in die Claude-Console von "
                    + "\(model.selectedProject?.key.uppercased() ?? "—"). Abgeschickt wird dort, "
                    + "nicht hier.")
            MarkdownComposer(text: $text, vorschauAn: $vorschauAn)
            fusszeile
        }
        .padding(16)
        .frame(width: MarkdownComposer.breite(vorschau: vorschauAn), height: MarkdownComposer.hoehe)
        .onAppear {
            // Aus einer Karte ohne Nummer heraus stehen Titel und Branch schon da (siehe
            // `AppModel.startTaskFromBranch`); der Entwurf wird dabei verbraucht, damit das nächste
            // „Task erstellen“ wieder leer aufgeht.
            if !model.newTaskDraft.isEmpty {
                text = model.newTaskDraft
                model.newTaskDraft = ""
            }
        }
    }

    private var fusszeile: some View {
        HStack(spacing: 8) {
            Text("Erstellen legt den Text in die Console, ohne ihn abzuschicken.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
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
}
