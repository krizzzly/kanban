import Foundation

/// Lightweight validation hint for a field; never blocks saving (a config may be partial), only
/// surfaces an inline warning when the entered value is clearly malformed.
public enum FieldValidation: Sendable {
    case none, url, email, phoneE164

    public func error(for value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return nil }   // empty = unset, not invalid
        switch self {
        case .none:
            return nil
        case .url:
            return (v.hasPrefix("http://") || v.hasPrefix("https://"))
                ? nil : "Sollte mit http:// oder https:// beginnen."
        case .email:
            return (v.contains("@") && v.contains(".")) ? nil : "Keine gültige E-Mail-Adresse."
        case .phoneE164:
            return (v.hasPrefix("+") && v.dropFirst().allSatisfy(\.isNumber) && v.count >= 8)
                ? nil : "Erwartet E.164-Format, z. B. +41791234567."
        }
    }
}

/// One editable field in the settings UI, addressed by its JSON key path.
public struct ConfigFieldSpec: Identifiable, Sendable {
    public enum Kind: Sendable {
        case string
        case secret            // rendered as SecureField with reveal toggle
        case bool(defaultOn: Bool)
        case path              // string that is a filesystem path (gets a "Wählen…" button)
        case stringList        // JSON string array, edited comma-separated
        case choice([String])  // enum; empty selection removes the key (= module default)
        /// Farbe als `#rrggbb`-Text. Leer entfernt den Schlüssel — und damit gilt wieder die
        /// eingebaute Vorgabe, nicht Schwarz.
        case color
        /// Zahl mit Grenzen, geschrieben als JSON-**Zahl**.
        ///
        /// Eigener Typ, weil `stringBinding` sonst `"16"` in die Datei schriebe — und ein String, wo
        /// eine Zahl erwartet wird, lässt den Config-Decoder werfen und setzt **die ganze**
        /// Darstellung auf die Vorgaben zurück (nachgemessen). Die Grenzen sind dieselben wie im
        /// Decoder, hier nur sichtbar statt stumm.
        case number(min: Double, max: Double)
        /// Auswahl, deren Optionen erst in der Datei stehen: die Schlüssel des Objekts an diesem
        /// Pfad (`terminal.themes`). Ohne das müsste das Schema Namen kennen, die der Benutzer
        /// gerade erst vergeben hat.
        case choiceFromKeys([String])
        /// Schriftauswahl aus den **installierten** Schriften des Rechners. Leer = nicht gesetzt.
        /// `monospaceOnly` filtert auf Festbreitenschriften — für das Terminal ist alles andere
        /// unbrauchbar. Ein Name, der hier nicht installiert ist, bleibt trotzdem stehen: die Config
        /// kann von einem anderen Rechner stammen.
        case fontFamily(monospaceOnly: Bool)
    }

    public let path: [String]
    public let label: String
    public let help: String?
    public let placeholder: String?
    public let kind: Kind
    public let validation: FieldValidation

    public var id: String { path.joined(separator: ".") }

    public init(_ path: [String], _ label: String, kind: Kind,
                placeholder: String? = nil, help: String? = nil,
                validation: FieldValidation = .none) {
        self.path = path
        self.label = label
        self.kind = kind
        self.placeholder = placeholder
        self.help = help
        self.validation = validation
    }
}

/// A sub-field of one entry in a project map (`modules.<m>.projects.<key>.<field>`).
public struct ProjectFieldSpec: Identifiable, Sendable {
    public enum Kind: Sendable {
        case string, secret, stringList
        case choice([String])   // Picker; leere Auswahl entfernt den Schlüssel (= Modul-Default)
        /// Schalter. `defaultOn` ist der Wert, der ohne Schlüssel gilt — bestehende Configs, in
        /// denen er fehlt, verhalten sich damit unverändert.
        case bool(defaultOn: Bool)
        /// Farbwähler, gespeichert als `#rrggbb`. Immer mit einem Weg zurück zu „nicht gesetzt" —
        /// ein Farbwähler allein kann nichts leer lassen, und leer ist hier der Normalfall.
        case color
        /// Bilddatei: wird beim Auswählen in Kanbans Datenordner kopiert (`ProjectImageStore`),
        /// gespeichert wird der Pfad der Kopie.
        case image
    }

    public let key: String
    public let label: String
    public let kind: Kind
    public let placeholder: String?
    public let required: Bool
    public let help: String?

    public var id: String { key }

    public init(_ key: String, _ label: String, kind: Kind = .string, required: Bool,
                placeholder: String? = nil, help: String? = nil) {
        self.key = key
        self.label = label
        self.kind = kind
        self.placeholder = placeholder
        self.required = required
        self.help = help
    }
}

/// A map of per-project objects with user-defined keys (add/remove projects in the UI).
public struct ProjectMapSpec: Sendable {
    public let path: [String]
    public let title: String
    public let keyPlaceholder: String
    public let fields: [ProjectFieldSpec]

    public init(path: [String], title: String = "Projekte",
                keyPlaceholder: String = "projekt-key", fields: [ProjectFieldSpec]) {
        self.path = path
        self.title = title
        self.keyPlaceholder = keyPlaceholder
        self.fields = fields
    }
}

