import Foundation

/// Die Änderungen an einer Themes-Map (`terminal.themes`, `markdown.themes`) als reine
/// JSON-Operationen — ohne SwiftUI, damit sie geprüft werden können.
///
/// Jede dieser Operationen hat einen Grund, der nicht in ihr selbst steht: eine leer angelegte
/// Fassung, eine Auswahl, die ins Leere zeigt, oder eine ANSI-Liste mit 15 Einträgen fällt beim
/// Laden **stumm** weg (`RawTheme.resolved`). Man hätte etwas eingestellt und nichts davon gesehen.
public enum ThemeMapEdit {

    /// Neue Fassung als **Kopie** — der aktiven, sonst der ersten, sonst der mitgelieferten Vorlage.
    /// Leer anzulegen hiesse: eine Fassung, die es in der Auswahl nie gibt.
    @discardableResult
    public static func add(_ root: inout JSONValue, spec: ThemeMapSpec, name roh: String) -> Bool {
        let name = roh.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, root.value(at: spec.path + [name]) == nil else { return false }
        let aktiv = root.value(at: spec.activePath)?.stringValue ?? ""
        let vorlage = root.value(at: spec.path + [aktiv])
            ?? namen(root, spec).first.flatMap { root.value(at: spec.path + [$0]) }
            ?? spec.vorlagen.first?.werte
            ?? .object([:])
        root.set(vorlage, at: spec.path + [name])
        return true
    }

    /// Entfernen zieht die Auswahl mit: zeigte sie auf die entfernte Fassung, griffe sonst stumm
    /// die erste — und die Einstellung behauptete etwas anderes, als die Ansicht zeigt.
    public static func remove(_ root: inout JSONValue, spec: ThemeMapSpec, name: String) {
        let warAktiv = root.value(at: spec.activePath)?.stringValue == name
        root.set(nil, at: spec.path + [name])
        guard warAktiv else { return }
        root.set(namen(root, spec).first.map(JSONValue.string), at: spec.activePath)
    }

    /// Umbenennen: Werte unter neuem Namen, alter Schlüssel weg — und die Auswahl hinterher, wenn
    /// sie auf die umbenannte Fassung zeigte.
    @discardableResult
    public static func rename(_ root: inout JSONValue, spec: ThemeMapSpec,
                              from: String, to roh: String) -> Bool {
        let neu = roh.trimmingCharacters(in: .whitespaces)
        guard !neu.isEmpty, neu != from,
              let werte = root.value(at: spec.path + [from]),
              root.value(at: spec.path + [neu]) == nil else { return false }
        let warAktiv = root.value(at: spec.activePath)?.stringValue == from
        root.set(werte, at: spec.path + [neu])
        root.set(nil, at: spec.path + [from])
        if warAktiv { root.set(.string(neu), at: spec.activePath) }
        return true
    }

    /// Eine der 16 ANSI-Farben setzen. Die Liste wird dabei auf 16 Einträge gebracht: mit 15 fällt
    /// die ganze Fassung beim Laden weg, und zu sehen wäre nur, dass sie fehlt.
    public static func setAnsi(_ root: inout JSONValue, path: [String], index: Int, hex: String) {
        guard (0..<16).contains(index) else { return }
        var liste = root.value(at: path)?.arrayValue ?? []
        while liste.count < 16 { liste.append(.string("")) }
        guard liste[index].stringValue != hex else { return }
        liste[index] = .string(hex)
        root.set(.array(liste), at: path)
    }

    public static func namen(_ root: JSONValue, _ spec: ThemeMapSpec) -> [String] {
        (root.value(at: spec.path)?.objectValue ?? [:]).keys.sorted()
    }

