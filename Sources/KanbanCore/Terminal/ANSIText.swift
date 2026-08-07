import Foundation

/// A run of terminal output sharing one style.
public struct ANSISpan: Sendable, Hashable {
    public let text: String
    /// ANSI colour index 0–15, or nil for the theme's default foreground.
    public let foreground: Int?
    public let background: Int?
    public let bold: Bool

    public init(text: String, foreground: Int?, background: Int?, bold: Bool) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.bold = bold
    }
}

/// Parses SGR escape sequences out of command output so it can be rendered with the terminal's own
/// palette instead of showing raw `ESC[32m` noise.
///
/// Deliberately limited to what tooling actually emits: the 16 base colours, bold, and reset.
/// Everything else (cursor moves, erase-line, 256/true-colour selectors) is **stripped**, not
/// rendered — a progress bar redrawing itself must not leave escape litter in a scrollback pane.
public enum ANSIParser {
    public static func parse(_ input: String) -> [ANSISpan] {
        var spans: [ANSISpan] = []
        var current = ""
        var foreground: Int?
        var background: Int?
        var bold = false

        func flush() {
            guard !current.isEmpty else { return }
            spans.append(ANSISpan(text: current, foreground: foreground,
                                  background: background, bold: bold))
            current = ""
        }

        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            guard character == "\u{1B}" else {
                current.append(character)
                index = input.index(after: index)
                continue
            }
            // ESC [ … <final byte>
            let afterEscape = input.index(after: index)
            guard afterEscape < input.endIndex, input[afterEscape] == "[" else {
                index = afterEscape          // lone ESC — drop it
                continue
            }
            var cursor = input.index(after: afterEscape)
            var parameters = ""
            while cursor < input.endIndex, !("@"..."~").contains(input[cursor]) {
                parameters.append(input[cursor])
                cursor = input.index(after: cursor)
            }
            guard cursor < input.endIndex else { break }   // truncated sequence
            let final = input[cursor]
            index = input.index(after: cursor)

            guard final == "m" else { continue }           // not a colour change → strip silently
            flush()
            apply(parameters, foreground: &foreground, background: &background, bold: &bold)
        }
        flush()
        return spans
    }

    private static func apply(_ parameters: String, foreground: inout Int?,
                              background: inout Int?, bold: inout Bool) {
        let codes = parameters.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        var iterator = codes.makeIterator()
        while let code = iterator.next() {
            switch code {
            case 0:
                foreground = nil; background = nil; bold = false
            case 1:
                bold = true
            case 22:
                bold = false
            case 30...37:
                foreground = code - 30
            case 90...97:
                foreground = code - 90 + 8      // bright
            case 39:
                foreground = nil
            case 40...47:
                background = code - 40
            case 100...107:
                background = code - 100 + 8
            case 49:
                background = nil
            case 38, 48:
                // 256-colour (`5;N`) or true-colour (`2;r;g;b`) — consume the operands and fall back
                // to the default colour rather than guessing a palette entry.
                if let mode = iterator.next() {
                    let operands = mode == 5 ? 1 : (mode == 2 ? 3 : 0)
                    for _ in 0..<operands { _ = iterator.next() }
                }
                if code == 38 { foreground = nil } else { background = nil }
            default:
                continue
            }
        }
    }

    /// Output without any escape sequences — for copying or when no colours are wanted.
    public static func strip(_ input: String) -> String {
        parse(input).map(\.text).joined()
    }
}
