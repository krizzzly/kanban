import Foundation

/// Baut aus Codex' Rollout-Datei dieselben `ClaudeTurn`s, die die ⏱-Anzeige von Claude kennt —
/// damit hängen Karten-Badge, Session-Chip, Turn-Liste und Worklog-Buchung unverändert daran.
///
/// Codex macht es einem leichter als Claude: jeder Turn steht **explizit** in der Datei, und der
/// abschliessende `task_complete` (bzw. `turn_aborted`) trägt Codex' eigene Turn-Uhr —
/// `duration_ms` plus `started_at`/`completed_at` als Unix-Sekunden. Deshalb braucht es hier
/// **keine** Lücken-Heuristik und keine Kappung (`idleGapCap`): die Wartezeit des Menschen liegt
/// ausserhalb der Messung. Alle Codex-Turns sind damit `isExact`, es gibt kein „≈".
///
/// Bewusst **nicht** die Zeitstempel der Zeilen: in einem geforkten oder fortgesetzten Rollout
/// (`forked_from_id` im `session_meta`) tragen alle nachgeschriebenen Zeilen denselben Schreib-
/// Zeitstempel — eine daraus berechnete Dauer war im geprüften Beispiel 0 für 23 von 23 Turns.
/// Die Felder im Payload sind in beiden Fällen echt.
///
/// `turn_aborted` zählt mit: ein abgebrochener Turn hat gearbeitet, und Codex misst ihn auch.
///
/// Ein `response_item/message` mit `role: user` innerhalb des Paars ist der Prompt. Codex' eigener
/// `<environment_context>`-Block ist auch so eine Nachricht und wird verworfen — sonst stünde in der
/// Timeline ein XML-Block statt der Frage des Menschen (in den geprüften Rollouts: 10 solche Blöcke
/// gegen 193 echte Prompts).
public struct CodexTurnAccumulator: Sendable {
    /// Ein Turn im Bau: gestartet, noch nicht abgeschlossen.
    private struct Open {
        let turnId: String
        let start: Date?
        var promptLines: [String] = []
    }

    private var open: Open?
    private var turns: [ClaudeTurn] = []

    public init() {}

    public func snapshot() -> [ClaudeTurn] { turns }

    public mutating func consume(line: String) {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: data),
              let payload = event.payload else { return }

        switch payload.type {
        case "task_started":
            // Öffnet den Turn — hier interessiert vor allem, welcher Prompt danach kommt.
            open = Open(turnId: payload.turn_id ?? "\(turns.count)",
                        start: Self.unixDate(payload.started_at) ?? Self.date(from: event.timestamp))

        case "task_complete", "turn_aborted":
            // Codex' eigene Messung. Ein `task_complete` ohne vorheriges `task_started` (am Anfang
            // eines nachgeschriebenen Rollouts) zählt trotzdem: die Zeit ist gemessen, nur der
            // Prompt fehlt.
            let seconds = payload.duration_ms.map { $0 / 1000 }
            let start = Self.unixDate(payload.started_at) ?? open?.start
            let end = Self.unixDate(payload.completed_at)
                ?? start.flatMap { s in seconds.map { s.addingTimeInterval($0) } }
            guard let start, let end, let seconds, seconds > 0 else { open = nil; return }

            let prompt = (open?.turnId == payload.turn_id || payload.turn_id == nil
                          ? open?.promptLines : nil)?.joined(separator: "\n") ?? ""
            turns.append(ClaudeTurn(
                index: turns.count,
                promptId: payload.turn_id ?? open?.turnId ?? "\(turns.count)",
                start: start,
                end: end,
                reportedSeconds: seconds,     // Codex' eigene Messung → exakt
                estimatedSeconds: seconds,
                prompt: Self.singleLine(prompt),
                promptFull: String(prompt.prefix(ClaudeTurnAccumulator.fullPromptLimit))))
            open = nil

        case "message":
            guard payload.role == "user", open != nil else { return }
            let text = (payload.content ?? [])
                .compactMap(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !Self.isSynthetic(text) else { return }
            open?.promptLines.append(text)

        default:
            return
        }
    }

    /// Von Codex selbst eingespeiste Nachrichten, die kein Mensch getippt hat.
    static func isSynthetic(_ text: String) -> Bool {
        text.hasPrefix("<environment_context>") || text.hasPrefix("<user_instructions>")
    }

    /// Erste nicht-leere Zeile fürs Kartenkürzel — dieselbe Kürzung wie bei Claude-Turns.
    static func singleLine(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? ""
        return String(line.prefix(200))
    }

    /// `started_at`/`completed_at` sind Unix-**Sekunden** (10-stellig; die ms-Varianten heissen
    /// ausdrücklich `*_ms`).
    static func unixDate(_ seconds: Double?) -> Date? {
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Codex schreibt ISO-8601 mit Millisekunden und `Z`; ältere Zeilen auch ohne Bruchteile.
    static func date(from raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    // MARK: - Rollout-Zeilen

    private struct Event: Decodable {
        let timestamp: String?
        let type: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let type: String?
        let turn_id: String?
        let role: String?
        let content: [Content]?
        let started_at: Double?
        let completed_at: Double?
        let duration_ms: Double?
    }

    private struct Content: Decodable {
        let text: String?
    }
}
