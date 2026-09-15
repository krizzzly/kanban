import Foundation

/// One tool Claude called during a turn, aggregated by name (`Bash ×42`).
public struct ClaudeToolUse: Sendable, Hashable, Identifiable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }

    public var id: String { name }
}

/// What one turn produced, read back out of the transcript — the fallback for prompts that have
/// already scrolled out of tmux's history, where jumping the terminal has nothing to jump to.
///
/// Deliberately *not* everything: one measured turn carried 80 tool results totalling 621 KB next to
/// 4 KB of prose. The prose is what a human reads back; the tool traffic is summarised, not rendered.
public struct ClaudeTurnContent: Sendable, Hashable {
    public let turnIndex: Int
    /// Claude's own text blocks, in order, joined as Markdown. Thinking blocks are left out.
    public let answer: String
    /// Tool calls of the turn, aggregated, in order of first use.
    public let tools: [ClaudeToolUse]
    /// Number of tool results that were not rendered, and roughly how many bytes they hold.
    public let hiddenResults: Int
    public let hiddenBytes: Int

    public init(turnIndex: Int, answer: String, tools: [ClaudeToolUse],
                hiddenResults: Int, hiddenBytes: Int) {
        self.turnIndex = turnIndex
        self.answer = answer
        self.tools = tools
        self.hiddenResults = hiddenResults
        self.hiddenBytes = hiddenBytes
    }

    public var isEmpty: Bool { answer.isEmpty && tools.isEmpty }
}

/// Reads a single turn's content out of a Claude Code transcript.
///
/// Turn boundaries are found exactly the way `ClaudeTurnAccumulator` finds them (a non-sidechain,
/// timestamped entry whose `promptId` differs from the open one), so the index handed in here is the
/// same `ClaudeTurn.index` the timeline shows — including the case where a queued prompt makes the
/// same `promptId` open two separate turns.
///
/// Cost: one pass over the file, JSON-parsing only the lines that carry a `promptId` plus the target
/// turn's own lines. On a 4.8 MB / 1682-line transcript that is single-digit milliseconds — which is
/// why nothing is cached and no byte offsets are threaded through the tail.
public enum ClaudeTurnReader {
    public static func content(turnIndex: Int, transcript url: URL) -> ClaudeTurnContent? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        let bounds = turnBoundaries(in: lines)
        guard turnIndex >= 0, turnIndex < bounds.count else { return nil }

        let start = bounds[turnIndex]
        let end = turnIndex + 1 < bounds.count ? bounds[turnIndex + 1] : lines.count
        return content(turnIndex: turnIndex, lines: lines[start..<end])
    }

    // MARK: - Boundaries

    private static let promptIdKey = Array("\"promptId\"".utf8)
    private static let sidechainKey = Array("\"isSidechain\":true".utf8)

    /// Line indices at which a new turn opens.
    private static func turnBoundaries(in lines: [Data.SubSequence]) -> [Int] {
        var bounds: [Int] = []
        var current: String?
        for (index, line) in lines.enumerated() {
            // Cheap pre-filter: only a handful of lines carry a promptId at all.
            guard contains(line, promptIdKey), !contains(line, sidechainKey) else { continue }
            guard let entry = json(line),
                  let promptId = entry["promptId"] as? String,
                  entry["timestamp"] is String,       // untimed records never open a turn
                  promptId != current
            else { continue }
            current = promptId
            bounds.append(index)
        }
        return bounds
    }

    // MARK: - Content of one turn

    private static func content(turnIndex: Int, lines: ArraySlice<Data.SubSequence>) -> ClaudeTurnContent {
        var answers: [String] = []
        var toolOrder: [String] = []
        var toolCounts: [String: Int] = [:]
        var hiddenResults = 0
        var hiddenBytes = 0

        for line in lines {
            guard let entry = json(line) else { continue }
            guard entry["isSidechain"] as? Bool != true else { continue }
            let type = entry["type"] as? String
            guard type == "assistant" || type == "user" else { continue }
            guard let message = entry["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { continue }

            for block in blocks {
                switch block["type"] as? String {
                case "text" where type == "assistant":
                    if let text = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty {
                        answers.append(text)
                    }
                case "tool_use":
                    guard let name = block["name"] as? String else { continue }
                    if toolCounts[name] == nil { toolOrder.append(name) }
                    toolCounts[name, default: 0] += 1
                case "tool_result":
                    hiddenResults += 1
                    hiddenBytes += line.count   // the whole record, close enough for "≈ 621 KB"
                default:
                    continue
                }
            }
        }

        return ClaudeTurnContent(
            turnIndex: turnIndex,
            answer: answers.joined(separator: "\n\n"),
            tools: toolOrder.map { ClaudeToolUse(name: $0, count: toolCounts[$0] ?? 0) },
            hiddenResults: hiddenResults,
            hiddenBytes: hiddenBytes)
    }

    // MARK: - Bytes

    private static func json(_ line: Data.SubSequence) -> [String: Any]? {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: Data(line)) else { return nil }
        return object as? [String: Any]
    }

    /// Substring search on raw bytes — `String(decoding:)` on every line of a multi-megabyte
    /// transcript costs more than the search itself.
    private static func contains(_ haystack: Data.SubSequence, _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count, let first = needle.first else { return false }
        let limit = haystack.count - needle.count
        var offset = 0
        for index in haystack.indices {
            if offset > limit { return false }
            defer { offset += 1 }
            guard haystack[index] == first else { continue }
            var matched = true
            var cursor = index
            for byte in needle {
                if haystack[cursor] != byte { matched = false; break }
                cursor = haystack.index(after: cursor)
            }
            if matched { return true }
        }
        return false
    }
}
