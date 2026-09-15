import Foundation

/// Ein Treffer im Task-File: in welcher Sektion, der wievielte dort, und die Zeile drumherum.
public struct TaskSearchHit: Sendable, Equatable, Identifiable {
    /// Id der Sektion aus `displaySections` — damit weiss die Ansicht, welcher Tab gemeint ist.
    public let sectionID: Int
    public let sectionTitle: String
    /// Der wievielte Treffer **innerhalb** dieser Sektion (0-basiert). Genau diese Zahl bekommt die
    /// WebView, um den richtigen von mehreren gleichen Treffern anzuspringen.
    public let indexInSection: Int
    /// Zeile um den Treffer, gekürzt — die Trefferliste soll lesbar sein, ohne zu springen.
    public let snippet: String

    public var id: String { "\(sectionID)#\(indexInSection)" }

    public init(sectionID: Int, sectionTitle: String, indexInSection: Int, snippet: String) {
        self.sectionID = sectionID
        self.sectionTitle = sectionTitle
        self.indexInSection = indexInSection
        self.snippet = snippet
    }
}

/// Die Suche im geöffneten Task-File — über **alle** Tabs, Review eingeschlossen.
///
/// Gesucht wird im **sichtbaren** Text, nicht im Markdown: wer „Lösung" tippt, meint das Wort auf
/// dem Schirm und nicht `**Lösung**` oder die `href` eines Links. Deshalb wird jede Sektion durch
/// denselben Renderer geschickt, der sie anzeigt (`MarkdownHTML`), und von Tags befreit.
///
/// Das ist zugleich die Bedingung dafür, dass das Anspringen stimmt: die Ansicht zählt ihre Treffer
/// im DOM ab, und der DOM enthält genau diesen Text. Zählte Swift auf dem Markdown, führte
/// „der 3. Treffer" die beiden Seiten auf verschiedene Stellen.
public enum TaskSearch {
    /// Kürzer wird nicht gesucht: ein einzelnes Zeichen trifft in jedem Task-File hunderte Male und
    /// sagt nichts.
    public static let minQueryLength = 2

    /// Wie viel Kontext links und rechts im Ausschnitt steht.
    static let snippetPadding = 32

    /// Einmalige Suche über frische Sektionen — für Tests und Aufrufer ohne Index.
    /// Die Ansicht benutzt `TaskSearchIndex`: der sichtbare Text jeder Sektion entsteht sonst bei
    /// jedem Tastendruck neu.
    public static func hits(query: String, in sections: [TaskSection]) -> [TaskSearchHit] {
        TaskSearchIndex(sections: sections).hits(query: query)
    }

    /// Alle Fundstellen, **ohne Überlappung** (wie die WebView sie abzählt: sie setzt hinter jedem
    /// Treffer neu an).
    ///
    /// Verglichen wird nur ohne Gross-/Kleinschreibung — bewusst **nicht** diakritika-unempfindlich:
    /// die Gegenseite ist JavaScripts `toLowerCase()`, und „uber" fände dort „über" nicht. Zwei
    /// verschiedene Zählweisen wären schlimmer als eine strenge.
    static func bereiche(of needle: String, in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let found = text.range(of: needle, options: .caseInsensitive, range: start..<text.endIndex) {
            result.append(found)
            start = found.upperBound
        }
        return result
    }

    /// Der sichtbare Text einer Sektion: gerendert, dann von Tags und Entities befreit.
    public static func visibleText(_ markdown: String) -> String {
        entschaerft(ohneTags(MarkdownHTML.render(markdown)))
    }

