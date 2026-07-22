import Foundation

public enum TicketMatching {
    /// True if `text` references `ticketKey` as a whole token — i.e. the key occurrence is not
    /// immediately followed by another digit. This prevents "EVEN-1" from matching "EVEN-10",
    /// "EVEN-123", etc., while still matching "feature/EVEN-1_slug" or a trailing "EVEN-1".
    public static func references(_ text: String, ticketKey: String) -> Bool {
        let haystack = text.lowercased()
        let needle = ticketKey.lowercased()
        guard !needle.isEmpty else { return false }
        var start = haystack.startIndex
        while let range = haystack.range(of: needle, range: start..<haystack.endIndex) {
            let after = range.upperBound
            if after == haystack.endIndex || !haystack[after].isNumber { return true }
            start = range.upperBound
        }
        return false
    }
}
