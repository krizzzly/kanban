import Foundation

/// Ein Profil: eine ganze Kanban-Welt — Zugänge, Projekte, Task-Files, Skill-Sets, Darstellung.
///
/// Der **Ordner steht ausdrücklich in der Datei** und wird nicht aus dem Slug gerechnet. Das ist
/// kein Detail: nur so ist der gewachsene flache Bestand ein ganz normales Profil (sein Ordner
/// *ist* der Datenordner) statt ein Sonderfall im Code, und nur so lässt ein Umbenennen den Ordner
/// in Ruhe.
public struct KanbanProfile: Codable, Sendable, Hashable, Identifiable {
    /// Dateisystem- und schlüsseltauglicher Kurzname. Bleibt beim Umbenennen **stehen**: er steckt
    /// in UserDefaults-Schlüsseln und tmux-Sitzungsnamen, und ein Umbenennen darf keine laufende
    /// Sitzung verwaisen lassen.
    public let slug: String
    public var name: String
    /// Absoluter Ordner dieses Profils.
    public let path: String
    public let created: Date?

    public var id: String { slug }
    public var folder: URL { URL(fileURLWithPath: path) }

    public init(slug: String, name: String, path: String, created: Date? = nil) {
        self.slug = slug
        self.name = name
        self.path = path
        self.created = created
    }

    /// Das migrierte Profil — das, dessen Ordner der globale Datenordner selbst ist.
    ///
    /// Drei Dinge hängen daran, und alle drei sind Rücksicht auf den gewachsenen Bestand: nur hier
    /// wird eine Hermes-Config übernommen, nur hier bleiben die alten UserDefaults-Schlüssel gültig,
    /// und nur hier behalten die tmux-Sitzungen ihre bisherigen Namen.
    public var isDefault: Bool {
        ProfileStore.sameFolder(path, KanbanPaths.globalRoot.path)
    }
}

/// Liste der Profile plus das aktive — der Inhalt von `profiles.json`.
public struct ProfileList: Codable, Sendable {
    public var active: String
    public var profiles: [KanbanProfile]

    public init(active: String, profiles: [KanbanProfile]) {
        self.active = active
        self.profiles = profiles
    }

    /// Das aktive Profil, oder — wenn der Slug ins Leere zeigt — das erste vorhandene.
    ///
    /// Ein von Hand gelöschtes Profil darf die App nicht lahmlegen; sie fällt zurück und sagt es,
    /// statt abzustürzen.
    public var activeProfile: KanbanProfile? {
        profiles.first { $0.slug == active } ?? profiles.first
    }
}

public enum ProfileError: LocalizedError, Sendable {
    case unknownProfile(String)
    case lastProfile
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .unknownProfile(let slug): return "Profil „\(slug)“ gibt es nicht."
        case .lastProfile:
            return "Das letzte Profil lässt sich nicht entfernen — ohne Profil gibt es keinen "
                 + "Datenordner."
        case .write(let m): return "profiles.json konnte nicht geschrieben werden: \(m)"
        }
    }
}

/// Liest und schreibt `profiles.json` — die einzige Datei, die **nicht** zu einem Profil gehört.
///
/// Die Migration des gewachsenen Bestands ist Absicht sparsam: sie schreibt genau diese eine Datei
/// und **verschiebt nichts**. Ein Umzug wäre teuer und riskant, weil die Config mit absoluten Pfaden
/// in den Datenordner zeigt (Task-Files, Doku, Projektbilder) und die Skill-Sets Ziel absoluter
/// Symlinks aus den Agent-Homes und aus jedem Repo sind — verschöbe man den Ordner, zeigte all das
/// ins Leere. Das migrierte Profil **ist** deshalb der flache Ordner; neue Profile bekommen
/// `profiles/<slug>/`.
public enum ProfileStore {
    /// Der Slug, den das migrierte Profil bekommt. Sichtbar wird er kaum: seine UserDefaults-
    /// Schlüssel und tmux-Namen bleiben ja gerade die alten, unpräfixierten.
    public static let defaultSlug = "arbeit"
    public static let defaultName = "Arbeit"

    /// Warum zuletzt auf die Vorgabe zurückgefallen wurde — für die Anzeige, nicht für die Logik.
    public private(set) static var lastError: String?

    // MARK: - Lesen