    /// Tags weg — samt dem **Inhalt** von `script`/`style`, der im DOM kein Text ist. Alles andere
    /// zwischen den Tags ist genau das, was auf dem Schirm steht; Attribute (Bild-`src`,
    /// Link-`href`) fallen mit ihrem Tag weg.
    ///
    /// Gescannt wird **vorwärts von Tag zu Tag**, nie über den Rest des Dokuments. Die erste Fassung
    /// prüfte an jedem `<` mit `html[index...].lowercased().hasPrefix("<script")`, ob ein Skript
    /// beginnt — und kleinschrieb dafür jedes Mal den **ganzen restlichen** HTML-Text. Auf einem
    /// echten Task-File (137 KB, 23 Sektionen) kostete ein Tastendruck dadurch 2,6 s.
    static func ohneTags(_ html: String) -> String {
        var result = ""
        result.reserveCapacity(html.count)
        var index = html.startIndex

        while index < html.endIndex {
            guard let tagStart = html[index...].firstIndex(of: "<") else {
                result.append(contentsOf: html[index...])
                break
            }
            result.append(contentsOf: html[index..<tagStart])
            guard let tagEnd = html[tagStart...].firstIndex(of: ">") else { break }

            let name = tagName(in: html, after: tagStart)
            if name == "script" || name == "style" {
                // Inhalt überspringen: er steht im DOM nicht als Text.
                let nachTag = html.index(after: tagEnd)
                if let schliessend = html.range(of: "</\(name)", options: .caseInsensitive,
                                               range: nachTag..<html.endIndex),
                   let ende = html[schliessend.upperBound...].firstIndex(of: ">") {
                    index = html.index(after: ende)
                } else {
                    index = html.endIndex
                }
            } else {
                // Ein Tag trennt Wörter — ohne das klebte „Ende</p><p>Anfang" zusammen.
                result.append(" ")
                index = html.index(after: tagEnd)
            }
        }
        return result
    }

    /// Der Tagname hinter einem `<` (oder `</`), kleingeschrieben. Liest höchstens ein paar Zeichen
    /// weit — es geht nur um `script`/`style`.
    static func tagName(in html: String, after tagStart: String.Index) -> String {
        var index = html.index(after: tagStart)
        if index < html.endIndex, html[index] == "/" { index = html.index(after: index) }
        var name = ""
        while index < html.endIndex, html[index].isLetter, name.count < 8 {
            name.append(html[index])
            index = html.index(after: index)
        }
        return name.lowercased()
    }

    /// Die paar Entities, die cmark wirklich schreibt.
    static func entschaerft(_ text: String) -> String {
        var result = text
        for (entity, zeichen) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                  ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            result = result.replacingOccurrences(of: entity, with: zeichen)
        }
        return result
    }

    /// Ausschnitt um den Treffer, auf eine Zeile gebracht und beidseitig mit „…" gekürzt.
    static func snippet(around bereich: Range<String.Index>, in text: String) -> String {
        let vorne = text.index(bereich.lowerBound, offsetBy: -snippetPadding,
                               limitedBy: text.startIndex) ?? text.startIndex
        let hinten = text.index(bereich.upperBound, offsetBy: snippetPadding,
                                limitedBy: text.endIndex) ?? text.endIndex
        var stueck = text[vorne..<hinten]
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        while stueck.contains("  ") { stueck = stueck.replacingOccurrences(of: "  ", with: " ") }
        stueck = stueck.trimmingCharacters(in: .whitespaces)
        if vorne != text.startIndex { stueck = "…" + stueck }
        if hinten != text.endIndex { stueck += "…" }
        return stueck
    }
}

/// Der vorbereitete Text aller Tabs, damit Tippen nur noch ein Stringvergleich ist.
///
/// Gebaut wird er, wenn sich der **Inhalt** ändert (Ticketwechsel, Task-File-Watcher), nicht bei
/// jedem Tastendruck: `visibleText` schickt jede Sektion durch cmark, und auf einem echten
/// Task-File (137 KB, 23 Sektionen) sind das ~20 ms — je Taste wäre das spürbar, einmal je Datei
/// ist es nichts.
public struct TaskSearchIndex: Sendable {
    /// Eine Sektion mit ihrem sichtbaren Text.
    struct Eintrag: Sendable {
        let id: Int
        let titel: String
        let text: String
    }

    let eintraege: [Eintrag]

    public init(sections: [TaskSection]) {
        eintraege = sections.map {
            Eintrag(id: $0.id, titel: $0.title, text: TaskSearch.visibleText($0.markdown))
        }
    }

    public var isEmpty: Bool { eintraege.isEmpty }

    public func hits(query: String) -> [TaskSearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= TaskSearch.minQueryLength else { return [] }

        var result: [TaskSearchHit] = []
        for eintrag in eintraege {
            for (index, bereich) in TaskSearch.bereiche(of: needle, in: eintrag.text).enumerated() {
                result.append(TaskSearchHit(
                    sectionID: eintrag.id, sectionTitle: eintrag.titel, indexInSection: index,
                    snippet: TaskSearch.snippet(around: bereich, in: eintrag.text)))
            }
        }
        return result
    }
}
