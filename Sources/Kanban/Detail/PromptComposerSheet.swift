import AppKit
import SwiftUI
import KanbanCore

/// Prompt verfassen: links Markdown schreiben, rechts sofort sehen, wie es ankommt — und dann in die
/// Claude-Console dieses Tickets geben.
///
/// Warum nicht ein Feld, in dem der formatierte Text direkt steht: der Prompt geht als **Markdown**
/// zur KI, nicht als Rich Text. Ein Editor, der die Sternchen versteckt, versteckt genau das, was
/// gesendet wird. Die Vorschau daneben zeigt dieselbe Darstellung, die auch Task-Files bekommen
/// (`MarkdownWebView`), und die Werkzeugleiste nimmt einem das Tippen der Zeichen ab.
struct PromptComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    @State private var text = ""
    @State private var selection = NSRange(location: 0, length: 0)
    /// Hochgezählt, sobald ein Knopf Text und Auswahl gesetzt hat — siehe `MarkdownSourceEditor`.
    @State private var applyToken = 0
    @State private var vorschauAn = true

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var leer: Bool { trimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            kopf
            werkzeugleiste
            editorUndVorschau
            fusszeile
        }
        .padding(16)
        .frame(width: vorschauAn ? 880 : 520, height: 560)
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt verfassen")
                .font(.app(.headline))
            Text("Geht als Markdown in die Claude-Console von "
                 + "\(model.selectedTicketKey ?? model.selectedProject?.key.uppercased() ?? "—").")
                .font(.app(.callout))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Werkzeugleiste

    private var werkzeugleiste: some View {
        HStack(spacing: 2) {
            knopf("bold", "Fett (⌘B)") { inline("**") }
            knopf("italic", "Kursiv (⌘I)") { inline("*") }
            knopf("curlybraces", "Code") { inline("`") }
            trenner
            knopf("number", "Überschrift") { zeile("## ") }
            knopf("list.bullet", "Liste") { zeile("- ") }
            knopf("text.quote", "Zitat") { zeile("> ") }
            trenner
            knopf("link", "Link") { anwenden(MarkdownFormatting.link(text, selection: selection)) }
            Spacer()
            Toggle("Vorschau", isOn: $vorschauAn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.app(.caption))
        }
    }

    private var trenner: some View {
        Divider().frame(height: 14).padding(.horizontal, 4)
    }

    private func knopf(_ symbol: String, _ hilfe: String,
                       _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(hilfe)
    }

    private func inline(_ marker: String) {
        anwenden(MarkdownFormatting.inline(text, selection: selection, marker: marker))
    }

    private func zeile(_ prefix: String) {
        anwenden(MarkdownFormatting.linePrefix(text, selection: selection, prefix: prefix))
    }

    private func anwenden(_ ergebnis: MarkdownFormatting.Result) {
        text = ergebnis.text
        selection = ergebnis.selection
        applyToken += 1
    }

    // MARK: - Schreiben und sehen

    private var editorUndVorschau: some View {
        HSplitView {
            MarkdownSourceEditor(text: $text, selection: $selection, applyToken: applyToken)
                .frame(minWidth: 320)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("## Was zu tun ist\n\n- Punkt eins\n- Punkt zwei")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                }
            if vorschauAn {
                // Dieselbe Darstellung wie Task-Files — was hier steht, liest sich später genauso.
                MarkdownWebView(markdown: text, baseURL: nil)
                    .frame(minWidth: 300)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
            }
        }
    }

    // MARK: - Absenden

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
