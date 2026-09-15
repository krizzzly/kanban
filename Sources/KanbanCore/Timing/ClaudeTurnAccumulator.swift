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
        var promptFull: String
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
            let texts = Self.promptTexts(from: entry)
            open = Open(promptId: promptId, start: timestamp, end: timestamp, previous: timestamp,
                        reportedSeconds: nil, prompt: texts?.short ?? "", promptFull: texts?.full ?? "")
            return
        }

        guard var current = open else { return }   // entries before the first prompt belong to no turn
        let type = entry["type"] as? String
        switch type {
        case "user", "assistant":
            // Conversation content: the answer is still being written — but it may also hold the
            // prompt itself. A turn does not always open on what the user typed (see
            // `isTypedPrompt`), so the first typed text of the turn stands in when the opening entry
            // carried none.
            if type == "user", current.promptFull.isEmpty,
               let texts = Self.promptTexts(from: entry), Self.isTypedPrompt(texts.full) {
                current.prompt = texts.short
                current.promptFull = texts.full
            }
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
                   prompt: open.prompt, promptFull: open.promptFull)
    }

    // MARK: - Prompt preview

    /// Longest prompt kept in full. Prompts are typed by hand, so this only ever bites on a pasted
    /// blob — which must not sit in memory once per turn for a session with hundreds of them.
    public static let fullPromptLimit = 4000

    /// Both renderings of one prompt entry, extracted in a single pass: the one-line preview for the
    /// turn list, and the full text for the prompt timeline.
    static func promptTexts(from entry: [String: Any]) -> (short: String, full: String)? {
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
        return (condense(raw), fullText(raw))
    }

    /// The prompt as typed — slash commands still collapsed, but line breaks and length kept.
    ///
    /// Empty when the entry is not something the user typed at all: running a local command opens a
    /// turn whose whole text is Claude Code's `<local-command-caveat>` boilerplate. Those carry time
    /// (so the ⏱ list keeps them) but have no place in a list of prompts.
    static func fullText(_ raw: String, limit: Int = fullPromptLimit) -> String {
        if let command = slashCommand(in: raw) { return command }
        let stripped = removing("local-command-caveat", from: raw)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix(Self.interruptMarker) else { return "" }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    /// What Claude Code writes when a turn is interrupted — `[Request interrupted by user]` or
    /// `[Request interrupted by user for tool use]`. Never a prompt, so it never fills a bubble.
    static let interruptMarker = "[Request interrupted by user"

    /// Whether a text can stand in as the turn's prompt. Excludes Claude Code's own injections
    /// (`<task-notification>`, `<local-command-stdout>`, …) — those arrive as a tag, never as prose,
    /// while a slash command has already been collapsed to `/name args` by then.
    ///
    /// Needed because **a turn does not always open on what the user typed**: interrupting Claude
    /// files its marker entry under the promptId of the prompt that *follows* it, a rejected tool use
    /// opens the turn with a `tool_result` that has no text at all, and a local command opens with
    /// the `<local-command-caveat>` boilerplate (the file even lists it ahead of the `<command-name>`
    /// entry written a millisecond earlier). Measured across 80 transcripts (974 turns): 38 turns
    /// showed `[Request interrupted by user]` in place of the prompt and 33 had no text at all, so
    /// the timeline dropped them — 7 % of all turns, and always the "Esc, then type again" pattern,
    /// which is why it hit the prompt one had just sent. Stealing from the next turn is impossible:
    /// not one typed entry in that corpus lacks a promptId, so a typed text always belongs to the
    /// turn it is read in.
    static func isTypedPrompt(_ full: String) -> Bool {
        !full.isEmpty && !full.hasPrefix("<")
    }

    /// Drops `<tag>…</tag>` including the tag itself; leaves the text untouched when it is absent.
    private static func removing(_ name: String, from text: String) -> String {
        guard let open = text.range(of: "<\(name)>"),
              let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex)
        else { return text }
        return text.replacingCharacters(in: open.lowerBound..<close.upperBound, with: "")
    }

    /// One readable line: slash commands arrive wrapped in `<command-name>` plus a fully expanded
    /// instruction body, which would otherwise flood the turn list.
    static func condense(_ raw: String, limit: Int = 160) -> String {
        let text = slashCommand(in: raw) ?? raw
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    /// `/name args` when the entry is a slash command (they arrive wrapped in `<command-name>` plus a
    /// fully expanded instruction body), else nil.
    private static func slashCommand(in raw: String) -> String? {
        guard let name = tag("command-name", in: raw) else { return nil }
        let args = tag("command-args", in: raw) ?? ""
        return [name.hasPrefix("/") ? name : "/" + name, args]
            .filter { !$0.isEmpty }.joined(separator: " ")
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
