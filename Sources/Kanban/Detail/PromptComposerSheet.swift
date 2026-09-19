import SwiftUI
import KanbanCore

/// Prompt verfassen: links Markdown schreiben, rechts sofort sehen, wie es ankommt — und dann in die
/// Claude-Console dieses Tickets geben.
///
/// Geschrieben wird in `MarkdownComposer`, dem gemeinsamen Bauteil mit „Neuen Task beschreiben“. Hier
/// steht nur, wohin der Text geht: **Einfügen** legt ihn in die Console, **Absenden** schickt ihn ab.
struct PromptComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    @State private var text = ""
    @State private var vorschauAn = true

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var leer: Bool { trimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ComposerKopf(
                titel: "Prompt verfassen",
                untertitel: "Geht als Markdown in die Claude-Console von "
                    + "\(model.selectedTicketKey ?? model.selectedProject?.key.uppercased() ?? "—").")
            MarkdownComposer(text: $text, vorschauAn: $vorschauAn)
            fusszeile
        }
        .padding(16)
        .frame(width: MarkdownComposer.breite(vorschau: vorschauAn), height: MarkdownComposer.hoehe)
    }

    private var fusszeile: some View {
        HStack(spacing: 8) {
            Text("Einfügen legt den Text in die Console, ohne ihn abzuschicken.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Abbrechen") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Einfügen") {
                model.sendComposedPrompt(trimmed, submit: false)
                dismiss()
            }
            .disabled(leer)
            Button("Absenden") {
                model.sendComposedPrompt(trimmed, submit: true)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(leer)
        }
    }
}
