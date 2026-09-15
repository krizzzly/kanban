import Foundation

/// Rückweg zu `MarkdownHTML`: das HTML eines `contenteditable`-Editors zurück nach Markdown.
///
/// Der Kreis, den der Lösungs-Editor läuft, ist **Markdown → HTML → (tippen) → Markdown → ADF**.
/// Erste und letzte Station gab es schon (`MarkdownHTML`, `MarkdownToADF`); das hier ist die dritte.
/// Deshalb ist das Ziel-Vokabular **nicht** „alles, was HTML kann", sondern genau das, was
/// `MarkdownToADF` in ADF-Knoten übersetzen kann: Überschriften, Absätze, Listen (verschachtelt,
/// geordnet), Codeblöcke, Zitate, Linien und die Marks `**fett**`, `*kursiv*`, `` `code` ``,
/// `~~weg~~`, `[Text](url)`. Alles andere wird **entpackt statt weggeworfen** — ein unbekanntes
/// Inline-Element gibt seinen Text her, ein unbekanntes Block-Element seine Kinder.
///
/// Geparst wird mit `XMLDocument(options: .documentTidyHTML)` — Foundations eigener HTML-Tidy. Kein
/// Fremdcode, und er verträgt genau das, was ein `contenteditable` produziert: nackte `<div>`s,
/// `<br>`, `<b>` statt `<strong>`, `style`-Attribute, `&nbsp;`, unvollständig geschlossene Tags.
///
/// **Kein Backslash-Escaping**, mit Absicht: `MarkdownToADF` kennt kein `\*`, ein escapetes Zeichen
/// stünde also als Backslash in Jira. Preis: ein Absatz, der mit „- " oder „# " anfängt, wird beim
/// nächsten Umlauf als Liste bzw. Überschrift gelesen. Das ist sichtbar (die Formatierung springt im
/// Editor) und über die Markdown-Ansicht korrigierbar — ein Backslash im Jira-Feld wäre es nicht.
public enum HTMLToMarkdown {
    public static func convert(_ html: String) -> String {
        guard let data = wrapped(html).data(using: .utf8),
              let document = try? XMLDocument(data: data, options: [.documentTidyHTML])
        else {
            // Tidy scheitert an einem Fragment ganz ohne Tags — dann ist der rohe Text schon das
            // Ergebnis, und ihn durchzulassen ist besser als ein leeres Feld.
            return html.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let body = document.rootElement()?.elements(forName: "body").first else {
            return ""   // geparst, aber ohne Inhalt (`<p></p>`) — kein Text, kein Fehler
        }
        return blocks(in: body, depth: 0)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Legt den Inhalt in ein Dokument mit **ausdrücklicher UTF-8-Angabe** — immer, und immer in
    /// der `http-equiv`-Form.
    ///
    /// Zwei Fallen, beide gemessen, beide lautlos:
    ///  1. **Ohne** Angabe liest Tidy die Bytes als Latin-1 und wirft weg, was es nicht kennt: aus
    ///     „Gebäude — Rücksprache" wurde „Gebude  Rcksprache".
    ///  2. Ein HTML5-`<meta charset="utf-8">` **reicht nicht** — Tidy beachtet es nicht und liefert
    ///     Mojibake („GrÃ¶ÃŸe"). Nur `<meta http-equiv="Content-Type" …>` greift.
    ///
    /// Deshalb wird ein vollständiges Dokument auf seinen Body reduziert und wie ein Fragment neu
    /// eingepackt, statt seiner eigenen Angabe zu vertrauen. Gefangen hat beides der
    /// Rundreise-Test, nicht das Auge.
    static func wrapped(_ html: String) -> String {
        "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">"
            + "</head><body>" + bodyContent(html) + "</body></html>"
    }

    /// Inhalt zwischen `<body …>` und `</body>`, falls vorhanden — sonst das Fragment selbst.
    private static func bodyContent(_ html: String) -> String {
        let lower = html.lowercased()
        guard let openStart = lower.range(of: "<body"),
              let openEnd = html[openStart.upperBound...].firstIndex(of: ">"),
              let close = lower.range(of: "</body>", options: .backwards)
        else { return html }
        let start = html.index(after: openEnd)
        guard start <= close.lowerBound else { return html }
        return String(html[start..<close.lowerBound])
    }

    // MARK: - Blöcke

    /// Block-Elemente. `div` ist dabei, weil ein `contenteditable` Absätze gern als `div` ablegt.
    private static let blockNames: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "blockquote",
        "pre", "hr", "table", "section", "article", "header", "footer", "figure", "figcaption",
    ]

    /// Elemente, deren Inhalt **kein Text** ist. Ohne diese Liste landet ein `<style>`-Block aus
    /// eingefügtem Browser-Inhalt als Absatz voller CSS im Jira-Feld — und ein `<script>` sogar mit
    /// seinem ganzen Quelltext.
    private static let skipNames: Set<String> = ["script", "style", "noscript", "template", "head"]

    static func blocks(in element: XMLElement, depth: Int) -> [String] {
        var out: [String] = []
        var pending: [XMLNode] = []      // lose Inline-Knoten → impliziter Absatz

        func flushParagraph() {
            guard !pending.isEmpty else { return }
            let text = paragraph(inline(pending))
            if !text.isEmpty { out.append(text) }
            pending = []
        }

        for child in element.children ?? [] {
            if let el = child as? XMLElement, skipNames.contains(el.name?.lowercased() ?? "") {
                continue
            }
            if let el = child as? XMLElement, blockNames.contains(el.name?.lowercased() ?? "") {
                flushParagraph()
                out.append(contentsOf: block(el, depth: depth))
            } else {
                pending.append(child)
            }
        }
        flushParagraph()
        return out
    }

    private static func block(_ element: XMLElement, depth: Int) -> [String] {
        let name = element.name?.lowercased() ?? ""
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(name.dropFirst()) ?? 2
            let text = paragraph(inline(element.children ?? []))
            return text.isEmpty ? [] : [String(repeating: "#", count: level) + " " + text]

        case "p", "div":
            // Ein `div` kann selbst wieder Blöcke enthalten (verschachtelte contenteditable-Struktur).
            if (element.children ?? []).contains(where: {
                ($0 as? XMLElement).map { blockNames.contains($0.name?.lowercased() ?? "") } ?? false
            }) {
                return blocks(in: element, depth: depth)
            }
            let text = paragraph(inline(element.children ?? []))
            return text.isEmpty ? [] : [text]

        case "hr":
            return ["---"]

        case "ul", "ol":
            let lines = listLines(element, depth: depth)
            return lines.isEmpty ? [] : [lines.joined(separator: "\n")]

        case "blockquote":
            // WebKit benutzt ein randloses `<blockquote>` als **Einrückung** (`execCommand('indent')`
            // ausserhalb einer Liste, und so kommt auch eingefügter Browser-Inhalt daher). Ein Zitat
            // hat es nie gemeint — also entpacken statt „> " davorzuschreiben.
            if (element.attribute(forName: "style")?.stringValue ?? "")
                .replacingOccurrences(of: " ", with: "").contains("border:none") {
                return blocks(in: element, depth: depth)
            }
            let inner = blocks(in: element, depth: depth)
            guard !inner.isEmpty else { return [] }
            // Auch die Trennzeile zwischen zwei Blöcken im Zitat braucht ihr „>", sonst endet das
            // Zitat dort: `MarkdownToADF` sammelt genau die zusammenhängenden `>`-Zeilen.
            let quoted = inner.map { block in
                block.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
            }
            return [quoted.joined(separator: "\n>\n")]

        case "pre":
            let code = rawText(element).replacingOccurrences(of: "\u{00A0}", with: " ")
            let trimmed = code.hasSuffix("\n") ? String(code.dropLast()) : code
            return ["```" + language(of: element) + "\n" + trimmed + "\n```"]

        default:
            // Tabellen und anderes Unbekanntes: Inhalt retten, Struktur fällt weg — `MarkdownToADF`
            // schreibt Tabellen ohnehin als Text (Jiras Tabellen-ADF braucht Zell-Attribute).
            return blocks(in: element, depth: depth)
        }
    }

