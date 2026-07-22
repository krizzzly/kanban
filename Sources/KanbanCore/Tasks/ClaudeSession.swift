import Foundation

/// Reads / writes the Claude session id that ties a ticket's task file to a resumable
/// `claude --resume <uuid>` conversation. The id is stored as an **invisible HTML comment**
/// in the file preamble (before the first H2), so it never becomes a tab and never renders:
///
///     <!-- kanban-claude-session: 4f2c… -->
///
/// We generate the id ourselves (see `TaskFileLoader.ensureSessionId`) and launch
/// `claude --session-id <uuid>`, which makes create/resume fully deterministic.
public enum ClaudeSession {
    static let markerPrefix = "kanban-claude-session:"

    /// Extracts the stored session id, or nil if the marker is absent.
    public static func parseSessionId(_ content: String) -> String? {
        // Match `<!-- kanban-claude-session: <id> -->`, tolerant of surrounding whitespace.
        let pattern = "<!--\\s*\(NSRegularExpression.escapedPattern(for: markerPrefix))\\s*([^\\s>]+)\\s*-->"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = content as NSString
        guard let match = regex.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        let id = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    /// Returns `content` with the session marker set to `sessionId`. If a marker already exists it is
    /// replaced in place; otherwise the marker is prepended to the top of the file. All other content
    /// is preserved byte-for-byte.
    public static func contentInserting(sessionId: String, into content: String) -> String {
        let marker = "<!-- \(markerPrefix) \(sessionId) -->"
        let pattern = "<!--\\s*\(NSRegularExpression.escapedPattern(for: markerPrefix))\\s*[^\\s>]+\\s*-->"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = content as NSString
            if let match = regex.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)) {
                return ns.replacingCharacters(in: match.range, with: marker)
            }
        }
        return content.isEmpty ? marker + "\n" : marker + "\n" + content
    }
}
