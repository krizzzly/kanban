import Foundation

/// Jira's duration vocabulary, ported from Hermes' `parseTimeSpentSeconds` /
/// `formatSecondsAsJiraDuration`. Jira's convention: **1d = 8h**, 1w = 5d — a working day, not 24 h.
public enum JiraDuration {
    public enum ParseError: Error, LocalizedError, Equatable {
        case empty
        case invalid(String)
        case tooShort(String)

        public var errorDescription: String? {
            switch self {
            case .empty:
                return #"Zeit fehlt. Beispiele: "1h 30m", "2d", "90m" oder "1.5"."#
            case .invalid(let input):
                return #"Ungültige Zeitangabe: "\#(input)". Erlaubt: "1h 30m", "2d", "90m" oder Dezimalstunden wie "1.5"."#
            case .tooShort(let input):
                return #"Zeit "\#(input)" ist zu klein (mindestens 1 Minute)."#
            }
        }
    }

    private static let unitSeconds: [Character: Double] = ["w": 5 * 8 * 3600, "d": 8 * 3600,
                                                           "h": 3600, "m": 60]
    private static let tokenPattern = #"(\d+(?:\.\d+)?)\s*([wdhm])"#

    /// `"1h 30m"` / `"2d"` / `"90m"` → seconds, and a bare number counts as **decimal hours**
    /// (`"1.5"` = 90 min). Anything not fully consumed by valid tokens is rejected rather than
    /// half-understood, and under a minute is refused — Jira would round it away anyway.
    public static func parse(_ input: String?) throws -> Int {
        let text = (input ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { throw ParseError.empty }

        let seconds: Int
        if text.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil {
            seconds = Int((Double(text) ?? 0) * 3600, rounding: .toNearestOrAwayFromZero)
        } else {
            let remainder = text.replacingOccurrences(of: tokenPattern, with: "",
                                                      options: .regularExpression)
            guard remainder.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ParseError.invalid(input ?? "")
            }
            var total: Double = 0
            for match in matches(in: text) {
                total += match.value * (unitSeconds[match.unit] ?? 0)
            }
            seconds = Int(total, rounding: .toNearestOrAwayFromZero)
        }

        guard seconds >= 60 else { throw ParseError.tooShort(input ?? "") }
        return seconds
    }

    /// Seconds → Jira's own notation (`"1d 2h 30m"`), nil for nothing worth showing.
    public static func format(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        var rest = seconds
        let days = rest / (8 * 3600); rest -= days * 8 * 3600
        let hours = rest / 3600; rest -= hours * 3600
        let minutes = rest / 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }

    private static func matches(in text: String) -> [(value: Double, unit: Character)] {
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]),
                  let unit = text[unitRange].first else { return nil }
            return (value, unit)
        }
    }
}

private extension Int {
    init(_ value: Double, rounding rule: FloatingPointRoundingRule) {
        self = Int(value.rounded(rule))
    }
}
