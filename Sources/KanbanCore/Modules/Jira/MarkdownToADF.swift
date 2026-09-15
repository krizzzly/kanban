import Foundation

/// Markdown → ADF, der Schreibweg zu Jiras Rich-Text-Feldern (`description`, textarea-Customfields
/// wie „Lösung"). Der Gegenweg ist `ADFToMarkdown`; beide Richtungen werden gegeneinander getestet.
///
/// Bewusst **kein** vollständiger Markdown-Parser: umgesetzt ist, was in einem Lösungstext vorkommt —
/// Überschriften, Absätze, Listen (auch verschachtelt, geordnet und ungeordnet), Codeblöcke,
/// Zitate, horizontale Linien und die Inline-Auszeichnungen `**fett**`, `*kursiv*`, `` `code` ``,
/// `~~durch~~` und `[Text](url)`. Tabellen bleiben als Text stehen: Jiras Tabellen-ADF verlangt
/// Zellbreiten und Layout-Attribute, die aus Markdown nicht ableitbar sind — lieber ein lesbarer
/// Absatz als eine kaputte Tabelle.
public enum MarkdownToADF {
    /// Das ADF-Dokument zu einem Markdown-Text. Leerer Text → leeres `doc` (Jira löscht damit das
    /// Feld, was der ehrliche Weg ist: ein Feld leeren heisst nicht, ein leeres Absatz-Array zu
    /// schicken).
    public static func convert(_ markdown: String) -> JSONValue {
        let blocks = parseBlocks(markdown.replacingOccurrences(of: "\r\n", with: "\n"))
        return .object([
            "type": .string("doc"),
            "version": .int(1),
            "content": .array(blocks),
        ])
    }

    // MARK: - Blöcke

    private static func parseBlocks(_ text: String) -> [JSONValue] {
        var lines = text.components(separatedBy: "\n")[...]
        var blocks: [JSONValue] = []

        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                lines = lines.dropFirst()
                continue
            }

