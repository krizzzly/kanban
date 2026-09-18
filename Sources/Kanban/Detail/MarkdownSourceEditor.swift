import AppKit
import SwiftUI
import KanbanCore

/// Ein einfacher Markdown-Texteditor, der seine **Auswahl nach aussen meldet**.
///
/// AppKit statt SwiftUIs `TextEditor` aus genau diesem einen Grund: `TextEditor` gibt die Auswahl
/// nicht heraus, und ohne sie könnte „Fett" nur ans Ende schreiben statt das Markierte umschliessen.
/// Die Werkzeugleiste rechnet damit in `MarkdownFormatting` und setzt Text **und** Auswahl zurück.
///
/// `applyToken` wird vom Besitzer hochgezählt, wenn er Text und Auswahl von aussen gesetzt hat
/// (Knopfdruck). Ohne dieses Signal liesse sich das nicht vom Tippen unterscheiden, und der Cursor
/// spränge bei jedem Zeichen an die zuletzt berechnete Stelle.
struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var applyToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.delegate = context.coordinator
        textView.isRichText = false
        // Markdown ist Klartext: „smarte" Anführungszeichen und Bindestriche machen daraus stillschweigend
        // etwas anderes, als man getippt hat — und der Prompt geht so zur KI.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = text
        context.coordinator.zuletztGesetzt = applyToken
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }
        // Nur nach einem Knopfdruck die Auswahl setzen — siehe `applyToken`.
        if context.coordinator.zuletztGesetzt != applyToken {
            context.coordinator.zuletztGesetzt = applyToken
            let laenge = (textView.string as NSString).length
            let sicher = NSRange(location: min(selection.location, laenge),
                                 length: min(selection.length, max(laenge - selection.location, 0)))
            textView.setSelectedRange(sicher)
            textView.scrollRangeToVisible(sicher)
            // Der Fokus muss zurück: nach einem Klick auf die Leiste läge er sonst dort, und der
            // nächste Tastendruck ginge ins Leere statt in den Text.
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceEditor
        var zuletztGesetzt = -1

        init(_ parent: MarkdownSourceEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.selection = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selection = textView.selectedRange()
        }
    }
}
