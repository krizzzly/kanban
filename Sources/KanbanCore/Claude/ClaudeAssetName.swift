import Foundation

/// Der Name eines Skills, einer Rule oder eines Sets — und warum er so streng ist.
///
/// Der Name ist **kein** Anzeigetext: er ist der Ordner- bzw. Dateiname, das Ziel des Symlinks im
/// Projekt und der Aufruf selbst (`/create-task` bzw. `$create-task`). Ein Leerzeichen oder ein
/// Grossbuchstabe darin ist damit nicht Geschmackssache, sondern ein Skill, der sich nicht aufrufen
/// lässt. Derselbe Massstab gilt für den Set-Namen: er steht in der Config und als Ordnername im
/// Repo.
public enum ClaudeAssetName {
    public enum Fehler: Error, LocalizedError, Equatable {
        case leer
        case ungueltig(String)
        case belegt(String)

        public var errorDescription: String? {
            switch self {
            case .leer:
                return "Der Name fehlt."
            case .ungueltig(let name):
                return "„\(name)" + "“ geht nicht: nur Kleinbuchstaben, Ziffern und Bindestriche, "
                     + "beginnend mit einem Buchstaben."
            case .belegt(let name):
                return "„\(name)“ gibt es schon."
            }
        }
    }

    public static let maxLength = 64

    /// Macht aus einer Eingabe einen Kandidaten: trimmen, kleinschreiben, Trenner zu Bindestrichen.
    /// Das ist Bequemlichkeit, keine Rettung — was danach noch falsch ist, meldet `pruefen`.
    public static func normalisiert(_ eingabe: String) -> String {
        var name = eingabe.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        name = name.map { $0 == " " || $0 == "_" || $0 == "." ? "-" : $0 }.reduce(into: "") { $0.append($1) }
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        while name.hasPrefix("-") { name.removeFirst() }
        while name.hasSuffix("-") { name.removeLast() }
        return String(name.prefix(maxLength))
    }

    public static func pruefen(_ name: String) throws {
        guard !name.isEmpty else { throw Fehler.leer }
        guard let erstes = name.first, erstes.isLetter, erstes.isASCII else {
            throw Fehler.ungueltig(name)
        }
        let erlaubt = name.allSatisfy { ($0.isLetter && $0.isASCII && $0.isLowercase)
            || ($0.isNumber && $0.isASCII) || $0 == "-" }
        guard erlaubt, name.count <= maxLength else { throw Fehler.ungueltig(name) }
    }

    /// Dieselbe Prüfung ohne Wurf — für den Set-Leser, der über einen Ordner im Bestand nur
    /// entscheiden muss, ob er dazugehört.
    public static func istGueltig(_ name: String) -> Bool {
        (try? pruefen(name)) != nil
    }
}
