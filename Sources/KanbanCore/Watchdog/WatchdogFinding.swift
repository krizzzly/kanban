import Foundation

/// Welche Sorte Problem ein Befund beschreibt.
///
/// Die Trennung ist der Grund, warum die Liste lesbar bleibt: einen Verhaltens-Befund behebt man mit
/// einer Regel (CLAUDE.md, Skill), einen technischen mit Werkzeug oder Umgebung. In einem Topf
/// gelesen wäre beides nur „irgendwas lief schief".
public enum WatchdogCategory: String, Codable, Sendable, CaseIterable, Equatable {
    /// Wie der Agent gearbeitet hat — was korrigiert, wiederholt oder zurückgenommen werden musste.
    case verhalten
    /// Was die Werkzeuge sagen — scheiternde Builds, Tests, Kommandos, verweigerte Freigaben.
    case technik

    public var label: String {
        switch self {
        case .verhalten: return "Verhalten"
        case .technik: return "Technik"
        }
    }

    public var icon: String {
        switch self {
        case .verhalten: return "bubble.left.and.exclamationmark.bubble.right"
        case .technik: return "wrench.and.screwdriver"
        }
    }
}

public enum WatchdogSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case niedrig, mittel, hoch

    private var rang: Int {
        switch self {
        case .niedrig: return 0
        case .mittel: return 1
        case .hoch: return 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rang < rhs.rang }

    public var label: String {
        switch self {
        case .niedrig: return "niedrig"
        case .mittel: return "mittel"
        case .hoch: return "hoch"
        }
    }

    /// Englische Schreibweisen des Modells mit übersetzen — der Prompt fragt deutsch, aber ein
    /// Modell antwortet gern trotzdem `"high"`, und daran darf ein Befund nicht scheitern.
    public init?(modellwert: String) {
        switch modellwert.lowercased() {
        case "hoch", "high": self = .hoch
        case "mittel", "medium": self = .mittel
        case "niedrig", "low": self = .niedrig
        default: return nil
        }
    }
}

/// Ein konkreter Beleg für einen Befund — der Zettel, der die Behauptung nachprüfbar macht.
/// Ohne ihn wäre ein Befund nur eine Meinung über die eigene Arbeit.
public struct WatchdogEvidence: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let sessionId: String
    public var sessionTitel: String?
    /// Projektordner der Session (aus dem Transcript), für die Zuordnung im Panel.
    public var projekt: String?
    /// Wörtliches Zitat aus dem Transcript, bereits gekürzt.
    public var zitat: String
    public var zeitpunkt: Date?

    public var id: String { sessionId + "|" + zitat.prefix(64) }

    public init(sessionId: String, sessionTitel: String? = nil, projekt: String? = nil,
                zitat: String, zeitpunkt: Date? = nil) {
        self.sessionId = sessionId
        self.sessionTitel = sessionTitel
        self.projekt = projekt
        self.zitat = zitat
        self.zeitpunkt = zeitpunkt
    }
}

/// Ein wiederkehrendes Muster, das der Watchdog über mehrere Sessions gefunden hat.
public struct WatchdogFinding: Codable, Sendable, Equatable, Identifiable {
    /// Über Scans hinweg stabil: aus Kategorie + Titel abgeleitet. Dasselbe Muster erneut gefunden
    /// aktualisiert den vorhandenen Eintrag (Anzahl, Belege, zuletzt), statt sich zu verdoppeln —
    /// und bleibt erledigt, wenn es erledigt war.
    public let id: String
    public var titel: String
    public var beschreibung: String
    public var kategorie: WatchdogCategory
    public var schwere: WatchdogSeverity
    /// Konkreter nächster Schritt — etwa eine Regel für CLAUDE.md.
    public var empfehlung: String?
    /// Wie oft beobachtet, über Scans hinweg aufsummiert.
    public var anzahl: Int
    public var belege: [WatchdogEvidence]
    public var zuerst: Date
    public var zuletzt: Date
    public var erledigt: Bool
    /// Aussortiert: taugt nichts, war nie gemeint, geht mich nichts an.
    ///
    /// Getrennt von `erledigt`, weil es etwas anderes sagt — „ich habe es behoben" gegenüber „das
    /// ist kein Befund". Und ein **Flag**, kein Löschen aus der Liste: die Id ist stabil
    /// (`stabileId` aus Kategorie + Titel), ein bloss entfernter Eintrag stünde beim nächsten Scan
    /// wieder da, und zwar als „NEU". Verworfenes bleibt deshalb im Papierkorb stehen und ist von
    /// dort zurückzuholen.
    public var verworfen: Bool

