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
    /// Finds the task file for a ticket via glob `<KEY>*.md` in the tasks directory. Review files
    /// (`<KEY>_review*.md`) are excluded — they're surfaced as their own "Review" tabs, not the main.
    public static func find(ticketKey: String, in tasksDirectory: String) -> URL? {
        let dir = URL(fileURLWithPath: tasksDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return nil }
        let prefix = ticketKey.uppercased()
        return entries
            .filter { $0.pathExtension == "md"
                && belongsToTicket($0.lastPathComponent, keyPrefix: prefix)
                && !isReviewFilename($0.lastPathComponent, keyPrefix: prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// Whether a filename belongs to exactly this ticket: the key must be followed by a `_` or `.`
    /// boundary, so `BFEZVM-4569` does not swallow `BFEZVM-45690_…`. Case-insensitive.
    static func belongsToTicket(_ name: String, keyPrefix: String) -> Bool {
        let upper = name.uppercased()
        guard upper.hasPrefix(keyPrefix) else { return false }
        let rest = upper.dropFirst(keyPrefix.count)
        return rest.hasPrefix("_") || rest.hasPrefix(".")
    }

    /// All review files for a ticket — `<KEY>_review.md`, `<KEY>_review_prong_b.md`, … — sorted by
    /// name so their tab numbering ("Review #1", "Review #2", …) is stable.
    public static func reviewFiles(ticketKey: String, in tasksDirectory: String) -> [URL] {
        let dir = URL(fileURLWithPath: tasksDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        let prefix = ticketKey.uppercased()
        return entries
            .filter { $0.pathExtension == "md" && isReviewFilename($0.lastPathComponent, keyPrefix: prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A review file is `<KEY>_review…` — the `_review` token immediately follows the ticket key
    /// (so `BFEZVM-45690_review.md` is not mistaken for a review of `BFEZVM-4569`). Case-insensitive.
    static func isReviewFilename(_ name: String, keyPrefix: String) -> Bool {
        let upper = name.uppercased()
        guard upper.hasPrefix(keyPrefix) else { return false }
        return upper.dropFirst(keyPrefix.count).hasPrefix("_REVIEW")
    }

    /// Loads a review file's **entire** content as one markdown blob (shown in a single "Review"
    /// tab), with local image paths inlined. Returns nil if the file can't be read.
    public static func loadReviewMarkdown(_ url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let directory = url.deletingLastPathComponent()
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : rewriteImagePaths(body, directory: directory)
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

    /// Reads the ticket's stored Claude session id **without** creating one. Returns nil if there's
    /// no task file or no marker yet. Used to map hook attention-markers back to tickets.
    public static func peekSessionId(ticketKey: String, in tasksDirectory: String) -> String? {
        guard let url = find(ticketKey: ticketKey, in: tasksDirectory),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return ClaudeSession.parseSessionId(content)
    }

    /// The session id stored in this task file, without creating one.
    public static func sessionId(in url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return ClaudeSession.parseSessionId(content)
    }

    /// Writes `sessionId` into the task file's marker, replacing any previous one. Used to pin the
    /// ticket's real conversation into the file — see `ClaudeSessionResolution` for why a task file
    /// may hold an id that no conversation was ever started under.
    @discardableResult
    public static func writeSessionId(_ sessionId: String, url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        guard ClaudeSession.parseSessionId(content) != sessionId else { return true }
        let updated = ClaudeSession.contentInserting(sessionId: sessionId, into: content)
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
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

    /// Writes the feature branch (from the ticket's GitLab MR) into the task file's
    /// `🌿 **BRANCH**` line. No-op if there's no BRANCH line or it already matches. Returns false
    /// only on a read/write error.
    @discardableResult
    public static func writeBranch(_ branch: String, url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let updated = settingBranch(branch, in: content)
        guard updated != content else { return true }
        do { try updated.write(to: url, atomically: true, encoding: .utf8); return true }
        catch { return false }
    }

    /// Returns `content` with the ticket's feature branch set to `branch`. If a `**BRANCH**` line
    /// exists, its first backtick code-span is replaced (preserving blockquote `>`, emoji, trailing
    /// `\`). Otherwise a `> 🌿 **BRANCH**: \`<branch>\`` line is inserted directly under the H1 title
    /// (or at the top if there is none). Unchanged if it already shows `branch`. Pure — unit-testable.
    static func settingBranch(_ branch: String, in content: String) -> String {
        var lines = content.components(separatedBy: "\n")

        if let idx = lines.firstIndex(where: { $0.contains("**BRANCH**") }) {
            let line = lines[idx]
            guard let open = line.firstIndex(of: "`") else { return content }
            let afterOpen = line.index(after: open)
            guard let close = line[afterOpen...].firstIndex(of: "`") else { return content }
            guard String(line[afterOpen..<close]) != branch else { return content }
            lines[idx] = line.replacingCharacters(in: afterOpen..<close, with: branch)
            return lines.joined(separator: "\n")
        }

        // No BRANCH line yet → insert one right under the task title (H1), else at the very top.
        let newLine = "> 🌿 **BRANCH**: `\(branch)`"
        let insertAt = lines.firstIndex { $0.hasPrefix("# ") && !$0.hasPrefix("## ") }.map { $0 + 1 } ?? 0
        lines.insert(newLine, at: insertAt)
        return lines.joined(separator: "\n")
    }

    /// Writes/updates the `**Merge Request:**` line (with the MR URL) at the bottom of the task file.
    /// Idempotent: updates the existing line in place, or appends one if absent. Returns false only
    /// on a read/write error.
    @discardableResult
    public static func writeMergeRequest(url mrURL: String, file: URL) -> Bool {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return false }
        let updated = settingMergeRequest(mrURL, in: content)
        guard updated != content else { return true }
        do { try updated.write(to: file, atomically: true, encoding: .utf8); return true }
        catch { return false }
    }

    /// Returns `content` with a `**Merge Request:** <url>` line: replaced in place if one already
    /// exists, otherwise appended at the bottom (after a blank line). Unchanged if already correct.
    /// Pure — unit-testable.
    static func settingMergeRequest(_ mrURL: String, in content: String) -> String {
        let newLine = "**Merge Request:** \(mrURL)"
        var lines = content.components(separatedBy: "\n")
        if let idx = lines.firstIndex(where: { $0.contains("**Merge Request:**") }) {
            guard lines[idx] != newLine else { return content }
            lines[idx] = newLine
            return lines.joined(separator: "\n")
        }
        var trimmed = content
        while trimmed.hasSuffix("\n") { trimmed.removeLast() }
        return trimmed + "\n\n" + newLine + "\n"
    }

    /// The task-file name derived from a feature branch: the branch's last path segment plus `.md`
    /// (e.g. `feature/ZBA-489_pdf_access` → `ZBA-489_pdf_access.md`). nil if empty.
    static func fileName(forBranch branch: String) -> String? {
        let base = (branch.split(separator: "/").last.map(String.init) ?? branch)
            .trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        return base.hasSuffix(".md") ? base : base + ".md"
    }

    /// Renames the task file so its name matches the MR's feature branch. Safe: only renames when the
    /// derived name **still belongs to the ticket** (so `find` keeps locating it), the name actually
    /// differs, and no other file already occupies the target. Returns the new URL, or nil (no change).
    @discardableResult
    public static func renameToMatchBranch(currentURL: URL, branch: String, ticketKey: String) -> URL? {
        guard let desired = fileName(forBranch: branch),
              belongsToTicket(desired, keyPrefix: ticketKey.uppercased()),
              desired.lowercased() != currentURL.lastPathComponent.lowercased() else { return nil }
        let target = currentURL.deletingLastPathComponent().appendingPathComponent(desired)
        guard !FileManager.default.fileExists(atPath: target.path) else { return nil }
        do { try FileManager.default.moveItem(at: currentURL, to: target); return target }
        catch { return nil }
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

    /// The marker a status line carries. First match wins, so the order is part of the contract:
    /// `hold` is checked first because a line naming two markers ("🟡 → ⏸️") describes a ticket being
    /// paused — the pause must not be swallowed by the emoji it replaces.
    ///
    /// ⏸️ is matched **by its base scalar** (U+23F8), not as a string. It is the only marker with an
    /// emoji-presentation variation selector (U+23F8 U+FE0F), and Swift compares grapheme clusters:
    /// `"⏸️ Hold".contains("⏸")` is `false`. A hand-typed or copied ⏸ without the selector would
    /// otherwise read as "no status at all" — silently, since an unparsed marker is indistinguishable
    /// from a task file that never had one. Written back is always the presentation form (`emoji`),
    /// so files this app writes stay uniform.
    private static func marker(in line: String) -> TaskStatusMarker? {
        if line.unicodeScalars.contains("\u{23F8}") { return .hold }
        if line.contains("🟡") { return .inArbeit }
        if line.contains("🔵") { return .review }
        if line.contains("🟢") { return .abgeschlossen }
        if line.contains("✅") { return .done }
        if line.contains("🔴") { return .offen }
        return nil
    }

    /// Ersetzt Markdown-Links auf **lokale `.json`-Dateien** durch deren Inhalt, der Linktext bleibt
    /// als Beschriftung darüber stehen. Eine Kommentar-Datei (`comments.json`) wird dabei als
    /// **Diskussion** gerendert (`CommentThread`), alles andere als ```json-Block. Entfernte oder
    /// unlesbare Links bleiben, wie sie sind.
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
            // Eine Kommentar-Diskussion wird als solche gezeigt; alles andere bleibt roher JSON —
            // eine fremde Datei zu interpretieren, nur weil sie `.json` heisst, ginge daneben.
            if let comments = CommentThread.parse(content) {
                out.append(CommentThread.markdown(comments, directory: directory))
            } else {
                out.append("```json")
                out.append(content.trimmingCharacters(in: .whitespacesAndNewlines))
                out.append("```")
            }
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
    /// Local media larger than this — and every non-image type (videos, PDFs, …) — is rendered as a
    /// clickable link instead of inlined. A multi-MB base64 `data:` URI makes the generated HTML huge
    /// and chokes WKWebView (and a video can't render as an `<img>` anyway; it just showed nothing).
    static let maxInlineImageBytes = 6 * 1024 * 1024

    public static func rewriteImagePaths(_ markdown: String, directory: URL) -> String {
        let pattern = "!\\[([^\\]]*)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return markdown }
        let ns = markdown as NSString
        var result = markdown
        // Iterate matches back-to-front so ranges stay valid while replacing.
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let alt = ns.substring(with: match.range(at: 1))
            let (dest, title) = splitDestination(ns.substring(with: match.range(at: 2)))
            let lower = dest.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") { continue }
            guard let fileURL = resolveLocalFile(dest, directory: directory) else { continue }
            let mime = mimeType(forExtension: fileURL.pathExtension.lowercased())
            let bytes = fileSize(fileURL)

            if mime.hasPrefix("image/"), let bytes, bytes <= maxInlineImageBytes,
               let data = try? Data(contentsOf: fileURL) {
                // Inline the image bytes (WKWebView's loadHTMLString grants no filesystem access).
                let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
                let replacement = title.map { "\(dataURI) \($0)" } ?? dataURI
                result = (result as NSString).replacingCharacters(in: match.range(at: 2), with: replacement)
            } else {
                // Video / other media / oversized image → clickable link (opens externally on click).
                let label = alt.isEmpty ? fileURL.lastPathComponent : alt
                let icon = mime.hasPrefix("video/") ? "▶ " : (mime.hasPrefix("image/") ? "🖼 " : "📎 ")
                let link = "[\(icon)\(label)](\(fileURL.absoluteString))"
                result = (result as NSString).replacingCharacters(in: match.range(at: 0), with: link)
            }
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

    /// Resolves a local media destination (relative to `directory`, or absolute / `file://`) to an
    /// existing file URL, or nil if it's missing.
    static func resolveLocalFile(_ dest: String, directory: URL) -> URL? {
        var path = dest
        if path.lowercased().hasPrefix("file://") {
            path = URL(string: path)?.path ?? path
        }
        let decoded = path.removingPercentEncoding ?? path
        let fileURL = (decoded.hasPrefix("/")
            ? URL(fileURLWithPath: decoded)
            : directory.appendingPathComponent(decoded)).standardizedFileURL
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
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
        case "mp4", "m4v":   return "video/mp4"
        case "mov":          return "video/quicktime"
        case "webm":         return "video/webm"
        case "avi":          return "video/x-msvideo"
        case "mkv":          return "video/x-matroska"
        default:             return "application/octet-stream"
        }
    }
}
