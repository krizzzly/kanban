import Foundation

/// Findet die Codex-Konversation eines Tickets — das Gegenstück zu `ClaudeTranscripts`.
///
/// Codex nimmt **keine** Session-Id an (`--session-id` gibt es nicht, `codex resume <id|name>`
/// greift erst nachträglich). Deshalb dreht Kanban die Richtung: nach dem Start bekommt die Session
/// über Codex' eigenen `/rename`-Command einen **deterministischen Namen** (`kanban-<TICKET>`), und
/// `~/.codex/session_index.jsonl` — die Datei, in der Codex ausschliesslich *benannte* Threads führt
/// — liefert danach die Id. Kein Raten über „jüngster Rollout mit passendem cwd": alle Tickets eines
/// Projekts laufen im selben Repo, das wäre nicht unterscheidbar.
///
/// Verifiziert am 2026-08-20 gegen Codex 0.147: `/rename kanban-PROBE-1` meldet „Session renamed to
/// kanban-PROBE-1 … (01a01e3b-…)" und schreibt genau diese Zeile in den Index.
public enum CodexSessions {
    /// `~/.codex`
    public static var defaultCodexDir: URL { AgentKind.codex.homeDir }

    /// Der Thread-Name, unter dem Kanban die Console eines Tickets führt — bewusst identisch zum
    /// tmux-Session-Namen, damit beide Seiten dieselbe Zeichenfolge benutzen.
    public static func threadName(forTicket key: String) -> String {
        TerminalSessionResolver.sessionName(forTicket: key)
    }

    /// Die Id des benannten Threads, oder nil. Bei mehreren gleichnamigen (Session neu gestartet und
    /// erneut umbenannt) gewinnt der **jüngste** `updated_at` — das ist die Konversation, in der
    /// gerade gearbeitet wird.
    public static func sessionId(threadName: String, codexDir: URL = defaultCodexDir) -> String? {
        let index = codexDir.appendingPathComponent("session_index.jsonl")
        guard let content = try? String(contentsOf: index, encoding: .utf8) else { return nil }

        var best: (id: String, updated: String)?
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(IndexEntry.self, from: data),
                  entry.thread_name == threadName else { continue }
            let updated = entry.updated_at ?? ""
            if best == nil || updated > best!.updated { best = (entry.id, updated) }
        }
        return best?.id
    }

    /// Die Rollout-Datei einer Session: `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl`.
    ///
    /// Gesucht wird **von neu nach alt** über die Datums-Ordner: eine Session, die gerade läuft,
    /// liegt im heutigen Ordner, und ein Monat Historie muss dafür nicht durchgelesen werden. Nil
    /// heisst „noch kein Turn": Codex schreibt die Datei erst, wenn Inhalt da ist — eine frisch
    /// umbenannte, leere Session hat noch keine (verifiziert).
    public static func rolloutURL(sessionId: String, codexDir: URL = defaultCodexDir) -> URL? {
        let root = codexDir.appendingPathComponent("sessions", isDirectory: true)
        let suffix = "-\(sessionId).jsonl"
        for day in dayDirectoriesNewestFirst(under: root) {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: day, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            if let hit = files.first(where: { $0.lastPathComponent.hasSuffix(suffix) }) { return hit }
        }
        return nil
    }

    /// Jahr/Monat/Tag absteigend — die Ordnernamen sind nullgepolstert, lexikografisch = zeitlich.
    private static func dayDirectoriesNewestFirst(under root: URL) -> [URL] {
        func sortedChildren(_ url: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles)) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        return sortedChildren(root).flatMap { sortedChildren($0) }.flatMap { sortedChildren($0) }
    }

    private struct IndexEntry: Decodable {
        let id: String
        let thread_name: String?
        let updated_at: String?
    }
}
