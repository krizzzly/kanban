import Foundation

/// „Datei + Zeilennummer" → das `old_line`/`new_line`-Paar, das GitLabs Discussions-API für einen
/// Inline-Kommentar verlangt. Port von Hermes' `modules/gitlab/position.js`.
///
/// GitLabs Regel, und der Grund für den ganzen Aufwand:
/// - hinzugefügte Zeile → nur `new_line`
/// - entfernte Zeile → nur `old_line`
/// - unveränderte Kontextzeile → **beide**
///
/// Zeilen ausserhalb jedes Hunks sind nicht kommentierbar; GitLab quittiert sie mit 400. Das hier
/// scheitert deshalb vor dem POST und sagt, welche Bereiche gehen.
public enum MRDiffPosition {
    public enum Side: String, Sendable {
        case new, old
    }

    public struct Line: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case added, removed, context }
        public let kind: Kind
        public let oldLine: Int?
        public let newLine: Int?
    }

    public struct Hunk: Sendable, Equatable {
        public let oldStart: Int
        public let newStart: Int
        public var oldEnd: Int
        public var newEnd: Int
        public var lines: [Line]
    }

    public struct Position: Sendable, Equatable {
        public let oldPath: String
        public let newPath: String
        public let oldLine: Int?
        public let newLine: Int?
    }

    public enum PositionError: Error, LocalizedError, Equatable {
        case invalidLine(Int)
        case fileNotInDiff(file: String, known: [String])
        case noCommentableLines(file: String)
        case lineOutsideDiff(file: String, line: Int, side: Side, ranges: String)

        public var errorDescription: String? {
            switch self {
            case .invalidLine(let line):
                return "Ungültige Zeilennummer: \(line)"
            case .fileNotInDiff(let file, let known):
                let list = known.isEmpty ? "(keine)" : known.joined(separator: ", ")
                return "Datei „\(file)“ ist nicht Teil des MR-Diffs. Geänderte Dateien: \(list)"
            case .noCommentableLines(let file):
                return "Datei „\(file)“ hat keine kommentierbaren Diff-Zeilen "
                     + "(binäre Datei oder reiner Rename)."
            case .lineOutsideDiff(let file, let line, let side, let ranges):
                return "Zeile \(line) (\(side == .old ? "alte" : "neue") Version) von „\(file)“ liegt "
                     + "ausserhalb des MR-Diffs und ist nicht kommentierbar. "
                     + "Kommentierbare Zeilen: \(ranges)"
            }
        }
    }

    private static let hunkHeader = #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#

    /// Zerlegt einen Unified Diff (GitLabs `diff`-Feld je Datei) in Hunks mit durchnummerierten
    /// alten und neuen Zeilen.
    public static func parseHunks(_ diffText: String) -> [Hunk] {
        var raw = diffText.components(separatedBy: "\n")
        // Ein abschliessendes \n erzeugt beim Splitten ein leeres Artefakt — eine echte leere
        // Kontextzeile ist ein einzelnes Leerzeichen, das Wegwerfen ist also gefahrlos.
        if raw.last == "" { raw.removeLast() }

        var hunks: [Hunk] = []
        var oldCursor = 0
        var newCursor = 0

        for line in raw {
            if let header = hunkStart(line) {
                oldCursor = header.old
                newCursor = header.new
                hunks.append(Hunk(oldStart: oldCursor, newStart: newCursor,
                                  oldEnd: oldCursor, newEnd: newCursor, lines: []))
                continue
            }
            guard !hunks.isEmpty else { continue }          // Präambel (--- / +++)
            if line.hasPrefix("\\") { continue }            // „\ No newline at end of file"

            if line.hasPrefix("+") {
                hunks[hunks.count - 1].lines.append(Line(kind: .added, oldLine: nil, newLine: newCursor))
                newCursor += 1
            } else if line.hasPrefix("-") {
                hunks[hunks.count - 1].lines.append(Line(kind: .removed, oldLine: oldCursor, newLine: nil))
                oldCursor += 1
            } else {
                hunks[hunks.count - 1].lines.append(Line(kind: .context, oldLine: oldCursor, newLine: newCursor))
                oldCursor += 1
                newCursor += 1
            }
            hunks[hunks.count - 1].oldEnd = oldCursor - 1
            hunks[hunks.count - 1].newEnd = newCursor - 1
        }
        return hunks
    }

    /// Löst eine Kommentar-Position gegen die Diffs eines MR auf.
    public static func resolve(diffs: [GitLabDiff], file: String, line: Int,
                               side: Side = .new) throws -> Position {
        guard line >= 1 else { throw PositionError.invalidLine(line) }

        guard let entry = diffs.first(where: { $0.newPath == file || $0.oldPath == file }) else {
            throw PositionError.fileNotInDiff(file: file, known: diffs.map(\.newPath))
        }

        let hunks = parseHunks(entry.diff)
        guard !hunks.isEmpty else { throw PositionError.noCommentableLines(file: file) }

        for hunk in hunks {
            for candidate in hunk.lines {
                switch side {
                case .new where candidate.newLine == line
                    && (candidate.kind == .added || candidate.kind == .context):
                    return Position(oldPath: entry.oldPath, newPath: entry.newPath,
                                    oldLine: candidate.oldLine, newLine: line)
                case .old where candidate.oldLine == line
                    && (candidate.kind == .removed || candidate.kind == .context):
                    return Position(oldPath: entry.oldPath, newPath: entry.newPath,
                                    oldLine: line, newLine: candidate.newLine)
                default:
                    continue
                }
            }
        }

        throw PositionError.lineOutsideDiff(file: file, line: line, side: side,
                                            ranges: ranges(hunks, side: side))
    }

    /// Der `position`-Body für `POST /discussions` — Position plus das SHA-Tripel des MR.
    public static func body(_ position: Position, refs: GitLabDiffRefs) -> [String: Any] {
        var body: [String: Any] = [
            "position_type": "text",
            "base_sha": refs.baseSha ?? "",
            "start_sha": refs.startSha ?? "",
            "head_sha": refs.headSha ?? "",
            "old_path": position.oldPath,
            "new_path": position.newPath,
        ]
        if let oldLine = position.oldLine { body["old_line"] = oldLine }
        if let newLine = position.newLine { body["new_line"] = newLine }
        return body
    }

    private static func ranges(_ hunks: [Hunk], side: Side) -> String {
        hunks.map { side == .old ? "\($0.oldStart)-\($0.oldEnd)" : "\($0.newStart)-\($0.newEnd)" }
            .joined(separator: ", ")
    }

    private static func hunkStart(_ line: String) -> (old: Int, new: Int)? {
        guard let regex = try? NSRegularExpression(pattern: hunkHeader),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 3), in: line),
              let old = Int(line[oldRange]), let new = Int(line[newRange]) else { return nil }
        return (old, new)
    }
}
