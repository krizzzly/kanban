import Foundation

/// The languages the commit dialog highlights. Detected from the file extension, since that is all the
/// diff gives us.
public enum CodeLanguage: String, Sendable, CaseIterable {
    case php, javascript, css, twig, html, json, yaml, markdown, swift, sql, plain

    public static func detect(path: String) -> CodeLanguage {
        let name = (path as NSString).lastPathComponent.lowercased()
        // Twig templates are `*.html.twig` — check before the plain `.html` mapping.
        if name.hasSuffix(".twig") { return .twig }
        switch (name as NSString).pathExtension {
        case "php", "phtml": return .php
        case "js", "jsx", "mjs", "cjs", "ts", "tsx": return .javascript
        case "css", "scss", "sass", "less": return .css
        case "html", "htm", "vue": return .html
        case "json": return .json
        case "yml", "yaml": return .yaml
        case "md", "markdown": return .markdown
        case "swift": return .swift
        case "sql": return .sql
        default: return .plain
        }
    }
}

/// One highlighted range of source text.
public struct SyntaxToken: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case comment, string, keyword, number, variable, tag, attribute, type
    }

    public let range: NSRange
    public let kind: Kind

    public init(range: NSRange, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

/// A small, dependency-free highlighter: comments and strings first (they win over everything), then
/// keywords, numbers, variables and markup on what is left.
///
/// Deliberately lexical, not a parser — it must survive half-typed code in the editor and diff
/// fragments that start mid-file. Overlaps are resolved by "first match wins", so a keyword inside a
/// string is never re-coloured.
public enum SyntaxHighlighter {
    public static func tokens(in text: String, language: CodeLanguage) -> [SyntaxToken] {
        guard language != .plain, !text.isEmpty else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var taken = IndexSet()
        var tokens: [SyntaxToken] = []

        func add(_ patterns: [String], _ kind: SyntaxToken.Kind, options: NSRegularExpression.Options = []) {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
                regex.enumerateMatches(in: text, range: full) { match, _, _ in
                    guard let range = match?.range, range.length > 0 else { return }
                    let indices = IndexSet(integersIn: range.location..<(range.location + range.length))
                    guard taken.intersection(indices).isEmpty else { return }   // erster Treffer gewinnt
                    taken.formUnion(indices)
                    tokens.append(SyntaxToken(range: range, kind: kind))
                }
            }
        }

        // 0. PHP attributes before everything: `#[ORM\Column(...)]` must not be read as a `#` comment.
        //    Only the `#[Name` part is claimed — die Argumente werden normal weitergefärbt.
        if language == .php {
            add([#"#\[\\?[A-Za-z_][A-Za-z0-9_\\]*"#], .attribute)
        }

        // 1. Comments and strings claim their text before anything else can.
        add(commentPatterns(language), .comment, options: [.dotMatchesLineSeparators])
        add(stringPatterns(language), .string, options: [])

        // 2. Markup: tag names and attributes (HTML/JSX/Twig).
        if language == .html || language == .twig || language == .javascript {
            add([#"</?[A-Za-z][A-Za-z0-9._:-]*"#, #"/?>"#], .tag)
            add([#"[A-Za-z_:][A-Za-z0-9_.:-]*(?=\s*=)"#], .attribute)
        }
        if language == .twig {
            add([#"\{[%{#]|[%}#]\}"#], .tag)
        }

        // 3. Variables: PHP `$foo`, Twig/CSS custom properties.
        if language == .php { add([#"\$[A-Za-z_][A-Za-z0-9_]*"#], .variable) }
        if language == .css {
            // Hex-Farben vor den Selektoren: `#ff5f56` hat in CSS dieselbe Form wie ein ID-Selektor,
            // und in einer Deklaration ist es fast immer die Farbe.
            add([#"#[0-9A-Fa-f]{3,8}\b"#], .number)
            add([#"--[A-Za-z0-9_-]+"#, #"[.#][A-Za-z_][A-Za-z0-9_-]*"#], .variable)
        }
        if language == .yaml { add([#"^\s*[A-Za-z_][A-Za-z0-9_.-]*(?=\s*:)"#], .attribute, options: [.anchorsMatchLines]) }
        if language == .json { add([#""[^"\\]*(?:\\.[^"\\]*)*"(?=\s*:)"#], .attribute) }

        // 4. Keywords and types.
        let words = keywords(language)
        if !words.isEmpty {
            add(["\\b(?:" + words.joined(separator: "|") + ")\\b"], .keyword)
        }
        if language == .css {
            add([#"[A-Za-z-]+(?=\s*:)"#], .keyword)
        }

        // 5. Numbers last — everything more specific already claimed its text.
        add([#"\b\d+(?:\.\d+)?(?:[a-z%]{1,4})?\b"#, #"#[0-9A-Fa-f]{3,8}\b"#], .number)

        return tokens.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Language configuration

    private static func commentPatterns(_ language: CodeLanguage) -> [String] {
        switch language {
        // `#(?!\[)`: PHP-8-Attribute (`#[ORM\Column]`) sind **keine** Kommentare — ohne den
        // Lookahead verschluckt die Kommentarregel jede Annotation und färbt sie grau.
        case .php:        return [#"/\*.*?\*/"#, #"//[^\n]*"#, #"#(?!\[)[^\n]*"#]
        case .javascript, .css, .swift:
                          return [#"/\*.*?\*/"#, #"//[^\n]*"#]
        case .html:       return [#"<!--.*?-->"#]
        case .twig:       return [#"\{#.*?#\}"#, #"<!--.*?-->"#]
        case .yaml:       return [#"#[^\n]*"#]
        case .sql:        return [#"--[^\n]*"#, #"/\*.*?\*/"#]
        case .markdown, .json, .plain: return []
        }
    }

    private static func stringPatterns(_ language: CodeLanguage) -> [String] {
        switch language {
        case .json, .yaml:
            return [#""[^"\\]*(?:\\.[^"\\]*)*""#, #"'[^'\\]*(?:\\.[^'\\]*)*'"#]
        case .markdown, .plain:
            return [#"`[^`\n]*`"#]
        case .javascript:
            return [#""[^"\\]*(?:\\.[^"\\]*)*""#, #"'[^'\\]*(?:\\.[^'\\]*)*'"#, #"`[^`\\]*(?:\\.[^`\\]*)*`"#]
        default:
            return [#""[^"\\]*(?:\\.[^"\\]*)*""#, #"'[^'\\]*(?:\\.[^'\\]*)*'"#]
        }
    }

    private static func keywords(_ language: CodeLanguage) -> [String] {
        switch language {
        case .php:
            return ["abstract", "as", "break", "callable", "case", "catch", "class", "clone", "const",
                    "continue", "declare", "default", "do", "echo", "else", "elseif", "enum", "extends",
                    "final", "finally", "fn", "for", "foreach", "function", "global", "if", "implements",
                    "instanceof", "interface", "match", "namespace", "new", "private", "protected",
                    "public", "readonly", "return", "static", "switch", "throw", "trait", "try", "use",
                    "var", "while", "yield", "true", "false", "null", "array", "string", "int", "bool",
                    "float", "void", "self", "parent", "this"]
        case .javascript:
            return ["as", "async", "await", "break", "case", "catch", "class", "const", "continue",
                    "default", "delete", "do", "else", "export", "extends", "finally", "for", "from",
                    "function", "if", "import", "in", "instanceof", "let", "new", "of", "return",
                    "static", "super", "switch", "this", "throw", "try", "typeof", "var", "void",
                    "while", "yield", "true", "false", "null", "undefined"]
        case .twig:
            return ["and", "as", "block", "do", "else", "elseif", "endblock", "endfor", "endif",
                    "endmacro", "endset", "extends", "for", "if", "import", "in", "include", "is",
                    "macro", "not", "or", "set", "use", "with", "true", "false", "null"]
        case .swift:
            return ["associatedtype", "class", "deinit", "enum", "extension", "func", "import", "init",
                    "let", "protocol", "struct", "subscript", "typealias", "var", "case", "default",
                    "defer", "do", "else", "for", "guard", "if", "in", "repeat", "return", "switch",
                    "where", "while", "as", "catch", "false", "is", "nil", "self", "super", "throw",
                    "throws", "true", "try", "async", "await", "private", "public", "internal", "static"]
        case .sql:
            return ["ALTER", "AND", "AS", "BY", "CREATE", "DELETE", "DROP", "FROM", "GROUP", "HAVING",
                    "INNER", "INSERT", "INTO", "JOIN", "LEFT", "LIMIT", "NOT", "NULL", "ON", "OR",
                    "ORDER", "SELECT", "SET", "TABLE", "UPDATE", "VALUES", "WHERE"]
        case .yaml:
            return ["true", "false", "null", "yes", "no"]
        case .css, .html, .json, .markdown, .plain:
            return []
        }
    }
}
