import Foundation

/// Turns Claude Code transcript lines (`~/.claude/projects/<slug>/<session>.jsonl`) into measured
/// turns. Fed line by line so a growing transcript can be tailed instead of re-read (see
/// `ClaudeTimingStore`); `snapshot()` is valid at any point.
///
/// How a turn is recognised: every conversation entry that belongs to one prompt carries the same
/// `promptId` — the prompt itself **and** the tool results that come back during the answer. A new
/// `promptId` therefore opens a new turn. Claude's assistant entries carry no `promptId` at all, so
/// they extend the turn that is currently open. When Claude finishes, it writes a
/// `system/turn_duration` record whose `durationMs` is its own measurement of that turn.
public struct ClaudeTurnAccumulator: Sendable {
    /// Longest silence inside a turn that still counts as work, used only for turns Claude wrote no
    /// `turn_duration` for. Claude appends an entry every few seconds while it works, so a longer
    /// silence means the turn is blocked on the user — a permission prompt or a question. Without the
    /// cap those waits land in the total: measured against the 81 % of turns that *do* carry Claude's
    /// own duration, capped gaps land within a second of it, while uncapped spans overshoot by ~20 %
    /// (one abandoned turn alone spanned 30 hours). Ten minutes keeps long builds and test runs whole.
    public static let idleGapCap: TimeInterval = 600

    private var finished: [ClaudeTurn] = []
    private var open: Open?

    private struct Open {
        let promptId: String
        let start: Date
        var end: Date
        /// Timestamp of the last entry counted, to measure the gap to the next one.
        var previous: Date
        var activeSeconds: TimeInterval = 0
        var reportedSeconds: TimeInterval?
        var prompt: String
    }

    public init() {}

    /// Every turn parsed so far, including the still-open last one.
    public func snapshot() -> [ClaudeTurn] {
        guard let open else { return finished }
        return finished + [turn(from: open, index: finished.count)]
    }

    public mutating func consume(line: String) {
        // Cheap pre-filter: file-history snapshots (the largest lines by far) and the mode/title
        // records carry no timestamp, so they can never contribute — skip before parsing JSON.
        guard line.contains("\"timestamp\"") else { return }
        guard let data = line.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        // Subagent traffic is not a user turn of this conversation.
        guard entry["isSidechain"] as? Bool != true else { return }
        guard let timestamp = (entry["timestamp"] as? String).flatMap(TranscriptTime.parse) else { return }

        if let promptId = entry["promptId"] as? String, promptId != open?.promptId {
            if let open { finished.append(turn(from: open, index: finished.count)) }
            open = Open(promptId: promptId, start: timestamp, end: timestamp, previous: timestamp,
                        reportedSeconds: nil, prompt: Self.prompt(from: entry) ?? "")
            return
        }

        guard var current = open else { return }   // entries before the first prompt belong to no turn
        switch entry["type"] as? String {
        case "user", "assistant":
            break   // conversation content: the answer is still being written
        case "system":
            guard entry["subtype"] as? String == "turn_duration" else { return }
            current.reportedSeconds = (entry["durationMs"] as? NSNumber).map { $0.doubleValue / 1000 }
        default:
            // attachment / queue-operation / … can be written at times unrelated to the answer.
            return
        }
        // Entries are usually but not strictly ordered — a batch written in the same instant can
        // land milliseconds apart the wrong way round, which must not subtract time.
        let gap = timestamp.timeIntervalSince(current.previous)
        if gap > 0 {
            current.activeSeconds += min(gap, Self.idleGapCap)
            current.previous = timestamp
        }
        current.end = max(current.end, timestamp)
        open = current
    }

    private func turn(from open: Open, index: Int) -> ClaudeTurn {
        ClaudeTurn(index: index, promptId: open.promptId, start: open.start, end: open.end,
                   reportedSeconds: open.reportedSeconds, estimatedSeconds: open.activeSeconds,
                   prompt: open.prompt)
    }

    // MARK: - Prompt preview

    private static func prompt(from entry: [String: Any]) -> String? {
        guard let message = entry["message"] as? [String: Any] else { return nil }
        let raw: String
        if let text = message["content"] as? String {
            raw = text
        } else if let blocks = message["content"] as? [[String: Any]] {
            raw = blocks.compactMap { block in
                block["type"] as? String == "text" ? block["text"] as? String : nil
            }.joined(separator: " ")
        } else {
            return nil
        }
        return condense(raw)
    }

    /// One readable line: slash commands arrive wrapped in `<command-name>` plus a fully expanded
    /// instruction body, which would otherwise flood the turn list.
    static func condense(_ raw: String, limit: Int = 160) -> String {
        var text = raw
        if let name = tag("command-name", in: raw) {
            let args = tag("command-args", in: raw) ?? ""
            text = ([name.hasPrefix("/") ? name : "/" + name, args])
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    private static func tag(_ name: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(name)>"),
              let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex)
        else { return nil }
        return text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Timestamp parsing for transcript entries (`2026-07-22T11:59:37.779Z`). Hand-rolled because this
/// runs on every line of multi-megabyte transcripts; anything unexpected falls back to ISO8601.
enum TranscriptTime {
    static func parse(_ text: String) -> Date? {
        let digits = Array(text.utf8)
        guard digits.count >= 20, digits.last == UInt8(ascii: "Z"),
              digits[4] == UInt8(ascii: "-"), digits[7] == UInt8(ascii: "-"),
              digits[10] == UInt8(ascii: "T"), digits[13] == UInt8(ascii: ":"),
              digits[16] == UInt8(ascii: ":"),
              let year = int(digits, 0, 4), let month = int(digits, 5, 2), let day = int(digits, 8, 2),
              let hour = int(digits, 11, 2), let minute = int(digits, 14, 2), let second = int(digits, 17, 2)
        else { return fallback(text) }

        var fraction = 0.0
        if digits.count > 20, digits[19] == UInt8(ascii: ".") {
            let millis = digits[20..<(digits.count - 1)]
            if let value = int(Array(millis), 0, millis.count) {
                fraction = Double(value) / pow(10, Double(millis.count))
            }
        }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        guard let date = utcCalendar.date(from: components) else { return fallback(text) }
        return date.addingTimeInterval(fraction)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func int(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> Int? {
        guard offset + length <= bytes.count, length > 0 else { return nil }
        var value = 0
        for byte in bytes[offset..<(offset + length)] {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }

    private static func fallback(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
