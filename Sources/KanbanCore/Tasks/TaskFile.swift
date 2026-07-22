import Foundation

/// A parsed task file: its H2 sections (→ tabs) and the `### Status` marker.
public struct TaskFile: Sendable {
    public let url: URL
    public let directory: URL
    public let sections: [TaskSection]
    public let statusMarker: TaskStatusMarker?
    /// The raw markdown of the file preamble (everything before the first H2): title, `### Status`,
    /// the 🌳 WORKTREE / 🌿 BRANCH / 🐳 STACK / 📅 blockquote, `Typ:`. Shown as the "Status" tab.
    /// The session-id comment is stripped out.
    public let preamble: String

    public init(url: URL, directory: URL, sections: [TaskSection],
                statusMarker: TaskStatusMarker?, preamble: String = "") {
        self.url = url
        self.directory = directory
        self.sections = sections
        self.statusMarker = statusMarker
        self.preamble = preamble
    }
}

public enum TaskFileLoader {
    /// Finds the task file for a ticket via glob `<KEY>*.md` in the tasks directory.
    public static func find(ticketKey: String, in tasksDirectory: String) -> URL? {
        let dir = URL(fileURLWithPath: tasksDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return nil }
        let prefix = ticketKey.uppercased()
        return entries
            .filter { $0.pathExtension == "md" && $0.lastPathComponent.uppercased().hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// Whether *any* task file exists for the ticket (cheaper than a full load).
    public static func exists(ticketKey: String, in tasksDirectory: String) -> Bool {
        find(ticketKey: ticketKey, in: tasksDirectory) != nil
    }

    /// Lightweight per-refresh lookup: does a task file exist, and what is its status marker?
    /// Avoids parsing all sections + rewriting image paths just to learn the marker.
    public static func statusMarker(ticketKey: String, in tasksDirectory: String) -> (exists: Bool, marker: TaskStatusMarker?) {
        guard let url = find(ticketKey: ticketKey, in: tasksDirectory) else { return (false, nil) }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return (true, nil) }
        return (true, parseStatusMarker(content))
    }

    public static func load(_ url: URL) -> TaskFile? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(content: content, url: url)
    }

    /// Returns the ticket's persisted Claude session id, generating and writing one if absent.
    /// The id lives in an invisible HTML comment (see `ClaudeSession`); writing it back is a
    /// one-time event per task file. Returns nil only if the file can't be read.
    @discardableResult
    public static func ensureSessionId(url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if let existing = ClaudeSession.parseSessionId(content) { return existing }
        let id = UUID().uuidString.lowercased()
        let updated = ClaudeSession.contentInserting(sessionId: id, into: content)
        try? updated.write(to: url, atomically: true, encoding: .utf8)
        return id
    }

    /// Writes the `### Status` marker into the task file, moving the card in the board. Returns false
    /// only if the file can't be read or written.
    @discardableResult
    public static func writeStatus(_ marker: TaskStatusMarker, url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let updated = settingStatus(marker, in: content)
        guard updated != content else { return true }
        do { try updated.write(to: url, atomically: true, encoding: .utf8); return true }
        catch { return false }
    }

    /// Returns `content` with the `### Status` line set to `<emoji> <label>`. If a status line already
    /// exists it is replaced (preserving surrounding text); otherwise a `### Status` block is inserted
    /// after the H1 title (or at the top). Pure — unit-testable.
    static func settingStatus(_ marker: TaskStatusMarker, in content: String) -> String {
        let statusLine = "\(marker.emoji) \(marker.label)"
        var lines = content.components(separatedBy: "\n")

        if let h = lines.firstIndex(where: { $0.hasPrefix("### Status") }) {
            let end = min(h + 5, lines.count)
            if let m = (h + 1 ..< end).first(where: { Self.marker(in: lines[$0]) != nil }) {
                lines[m] = statusLine
            } else {
                lines.insert(statusLine, at: h + 1)
            }
            return lines.joined(separator: "\n")
        }

        // No `### Status` section yet → insert one after the H1 title (or at the very top).
        let insertAt = lines.firstIndex { $0.hasPrefix("# ") && !$0.hasPrefix("## ") }.map { $0 + 1 } ?? 0
        lines.insert(contentsOf: ["", "### Status", statusLine], at: insertAt)
        return lines.joined(separator: "\n")
    }

    static func parse(content: String, url: URL) -> TaskFile {
        let directory = url.deletingLastPathComponent()
        let sections = parseSections(content, directory: directory)
        let marker = parseStatusMarker(content)
        let preamble = parsePreamble(content, directory: directory)
        return TaskFile(url: url, directory: directory, sections: sections,
                        statusMarker: marker, preamble: preamble)
    }

