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
    /// Was am Ende eines Stücks offen bleibt: die geltenden Farben **und** eine angefangene
    /// Escape-Sequenz.
    ///
    /// Nötig, seit die Ausgabe **stückweise** gerendert wird (`LogTextView` hängt nur das Neue an,
    /// statt alles neu zu bauen): ein `ESC[32m` gilt bis zum nächsten Reset, also über die
    /// Stückgrenze hinweg, und eine Grenze mitten in der Sequenz darf nicht als Text durchfallen —
    /// bei 47 Byte je pty-Lesevorgang trifft sie ständig eine.
    public struct State: Sendable, Equatable {
        var foreground: Int?
        var background: Int?
        var bold: Bool
        /// Angefangene, noch unvollständige Sequenz — wird dem nächsten Stück vorangestellt.
        var pending: String

        public init() {
            foreground = nil
            background = nil
            bold = false
            pending = ""
        }
    }

    public static func parse(_ input: String) -> [ANSISpan] {
        var state = State()
        return parse(input, state: &state)
    }

    /// Parst das nächste Stück eines Stroms und schreibt den offenen Zustand fort.
    public static func parse(_ input: String, state: inout State) -> [ANSISpan] {
        let input = state.pending.isEmpty ? input : state.pending + input
        state.pending = ""
        var spans: [ANSISpan] = []
        var current = ""
        var foreground: Int? = state.foreground
        var background: Int? = state.background
        var bold = state.bold
        defer {
            state.foreground = foreground
            state.background = background
            state.bold = bold
        }

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
            guard afterEscape < input.endIndex else {
                flush()
                state.pending = String(input[index...])   // ESC am Stückende — im nächsten weiterlesen
                return spans
            }
            guard input[afterEscape] == "[" else {
                index = afterEscape          // lone ESC — drop it
                continue
            }
            var cursor = input.index(after: afterEscape)
            var parameters = ""
            while cursor < input.endIndex, !("@"..."~").contains(input[cursor]) {
                parameters.append(input[cursor])
                cursor = input.index(after: cursor)
            }
            guard cursor < input.endIndex else {          // abgeschnittene Sequenz
                flush()
                state.pending = String(input[index...])   // ganz aufheben, nicht halb verwerfen
                return spans
            }
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
