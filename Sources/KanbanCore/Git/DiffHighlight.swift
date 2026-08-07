import Foundation

/// Maps a diff onto the *current* file, so an editor can show the same green/red pattern the diff view
/// shows — but against the text that is actually on disk.
///
/// Additions exist in the current file and get tinted. Deletions do not exist there any more, so they
/// cannot be tinted; instead the line they sat in front of is marked, which is what editors do to say
/// "something was removed here".
public struct DiffHighlight: Sendable, Hashable {
    /// 1-based line numbers of the current file that were added or changed.
    public let addedLines: Set<Int>
    /// 1-based line numbers of the current file that directly follow a deletion.
    public let deletionMarkers: Set<Int>

    public init(addedLines: Set<Int>, deletionMarkers: Set<Int>) {
        self.addedLines = addedLines
        self.deletionMarkers = deletionMarkers
    }

    public var isEmpty: Bool { addedLines.isEmpty && deletionMarkers.isEmpty }

    /// Derives the highlight from parsed diff lines.
    public static func from(_ lines: [DiffLine]) -> DiffHighlight {
        var added: Set<Int> = []
        var markers: Set<Int> = []
        var pendingDeletion = false
        /// The next new-side line number, tracked so a deletion can be attached to the line that
        /// follows it even when the deletion is the last thing in a hunk.
        var nextNewLine: Int?

        for line in lines {
            switch line.kind {
            case .addition:
                if let number = line.newNumber {
                    added.insert(number)
                    if pendingDeletion { pendingDeletion = false }   // shown as green, no extra marker
                    nextNewLine = number + 1
                }
            case .deletion:
                pendingDeletion = true
            case .context:
                if let number = line.newNumber {
                    if pendingDeletion {
                        markers.insert(number)
                        pendingDeletion = false
                    }
                    nextNewLine = number + 1
                }
            case .hunk:
                // A deletion at the very end of a hunk marks the line the next hunk continues at.
                if pendingDeletion, let number = nextNewLine {
                    markers.insert(number)
                }
                pendingDeletion = false
            case .meta:
                continue
            }
        }
        if pendingDeletion, let number = nextNewLine { markers.insert(number) }
        return DiffHighlight(addedLines: added, deletionMarkers: markers)
    }
}
