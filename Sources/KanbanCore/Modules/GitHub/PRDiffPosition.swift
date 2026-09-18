import Foundation

/// „Datei + Zeilennummer" → der Positions-Body, den GitHubs Review-Comment-API verlangt.
/// Gegenstück zu `MRDiffPosition`: **dieselbe Eingabe, andere Ausgabe**.
///
/// Wo GitLab ein Paar aus `old_line`/`new_line` will, will GitHub `path` + `line` + `side` (plus
/// `start_line`/`start_side` für einen Block über mehrere Zeilen) und dazu den Commit, auf den sich
/// das bezieht. Die **Seite** trägt hier die Information, die dort aus „welches der beiden Felder
/// ist gesetzt" kam:
/// - hinzugefügte Zeile → `RIGHT`
/// - entfernte Zeile → `LEFT`
/// - unveränderte Kontextzeile → beides möglich; es gilt die gefragte Seite
///
/// Der Hunk-Parser ist derselbe (`MRDiffPosition.parseHunks`) — ein Unified Diff ist ein Unified
/// Diff, und zwei Kopien davon wären zwei Stellen, an denen dieselbe Zählung schiefgehen kann.
/// Zeilen ausserhalb jedes Hunks sind auch bei GitHub nicht kommentierbar (422); das scheitert
/// deshalb **vor** dem POST und sagt, welche Bereiche gehen.
public enum PRDiffPosition {
    /// GitHubs Seitenbezeichnung. `LEFT` ist die Datei **vor** dem PR, `RIGHT` die danach.
    public enum Side: String, Sendable {
        case right = "RIGHT"
        case left = "LEFT"

        /// Dieselbe Seite in GitLabs Vokabular — damit der Aufrufer nicht zwei Enums kennen muss.
        public init(_ side: MRDiffPosition.Side) {
            self = side == .new ? .right : .left
        }
    }

    public struct Position: Sendable, Equatable {
        public let path: String
        public let line: Int
        public let side: Side
        /// Anfang eines Mehrzeilen-Kommentars; nil bei einer einzelnen Zeile.
        public let startLine: Int?
        public let startSide: Side?
    }

    public enum PositionError: Error, LocalizedError, Equatable {
        case invalidLine(Int)
        case fileNotInDiff(file: String, known: [String])
        case noCommentableLines(file: String)
        case lineOutsideDiff(file: String, line: Int, side: Side, ranges: String)
        case startAfterEnd(start: Int, line: Int)

        public var errorDescription: String? {
            switch self {
            case .invalidLine(let line):
                return "Ungültige Zeilennummer: \(line)"
            case .fileNotInDiff(let file, let known):
                let list = known.isEmpty ? "(keine)" : known.joined(separator: ", ")
                return "Datei „\(file)“ ist nicht Teil des PR-Diffs. Geänderte Dateien: \(list)"
            case .noCommentableLines(let file):
                return "Datei „\(file)“ hat keine kommentierbaren Diff-Zeilen "
                     + "(binäre Datei, reiner Rename oder ein von GitHub ausgelassener Patch)."
            case .lineOutsideDiff(let file, let line, let side, let ranges):
                return "Zeile \(line) (\(side == .left ? "alte" : "neue") Version) von „\(file)“ "
                     + "liegt ausserhalb des PR-Diffs und ist nicht kommentierbar. "
                     + "Kommentierbare Zeilen: \(ranges)"
            case .startAfterEnd(let start, let line):
                return "Anfangszeile \(start) liegt hinter der Endzeile \(line)."
            }
        }
    }

    /// Löst eine Kommentar-Position gegen die Diffs eines PR auf.
    ///
    /// `startLine` macht daraus einen Kommentar über mehrere Zeilen — GitHubs eigener Weg, für den
    /// GitLab kein Gegenstück hat. Ohne ihn ist es eine einzelne Zeile.
    public static func resolve(diffs: [GitHubDiff], file: String, line: Int,
                               side: Side = .right, startLine: Int? = nil) throws -> Position {
        guard line >= 1 else { throw PositionError.invalidLine(line) }
        if let startLine {
            guard startLine >= 1 else { throw PositionError.invalidLine(startLine) }
            guard startLine <= line else { throw PositionError.startAfterEnd(start: startLine, line: line) }
        }

        guard let entry = diffs.first(where: { $0.newPath == file || $0.oldPath == file }) else {
            throw PositionError.fileNotInDiff(file: file, known: diffs.map(\.newPath))
        }

        let hunks = MRDiffPosition.parseHunks(entry.diff)
        guard !hunks.isEmpty else { throw PositionError.noCommentableLines(file: file) }
        try requireCommentable(hunks, file: entry.newPath, line: line, side: side)
        if let startLine, startLine != line {
            try requireCommentable(hunks, file: entry.newPath, line: startLine, side: side)
        }

        return Position(path: entry.newPath, line: line, side: side,
                        startLine: startLine == line ? nil : startLine,
                        startSide: startLine == nil || startLine == line ? nil : side)
    }

    /// Der POST-Body für `POST /pulls/{n}/comments` — Position plus der Commit, auf den sie zeigt.
    /// Ohne `commit_id` weist GitHub den Kommentar ab, genauso wie GitLab ohne das SHA-Tripel.
    public static func body(_ position: Position, commitId: String) -> [String: Any] {
        var body: [String: Any] = [
            "commit_id": commitId,
            "path": position.path,
            "line": position.line,
            "side": position.side.rawValue,
        ]
        if let startLine = position.startLine { body["start_line"] = startLine }
        if let startSide = position.startSide { body["start_side"] = startSide.rawValue }
        return body
    }

    /// Liegt die Zeile in einem Hunk, und ist sie auf dieser Seite überhaupt vorhanden? Eine
    /// entfernte Zeile gibt es auf `RIGHT` nicht, eine hinzugefügte auf `LEFT` nicht.
    private static func requireCommentable(_ hunks: [MRDiffPosition.Hunk], file: String,
                                           line: Int, side: Side) throws {
        for hunk in hunks {
            for candidate in hunk.lines {
                switch side {
                case .right where candidate.newLine == line
                    && (candidate.kind == .added || candidate.kind == .context):
                    return
                case .left where candidate.oldLine == line
                    && (candidate.kind == .removed || candidate.kind == .context):
                    return
                default:
                    continue
                }
            }
        }
        throw PositionError.lineOutsideDiff(file: file, line: line, side: side,
                                            ranges: ranges(hunks, side: side))
    }

    private static func ranges(_ hunks: [MRDiffPosition.Hunk], side: Side) -> String {
        hunks.map { side == .left ? "\($0.oldStart)-\($0.oldEnd)" : "\($0.newStart)-\($0.newEnd)" }
            .joined(separator: ", ")
    }
}
