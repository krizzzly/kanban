import AppKit
import SwiftUI
import KanbanCore

/// An editable, monospaced text view that paints the diff pattern behind the text: added lines on
/// light green, a red bar where something was deleted.
///
/// AppKit rather than SwiftUI's `TextEditor`, which cannot draw per-line backgrounds. The tint comes
/// from `NSBackgroundColorAttributeName` on whole line ranges, applied whenever the text is loaded —
/// not on every keystroke, since the diff describes the file as it was when the dialog opened.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let highlight: DiffHighlight
    /// Drives syntax colouring; derived from the file path by the caller.
    let language: CodeLanguage
    /// Bumped by the owner to force a reload from `text` (e.g. after switching files or saving).
    let reloadToken: Int
    /// Schreibbar? Der Commit-Dialog bearbeitet hier; die Knowledgebase **zeigt** nur eine Datei
    /// aus dem Repo — ein Feld, das Tippen annimmt und die Änderung wegwirft, wäre schlimmer als
    /// ein sichtbar gesperrtes.
    var isEditable = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = CodeTheme.nsFont          // gleiche Schrift wie das Terminal
        textView.textContainerInset = NSSize(width: 6, height: 6)
        // Dark editor surface, unabhängig vom App-Appearance — wie ein Code-Editor.
        textView.appearance = NSAppearance(named: .darkAqua)
        textView.backgroundColor = CodeTheme.backgroundNS
        textView.drawsBackground = true
        textView.insertionPointColor = CodeTheme.foregroundNS
        scroll.appearance = NSAppearance(named: .darkAqua)
        scroll.backgroundColor = CodeTheme.backgroundNS
        scroll.drawsBackground = true
        // No wrapping: code scrolls horizontally, like the diff pane next to it.
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        let unbounded = CGFloat.greatestFiniteMagnitude
        textView.textContainer?.containerSize = NSSize(width: unbounded, height: unbounded)
        textView.maxSize = NSSize(width: unbounded, height: unbounded)
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false

        // Zeilennummern als Ruler — nicht als Text im Dokument, damit ⌘C nur den Code liefert.
        let ruler = LineNumberRuler(textView: textView,
                                    textColor: CodeTheme.gutterNS,
                                    font: CodeTheme.gutterNSFont)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.ruler = ruler

        context.coordinator.apply(text: text, highlight: highlight, language: language, to: textView)
        context.coordinator.loadedToken = reloadToken
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // Only reload when the owner says so — otherwise every keystroke would reset the cursor.
        guard context.coordinator.loadedToken != reloadToken else { return }
        context.coordinator.loadedToken = reloadToken
        context.coordinator.apply(text: text, highlight: highlight, language: language, to: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var loadedToken = -1
        weak var ruler: LineNumberRuler?

        init(_ parent: CodeEditorView) { self.parent = parent }

        /// Sets the content and tints whole lines. Colours are appearance-aware so the editor stays
        /// readable in dark mode.
        func apply(text: String, highlight: DiffHighlight, language: CodeLanguage, to textView: NSTextView) {
            textView.string = text
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: CodeTheme.foregroundNS, range: full)
            storage.addAttribute(.font, value: CodeTheme.nsFont, range: full)

            // Syntax first, then the diff tint on top — the tint is a background, so it does not
            // fight the token colours.
            for token in SyntaxHighlighter.tokens(in: text, language: language) {
                guard NSMaxRange(token.range) <= storage.length else { continue }
                storage.addAttribute(.foregroundColor,
                                     value: CodeTheme.nsColor(for: token.kind), range: token.range)
            }
            ruler?.updateThickness()
            ruler?.needsDisplay = true
            guard !highlight.isEmpty else { return }

            let added = CodeTheme.additionBackgroundNS
            let removed = CodeTheme.deletionBackgroundNS
            for (index, range) in Self.lineRanges(in: text).enumerated() {
                let number = index + 1
                if highlight.addedLines.contains(number) {
                    storage.addAttribute(.backgroundColor, value: added, range: range)
                } else if highlight.deletionMarkers.contains(number) {
                    storage.addAttribute(.backgroundColor, value: removed, range: range)
                }
            }
        }

        /// Line ranges including the trailing newline, so the tint spans the full line.
        static func lineRanges(in text: String) -> [NSRange] {
            let ns = text as NSString
            var ranges: [NSRange] = []
            var location = 0
            while location <= ns.length {
                let line = ns.lineRange(for: NSRange(location: location, length: 0))
                ranges.append(line)
                if line.location + line.length <= location { break }   // guard against no progress
                location = line.location + line.length
                if location >= ns.length { break }
            }
            return ranges
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            ruler?.updateThickness()
            ruler?.needsDisplay = true
        }
    }
}
