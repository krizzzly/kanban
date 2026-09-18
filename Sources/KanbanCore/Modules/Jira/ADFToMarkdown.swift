import Foundation

/// An image referenced from an ADF document (`media` node). The markdown carries a
/// `{{IMG_<index>}}` placeholder instead of a URL — the attachment has to be fetched separately
/// (`JiraClient.attachment`), and only the caller knows where it should end up.
public struct ADFImage: Sendable, Equatable {
    public let id: String?
    public let originalName: String
    public let collection: String?
    /// `<n>-<originalName>` — the numbering keeps two attachments with the same name apart.
    public let filename: String
    public let index: Int
}

/// Ein aufgelöster Smart-Link: das, was Jira und Confluence auf ihrer Karte zeigen.
/// `chip` ist der nachgestellte Zusatz (Ticket-Status, „Kommentar"), soweit es einen gibt.
public struct SmartLinkTarget: Sendable, Equatable {
    public let label: String
    public let chip: String?

    public init(label: String, chip: String? = nil) {
        self.label = label
        self.chip = chip
    }
}

/// ADF (Atlassian Document Format) → Markdown, ported from Hermes' `lib/adf-to-markdown.js`.
///
/// Replaces the earlier `ADFFlattener`, which only concatenated text nodes: it lost every heading,
/// list, table and link — fine for a one-line preview, useless as a description.
public enum ADFToMarkdown {
    public struct Result: Sendable, Equatable {
        public let markdown: String
        public let images: [ADFImage]
    }

    /// `imageCounter` continues the numbering across several documents of one issue (description,
    /// then each comment), exactly like Hermes threads its counter through.
    ///
    /// `smartLinks` ist vorab aufgelöst (`SmartLinks.resolve`), damit der Konverter synchron bleibt.
    /// **Der Default `nil` ist die wichtige Hälfte dieser Signatur:** wer nichts übergibt, bekommt
    /// exakt das Verhalten ohne Smart-Links. Das schützt die Aufrufer, die nur lesen wollen — und
    /// vor allem `JiraSolutionField`, das sein Ergebnis über `MarkdownToADF` nach Jira zurück
    /// schreibt: dort würde eine gerenderte Karte die lebende Karte durch eingefrorenen Text ersetzen.
    public static func convert(_ adf: JSONValue, imageCounter: Int = 0,
                               smartLinks: [String: SmartLinkTarget]? = nil) -> Result {
        guard adf.value(at: ["content"]) != nil else {
            return Result(markdown: "", images: [])
        }
        var converter = Converter(counter: imageCounter, smartLinks: smartLinks)
        let text = converter.process(adf)
        return Result(markdown: text.trimmingCharacters(in: .whitespacesAndNewlines),
                      images: converter.images)
    }

