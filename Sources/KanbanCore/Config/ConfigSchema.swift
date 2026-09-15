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

/// A sidebar section of the settings sheet.
public struct ConfigSectionSpec: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let intro: String?
    public let fields: [ConfigFieldSpec]
    public let projectMap: ProjectMapSpec?

    public init(id: String, title: String, icon: String, intro: String? = nil,
                fields: [ConfigFieldSpec], projectMap: ProjectMapSpec? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.intro = intro
        self.fields = fields
        self.projectMap = projectMap
    }
}
