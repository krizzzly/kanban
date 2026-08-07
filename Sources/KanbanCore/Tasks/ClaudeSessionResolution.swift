import Foundation

/// Decides which of a ticket's recorded Claude session ids is the conversation that actually exists.
///
/// A ticket can end up with two ids, and they disagree: the app generates one when the ticket is
/// opened before a task file exists (kept in `sessions.json`), and once the task file appears —
/// usually written by that very console — the marker in the file gets filled with a *fresh* id. The
/// file used to win unconditionally, so the board pointed at a conversation that was never started:
/// no ⏱ time, no hook attention, and a new console would open blank instead of resuming.
///
/// The transcript on disk is the tie-breaker: an id Claude has actually run under has one.
public enum ClaudeSessionResolution {
    /// The id to use, or nil when the ticket has none recorded yet (the caller then makes one).
    ///
    /// Preference: an id with a transcript wins over one without; between two of those the task file
    /// wins, because that is where the id belongs long-term.
    public static func resolve(taskFileId: String?, storeId: String?,
                              hasTranscript: (String) -> Bool) -> String? {
        let candidates = [taskFileId, storeId].compactMap { $0 }.filter { !$0.isEmpty }
        return candidates.first(where: hasTranscript) ?? candidates.first
    }

    /// Convenience for the app: resolves against the transcripts of `cwd`.
    public static func resolve(taskFileId: String?, storeId: String?, cwd: String) -> String? {
        resolve(taskFileId: taskFileId, storeId: storeId) { id in
            ClaudeTranscripts.transcriptURL(sessionId: id, cwd: cwd) != nil
        }
    }
}
