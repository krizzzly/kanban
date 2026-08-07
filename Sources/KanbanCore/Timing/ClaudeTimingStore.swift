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

/// Cumulative Claude timings per session, cached across refreshes.
///
/// The first look at a session parses its whole transcript (they reach tens of megabytes); every
/// later look reads only what Claude appended since. That is what makes polling the board — and
/// watching the live transcript of the selected ticket — cheap.
public actor ClaudeTimingStore {
    public static let shared = ClaudeTimingStore()

    private struct Cached {
        var url: URL
        var tail: TranscriptTail
        var accumulator: ClaudeTurnAccumulator
    }

    private var cache: [String: Cached] = [:]

    public init() {}

    /// Timing for one session, or nil when no transcript exists yet (Claude was never launched).
    /// `cwd` is the directory Claude runs in — the transcript is looked up there first.
    public func timing(sessionId: String, cwd: String) -> ClaudeSessionTiming? {
        guard let url = ClaudeTranscripts.transcriptURL(sessionId: sessionId, cwd: cwd) else {
            cache[sessionId] = nil
            return nil
        }
        var state = cache[sessionId]
        if state?.url != url {
            state = Cached(url: url, tail: TranscriptTail(), accumulator: ClaudeTurnAccumulator())
        }
        guard var state else { return nil }

        var accumulator = state.accumulator
        if !state.tail.consumeNewLines(url: url, into: { accumulator.consume(line: $0) }) {
            // The file was rewritten under us — reparse from the top rather than report nonsense.
            state = Cached(url: url, tail: TranscriptTail(), accumulator: ClaudeTurnAccumulator())
            accumulator = ClaudeTurnAccumulator()
            guard state.tail.consumeNewLines(url: url, into: { accumulator.consume(line: $0) }) else {
                cache[sessionId] = nil
                return nil
            }
        }
        state.accumulator = accumulator
        cache[sessionId] = state

        let turns = accumulator.snapshot()
        guard !turns.isEmpty else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return ClaudeSessionTiming(sessionId: sessionId, turns: turns, lastModified: mtime)
    }

    /// Timings for a whole board: `sessionIds` maps ticket key → Claude session id.
    public func timings(sessionIds: [String: String], cwd: String) -> [String: ClaudeSessionTiming] {
        var result: [String: ClaudeSessionTiming] = [:]
        for (ticketKey, sessionId) in sessionIds {
            if let timing = timing(sessionId: sessionId, cwd: cwd) { result[ticketKey] = timing }
        }
        return result
    }
}
