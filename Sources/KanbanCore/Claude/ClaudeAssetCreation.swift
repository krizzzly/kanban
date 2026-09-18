import Foundation

/// Der Name eines neuen Assets — und warum er so streng ist.
///
/// Der Name ist **kein** Anzeigetext: er ist der Dateiname im Bestand, das Ziel des Symlinks in
/// beiden Agent-Homes und der Aufruf selbst (`/create-task` bzw. `$create-task`). Ein Leerzeichen
/// oder ein Grossbuchstabe darin ist damit nicht Geschmackssache, sondern ein Skill, der sich nicht
/// aufrufen lässt. Der ganze kanonische Bestand ist deshalb kebab-case, und neue Assets bleiben es.
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
}

public extension ClaudeAssetStore {
    /// Legt ein neues Asset im Bestand an und liefert es zurück.
    ///
    /// Ein Skill wird ein **Ordner** mit `SKILL.md` — die Gattung, die beide Agents lesen, und der
    /// Ordner ist zugleich das Symlink-Ziel (Beiwerk-Dateien reisen dadurch mit). Eine Rule ist eine
    /// einzelne Datei und wird nicht verlinkt: keiner der Agents hat einen Rules-Mechanismus, sie
    /// werden aus den Skills per Pfad referenziert.
    /// - Parameter inhalt: Fertiger Inhalt statt der Vorlage — für „aus einer Datei anlegen". Bringt
    ///   er kein Frontmatter mit, bekommt ein Skill das der Vorlage vorangestellt
    ///   (`ClaudeAssetImport.zusammengefuegt`); ohne Kopf wäre er für beide Agents unsichtbar.
    @discardableResult
    func create(kind: ClaudeAssetKind, name roh: String,
                beschreibung: String = "", inhalt: String? = nil) throws -> ClaudeAsset {
        let name = ClaudeAssetName.normalisiert(roh)
        try ClaudeAssetName.pruefen(name)

        let kindDir = canonicalRoot.appendingPathComponent(kind.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: kindDir, withIntermediateDirectories: true)

        let ziel: URL
        let datei: URL
        switch kind {
        case .skill:
            ziel = kindDir.appendingPathComponent(name, isDirectory: true)
            datei = ziel.appendingPathComponent("SKILL.md")
        case .command, .rule:
            ziel = kindDir.appendingPathComponent("\(name).md")
            datei = ziel
        }
        guard !FileManager.default.fileExists(atPath: ziel.path) else {
            throw ClaudeAssetName.Fehler.belegt(name)
        }

        if kind == .skill {
            try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        }
        let vorlage = Self.vorlage(kind: kind, name: name, beschreibung: beschreibung)
        let text = inhalt.map { ClaudeAssetImport.zusammengefuegt(bisher: vorlage, eingelesen: $0) }
            ?? vorlage
        try text.write(to: datei, atomically: true, encoding: .utf8)
        return ClaudeAsset(kind: kind, name: name, url: ziel)
    }

    /// Der Anfangsinhalt. Beim Skill steht das Frontmatter drin, das Kanbans Bestand überall trägt:
    /// `name` (Codex liest ihn), `description` (beide zeigen sie im Menü) und
    /// `disable-model-invocation: true` — ein Skill soll nicht von allein loslaufen, was ein Command
    /// nie konnte. `$ARGUMENTS` ist die Form, die **beide** Agents einsetzen (verifiziert, siehe
    /// „Zwei Agents"); `$1` zählt bei Claude ab dem zweiten Token und wird deshalb nirgends benutzt.
    static func vorlage(kind: ClaudeAssetKind, name: String, beschreibung: String) -> String {
        let text = beschreibung.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .skill:
            return """
            ---
            name: \(name)
            description: \(text.isEmpty ? "TODO: wofür ist dieser Skill da?" : text)
            disable-model-invocation: true
            ---

            # \(name)

            TODO: Was soll der Agent tun? Argumente stehen in $ARGUMENTS.

            Projektwerte (Prefix, Pfade) stehen in `<repo>/.claude/project.json` — nicht hier
            hineinschreiben, der Bestand gilt für jedes Projekt.

            """
        case .rule, .command:
            return """
            # \(name)

            \(text.isEmpty ? "TODO: Welche Regel gilt hier, und warum?" : text)

            """
        }
    }

    /// Löscht ein Asset aus dem Bestand — samt seiner Symlinks, sonst zeigten sie ins Leere.
    func delete(_ asset: ClaudeAsset) throws {
        for agent in linkableAgents(for: asset) {
            try? removeSymlink(for: asset, agent: agent)
        }
        guard FileManager.default.fileExists(atPath: asset.url.path) else { return }
        try FileManager.default.removeItem(at: asset.url)
    }
}
