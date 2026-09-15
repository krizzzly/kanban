import Foundation

/// Merkt, wie weit eine Session schon ausgewertet ist, damit ein wiederholter Scan nur zahlt, was
/// sich geändert hat. Ohne das würde jeder Durchgang dieselbe Historie erneut schicken.
public struct WatchdogCursor: Codable, Sendable, Equatable {
    public var geaendert: Date
    public var signale: Int

    public init(geaendert: Date, signale: Int) {
        self.geaendert = geaendert
        self.signale = signale
    }
}

/// Alles, was der Watchdog zwischen zwei Läufen behält.
public struct WatchdogState: Codable, Sendable, Equatable {
    public var befunde: [WatchdogFinding]
    public var cursors: [String: WatchdogCursor]
    public var letzterScan: Date?
    public var letzterFehler: String?
    /// Ungefähre Kosten des letzten Auswertungsaufrufs — Hintergrund-Ausgaben sollen sichtbar sein.
    public var letzteKostenUSD: Double?
    public var sessionsGescannt: Int?

    public init(befunde: [WatchdogFinding] = [], cursors: [String: WatchdogCursor] = [:],
                letzterScan: Date? = nil, letzterFehler: String? = nil,
                letzteKostenUSD: Double? = nil, sessionsGescannt: Int? = nil) {
        self.befunde = befunde
        self.cursors = cursors
        self.letzterScan = letzterScan
        self.letzterFehler = letzterFehler
        self.letzteKostenUSD = letzteKostenUSD
        self.sessionsGescannt = sessionsGescannt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Feldweise mit Rückfallwerten — dieselbe Begründung wie beim Befund: ein kaputter Wert darf
        // nicht die ganze Liste kosten.
        befunde = (try? c.decodeIfPresent([WatchdogFinding].self, forKey: .befunde)) ?? []
        cursors = (try? c.decodeIfPresent([String: WatchdogCursor].self, forKey: .cursors)) ?? [:]
        letzterScan = try? c.decodeIfPresent(Date.self, forKey: .letzterScan)
        letzterFehler = try? c.decodeIfPresent(String.self, forKey: .letzterFehler)
        letzteKostenUSD = try? c.decodeIfPresent(Double.self, forKey: .letzteKostenUSD)
        sessionsGescannt = try? c.decodeIfPresent(Int.self, forKey: .sessionsGescannt)
    }
}

/// Liest und schreibt `~/Library/Application Support/Kanban/watchdog.json` — neben der Config, im
/// selben Datenordner, den der Ordner-Knopf in der Leiste öffnet.
public struct WatchdogStore: Sendable {
    public let path: String

    public init(path: String? = nil) {
        self.path = path
            ?? (KanbanConfig.supportDirectory as NSString).appendingPathComponent("watchdog.json")
    }

    public func laden() -> WatchdogState {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return WatchdogState()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Eine kaputte Datei fällt auf „noch keine Historie" zurück statt das Panel zu sprengen:
        // Befunde sind abgeleitete Daten, ein Scan stellt sie wieder her.
        guard let state = try? decoder.decode(WatchdogState.self, from: data) else {
            return WatchdogState()
        }
        return state
    }

    public func speichern(_ state: WatchdogState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
