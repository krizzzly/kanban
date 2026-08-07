import Foundation

/// One rendered line of a unified diff, with the line numbers GitLab shows in its gutters.
public struct DiffLine: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case addition     // "+" → light green
        case deletion     // "-" → light red
        case context      // " " → plain
        case hunk         // "@@ …" → the jump marker
        case meta         // "diff --git", "index …", "+++/---" → file header noise
    }

    public let id: Int
    public let kind: Kind
    /// Line content without the leading +/-/space marker.
    public let text: String
    /// Line number on the old side (nil for additions and headers).
    public let oldNumber: Int?
    /// Line number on the new side (nil for deletions and headers).
    public let newNumber: Int?

    public init(id: Int, kind: Kind, text: String, oldNumber: Int?, newNumber: Int?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.oldNumber = oldNumber
        self.newNumber = newNumber
    }
}

/// Turns `git diff` output into renderable lines. Pure — the view only paints what it gets.
public enum DiffParser {
    /// Parses a unified diff. `includeMeta: false` drops the `diff --git` / `index` / `+++` header
    /// lines, which carry no information the dialog doesn't already show.
    public static func parse(_ raw: String, includeMeta: Bool = false) -> [DiffLine] {
        var result: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        var id = 0

        for line in raw.components(separatedBy: .newlines) {
            if line.hasPrefix("@@") {
                let numbers = hunkStart(line)
                oldLine = numbers.old
                newLine = numbers.new
                append(&result, &id, .hunk, line, nil, nil)
                continue
            }
            if isMeta(line) {
                if includeMeta { append(&result, &id, .meta, line, nil, nil) }
                continue
            }
            guard let marker = line.first else {
                // A blank line inside a hunk is context whose leading space was trimmed.
                if !result.isEmpty {
                    append(&result, &id, .context, "", oldLine, newLine)
                    oldLine += 1; newLine += 1
                }
                continue
            }
            let text = String(line.dropFirst())
            switch marker {
            case "+":
                append(&result, &id, .addition, text, nil, newLine)
                newLine += 1
            case "-":
                append(&result, &id, .deletion, text, oldLine, nil)
                oldLine += 1
            case " ":
                append(&result, &id, .context, text, oldLine, newLine)
                oldLine += 1; newLine += 1
            case "\\":
                continue          // "\ No newline at end of file"
            default:
                continue
            }
        }
        return result
    }

    private static func append(_ result: inout [DiffLine], _ id: inout Int,
                               _ kind: DiffLine.Kind, _ text: String, _ old: Int?, _ new: Int?) {
        result.append(DiffLine(id: id, kind: kind, text: text, oldNumber: old, newNumber: new))
        id += 1
    }

    private static func isMeta(_ line: String) -> Bool {
        line.hasPrefix("diff --git") || line.hasPrefix("index ") || line.hasPrefix("--- ")
            || line.hasPrefix("+++ ") || line.hasPrefix("new file mode")
            || line.hasPrefix("deleted file mode") || line.hasPrefix("similarity index")
            || line.hasPrefix("rename from") || line.hasPrefix("rename to")
            || line.hasPrefix("old mode") || line.hasPrefix("new mode")
            || line.hasPrefix("Binary files")
    }

    /// `@@ -12,7 +12,9 @@` → the first line number on each side.
    static func hunkStart(_ line: String) -> (old: Int, new: Int) {
        var old = 1, new = 1
        for token in line.split(separator: " ") {
            guard let sign = token.first, sign == "-" || sign == "+" else { continue }
            let numbers = token.dropFirst().split(separator: ",")
            guard let value = Int(numbers.first ?? "") else { continue }
            if sign == "-" { old = value } else { new = value }
        }
        return (old, new)
    }
}
