import AppKit

/// Line-number gutter for the editor's `NSTextView`.
///
/// A ruler rather than text in the document, so the numbers never end up in a copy: selecting code and
/// pressing ⌘C yields the code alone.
final class LineNumberRuler: NSRulerView {
    private let textColor: NSColor
    private let font: NSFont

    init(textView: NSTextView, textColor: NSColor, font: NSFont) {
        self.textColor = textColor
        self.font = font
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Recomputes the width from the highest line number, so a 4-digit file does not clip.
    func updateThickness() {
        guard let textView = clientView as? NSTextView else { return }
        let lines = max(1, textView.string.reduce(into: 1) { count, char in
            if char == "\n" { count += 1 }
        })
        let digits = String(lines).count
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: font]).width + 16
        if abs(width - ruleThickness) > 0.5 { ruleThickness = width }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let content = textView.string as NSString
        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let visibleChars = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)

        // Line number of the first visible character: count the newlines before it once, then step.
        var lineNumber = 1
        content.enumerateSubstrings(in: NSRange(location: 0, length: visibleChars.location),
                                    options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let inset = textView.textContainerInset.height
        var index = visibleChars.location

        while index <= NSMaxRange(visibleChars), index <= content.length {
            let lineRange = content.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)

            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = lineRect.minY + inset - visibleRect.minY + (lineRect.height - size.height) / 2
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y), withAttributes: attributes)

            lineNumber += 1
            let next = NSMaxRange(lineRange)
            if next <= index { break }          // no progress → stop rather than spin
            index = next
        }
    }
}
