import Foundation

/// Die Konversation **eines** Agents an einem Ticket: die Id, unter der sie läuft, und ob es dazu
/// wirklich etwas auf der Platte gibt (Transcript bei Claude, Rollout bei Codex).
public struct AgentConversation: Sendable, Hashable {
    public let agent: AgentKind
    public let sessionId: String
    /// Gibt es eine aufgezeichnete Konversation zu dieser Id? Nur dann kann `--resume` gelingen —
    /// ohne sie bricht Codex sichtbar ab und Claude legt eine leere neue an.
    public let hasTranscript: Bool

    public init(agent: AgentKind, sessionId: String, hasTranscript: Bool) {
        self.agent = agent
        self.sessionId = sessionId
        self.hasTranscript = hasTranscript
    }
}

/// Findet die **vorhandene** Konversation eines Agents zu einem Ticket, ohne eine anzulegen.
///
/// Das ist die Frage des zweiten Reiters: Steht am Ticket noch etwas vom anderen Agent? Wo der
/// Projekt-Agent notfalls eine Id erfindet (Claude, `claude --session-id`), erfindet diese Suche
/// nie etwas — sie gibt nil zurück, und dann gibt es nichts anzuknüpfen.
public enum AgentConversationLookup {
    /// `taskFileURL` darf nil sein (Ticket ohne Datei), `storeId` ist die Id aus `sessions.json`
    /// (nur Claude führt dort welche); `cwd` ist das Verzeichnis, in dem der Agent läuft — bei
    /// Claude liegt das Transcript darunter, bei Codex sind die Rollouts global.
    public static func existing(agent: AgentKind, ticketKey: String, taskFileURL: URL?,
                                storeId: String? = nil, cwd: String) -> AgentConversation? {
        let marker = taskFileURL.flatMap { TaskFileLoader.sessionId(in: $0, agent: agent) }
        // Die zweite Fundstelle je Agent: bei Claude `sessions.json`, bei Codex der Thread-Index —
        // er führt jeden benannten Thread, auch den eines Tickets ohne Task-File.
        let second = agent == .codex ? CodexSessions.sessionId(forTicket: ticketKey) : storeId
        return resolve(agent: agent, markerId: marker, otherId: second) {
            hasConversation(agent: agent, sessionId: $0, cwd: cwd)
        }
    }

    /// Welche der beiden Fundstellen die Konversation ist, die es **gibt** — die Entscheidung allein,
    /// ohne Platte, damit sie prüfbar bleibt.
    ///
    /// Die Regel ist die von `ClaudeSessionResolution` und steht dort auch nur einmal: eine Id, unter
    /// der wirklich gearbeitet wurde, trägt eine Aufzeichnung und sticht eine, die keine hat. Das ist
    /// für Codex kein Randfall — wird eine Session neu gestartet und wieder umbenannt, zeigt der
    /// Marker auf den alten Thread, während der Index den laufenden führt. Ohne die Probe setzte
    /// `codex resume` auf der toten Id auf; die Sonde läuft je Kandidat höchstens einmal, weil ein
    /// Rollout-Fund die Datums-Ordner durchgeht.
    static func resolve(agent: AgentKind, markerId: String?, otherId: String?,
                        hasConversation: (String) -> Bool) -> AgentConversation? {
        var probed: [String: Bool] = [:]
        func probe(_ id: String) -> Bool {
            if let known = probed[id] { return known }
            let found = hasConversation(id)
            probed[id] = found
            return found
        }
        guard let id = ClaudeSessionResolution.resolve(taskFileId: markerId, storeId: otherId,
                                                       hasTranscript: probe) else { return nil }
        return AgentConversation(agent: agent, sessionId: id, hasTranscript: probe(id))
    }

    /// Liegt zu dieser Id eine Aufzeichnung auf der Platte? Nur dann lässt sich fortsetzen.
    public static func hasConversation(agent: AgentKind, sessionId: String, cwd: String) -> Bool {
        switch agent {
        case .claude: return ClaudeTranscripts.transcriptExists(sessionId: sessionId, cwd: cwd)
        case .codex:  return CodexSessions.rolloutURL(sessionId: sessionId) != nil
        }
    }
}
