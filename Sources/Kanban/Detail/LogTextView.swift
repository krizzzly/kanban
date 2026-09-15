import AppKit
import SwiftUI
import KanbanCore

/// Die Ausgabefläche für laufende Befehle (Stack-Panel, Stack-Sweep): eine `NSTextView`, die das
/// **Neue anhängt**, statt den ganzen Puffer neu zu bauen.
///
/// Vorher stand hier ein `Text(CodeTheme.ansiText(text))` mitten im SwiftUI-Body. Gemessen (Release):
///
/// | Puffer | Spans | `ANSIParser.parse` | + `AttributedString` |
/// |---|---|---|---|
/// | 10 000 Zeichen | 843 | 1,1 ms | **12,2 ms** |
/// | 30 000 Zeichen | 2510 | 1,3 ms | **19,1 ms** |
/// | 60 000 Zeichen | 5008 | 2,5 ms | **40,1 ms** |
///
/// Das Parsen war nie das Teure — das stückweise `AttributedString.append` ist es. Und diese 40 ms
/// fielen bei **jedem** Body-Durchlauf an, nicht nur bei neuer Ausgabe: der Body des Panels liest
/// `cards` mit, und die schreibt die ⏱-Nachführung alle ~1,5 s, solange Claude antwortet. Dazu kam
/// die Textlage: ein einziges `Text` mit 38 000 Zeichen und ~2500 Farb-Runs braucht 5–7 ms je
/// Breite — also je Frame, während man den Trenner zieht.
///
/// Angehängt wird nur der Zuwachs, deshalb kostet ein Body-Durchlauf ohne neue Ausgabe hier nichts
/// ausser einem Byte-Vergleich. Der Preis ist der Zustand im Coordinator: die geltende ANSI-Farbe
/// muss über die Stückgrenze reisen (`ANSIParser.State`), sonst begänne jedes Stück wieder weiss.
struct LogTextView: NSViewRepresentable {
    /// Der ganze bisherige Ausgabetext. Die View leitet daraus ab, was neu ist.
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = CodeTheme.backgroundNS
        textView.textContainerInset = NSSize(width: 10, height: 8)   // wie die bisherige Polsterung
        // Dunkel wie die eingebettete Console, unabhängig vom App-Appearance.
        textView.appearance = NSAppearance(named: .darkAqua)
        scroll.appearance = NSAppearance(named: .darkAqua)
        scroll.backgroundColor = CodeTheme.backgroundNS
        scroll.drawsBackground = true
        scroll.hasHorizontalScroller = false
        // Umbrechen statt seitwärts scrollen: Docker-Zeilen sind lang, und beim Mitlesen einer
        // laufenden Ausgabe will niemand horizontal scrollen.
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        context.coordinator.apply(text: text, to: textView, scroll: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.apply(text: text, to: textView, scroll: scroll)
    }

    /// Hält fest, was schon gerendert ist — als Text **und** als offener ANSI-Zustand.
    @MainActor
    final class Coordinator {
        private var rendered = ""
        private var ansi = ANSIParser.State()

        /// Ab hier gilt neuer Inhalt als „gewachsen" statt „neu angefangen" — eine Handvoll Zeilen
        /// ist der Kopf eines frisch gestarteten Befehls, 150 KB sind ein gekappter Puffer.
        private static let freshOutputBytes = 4_000

        func apply(text: String, to textView: NSTextView, scroll: NSScrollView) {
            let text = text.isEmpty ? "—" : text
            let delta = LogText.appendedPart(of: text, after: rendered)
            guard delta != "" else { return }   // unverändert — der übliche Fall bei einem Rerender
            // Am unteren Rand mitlesen heisst: mitlaufen. Wer hochgescrollt hat, liest etwas
            // Bestimmtes — dem darf die nächste Zeile die Stelle nicht wegziehen. Ein **neuer**
            // Befehl fängt trotzdem am Ende an: dort steht seine erste Zeile.
            let followTail = isAtBottom(scroll)
                || (delta == nil && text.utf8.count < Self.freshOutputBytes)

            if let delta {
                textView.textStorage?.append(attributed(delta))
            } else {
                // Vorne gekappt (`LogText`) oder ein neuer Befehl — dann von vorn, mit frischem
                // Farbzustand.
                ansi = ANSIParser.State()
                textView.textStorage?.setAttributedString(attributed(text))
            }
            rendered = text
            if followTail { textView.scrollToEndOfDocument(nil) }
        }

        /// Farbige Fassung eines Stücks; der ANSI-Zustand läuft über die Stückgrenze weiter.
        private func attributed(_ chunk: String) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let font = CodeTheme.nsFont
            for span in ANSIParser.parse(chunk, state: &ansi) {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: span.bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font,
                    .foregroundColor: span.foreground.map(CodeTheme.ansiNS) ?? CodeTheme.foregroundNS,
                ]
                if let background = span.background {
                    attributes[.backgroundColor] = CodeTheme.ansiNS(background)
                }
                result.append(NSAttributedString(string: span.text, attributes: attributes))
            }
            return result
        }

        /// Innerhalb einer Zeilenhöhe vom unteren Rand gilt als „unten" — beim Mitlesen bleibt der
        /// Scroller selten exakt auf dem letzten Pixel stehen.
        private func isAtBottom(_ scroll: NSScrollView) -> Bool {
            let visible = scroll.contentView.documentVisibleRect
            let height = scroll.documentView?.bounds.height ?? 0
            guard height > visible.height else { return true }   // passt ganz hinein
            return visible.maxY >= height - max(CodeTheme.nsFont.pointSize * 1.5, 12)
        }
    }
}
