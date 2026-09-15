import Foundation

/// Sprungmarken für Überschriften — `<h2>Zwei CQRS-Generationen</h2>` bekommt
/// `id="zwei-cqrs-generationen"`.
///
/// cmark-gfm vergibt keine IDs, also zeigt ein `#anker`-Link im gerenderten HTML auf nichts. In der
/// Knowledgebase stehen solche Links reichlich (`architektur.md#zwei-cqrs-generationen`), und sie
/// sind im **GitHub-Format** geschrieben — nachgeprüft an den Dateien: „RealTemplates — Tests gegen
/// echte Vorlagen" wird dort zu `realtemplates--tests-gegen-echte-vorlagen`, mit **zwei**
/// Bindestrichen, weil GitHub die Interpunktion entfernt und erst danach Leerzeichen ersetzt. Ein
/// Verfahren, das Zeichenfolgen zusammenzieht (wie das `md2html.py` der KB selbst), träfe genau
/// diese Anker nicht.
public enum HeadingAnchors {
    /// GitHubs Regel: Tags raus, kleinschreiben, alles ausser Buchstaben/Ziffern/`-`/`_`/Leerzeichen
    /// entfernen, dann Leerzeichen zu `-`. Bewusst **ohne** Zusammenziehen aufeinanderfolgender
    /// Bindestriche und **mit** Umlauten — beides so wie GitHub, und beides so wie die Links in der
    /// Knowledgebase es erwarten.
    public static func slug(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Zeilenumbrüche zählen wie Leerzeichen: cmark bricht lange Überschriften um, und der Autor
        // hat dort ein Wortende gemeint, keine Zusammenziehung.
        let flat = decodeEntities(plain)
            .replacingOccurrences(of: "\\s", with: " ", options: .regularExpression)
        let kept = flat.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == " "
        }
        let slug = String(String.UnicodeScalarView(kept)).replacingOccurrences(of: " ", with: "-")
        // Eine Überschrift ganz ohne Buchstaben oder Ziffern („— —", „***") ergibt keinen Anker,
        // sondern nur Bindestriche — darauf zeigt nie ein Link.
        return slug.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) ? slug : ""
    }

    /// Ergänzt jede Überschrift ohne eigene `id` um eine. Gleiche Überschriften bekommen wie bei
    /// GitHub `-1`, `-2` … angehängt, sonst zeigten zwei „## Ablauf" auf dieselbe Stelle.
    public static func inject(into html: String) -> String {
        let pattern = "<h([1-6])>(.*?)</h\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return html }

        let ns = html as NSString
        var seen: [String: Int] = [:]
        var result = ""
        var cursor = 0

        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let level = ns.substring(with: match.range(at: 1))
            let inner = ns.substring(with: match.range(at: 2))
            let base = slug(inner)
            guard !base.isEmpty else { continue }

            let count = seen[base, default: 0]
            seen[base] = count + 1
            let id = count == 0 ? base : "\(base)-\(count)"

            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += "<h\(level) id=\"\(id)\">\(inner)</h\(level)>"
            cursor = match.range.location + match.range.length
        }

        result += ns.substring(from: cursor)
        return result
    }

    /// Die Entities, die cmark in Überschriften erzeugt. Ohne das Zurückübersetzen fiele bei
    /// „Konfiguration & Betrieb" das `&amp;` als `amp` in den Anker.
    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