    /// Die mitgelieferten Fassungen in die Datei schreiben, **wenn dort noch keine steht**.
    ///
    /// Ohne das bleibt die Oberfläche leer, obwohl die Darstellung funktioniert: die Auswahl listet
    /// die Namen aus der Datei, die eingebauten Fassungen stehen aber nur im Code. Der Seed hilft
    /// nur einer frischen Installation — eine gewachsene Config hat nie einen `markdown`-Abschnitt
    /// gesehen und zeigte deshalb genau nichts zum Einstellen. Das war der ursprüngliche Befund
    /// dieses Tasks, nur eine Ebene weiter oben.
    ///
    /// Additiv und nur einmal: sobald **eine** Fassung dasteht (auch eine selbst angelegte oder die
    /// aus einem Altblock übernommene), passiert nichts mehr.
    @discardableResult
    public static func ergaenzeVorlagen(_ root: inout JSONValue, spec: ThemeMapSpec) -> Bool {
        guard !spec.vorlagen.isEmpty, namen(root, spec).isEmpty else { return false }
        for vorlage in spec.vorlagen {
            root.set(vorlage.werte, at: spec.path + [vorlage.name])
        }
        // Die aktive Wahl nur setzen, wenn keine dasteht — und dann auf das, was ohnehin gilt.
        if root.value(at: spec.activePath)?.stringValue == nil {
            root.set(.string(spec.vorlagen[0].name), at: spec.activePath)
        }
        return true
    }
}

/// Die feste Flächenfarbe wegräumen, die eine Fassung von der **alten** mitgelieferten geerbt hat.
///
/// Bis die Flächen aus dem Blatt abgeleitet wurden, trugen `Blatt` und `Blatt Dunkel` eine feste
/// `codeBackground`. Wer eine eigene Fassung als Kopie anlegte, erbte sie mit — und änderte dann
/// den Hintergrund, blieben kaltgraue Codeblöcke auf cremefarbenem Blatt stehen. Genau der Fall,
/// der das hier ausgelöst hat.
///
/// Entfernt wird **nur**, was bitgleich einer dieser alten Vorgaben ist: eine selbst gewählte Farbe
/// ist eine Entscheidung und bleibt. Trifft es zufällig doch eine selbst gesetzte, ist der
/// abgeleitete Wert an derselben Stelle (`#f0f0f0` statt `#f1f1f4`) — und das Feld steht weiterhin
/// in den Einstellungen.
public enum GeerbteFlaechenfarbe {
    static let alteVorgaben = ["#f1f1f4", "#22262d"]

    @discardableResult
    public static func entferne(_ root: inout JSONValue) -> Int {
        let pfad = ["markdown", "themes"]
        var entfernt = 0
        for name in (root.value(at: pfad)?.objectValue ?? [:]).keys {
            let farbe = root.value(at: pfad + [name, "codeBackground"])?.stringValue?.lowercased()
            guard let farbe, alteVorgaben.contains(farbe) else { continue }
            root.set(nil, at: pfad + [name, "codeBackground"])
            entfernt += 1
        }
        return entfernt
    }
}

/// Der Umzug des flachen `markdown`-Blocks in eine benannte Fassung.
///
/// Vor den benannten Fassungen standen die Werte direkt unter `markdown`. Diese Form bleibt
/// **lesbar** (wer sie von Hand angelegt hat, verliert nichts), aber sobald `markdown.themes`
/// existiert, gewinnt `themes` — der flache Block wäre dann eine zweite Wahrheit in derselben
/// Datei, die stumm ignoriert wird. Deshalb zieht er beim ersten Speichern um, verlustfrei.
public enum MarkdownAltblock {
    /// Die Schlüssel, die früher direkt unter `markdown` standen. `theme` und `themes` gehören
    /// **nicht** dazu: die beschreiben die Auswahl, nicht eine Fassung.
    public static let schluessel = ["fontFamily", "headingFont", "headingFonts", "background",
                                    "text", "secondaryText", "codeBackground", "shade", "link",
                                    "border", "fontSize", "headings"]

    /// Übernimmt einen vorhandenen flachen Block als Fassung `Eigene` und macht sie zur aktiven,
    /// falls noch keine gewählt ist. Gibt `true` zurück, wenn etwas umgezogen ist.
    @discardableResult
    public static func migriere(_ root: inout JSONValue) -> Bool {
        guard root.value(at: ["markdown", "themes"]) == nil else { return false }
        let alt = schluessel.compactMap { key -> (String, JSONValue)? in
            root.value(at: ["markdown", key]).map { (key, $0) }
        }
        guard !alt.isEmpty else { return false }
        let name = MarkdownTheme.eigeneName
        root.set(.object(Dictionary(uniqueKeysWithValues: alt)), at: ["markdown", "themes", name])
        for (key, _) in alt { root.set(nil, at: ["markdown", key]) }
        if root.value(at: ["markdown", "theme"])?.stringValue == nil {
            root.set(.string(name), at: ["markdown", "theme"])
        }
        return true
    }
}