    /// Der Stand auf der Platte. Eine fehlende Datei ist der Normalfall und kein Fehler: dann gilt
    /// genau ein Profil, und sein Ordner ist der flache Datenordner — also exakt das Verhalten von
    /// vor der Profil-Ebene.
    public static func load() -> ProfileList {
        let url = KanbanPaths.profilesFile
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback() }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let liste = try decoder.decode(ProfileList.self, from: data)
            guard !liste.profiles.isEmpty else { return fallback() }
            lastError = nil
            return liste
        } catch {
            // Eine kaputte Liste darf niemanden von seinen Daten aussperren — lieber das
            // Vorgabe-Profil und ein Hinweis in der Übersicht als eine App, die nicht startet.
            lastError = error.localizedDescription
            return fallback()
        }
    }

    private static func fallback() -> ProfileList {
        let profil = KanbanProfile(slug: defaultSlug, name: defaultName,
                                   path: KanbanPaths.globalRoot.path)
        return ProfileList(active: profil.slug, profiles: [profil])
    }

    /// Das aktive Profil — nie nil: ohne Liste gilt das Vorgabe-Profil.
    public static func active() -> KanbanProfile {
        load().activeProfile ?? fallback().profiles[0]
    }

    /// Der Ordner des aktiven Profils. Einstiegspunkt für `KanbanPaths.root`.
    public static func activeFolder() -> URL { active().folder }

    // MARK: - Schreiben

    public static func save(_ liste: ProfileList) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: KanbanPaths.globalRoot,
                                                    withIntermediateDirectories: true)
            let data = try encoder.encode(liste)
            try data.write(to: KanbanPaths.profilesFile, options: .atomic)
            lastError = nil
        } catch {
            throw ProfileError.write(error.localizedDescription)
        }
    }

    /// Schreibt `profiles.json`, falls es sie noch nicht gibt: ein Profil, dessen Ordner der
    /// bestehende Datenordner ist. Verschoben wird **nichts**.
    ///
    /// Scheitert das Schreiben, passiert nichts weiter — ohne die Datei gilt ohnehin dasselbe
    /// Vorgabe-Profil, die App startet also wie bisher.
    @discardableResult
    public static func migrateIfNeeded() -> Bool {
        guard !FileManager.default.fileExists(atPath: KanbanPaths.profilesFile.path) else {
            return false
        }
        var liste = fallback()
        liste.profiles[0] = KanbanProfile(slug: defaultSlug, name: defaultName,
                                          path: KanbanPaths.globalRoot.path, created: Date())
        do { try save(liste); return true } catch { return false }
    }

    /// Legt ein Profil an: eigener Ordner unter `profiles/<slug>`, leere Config, nicht aktiv.
    ///
    /// Die Config trägt genau einen Wert, und der ist eine Sicherheitsfrage: `hermes.syncProjects`
    /// steht auf **false**. Sonst schriebe ein frisch angelegtes, privates Profil seine Projekte in
    /// die Hermes-Config, die zur anderen Welt gehört.
    @discardableResult
    public static func create(name: String) throws -> KanbanProfile {
        var liste = load()
        let slug = self.slug(for: name, taken: Set(liste.profiles.map(\.slug)))
        let ordner = KanbanPaths.globalRoot
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        } catch {
            throw ProfileError.write(error.localizedDescription)
        }
        let config = ordner.appendingPathComponent("config.json")
        if !FileManager.default.fileExists(atPath: config.path) {
            let inhalt = "{\n  \"hermes\" : {\n    \"syncProjects\" : false\n  }\n}\n"
            try? inhalt.write(to: config, atomically: true, encoding: .utf8)
        }
        let profil = KanbanProfile(slug: slug, name: name.trimmed.isEmpty ? slug : name.trimmed,
                                   path: ordner.path, created: Date())
        liste.profiles.append(profil)
        try save(liste)
        return profil
    }

    public static func rename(slug: String, to name: String) throws {
        var liste = load()
        guard let index = liste.profiles.firstIndex(where: { $0.slug == slug }) else {
            throw ProfileError.unknownProfile(slug)
        }
        let sauber = name.trimmed
        liste.profiles[index].name = sauber.isEmpty ? liste.profiles[index].name : sauber
        try save(liste)
    }

    /// Nimmt das Profil aus der Liste — **der Ordner bleibt stehen**.
    ///
    /// Dieselbe Haltung wie bei den Skill-Sets: entfernt wird die Zuordnung, nicht die Arbeit. In
    /// einem Profilordner liegen Task-Files, gebuchte Zeiten und Zugangsdaten; ein Klick, der das
    /// alles mitnimmt, wäre der teuerste Fehlklick der ganzen App. Wer den Ordner wirklich los sein
    /// will, tut es im Finder.
    public static func remove(slug: String) throws {
        var liste = load()
        guard liste.profiles.contains(where: { $0.slug == slug }) else {
            throw ProfileError.unknownProfile(slug)
        }
        guard liste.profiles.count > 1 else { throw ProfileError.lastProfile }
        liste.profiles.removeAll { $0.slug == slug }
        if liste.active == slug { liste.active = liste.profiles[0].slug }
        try save(liste)
    }

    public static func activate(slug: String) throws {
        var liste = load()
        guard liste.profiles.contains(where: { $0.slug == slug }) else {
            throw ProfileError.unknownProfile(slug)
        }
        liste.active = slug
        try save(liste)
    }

    // MARK: - Hilfen

    /// Dateisystemtauglicher Kurzname aus dem Anzeigenamen; bei Kollision zählt er hoch.
    ///
    /// Umlaute werden **ausgeschrieben** statt weggeworfen: aus „Büro" würde sonst „bro".
    public static func slug(for name: String, taken: Set<String>) -> String {
        var basis = ""
        for zeichen in name.lowercased() {
            switch zeichen {
            case "ä": basis += "ae"
            case "ö": basis += "oe"
            case "ü": basis += "ue"
            case "ß": basis += "ss"
            case "a"..."z", "0"..."9": basis.append(zeichen)
            default: basis += "-"
            }
        }
        while basis.contains("--") { basis = basis.replacingOccurrences(of: "--", with: "-") }
        basis = basis.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if basis.isEmpty { basis = "profil" }
        guard taken.contains(basis) else { return basis }
        var zaehler = 2
        while taken.contains("\(basis)-\(zaehler)") { zaehler += 1 }
        return "\(basis)-\(zaehler)"
    }

    /// Zwei Pfade, die denselben Ordner meinen. Verglichen wird normalisiert **und** symlink-
    /// aufgelöst, weil `/var` und `/private/var` denselben Ort bezeichnen.
    static func sameFolder(_ a: String, _ b: String) -> Bool {
        let links = URL(fileURLWithPath: a), rechts = URL(fileURLWithPath: b)
        if links.standardizedFileURL.path == rechts.standardizedFileURL.path { return true }
        return links.resolvingSymlinksInPath().path == rechts.resolvingSymlinksInPath().path
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Wie die gemerkte Auswahl in `UserDefaults` je Profil getrennt wird.
///
/// Reine Schlüssel-Abbildung, absichtlich ohne `UserDefaults` darin: die App hängt den Speicher
/// dran, und geprüft wird hier, was allein interessant ist — unter welchem Namen gelesen und
/// geschrieben wird.
///
/// Geschrieben wird **immer** präfixiert. Gelesen wird beim migrierten Profil zusätzlich der alte,
/// unpräfixierte Schlüssel, falls der neue noch leer ist: niemand soll seine offenen Fenster
/// verlieren, bloss weil das Format eine Profil-Ebene bekommen hat. Für jedes andere Profil gibt es
/// diesen Rückgriff nicht — es soll die Fenster der anderen Welt ja gerade nicht sehen.
public struct ProfileDefaults: Sendable, Equatable {
    public let slug: String?
    public let readsLegacyKeys: Bool

    /// Ohne Profil verhält es sich wie vor der Profil-Ebene: keine Präfixe, keine Rückgriffe.
    public init(profile: KanbanProfile?) {
        self.slug = profile?.slug
        self.readsLegacyKeys = profile?.isDefault ?? true
    }

    public init(slug: String?, readsLegacyKeys: Bool) {
        self.slug = slug
        self.readsLegacyKeys = readsLegacyKeys
    }

    /// Der Schlüssel, unter dem dieses Profil schreibt.
    public func key(_ name: String) -> String {
        guard let slug, !slug.isEmpty else { return name }
        return "\(slug).\(name)"
    }

    /// Der alte Schlüssel, der beim Lesen einspringt — nil, wo es ihn nicht zu erben gibt.
    public func legacyKey(_ name: String) -> String? {
        guard readsLegacyKeys else { return nil }
        let eigener = key(name)
        return eigener == name ? nil : name
    }
}
