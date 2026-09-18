import Foundation

/// Der YAML-Kopf am Anfang einer Markdown-Datei (`---` … `---`).
///
/// Markdown kennt ihn nicht, und cmark liest ihn deshalb als etwas ganz anderes: die erste
/// `---`-Zeile wird eine Trennlinie, die zweite macht aus den Zeilen darüber eine **Setext-
/// Überschrift**. Aus dem Kopf eines Skills wurde so:
///
/// ```html
/// <hr />
/// <h2>name: solve-task
/// description: löst ein Ticket
/// disable-model-invocation: true</h2>
/// ```
///
/// — also eine fette Überschrift quer über die Seite, dort wo eigentlich Metadaten stehen. Deshalb
/// wird der Block **vor** dem Rendern zu einem Codeblock: dort steht er als das da, was er ist,
/// und cmark fasst ihn nicht mehr an.
public enum Frontmatter {

    /// Der vollständige Block **einschliesslich** der beiden `---`-Zeilen, oder nil.
    ///
    /// Bewusst textuell und nicht über einen YAML-Leser: die Aufrufer wollen den Kopf wortgleich —
    /// mit Reihenfolge und Kommentaren, die ein Parser wegwerfen würde.
    public static func block(_ text: String) -> String? {
        let zeilen = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard zeilen.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let ende = zeilen.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else { return nil }   // offener Block: kein Frontmatter, sondern eine Trennlinie
        return zeilen[...ende].joined(separator: "\n")
    }

    /// Ersetzt einen führenden Kopf durch einen `yaml`-Codeblock. Ohne Kopf bleibt der Text, wie er ist.
    public static func alsCodeblock(_ text: String) -> String {
        guard let kopf = block(text) else { return text }
        let rumpf = text.dropFirst(kopf.count)
        let inhalt = kopfOhneZaeune(kopf)
        let zaun = String(repeating: "`", count: zaunlaenge(fuer: inhalt))
        return "\(zaun)yaml\n\(inhalt)\n\(zaun)\n\(rumpf)"
    }

    /// Die `---`-Zeilen fallen weg — im Codeblock sind sie nur noch Rauschen, der Block ist ja
    /// schon als Einheit zu sehen.
    static func kopfOhneZaeune(_ kopf: String) -> String {
        let zeilen = kopf.split(separator: "\n", omittingEmptySubsequences: false)
        guard zeilen.count > 2 else { return "" }
        return zeilen[1..<(zeilen.count - 1)].joined(separator: "\n")
    }

    /// Ein Zaun muss länger sein als die längste Backtick-Folge im Inhalt, sonst endet der Block
    /// mittendrin — `description: nutzt \`foo\`` ist in einem Skill-Kopf nichts Besonderes.
    static func zaunlaenge(fuer inhalt: String) -> Int {
        var laengste = 0
        var aktuell = 0
        for zeichen in inhalt {
            if zeichen == "`" {
                aktuell += 1
                laengste = max(laengste, aktuell)
            } else {
                aktuell = 0
            }
        }
        return max(3, laengste + 1)
    }
}
