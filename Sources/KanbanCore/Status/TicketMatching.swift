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

    /// Gehört dieser Merge Request zu dem Ticket?
    ///
    /// Normalerweise über den Key in Branch oder Titel. Ein **Ticket ohne Nummer** (freier Modus,
    /// `Ticket.sourceBranch`) hat keinen Key, nach dem sich suchen liesse — es wird über den Branch
    /// erkannt, und zwar **genau**: ein Teilstring-Vergleich zöge `feature/pdf` auch
    /// `feature/pdf_improvements` an sich, und beide sind eigene Arbeiten.
    public static func matches(_ mergeRequest: MergeRequestRef,
                               ticketKey: String, branch: String?) -> Bool {
        if let branch { return mergeRequest.sourceBranch == branch }
        return references(mergeRequest.sourceBranch, ticketKey: ticketKey)
            || references(mergeRequest.title, ticketKey: ticketKey)
    }

    /// Dasselbe für einen Worktree: exakter Branch, sonst der Key irgendwo im Branchnamen.
    public static func matches(_ worktree: Worktree, ticketKey: String, branch: String?) -> Bool {
        if let branch { return worktree.branch == branch }
        return references(worktree.branch ?? "", ticketKey: ticketKey)
    }
}