    /// `<pre class="language-swift">` oder `<pre><code class="language-swift">` — so schreibt cmark
    /// die Sprache, und so liest `MarkdownToADF` sie am Zaun wieder ein.
    private static func language(of pre: XMLElement) -> String {
        let candidates = [pre] + (pre.elements(forName: "code"))
        for element in candidates {
            let classes = element.attribute(forName: "class")?.stringValue ?? ""
            for token in classes.components(separatedBy: .whitespaces) where token.hasPrefix("language-") {
                return String(token.dropFirst("language-".count))
            }
        }
        return ""
    }

    // MARK: - Listen

    /// Zeilen einer Liste — Kinder in ihrer Reihenfolge, und ein Punkt **ohne eigenen Text** trägt
    /// nur seine Unterliste.
    ///
    /// Beides kommt von derselben Beobachtung: WebKit hängt eine verschachtelte Liste als
    /// **Geschwister** des Listenpunkts an (`<ul><li>eins</li><ul><li>zwei</li></ul></ul>`) — so
    /// kommt jedes „einrücken" im Editor heraus. Tidy räumt das in ein *künstliches* leeres
    /// `<li style="list-style: none">` um, das die Unterliste enthält. Wer daraus einen Punkt macht,
    /// schreibt ein leeres „- " in die Liste; wer nur `<li>`-Kinder durchgeht, verliert bei einem
    /// anderen Parser die ganze Ebene. Beide Formen sind deshalb bedient — gemessen im kopflosen
    /// Probelauf gegen die echte WebView.
    private static func listLines(_ list: XMLElement, depth: Int) -> [String] {
        let ordered = (list.name?.lowercased() ?? "") == "ol"
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []
        var number = 0

        for child in list.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            let name = element.name?.lowercased() ?? ""
            if name == "ul" || name == "ol" {
                lines.append(contentsOf: listLines(element, depth: depth + 1))
                continue
            }
            guard name == "li" else { continue }
            let item = element
            number += 1
            var inlineNodes: [XMLNode] = []
            var nested: [String] = []

            for child in item.children ?? [] {
                if let el = child as? XMLElement, ["ul", "ol"].contains(el.name?.lowercased() ?? "") {
                    nested.append(contentsOf: listLines(el, depth: depth + 1))
                } else if let el = child as? XMLElement,
                          blockNames.contains(el.name?.lowercased() ?? "") {
                    // `<li><p>…</p></li>`: der Absatz ist der Punkt selbst, nicht ein neuer Block.
                    inlineNodes.append(contentsOf: el.children ?? [])
                } else {
                    inlineNodes.append(child)
                }
            }

            let text = paragraph(inline(inlineNodes))
            guard !text.isEmpty else {
                // Punkt ohne Text: entweder Tidys künstlicher Träger einer Unterliste (dann sind
                // ihre Zeilen alles, was hier hingehört) oder ein leerer Punkt, den niemand braucht.
                number -= 1
                lines.append(contentsOf: nested)
                continue
            }
            let marker = ordered ? "\(number). " : "- "
            let itemLines = text.components(separatedBy: "\n")
            lines.append(indent + marker + (itemLines.first ?? ""))
            // Fortsetzungszeilen müssen eingerückt bleiben, sonst zählen sie als neuer Absatz.
            for line in itemLines.dropFirst() where !line.isEmpty {
                lines.append(indent + "  " + line)
            }
            lines.append(contentsOf: nested)
        }
        return lines
    }

    // MARK: - Inline

    static func inline(_ nodes: [XMLNode]) -> String {
        nodes.map(inline).joined()
    }

    private static func inline(_ node: XMLNode) -> String {
        if node.kind == .text { return collapse(node.stringValue ?? "") }
        guard let element = node as? XMLElement else { return "" }
        let name = element.name?.lowercased() ?? ""
        let children = element.children ?? []

        switch name {
        case _ where skipNames.contains(name):
            return ""
        case "br":
            return "\n"
        case "strong", "b":
            return mark(inline(children), "**")
        case "em", "i":
            return mark(inline(children), "*")
        case "del", "s", "strike":
            return mark(inline(children), "~~")
        case "code":
            // Kein verschachteltes Markup in Code — `MarkdownToADF` liest zwischen Backticks
            // ohnehin nur Text.
            let text = collapse(rawText(element))
            return text.isEmpty ? "" : "`" + text + "`"
        case "a":
            let href = element.attribute(forName: "href")?.stringValue ?? ""
            let label = inline(children)
            if href.isEmpty { return label }
            return "[" + (label.isEmpty ? href : label) + "](" + href + ")"
        case "img":
            // Bilder brauchen in Jira einen Attachment-Verweis, den es hier nicht gibt — der
            // Alt-Text ist das Einzige, was zu retten ist.
            return element.attribute(forName: "alt")?.stringValue ?? ""
        default:
            return styled(element, inline(children))
        }
    }

    /// `style`-Attribute, die ein `contenteditable` anstelle von Tags setzt (Safari macht das für
    /// eingefügten Text aus anderen Programmen). Ohne diese Auswertung käme fett gepasteter Text als
    /// nackter Absatz zurück.
    private static func styled(_ element: XMLElement, _ inner: String) -> String {
        let style = (element.attribute(forName: "style")?.stringValue ?? "").lowercased()
        var text = inner
        if style.contains("font-weight: bold") || style.contains("font-weight:bold")
            || style.range(of: #"font-weight:\s*[6-9]00"#, options: .regularExpression) != nil {
            text = mark(text, "**")
        }
        if style.contains("font-style: italic") || style.contains("font-style:italic") {
            text = mark(text, "*")
        }
        if style.contains("line-through") {
            text = mark(text, "~~")
        }
        return text
    }

    /// Setzt eine Mark, ohne kaputte Marker zu produzieren: leerer Inhalt bleibt leer (sonst stünde
    /// `****` da), führende/folgende Leerzeichen wandern **nach draussen** (`** fett **` ist in
    /// Markdown keine Hervorhebung), und eine schon vorhandene gleiche Mark wird nicht verdoppelt
    /// (`<b><strong>x</strong></b>` → `**x**`, nicht `****x****`).
    private static func mark(_ text: String, _ marker: String) -> String {
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return text }
        if core.hasPrefix(marker) && core.hasSuffix(marker) && core.count > 2 * marker.count {
            return text
        }
        let leading = String(text.prefix(while: { $0 == " " }))
        let trailing = String(text.reversed().prefix(while: { $0 == " " }))
        return leading + marker + core + marker + trailing
    }

    // MARK: - Text

    /// HTML-Whitespace-Regeln: jede Folge aus Leerzeichen, Tabs und Umbrüchen ist **ein** Leerzeichen,
    /// und ein geschütztes Leerzeichen ist auch nur eins. Ohne das käme der Zeilenumbruch, den cmark
    /// zwischen zwei Wörtern eines Absatzes setzt, als echter Umbruch zurück.
    private static func collapse(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        return normalized.replacingOccurrences(of: #"[ \t\n\r]+"#, with: " ",
                                               options: .regularExpression)
    }

    /// Text eines Elements ohne Whitespace-Normalisierung (für `<pre>`).
    private static func rawText(_ element: XMLElement) -> String {
        (element.children ?? []).map { node -> String in
            if node.kind == .text { return node.stringValue ?? "" }
            if let el = node as? XMLElement {
                return (el.name?.lowercased() == "br") ? "\n" : rawText(el)
            }
            return ""
        }.joined()
    }

    /// Zeilen eines Absatzes einzeln trimmen: ein `<br>` bleibt weicher Umbruch (den
    /// `MarkdownToADF` als `hardBreak` überträgt), aber ohne führende Leerzeichen — zwei davon
    /// würden als Listen-Fortsetzung gelesen.
    private static func paragraph(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .drop(while: \.isEmpty)
            .reversed().drop(while: \.isEmpty).reversed()
            .joined(separator: "\n")
    }
}