            // Codeblock: ```lang … ```
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                lines = lines.dropFirst()
                var code: [String] = []
                while let next = lines.first, !next.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(next)
                    lines = lines.dropFirst()
                }
                if lines.first != nil { lines = lines.dropFirst() }   // schliessende Zäunung
                blocks.append(codeBlock(code.joined(separator: "\n"), language: language))
                continue
            }

            // Überschrift: # … ######
            if let heading = headingLevel(trimmed) {
                let content = String(trimmed.dropFirst(heading)).trimmingCharacters(in: .whitespaces)
                blocks.append(.object([
                    "type": .string("heading"),
                    "attrs": .object(["level": .int(min(heading, 6))]),
                    "content": .array(inline(content)),
                ]))
                lines = lines.dropFirst()
                continue
            }

            // Horizontale Linie
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.object(["type": .string("rule")]))
                lines = lines.dropFirst()
                continue
            }

            // Zitat: > …
            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while let next = lines.first,
                      next.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let body = next.trimmingCharacters(in: .whitespaces).dropFirst()
                    quoted.append(String(body).trimmingCharacters(in: .whitespaces))
                    lines = lines.dropFirst()
                }
                blocks.append(.object([
                    "type": .string("blockquote"),
                    "content": .array(parseBlocks(quoted.joined(separator: "\n"))),
                ]))
                continue
            }

            // Liste: sammelt alle zusammenhängenden Listenzeilen inklusive Einrückung
            if listMarker(line) != nil {
                var items: [String] = []
                while let next = lines.first, listMarker(next) != nil || isContinuation(next) {
                    items.append(next)
                    lines = lines.dropFirst()
                }
                blocks.append(list(from: items))
                continue
            }

            // Absatz: bis zur nächsten Leerzeile oder einem anderen Blockanfang
            var paragraph: [String] = []
            while let next = lines.first {
                let t = next.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || headingLevel(t) != nil || t.hasPrefix("```") || t.hasPrefix(">")
                    || listMarker(next) != nil || t == "---" { break }
                paragraph.append(t)
                lines = lines.dropFirst()
            }
            if !paragraph.isEmpty {
                // Weiche Umbrüche innerhalb eines Absatzes bleiben als hardBreak erhalten.
                blocks.append(.object([
                    "type": .string("paragraph"),
                    "content": .array(inlineWithBreaks(paragraph)),
                ]))
            }
        }
        return blocks
    }

    private static func codeBlock(_ code: String, language: String) -> JSONValue {
        var node: [String: JSONValue] = ["type": .string("codeBlock")]
        if !language.isEmpty { node["attrs"] = .object(["language": .string(language)]) }
        if !code.isEmpty { node["content"] = .array([.object(["type": .string("text"),
                                                             "text": .string(code)])]) }
        return .object(node)
    }

    private static func headingLevel(_ trimmed: String) -> Int? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes <= 6, trimmed.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return hashes
    }

    // MARK: - Listen

    /// Einrückung und Art einer Listenzeile, oder nil wenn es keine ist.
    static func listMarker(_ line: String) -> (indent: Int, ordered: Bool, content: String)? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
            .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let rest = line.drop(while: { $0 == " " || $0 == "\t" })
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            return (indent, false, String(rest.dropFirst(2)))
        }
        // "1. " / "12) "
        let digits = rest.prefix(while: \.isNumber)
        if !digits.isEmpty {
            let after = rest.dropFirst(digits.count)
            if after.hasPrefix(". ") || after.hasPrefix(") ") {
                return (indent, true, String(after.dropFirst(2)))
            }
        }
        return nil
    }

    /// Fortsetzungszeile eines Listenpunkts (eingerückt, aber selbst kein Marker).
    private static func isContinuation(_ line: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return line.hasPrefix("  ") || line.hasPrefix("\t")
    }

    /// Baut aus den gesammelten Zeilen eine (ggf. verschachtelte) Liste.
    private static func list(from lines: [String]) -> JSONValue {
        var index = 0
        return buildList(lines, &index, indent: listMarker(lines[0])?.indent ?? 0)
    }

    private static func buildList(_ lines: [String], _ index: inout Int, indent: Int) -> JSONValue {
        let ordered = listMarker(lines[index])?.ordered ?? false
        var items: [JSONValue] = []

        while index < lines.count {
            guard let marker = listMarker(lines[index]) else {
                // Fortsetzungszeile: an den letzten Punkt anhängen.
                index += 1
                continue
            }
            if marker.indent < indent { break }
            if marker.indent > indent {
                // Tiefere Ebene → als eigene Liste in den letzten Punkt hängen.
                let nested = buildList(lines, &index, indent: marker.indent)
                if let last = items.popLast(), var node = last.objectValue,
                   var content = node["content"]?.arrayValue {
                    content.append(nested)
                    node["content"] = .array(content)
                    items.append(.object(node))
                } else {
                    items.append(.object(["type": .string("listItem"), "content": .array([nested])]))
                }
                continue
            }
            if marker.ordered != ordered { break }   // Art wechselt → neue Liste

            items.append(.object([
                "type": .string("listItem"),
                "content": .array([.object(["type": .string("paragraph"),
                                            "content": .array(inline(marker.content))])]),
            ]))
            index += 1
        }

        var node: [String: JSONValue] = [
            "type": .string(ordered ? "orderedList" : "bulletList"),
            "content": .array(items),
        ]
        if ordered { node["attrs"] = .object(["order": .int(1)]) }
        return .object(node)
    }

    // MARK: - Inline

    /// Absatzzeilen mit `hardBreak` dazwischen — so bleibt ein weicher Umbruch sichtbar.
    private static func inlineWithBreaks(_ lines: [String]) -> [JSONValue] {
        var nodes: [JSONValue] = []
        for (offset, line) in lines.enumerated() {
            if offset > 0 { nodes.append(.object(["type": .string("hardBreak")])) }
            nodes.append(contentsOf: inline(line))
        }
        return nodes
    }

    /// Zerlegt eine Zeile in Textknoten mit Marks. Reihenfolge der Muster ist Absicht: `**` vor `*`,
    /// sonst würde fett als zweimal kursiv gelesen.
    static func inline(_ text: String) -> [JSONValue] {
        guard !text.isEmpty else { return [] }
        let patterns: [(String, (String) -> [JSONValue])] = [
            (#"\[([^\]]+)\]\(([^)]+)\)"#, { _ in [] }),   // Link, Sonderfall unten
            (#"\*\*([^*]+)\*\*"#, { text in [textNode(text, marks: ["strong"])] }),
            (#"~~([^~]+)~~"#, { text in [textNode(text, marks: ["strike"])] }),
            (#"`([^`]+)`"#, { text in [textNode(text, marks: ["code"])] }),
            (#"(?<![*\w])\*([^*]+)\*(?!\*)"#, { text in [textNode(text, marks: ["em"])] }),
        ]

        // Erstes Vorkommen irgendeines Musters suchen und links/rechts rekursiv weiterarbeiten.
        var earliest: (range: NSRange, index: Int, match: NSTextCheckingResult)?
        let ns = text as NSString
        for (index, pattern) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: pattern.0),
                  let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
            else { continue }
            if earliest == nil || match.range.location < earliest!.range.location {
                earliest = (match.range, index, match)
            }
        }

        guard let hit = earliest else { return [textNode(text, marks: [])] }

        var nodes: [JSONValue] = []
        if hit.range.location > 0 {
            nodes += inline(ns.substring(to: hit.range.location))
        }
        if hit.index == 0 {   // Link
            let label = ns.substring(with: hit.match.range(at: 1))
            let href = ns.substring(with: hit.match.range(at: 2))
            nodes.append(.object([
                "type": .string("text"),
                "text": .string(label),
                "marks": .array([.object(["type": .string("link"),
                                          "attrs": .object(["href": .string(href)])])]),
            ]))
        } else {
            nodes += patterns[hit.index].1(ns.substring(with: hit.match.range(at: 1)))
        }
        let tailStart = hit.range.location + hit.range.length
        if tailStart < ns.length {
            nodes += inline(ns.substring(from: tailStart))
        }
        return nodes
    }

    private static func textNode(_ text: String, marks: [String]) -> JSONValue {
        var node: [String: JSONValue] = ["type": .string("text"), "text": .string(text)]
        if !marks.isEmpty {
            node["marks"] = .array(marks.map { .object(["type": .string($0)]) })
        }
        return .object(node)
    }
}
