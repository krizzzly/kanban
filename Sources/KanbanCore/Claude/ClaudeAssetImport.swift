import Foundation

/// Den Inhalt eines Assets aus einer Markdown-Datei von der Platte einlesen.
///
/// Der Grund für einen eigenen Typ statt eines `String(contentsOf:)` an der Aufrufstelle ist die
/// **Frontmatter-Falle**: ein `SKILL.md` lebt von seinem Kopf (`name` liest Codex, `description`
/// zeigen beide im Menü, `disable-model-invocation` hält ihn davon ab, von allein loszulaufen).
/// Eine beliebige Markdown-Datei von der Platte hat keinen — sie einfach hineinzukopieren machte
/// aus einem funktionierenden Skill eine Datei, die kein Agent mehr anbietet, und zwar lautlos.
public enum ClaudeAssetImport {
    /// Grösste Datei, die als Asset-Inhalt durchgeht. Das grösste Asset im Bestand hat 49 KB; ein
    /// Megabyte ist kein Skill mehr, sondern ein Versehen (ein Log, ein Export, ein Dump).
    public static let maxBytes = 1_024 * 1_024

    public enum Fehler: Error, LocalizedError, Equatable {
        case zuGross(Int)
        case keinText(String)

        public var errorDescription: String? {
            switch self {
            case .zuGross(let bytes):
                let mb = Double(bytes) / 1_048_576
                return String(format: "Die Datei ist %.1f MB gross — das ist kein Asset-Inhalt.", mb)
            case .keinText(let name):
                return "\(name) lässt sich nicht als UTF-8-Text lesen."
            }
        }
    }

    /// Liest die Datei und fügt sie mit dem bisherigen Inhalt zusammen (siehe `zusammengefuegt`).
    public static func lesen(_ url: URL, bisher: String) throws -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard bytes <= maxBytes else { throw Fehler.zuGross(bytes) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw Fehler.keinText(url.lastPathComponent)
        }
        return zusammengefuegt(bisher: bisher, eingelesen: text)
    }

    /// Bringt der eingelesene Text **kein** Frontmatter, das bisherige aber schon, bleibt der Kopf
    /// stehen und nur der Rumpf wird ersetzt.
    ///
    /// Andersherum nicht: hat die eingelesene Datei ein eigenes Frontmatter, gilt es unverändert —
    /// wer eins mitbringt, meint es auch. Zwei Köpfe übereinander wären in beiden Agents ungültig.
    public static func zusammengefuegt(bisher: String, eingelesen: String) -> String {
        guard let kopf = frontmatterBlock(bisher), frontmatterBlock(eingelesen) == nil else {
            return eingelesen
        }
        let rumpf = eingelesen.drop { $0 == "\n" }
        return kopf + "\n" + rumpf
    }

    /// Der Kopf-Leser steht in `Frontmatter` — dieselbe Frage, dieselbe Antwort wie beim Rendern.
    static func frontmatterBlock(_ text: String) -> String? { Frontmatter.block(text) }
}