    /// Convenience for a raw JSON object (what `JSONSerialization` hands back).
    public static func convert(object: [String: Any], imageCounter: Int = 0,
                               smartLinks: [String: SmartLinkTarget]? = nil) -> Result {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return Result(markdown: "", images: [])
        }
        return convert(value, imageCounter: imageCounter, smartLinks: smartLinks)
    }

    // MARK: - Walker

    private struct Converter {
        var counter: Int
        let smartLinks: [String: SmartLinkTarget]?
        var images: [ADFImage] = []

        mutating func process(_ node: JSONValue, ordinal: Int? = nil,
                              parentIndent: String = "") -> String {
            let type = node.value(at: ["type"])?.stringValue ?? ""
            let children = node.value(at: ["content"])?.arrayValue ?? []

            switch type {
            case "doc", "bulletList", "mediaSingle", "mediaGroup":
                return joined(children)

            case "orderedList":
                return children.enumerated()
                    .map { index, child in process(child, ordinal: index + 1) }
                    .joined()

            case "paragraph":
                return joined(children) + "\n\n"

            case "text":
                return marked(node)

            // Status-Lozenge aus Confluence/Jira („In Arbeit", „Hoch", „Q3 2026"). Ohne diesen
            // Fall fällt der Knoten auf "" durch, und die Zelle sieht leer aus, obwohl auf der
            // Seite ein Wert steht.
            case "status":
                return node.value(at: ["attrs", "text"])?.stringValue ?? ""

            case "mention":
                let label = (node.value(at: ["attrs", "text"])?.stringValue ?? "")
                    .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
                return "@\(label)"

            case "hardBreak":
                return "\n"

            case "listItem":
                return listItem(children, ordinal: ordinal, parentIndent: parentIndent)

            // Confluence-Checkboxen. Eine verschachtelte Liste kommt als **Geschwister** im
            // Eltern-`taskList` an, nicht als Kind eines `taskItem` — deshalb wird die Einrückung
            // hier vergeben und nicht beim Punkt.
            case "taskList":
                let items = children.map { child -> String in
                    let nested = child.value(at: ["type"])?.stringValue == "taskList"
                    return process(child, parentIndent: nested ? parentIndent + "  " : parentIndent)
                }.joined()
                // Die oberste Liste schliesst mit einer Leerzeile, sonst klebt die nächste
                // Überschrift an der letzten Checkbox.
                return parentIndent.isEmpty ? items + "\n" : items

            case "taskItem":
                let box = node.value(at: ["attrs", "state"])?.stringValue == "DONE" ? "[x]" : "[ ]"
                let label = joined(children).trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(parentIndent)- \(box) \(label)\n"

            case "heading":
                let level = node.value(at: ["attrs", "level"])?.intValue ?? 1
                return String(repeating: "#", count: level) + " " + joined(children) + "\n\n"

            case "codeBlock":
                let language = node.value(at: ["attrs", "language"])?.stringValue ?? ""
                let code = children.compactMap { $0.value(at: ["text"])?.stringValue }.joined()
                return "```\(language)\n\(code)\n```\n\n"

            case "blockquote":
                return joined(children)
                    .components(separatedBy: "\n")
                    .map { "> " + $0 }
                    .joined(separator: "\n") + "\n"

            case "rule":
                return "---\n\n"

            case "media":
                return media(node)

            case "table":
                return table(children)

            case "tableRow":
                return "| " + children.map { process($0) }.joined(separator: " | ") + " |\n"

            case "tableCell", "tableHeader":
                return cell(children)

            case "inlineCard":
                return card(node)

            case "blockCard", "embedCard":
                return card(node) + "\n\n"

            default:
                return joined(children)
            }
        }

        private mutating func joined(_ nodes: [JSONValue]) -> String {
            nodes.map { process($0) }.joined()
        }

        /// Text marks, in Hermes' order — several can sit on one node (`**\`code\`**`).
        private func marked(_ node: JSONValue) -> String {
            var text = node.value(at: ["text"])?.stringValue ?? ""
            for mark in node.value(at: ["marks"])?.arrayValue ?? [] {
                let type = mark.value(at: ["type"])?.stringValue ?? ""
                switch type {
                case "strong": text = "**\(text)**"
                case "em": text = "*\(text)*"
                case "strike": text = "~~\(text)~~"
                case "code": text = "`\(text)`"
                case "underline": text = "<u>\(text)</u>"
                case "link":
                    let href = mark.value(at: ["attrs", "href"])?.stringValue ?? ""
                    // Ein Link, dessen sichtbarer Text die URL selbst ist, ist derselbe Fall wie
                    // eine Karte. Ein Link mit eigenem Text bleibt, wie er ist — den hat jemand
                    // bewusst so beschriftet.
                    if !href.isEmpty,
                       text.trimmingCharacters(in: .whitespaces) == href.trimmingCharacters(in: .whitespaces),
                       smartLinks?[href] != nil {
                        text = renderCard(href)
                    } else {
                        text = "[\(text)](\(href))"
                    }
                case "subsup":
                    let kind = mark.value(at: ["attrs", "type"])?.stringValue
                    if kind == "sub" { text = "<sub>\(text)</sub>" }
                    if kind == "sup" { text = "<sup>\(text)</sup>" }
                case "textColor":
                    if let color = mark.value(at: ["attrs", "color"])?.stringValue {
                        text = "<span style=\"color:\(color)\">\(text)</span>"
                    }
                default: break
                }
            }
            return text
        }

        private mutating func listItem(_ children: [JSONValue], ordinal: Int?,
                                       parentIndent: String) -> String {
            let prefix = ordinal.map { "\($0). " } ?? "- "
            let childIndent = parentIndent + String(repeating: " ", count: prefix.count)

            var content = ""
            for child in children {
                let type = child.value(at: ["type"])?.stringValue ?? ""
                let grandchildren = child.value(at: ["content"])?.arrayValue ?? []
                switch type {
                case "paragraph":
                    content += joined(grandchildren)
                case "bulletList", "orderedList":
                    let ordered = type == "orderedList"
                    content += "\n" + grandchildren.enumerated().map { index, item in
                        process(item, ordinal: ordered ? index + 1 : nil, parentIndent: childIndent)
                    }.joined()
                default:
                    content += process(child)
                }
            }
            let trimmed = content.replacingOccurrences(of: "\n+$", with: "", options: .regularExpression)
            return parentIndent + prefix + trimmed + "\n"
        }

        private mutating func media(_ node: JSONValue) -> String {
            guard node.value(at: ["attrs"]) != nil else { return "" }
            let id = node.value(at: ["attrs", "id"])?.stringValue
            let originalName = node.value(at: ["attrs", "alt"])?.stringValue ?? "\(id ?? "media").png"
            let filename = "\(counter + 1)-\(originalName)"
            images.append(ADFImage(id: id, originalName: originalName,
                                   collection: node.value(at: ["attrs", "collection"])?.stringValue,
                                   filename: filename, index: counter))
            let markdown = "\n![\(filename)]({{IMG_\(counter)}})\n"
            counter += 1
            return markdown
        }

        /// Markdown needs a separator after the first row — emitted even when the source uses
        /// `tableCell` throughout, because some Jira authors style the header row visually instead.
        private mutating func table(_ rows: [JSONValue]) -> String {
            var result = "\n"
            for (index, row) in rows.enumerated() {
                result += process(row)
                if index == 0 {
                    let columns = row.value(at: ["content"])?.arrayValue?.count ?? 0
                    result += "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |\n"
                }
            }
            return result + "\n"
        }

        /// A cell is one line: blocks joined with `<br>`, newlines flattened, pipes escaped.
        private mutating func cell(_ children: [JSONValue]) -> String {
            var parts: [String] = []
            for child in children {
                let type = child.value(at: ["type"])?.stringValue ?? ""
                switch type {
                case "paragraph":
                    let text = joined(child.value(at: ["content"])?.arrayValue ?? [])
                    if !text.isEmpty { parts.append(text) }
                case "heading":
                    // Eine Zelle ist Inline-Kontext: `#### x` ist dort keine Überschrift, sondern
                    // der wörtliche Text „#### x“ (so in PhpStorm gesehen). Fett hält die
                    // Hervorhebung fest, die der Autor gemeint hat.
                    let text = joined(child.value(at: ["content"])?.arrayValue ?? [])
                    if !text.isEmpty { parts.append("**\(text)**") }
                case "bulletList", "orderedList":
                    let ordered = type == "orderedList"
                    if Self.hasNestedList(child) { parts.append(htmlList(child, ordered: ordered)) }
                    else { parts.append(contentsOf: flattenList(child, ordered: ordered)) }
                default:
                    let rendered = process(child).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rendered.isEmpty { parts.append(rendered) }
                }
            }
            return parts.joined(separator: " <br> ")
                .replacingOccurrences(of: "\n+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "|", with: "\\|")
                .trimmingCharacters(in: .whitespaces)
        }

        /// Eine Tabellenzelle ist **eine Zeile** — eine echte Markdown-Liste würde die Zeile
        /// sprengen. Zwei Wege, und welcher richtig ist, hängt daran, ob Verschachtelung im Spiel ist:
        ///
        ///   flach         → `- a <br> - b`      die Rohdatei bleibt lesbar
        ///   verschachtelt → inline `<ul>/<ol>`  Struktur statt Verabredung
        ///
        /// Nur der HTML-Weg trägt die Ebene wirklich: die Zelle wird mit ` <br> ` zusammengefügt,
        /// also inline — Einrückung fällt beim Rendern weg, und ein Ebenen-Zeichen wie „◦" bleibt
        /// eine Verabredung, die der Leser kennen muss. Markdown **innerhalb** der Tags wird weiter
        /// gerendert (Links, `**fett**`, `` `code` ``, escapte Pipes — gegen cmark-gfm geprüft).
        static func hasNestedList(_ list: JSONValue) -> Bool {
            (list.value(at: ["content"])?.arrayValue ?? []).contains { item in
                (item.value(at: ["content"])?.arrayValue ?? []).contains { child in
                    let type = child.value(at: ["type"])?.stringValue ?? ""
                    return type == "bulletList" || type == "orderedList"
                }
            }
        }

        private mutating func htmlList(_ list: JSONValue, ordered: Bool) -> String {
            let tag = ordered ? "ol" : "ul"
            var items = ""
            for item in list.value(at: ["content"])?.arrayValue ?? [] {
                var nested = ""
                for child in item.value(at: ["content"])?.arrayValue ?? [] {
                    let type = child.value(at: ["type"])?.stringValue ?? ""
                    if type == "bulletList" || type == "orderedList" {
                        nested += htmlList(child, ordered: type == "orderedList")
                    }
                }
                // Ein Punkt ohne Text und ohne Unterliste ist ein Phantom-Aufzählungszeichen
                // (kommt vor, wenn die Zeile nur einen Knoten trägt, der hier zu nichts rendert).
                // Der flache Weg lässt solche Punkte ebenfalls weg.
                let text = itemText(item).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty || !nested.isEmpty { items += "<li>\(text)\(nested)</li>" }
            }
            return "<\(tag)>\(items)</\(tag)>"
        }

        /// Flache Liste in einer Zelle: eine Zeile je Punkt. Verschachteltes kommt hier nicht an,
        /// das geht über `htmlList`.
        private mutating func flattenList(_ list: JSONValue, ordered: Bool) -> [String] {
            var items: [String] = []
            for (index, item) in (list.value(at: ["content"])?.arrayValue ?? []).enumerated() {
                let text = itemText(item)
                if !text.isEmpty { items.append((ordered ? "\(index + 1). " : "- ") + text) }
            }
            return items
        }

        /// Der Text eines Listenpunkts ohne seine Unterlisten.
        private mutating func itemText(_ item: JSONValue) -> String {
            var texts: [String] = []
            for child in item.value(at: ["content"])?.arrayValue ?? [] {
                let type = child.value(at: ["type"])?.stringValue ?? ""
                if type == "paragraph" {
                    let text = joined(child.value(at: ["content"])?.arrayValue ?? [])
                    if !text.isEmpty { texts.append(text) }
                } else if type != "bulletList" && type != "orderedList" {
                    let text = process(child).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { texts.append(text) }
                }
            }
            return texts.joined(separator: " ")
        }

        private func card(_ node: JSONValue) -> String {
            renderCard(node.value(at: ["attrs", "url"])?.stringValue ?? "")
        }

        /// So, wie Jira und Confluence die Karte zeigen: Titel statt URL, Status bzw. Typ als
        /// nachgestellter Chip. Ohne aufgelösten Eintrag bleibt es beim Key/Slug aus der URL.
        private func renderCard(_ url: String) -> String {
            let resolved = smartLinks?[url]
            let label = resolved?.label ?? ADFToMarkdown.cardLabel(url)
            let link = "[\(ADFToMarkdown.escapeLinkText(label))](\(url))"
            guard let chip = resolved?.chip else { return link }
            return "\(link) `\(chip)`"
        }
    }

    /// Eckige Klammern im Label zerlegen das Markdown-Link-Konstrukt — ein Seitentitel wie
    /// „[Entwurf] Konzept" bringt sie mit.
    static func escapeLinkText(_ label: String) -> String {
        label.replacingOccurrences(of: #"([\[\]])"#, with: #"\\$1"#, options: .regularExpression)
    }

    /// A readable label for a smart link: the ticket key for Jira, the page title for Confluence,
    /// the bare URL for anything else.
    static func cardLabel(_ url: String) -> String {
        guard !url.isEmpty else { return "" }
        if let match = url.range(of: #"/browse/([A-Z][A-Z0-9_]+-\d+)"#, options: .regularExpression) {
            return String(url[match]).replacingOccurrences(of: "/browse/", with: "")
        }
        if let match = url.range(of: #"/pages/\d+/([^?#]+)"#, options: .regularExpression) {
            let tail = String(url[match]).replacingOccurrences(of: #"^/pages/\d+/"#, with: "",
                                                               options: .regularExpression)
            return (tail.removingPercentEncoding ?? tail).replacingOccurrences(of: "+", with: " ")
        }
        return url
    }
}