    public init(id: String, titel: String, beschreibung: String, kategorie: WatchdogCategory,
                schwere: WatchdogSeverity, empfehlung: String? = nil, anzahl: Int = 1,
                belege: [WatchdogEvidence] = [], zuerst: Date = Date(), zuletzt: Date = Date(),
                erledigt: Bool = false, verworfen: Bool = false) {
        self.id = id
        self.titel = titel
        self.beschreibung = beschreibung
        self.kategorie = kategorie
        self.schwere = schwere
        self.empfehlung = empfehlung
        self.anzahl = anzahl
        self.belege = belege
        self.zuerst = zuerst
        self.zuletzt = zuletzt
        self.erledigt = erledigt
        self.verworfen = verworfen
    }

    /// Feldweise mit Rückfallwerten dekodiert: ein einzelner kaputter Wert darf nie die ganze
    /// Befundliste kosten — sie ist das Einzige am Watchdog, das der Benutzer selbst gepflegt hat
    /// (Erledigt-Haken).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        titel = (try? c.decode(String.self, forKey: .titel)) ?? "(ohne Titel)"
        beschreibung = (try? c.decode(String.self, forKey: .beschreibung)) ?? ""
        kategorie = (try? c.decode(WatchdogCategory.self, forKey: .kategorie)) ?? .verhalten
        schwere = (try? c.decode(WatchdogSeverity.self, forKey: .schwere)) ?? .niedrig
        empfehlung = try? c.decodeIfPresent(String.self, forKey: .empfehlung)
        anzahl = (try? c.decode(Int.self, forKey: .anzahl)) ?? 1
        belege = (try? c.decode([WatchdogEvidence].self, forKey: .belege)) ?? []
        zuerst = (try? c.decode(Date.self, forKey: .zuerst)) ?? Date()
        zuletzt = (try? c.decode(Date.self, forKey: .zuletzt)) ?? Date()
        erledigt = (try? c.decode(Bool.self, forKey: .erledigt)) ?? false
        // Fehlt in Dateien, die vor dem Papierkorb geschrieben wurden — dort ist nichts verworfen.
        verworfen = (try? c.decodeIfPresent(Bool.self, forKey: .verworfen)) ?? false
    }

    /// Kennung aus Kategorie + Titel. Zeichensetzung und Gross-/Kleinschreibung fallen weg, damit
    /// dasselbe Muster leicht anders formuliert nicht als zweiter Befund auftaucht.
    public static func stabileId(kategorie: WatchdogCategory, titel: String) -> String {
        var slug = ""
        for scalar in titel.lowercased().unicodeScalars {
            let zeichen = CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
            if zeichen == "-" && (slug.isEmpty || slug.hasSuffix("-")) { continue }
            slug.append(zeichen)
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return kategorie.rawValue + ":" + String(slug.prefix(80))
    }

    /// Zeile zum Einfügen in CLAUDE.md oder eine Memory-Datei.
    public var alsRegel: String {
        let kern = (empfehlung?.isEmpty == false ? empfehlung! : beschreibung)
        return kern.isEmpty ? "- **\(titel)**" : "- **\(titel)** — \(kern)"
    }
}