/// Eine benannte Fassung in einer Themes-Map (`terminal.themes.<name>`, `markdown.themes.<name>`),
/// als Kopiervorlage für „neue Fassung".
public struct ThemeVorlage: Sendable {
    public let name: String
    public let werte: JSONValue

    public init(name: String, werte: JSONValue) {
        self.name = name
        self.werte = werte
    }
}

/// Ein Feld **innerhalb** einer Fassung. Unterpfad statt Schlüssel, weil `headings.h1` zwei Ebenen
/// tief liegt und ein Editor, der nur einen Schlüssel anhängen kann, daran scheitert.
public struct ThemeFieldSpec: Identifiable, Sendable {
    public let subpath: [String]
    public let label: String
    public let kind: ConfigFieldSpec.Kind
    public let placeholder: String?
    public let help: String?

    public var id: String { subpath.joined(separator: ".") }

    public init(_ subpath: [String], _ label: String, kind: ConfigFieldSpec.Kind = .color,
                placeholder: String? = nil, help: String? = nil) {
        self.subpath = subpath
        self.label = label
        self.kind = kind
        self.placeholder = placeholder
        self.help = help
    }
}

/// Eine Map benannter Fassungen samt der Auswahl darüber — **ein** Bauteil für Terminal und
/// Markdown. Der Unterschied ist die Feldliste, nicht die Bedienung: auswählen, anlegen (als Kopie),
/// umbenennen, entfernen.
public struct ThemeMapSpec: Sendable {
    /// Wo die Fassungen stehen, z. B. `["markdown", "themes"]`.
    public let path: [String]
    /// Wo der Name der aktiven steht, z. B. `["markdown", "theme"]`.
    public let activePath: [String]
    public let title: String
    public let keyPlaceholder: String
    public let fields: [ThemeFieldSpec]
    /// Schlüssel, ohne die eine Fassung **stumm** aus der Auswahl fällt (`RawTheme.resolved` wirft
    /// sie weg). Der Editor warnt, statt sie verschwinden zu lassen.
    public let requiredKeys: [String]
    /// Unterschlüssel mit genau 16 ANSI-Farben — nil, wo es keine gibt (Markdown).
    public let ansiKey: String?
    /// Womit eine neue Fassung startet, wenn es noch keine zum Kopieren gibt.
    public let vorlagen: [ThemeVorlage]

    public init(path: [String], activePath: [String], title: String, keyPlaceholder: String,
                fields: [ThemeFieldSpec], requiredKeys: [String] = [], ansiKey: String? = nil,
                vorlagen: [ThemeVorlage] = []) {
        self.path = path
        self.activePath = activePath
        self.title = title
        self.keyPlaceholder = keyPlaceholder
        self.fields = fields
        self.requiredKeys = requiredKeys
        self.ansiKey = ansiKey
        self.vorlagen = vorlagen
    }

    /// Warum eine Fassung nicht zählt — nil heisst „vollständig". Dieselbe Prüfung wie beim Laden,
    /// damit die Oberfläche nicht etwas anderes behauptet als der Decoder tut.
    public func fehler(in werte: JSONValue?) -> String? {
        let fehlend = requiredKeys.filter { key in
            TerminalRGB(hex: werte?.value(at: [key])?.stringValue ?? "") == nil
        }
        if !fehlend.isEmpty {
            return "Ohne \(fehlend.joined(separator: ", ")) fällt die Fassung aus der Auswahl."
        }
        if let ansiKey {
            let lesbar = (werte?.value(at: [ansiKey])?.arrayValue ?? [])
                .filter { TerminalRGB(hex: $0.stringValue ?? "") != nil }.count
            if lesbar != 16 {
                return "\(lesbar) von 16 ANSI-Farben lesbar — erst mit allen 16 zählt die Fassung."
            }
        }
        return nil
    }
}

/// Eine Gruppe innerhalb einer Sektion: eigener Titel, eigene Felder, optional eine Themes-Map.
/// „Darstellung" führt drei davon (Kopfzeile, Markdown, Terminal), statt die Seitenleiste um zwei
/// weitere Einträge zu verlängern.
public struct ConfigFieldGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let intro: String?
    public let fields: [ConfigFieldSpec]
    public let themeMap: ThemeMapSpec?

    public init(id: String, title: String, intro: String? = nil,
                fields: [ConfigFieldSpec] = [], themeMap: ThemeMapSpec? = nil) {
        self.id = id
        self.title = title
        self.intro = intro
        self.fields = fields
        self.themeMap = themeMap
    }
}

/// A sidebar section of the settings sheet.
public struct ConfigSectionSpec: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let intro: String?
    public let fields: [ConfigFieldSpec]
    public let projectMap: ProjectMapSpec?
    public let groups: [ConfigFieldGroup]

    public init(id: String, title: String, icon: String, intro: String? = nil,
                fields: [ConfigFieldSpec], projectMap: ProjectMapSpec? = nil,
                groups: [ConfigFieldGroup] = []) {
        self.id = id
        self.title = title
        self.icon = icon
        self.intro = intro
        self.fields = fields
        self.projectMap = projectMap
        self.groups = groups
    }
}
