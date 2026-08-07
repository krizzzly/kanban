import Foundation

/// Locates Claude Code conversation transcripts (`~/.claude/projects/<cwd-slug>/<id>.jsonl`) so
/// the launch command can decide deterministically between `claude --resume` (transcript exists)
/// and `claude --session-id` (first launch) — instead of a `resume || session-id` fallback chain
/// whose error output ("No conversation found …") landed visibly in every fresh console.
public enum ClaudeTranscripts {
    /// Claude Code's project-directory slug: the resolved absolute cwd with every character that
    /// is not an ASCII letter or digit replaced by `-`. Symlinks are resolved the way Claude sees
    /// the cwd (e.g. `/tmp` → `-private-tmp`).
    public static func projectDirName(forCwd cwd: String) -> String {
        let expanded = (cwd as NSString).expandingTildeInPath
        // POSIX realpath, not Foundation's resolvingSymlinksInPath — the latter deliberately
        // strips "/private" (so /tmp stays /tmp), while Claude's Node cwd is the real path.
        var resolved = expanded
        if let rp = realpath(expanded, nil) {
            resolved = String(cString: rp)
            free(rp)
        }
        return String(resolved.map { char in
            char.isASCII && (char.isLetter || char.isNumber) ? char : "-"
        })
    }

    /// True if a conversation with `sessionId` exists for the given working directory.
    public static func transcriptExists(
        sessionId: String, cwd: String,
        claudeDir: String = ("~/.claude" as NSString).expandingTildeInPath
    ) -> Bool {
        let file = (claudeDir as NSString).appendingPathComponent(
            "projects/\(projectDirName(forCwd: cwd))/\(sessionId).jsonl")
        return FileManager.default.fileExists(atPath: file)
    }

    /// The conversation file for `sessionId`, or nil if Claude never wrote one. Looks in the project
    /// directory for `cwd` first, then across all project directories — the same conversation can
    /// live under a worktree's slug when its console was started there.
    public static func transcriptURL(
        sessionId: String, cwd: String,
        claudeDir: String = ("~/.claude" as NSString).expandingTildeInPath
    ) -> URL? {
        let projects = URL(fileURLWithPath: claudeDir).appendingPathComponent("projects", isDirectory: true)
        let file = "\(sessionId).jsonl"
        let expected = projects
            .appendingPathComponent(projectDirName(forCwd: cwd), isDirectory: true)
            .appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: expected.path) { return expected }

        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: nil) else { return nil }
        for dir in dirs {
            let candidate = dir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
