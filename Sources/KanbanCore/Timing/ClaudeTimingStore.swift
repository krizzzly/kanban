import Foundation

/// Reads complete lines out of an append-only file, remembering where it stopped, so a growing
/// transcript is parsed once instead of from the top on every poll. Splitting happens on raw bytes:
/// a read can end mid-codepoint, which decoding per chunk would corrupt.
struct TranscriptTail: Sendable {
    private var offset: UInt64 = 0
    private var pending = Data()

    /// Appends every line completed since the last call. Returns false when the file went away or
    /// shrank — the caller must then start over with a fresh accumulator.
    mutating func consumeNewLines(url: URL, into body: (String) -> Void) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { return false }   // truncated or replaced → the cached state is worthless
        guard size > offset else { return true }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return true }
        offset += UInt64(chunk.count)

        pending.append(chunk)
        let newline = UInt8(ascii: "\n")
        var lineStart = pending.startIndex
        while let breakIndex = pending[lineStart...].firstIndex(of: newline) {
            let line = pending[lineStart..<breakIndex]
            if !line.isEmpty { body(String(decoding: line, as: UTF8.self)) }
            lineStart = pending.index(after: breakIndex)
        }
        pending = Data(pending[lineStart...])
        return true
    }
}

/// Welcher Parser die Zeilen deutet — Claudes Transcript oder Codex' Rollout. Ein Enum statt eines
/// Protokolls, weil `consume` `mutating` ist: durch ein Existential mutiert man nur eine Kopie.
enum TurnParser: Sendable {
    case claude(ClaudeTurnAccumulator)
    case codex(CodexTurnAccumulator)

    static func fresh(for agent: AgentKind) -> TurnParser {
        switch agent {
        case .claude: return .claude(ClaudeTurnAccumulator())
        case .codex:  return .codex(CodexTurnAccumulator())
        }
    }

    mutating func consume(line: String) {
        switch self {
        case .claude(var acc): acc.consume(line: line); self = .claude(acc)
        case .codex(var acc):  acc.consume(line: line); self = .codex(acc)
        }
    }

    func snapshot() -> [ClaudeTurn] {
        switch self {
        case .claude(let acc): return acc.snapshot()
        case .codex(let acc):  return acc.snapshot()
        }
    }
}

/// Cumulative agent timings per session, cached across refreshes.
///
/// The first look at a session parses its whole transcript (they reach tens of megabytes); every
/// later look reads only what the agent appended since. That is what makes polling the board — and
/// watching the live transcript of the selected ticket — cheap.
///
/// Die Datei unterscheidet sich je Agent (`~/.claude/projects/<slug>/<id>.jsonl` gegen
/// `~/.codex/sessions/…/rollout-*-<id>.jsonl`), das Format ebenso — dahinter ist alles gleich:
/// beide Parser liefern `ClaudeTurn`s, also hängen Badge, Chip, Turn-Liste und Buchung unverändert
/// daran. Codex' Turns sind dabei durchweg exakt (siehe `CodexTurnAccumulator`).
public actor ClaudeTimingStore {
    public static let shared = ClaudeTimingStore()

    private struct Cached {
        var url: URL
        var tail: TranscriptTail
        var parser: TurnParser
    }

    private var cache: [String: Cached] = [:]

    public init() {}

    /// Timing for one session, or nil when no transcript exists yet (the agent was never launched,
    /// or — bei Codex — noch kein Turn gelaufen: die Rollout-Datei entsteht erst mit dem Inhalt).
    /// `cwd` is the directory the agent runs in — Claudes Transcript wird dort zuerst gesucht.
    public func timing(sessionId: String, cwd: String,
                       agent: AgentKind = .claude) -> ClaudeSessionTiming? {
        guard let url = Self.transcriptURL(sessionId: sessionId, cwd: cwd, agent: agent) else {
            cache[sessionId] = nil
            return nil
        }
        var state = cache[sessionId]
        if state?.url != url {
            state = Cached(url: url, tail: TranscriptTail(), parser: .fresh(for: agent))
        }
        guard var state else { return nil }

        var parser = state.parser
        if !state.tail.consumeNewLines(url: url, into: { parser.consume(line: $0) }) {
            // The file was rewritten under us — reparse from the top rather than report nonsense.
            state = Cached(url: url, tail: TranscriptTail(), parser: .fresh(for: agent))
            parser = .fresh(for: agent)
            guard state.tail.consumeNewLines(url: url, into: { parser.consume(line: $0) }) else {
                cache[sessionId] = nil
                return nil
            }
        }
        state.parser = parser
        cache[sessionId] = state

        let turns = parser.snapshot()
        guard !turns.isEmpty else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return ClaudeSessionTiming(sessionId: sessionId, turns: turns, lastModified: mtime)
    }

    /// Timings for a whole board: `sessionIds` maps ticket key → session id des Agents.
    public func timings(sessionIds: [String: String], cwd: String,
                        agent: AgentKind = .claude) -> [String: ClaudeSessionTiming] {
        var result: [String: ClaudeSessionTiming] = [:]
        for (ticketKey, sessionId) in sessionIds {
            if let timing = timing(sessionId: sessionId, cwd: cwd, agent: agent) {
                result[ticketKey] = timing
            }
        }
        return result
    }

    /// Wo die Konversation liegt — der einzige agent-abhängige Schritt. Öffentlich, weil auch der
    /// Live-Watcher (`AppModel.startTimingWatch`) genau diese Datei beobachtet.
    public static func transcriptURL(sessionId: String, cwd: String, agent: AgentKind) -> URL? {
        switch agent {
        case .claude: return ClaudeTranscripts.transcriptURL(sessionId: sessionId, cwd: cwd)
        case .codex:  return CodexSessions.rolloutURL(sessionId: sessionId)
        }
    }
}
