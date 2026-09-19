import AppKit
import SwiftUI
import KanbanCore

/// Markdown schreiben und daneben sehen, wie es ankommt: Werkzeugleiste, Editor, Vorschau.
///
/// Dasselbe Bauteil in „Prompt verfassen“ und „Neuen Task beschreiben“ — beide schreiben Markdown für
/// dieselbe Console, und zwei Ausprägungen derselben Handlung müsste man sich zweimal merken.
/// Verschieden bleibt nur der Rahmen: Kopfzeile und Fusszeile stehen im jeweiligen Sheet, weil dort
/// steht, wohin der Text geht und was auf dem Knopf steht.
///
/// Warum kein Feld, in dem der formatierte Text direkt steht: der Text geht als **Markdown** zur KI,
/// nicht als Rich Text. Ein Editor, der die Sternchen versteckt, versteckt genau das, was gesendet
/// wird. Die Vorschau zeigt dieselbe Darstellung wie die Task-Files (`MarkdownWebView`), und die
/// Werkzeugleiste nimmt einem das Tippen der Zeichen ab.
struct MarkdownComposer: View {
    @Binding var text: String
    /// Der Schalter steht hier, der Zustand gehört dem Sheet: die Fensterbreite hängt an ihm, und das
    /// `frame` sitzt aussen. Ein `@State` an dieser Stelle wäre von dort nicht lesbar.
    @Binding var vorschauAn: Bool

    @State private var selection = NSRange(location: 0, length: 0)
    /// Hochgezählt, sobald ein Knopf Text und Auswahl gesetzt hat — siehe `MarkdownSourceEditor`.
    @State private var applyToken = 0

    /// Ein Gerüst statt eines fertigen Satzes: es soll zeigen, dass hier Markdown erwartet wird.
    private static let platzhalter = "## Was zu tun ist\n\n- Punkt eins\n- Punkt zwei"

    /// Mit Vorschau braucht das Fenster zwei Spalten, ohne sie eine. Die Masse stehen hier, damit sie
    /// nicht in zwei Sheets getrennt gepflegt werden.
    static func breite(vorschau: Bool) -> CGFloat { vorschau ? 880 : 520 }
    static let hoehe: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            werkzeugleiste
            editorUndVorschau
        }
    }

    // MARK: - Werkzeugleiste

    private var werkzeugleiste: some View {
        HStack(spacing: 2) {
            knopf("bold", "Fett (⌘B)", taste: "b") { inline("**") }
            knopf("italic", "Kursiv (⌘I)", taste: "i") { inline("*") }
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

    /// `taste` bindet den Kurzbefehl, den der Hilfetext verspricht. Er greift auch, während der Cursor
    /// im Editor steht: AppKit lässt `performKeyEquivalent` über die View-Hierarchie laufen, bevor der
    /// First Responder sein `keyDown` sieht (an echtem AppKit gemessen, siehe CLAUDE.md).
    private func knopf(_ symbol: String, _ hilfe: String, taste: KeyEquivalent? = nil,
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
        .modifier(Kurzbefehl(taste: taste))
    }

    /// `keyboardShortcut` nimmt kein `nil`, und ein `if` im ViewBuilder gäbe zwei verschiedene Typen.
    private struct Kurzbefehl: ViewModifier {
        let taste: KeyEquivalent?

        func body(content: Content) -> some View {
            if let taste {
                content.keyboardShortcut(taste, modifiers: .command)
            } else {
                content
            }
        }
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
                        Text(Self.platzhalter)
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
}

/// Titel und eine Zeile darunter, für beide Verfasser-Fenster gleich gesetzt.
struct ComposerKopf: View {
    let titel: String
    let untertitel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titel)
                .font(.app(.headline))
            Text(untertitel)
                .font(.app(.callout))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
