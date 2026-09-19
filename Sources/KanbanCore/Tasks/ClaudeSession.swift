import Foundation

/// Reads / writes the session ids that tie a ticket's task file to resumable conversations — **one
/// marker per agent**, stored as an **invisible HTML comment** in the file preamble (before the
/// first H2), so neither becomes a tab and neither renders:
///
///     <!-- kanban-claude-session: 4f2c… -->
///     <!-- kanban-codex-session: 01a01e3b… -->
///
/// The two are independent: reading or writing one leaves the other byte-for-byte alone, which is
/// what keeps both conversations of an agent-switched ticket addressable. Their order in the file is
/// fixed (see `AgentKind`), so writing the same file twice never reshuffles it.
///
/// Where the id comes from differs per agent: Claude's we generate and hand to
/// `claude --session-id <uuid>`, which makes create/resume deterministic; Codex invents its own and
/// Kanban finds it through the thread name (see `CodexSessions`).
public enum ClaudeSession {
    /// Every agent's marker prefix — what `TaskFileLoader.parsePreamble` has to drop so no marker
    /// ever shows up in the rendered Status tab.
    public static var markerPrefixes: [String] { AgentKind.allCases.map(\.sessionMarkerPrefix) }

    /// Extracts the stored session id of `agent`, or nil if its marker is absent.
    public static func parseSessionId(_ content: String, agent: AgentKind = .claude) -> String? {
        guard let range = markerRange(of: agent, in: content) else { return nil }
        let ns = content as NSString
        let id = ns.substring(with: range.id).trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    /// Returns `content` with `agent`'s session marker set to `sessionId`. An existing marker of the
    /// same agent is replaced in place; otherwise the marker joins the block in agent order. All
    /// other content is preserved byte-for-byte — markers of other agents included.
    public static func contentInserting(sessionId: String, agent: AgentKind = .claude,
                                        into content: String) -> String {
        let marker = "<!-- \(agent.sessionMarkerPrefix) \(sessionId) -->"
        let ns = content as NSString

        if let own = markerRange(of: agent, in: content) {
            return ns.replacingCharacters(in: own.whole, with: marker)
        }
        // Behind the nearest marker that ranks before this agent, so the block stays sorted whatever
        // order the two ids arrive in.
        for earlier in AgentKind.allCases.prefix(while: { $0 != agent }).reversed() {
            guard let range = markerRange(of: earlier, in: content) else { continue }
            let line = ns.substring(with: range.whole)
            return ns.replacingCharacters(in: range.whole, with: line + "\n" + marker)
        }
        return content.isEmpty ? marker + "\n" : marker + "\n" + content
    }

    /// The marker of `agent` in `content`: the whole comment and, inside it, the id.
    private static func markerRange(of agent: AgentKind,
                                    in content: String) -> (whole: NSRange, id: NSRange)? {
        let prefix = NSRegularExpression.escapedPattern(for: agent.sessionMarkerPrefix)
        // Tolerant of surrounding whitespace, as a hand-edited file may carry any.
        guard let regex = try? NSRegularExpression(pattern: "<!--\\s*\(prefix)\\s*([^\\s>]+)\\s*-->")
        else { return nil }
        let ns = content as NSString
        guard let match = regex.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return (match.range, match.range(at: 1))
    }
}
