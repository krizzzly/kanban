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
        // Steht schon Text da (ein übernommener Entwurf), gehört der Cursor dahinter — je nachdem,
        // wann SwiftUI `onAppear` ausführt, kommt er hier oder in `updateNSView` an.
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        context.coordinator.zuletztGesetzt = applyToken
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            // Text von aussen in einen leeren Editor — das ist der Entwurf aus einer Karte ohne
            // Nummer. AppKit setzt den Einfügepunkt beim Zuweisen auf 0; man täte also mitten in
            // den fremden Text hinein. Beim Tippen wird dieser Zweig nie betreten: dann hat der
            // Coordinator den Text längst gemeldet und beide Seiten sind gleich.
            let warLeer = textView.string.isEmpty
            textView.string = text
            if warLeer, !text.isEmpty {
                textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            }
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

        // Der Editor ist das Feld, in dem geschrieben wird — er bekommt den Fokus, sobald er in
        // einem Fenster hängt, damit das Sheet tippbereit aufgeht. Vermerkt wird das **erst dann**:
        // beim ersten Durchlauf gibt es noch kein Fenster, und ein vorschnelles Flag hätte den
        // Fokus für immer verschluckt. (`@FocusState` hilft hier nicht, das greift nur auf
        // SwiftUI-Views.)
        if !context.coordinator.fokusGesetzt, let window = textView.window {
            context.coordinator.fokusGesetzt = true
            window.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceEditor
        var zuletztGesetzt = -1
        var fokusGesetzt = false

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