    /// Extracts the raw preamble markdown (everything before the first H2), dropping only the
    /// session-id comment line. Rendered as the "Status" tab, so blockquotes / bold / code / emoji
    /// display natively. Returns "" when there is no meaningful preamble.
    static func parsePreamble(_ content: String, directory: URL) -> String {
        var lines: [String] = []
        for raw in content.components(separatedBy: "\n") {
            if raw.hasPrefix("## ") && !raw.hasPrefix("### ") { break }   // first H2 → preamble ends
            if raw.contains(ClaudeSession.markerPrefix) { continue }      // drop session-id comment
            lines.append(raw)
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? "" : rewriteImagePaths(body, directory: directory)
    }

    /// Splits on H2 (`## `) headings. Preamble before the first H2 (H1 title + `### Status`)
    /// is intentionally dropped from the tabs.
    static func parseSections(_ content: String, directory: URL) -> [TaskSection] {
        var sections: [TaskSection] = []
        var currentTitle: String?
        var buffer: [String] = []

        func flush() {
            guard let title = currentTitle else { return }
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let embedded = rewriteImagePaths(embedJsonLinks(body, directory: directory), directory: directory)
            sections.append(TaskSection(id: sections.count, title: title, markdown: embedded))
            buffer = []
        }

        for line in content.components(separatedBy: "\n") {
            // H2 only: starts with "## " but not "### " etc.
            if line.hasPrefix("## ") && !line.hasPrefix("### ") {
                flush()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if currentTitle != nil {
                buffer.append(line)
            }
        }
        flush()
        return sections
    }

    /// Detects the status marker emoji near the `### Status` heading.
    static func parseStatusMarker(_ content: String) -> TaskStatusMarker? {
        let lines = content.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.hasPrefix("### Status") {
            // Look at the heading line itself and the following few lines.
            for candidate in lines[i..<min(i + 4, lines.count)] {
                if let marker = marker(in: candidate) { return marker }
            }
        }
        // Fallback: first marker anywhere in the file.
        return lines.lazy.compactMap { marker(in: $0) }.first
    }

    private static func marker(in line: String) -> TaskStatusMarker? {
        if line.contains("🟡") { return .inArbeit }
        if line.contains("🔵") { return .review }
        if line.contains("🟢") { return .abgeschlossen }
        if line.contains("✅") { return .done }
        if line.contains("🔴") { return .offen }
        return nil
    }

    /// Replaces markdown links to **local `.json` files** with the file's contents rendered as a
    /// fenced ```json code block (monospace), keeping the link text as a label above it. Used for
    /// the "Kommentare" tab, which links to a `comments.json`. Remote/unreadable links are left as-is.
    static func embedJsonLinks(_ markdown: String, directory: URL) -> String {
        let pattern = "\\[([^\\]]*)\\]\\(([^)\\s]+\\.json)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return markdown }
        var out: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let ns = line as NSString
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let content = localFileContents(ns.substring(with: m.range(at: 2)), directory: directory)
            else { out.append(line); continue }
            out.append(ns.replacingCharacters(in: m.range, with: ns.substring(with: m.range(at: 1))))
            out.append("")
            out.append("```json")
            out.append(content.trimmingCharacters(in: .whitespacesAndNewlines))
            out.append("```")
        }
        return out.joined(separator: "\n")
    }

    /// Reads a local text file referenced relative to `directory` (or absolute / `file://`).
    static func localFileContents(_ dest: String, directory: URL) -> String? {
        var path = dest
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") { return nil }
        if path.lowercased().hasPrefix("file://") { path = URL(string: path)?.path ?? path }
        let decoded = path.removingPercentEncoding ?? path
        let url = decoded.hasPrefix("/") ? URL(fileURLWithPath: decoded)
                                         : directory.appendingPathComponent(decoded)
        return try? String(contentsOf: url.standardizedFileURL, encoding: .utf8)
    }

    /// Inlines **local** image links as base64 `data:` URIs. WKWebView's `loadHTMLString(_:baseURL:)`
    /// does not grant filesystem read access, so `file://` image URLs never load (broken-image
    /// placeholder). Embedding the bytes as a `data:` URI sidesteps that entirely. Remote (`http(s)`)
    /// and existing `data:` URIs are left untouched; local files that can't be read are left as-is.
    static func rewriteImagePaths(_ markdown: String, directory: URL) -> String {
        let pattern = "!\\[([^\\]]*)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return markdown }
        let ns = markdown as NSString
        var result = markdown
        // Iterate matches back-to-front so ranges stay valid while replacing.
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let urlRange = match.range(at: 2)
            let (dest, title) = splitDestination(ns.substring(with: urlRange))
            let lower = dest.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") { continue }
            guard let dataURI = imageDataURI(for: dest, directory: directory) else { continue }
            let replacement = title.map { "\(dataURI) \($0)" } ?? dataURI
            result = (result as NSString).replacingCharacters(in: urlRange, with: replacement)
        }
        return result
    }

    /// Splits a markdown link destination into the path and an optional `"title"` part, handling
    /// angle-bracketed `<path>` and trailing titles. In the common case (bare path) `title` is nil.
    static func splitDestination(_ raw: String) -> (dest: String, title: String?) {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("<"), let close = s.dropFirst().firstIndex(of: ">") {
            let dest = String(s[s.index(after: s.startIndex)..<close])
            let title = s[s.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return (dest, title.isEmpty ? nil : title)
        }
        if let space = s.firstIndex(where: { $0.isWhitespace }) {
            let title = s[space...].trimmingCharacters(in: .whitespaces)
            return (String(s[..<space]), title.isEmpty ? nil : title)
        }
        return (s, nil)
    }

    /// Reads a local image (relative to `directory`, or absolute / `file://`) and encodes it as a
    /// `data:<mime>;base64,…` URI. Returns nil when the file can't be read.
    static func imageDataURI(for dest: String, directory: URL) -> String? {
        var path = dest
        if path.lowercased().hasPrefix("file://") {
            path = URL(string: path)?.path ?? path
        }
        let decoded = path.removingPercentEncoding ?? path
        let fileURL = decoded.hasPrefix("/")
            ? URL(fileURLWithPath: decoded)
            : directory.appendingPathComponent(decoded)
        guard let data = try? Data(contentsOf: fileURL.standardizedFileURL) else { return nil }
        let mime = mimeType(forExtension: fileURL.pathExtension.lowercased())
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "gif":          return "image/gif"
        case "webp":         return "image/webp"
        case "svg":          return "image/svg+xml"
        case "bmp":          return "image/bmp"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff":  return "image/tiff"
        case "avif":         return "image/avif"
        default:             return "application/octet-stream"
        }
    }
}
