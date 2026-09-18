import Foundation

/// Installs a Claude Code hook into `~/.claude/settings.json` (global, so every project's console is
/// covered) that writes/removes Kanban attention markers. The hook script is a tiny dependency-free
/// bash that parses the hook JSON from stdin with `sed` — no `jq` required.
///
/// settings.json is edited round-trip-safe via `JSONValue`: unknown keys and existing hooks survive.
public enum ClaudeHookInstaller {
    public static var settingsPath: String {
        ("~/.claude/settings.json" as NSString).expandingTildeInPath
    }

    /// Global wie die Marker daneben: `~/.claude/settings.json` ruft dieses Skript mit absolutem
    /// Pfad auf, ein Skript je Profil wäre bei jedem Wechsel ein Schreibzugriff auf fremde Config.
    public static var scriptPath: String { KanbanPaths.hookScript.path }

    /// The event → command mapping we own. All three point at the same script; the script branches
    /// on `hook_event_name`.
    private static let hookedEvents = ["Notification", "UserPromptSubmit", "SessionEnd"]

    private static var scriptBody: String {
        """
        #!/bin/bash
        # Kanban attention hook (managed by the Kanban app — HERMES-038). Maps Claude Code hook
        # events to marker files the app watches. Dependency-free: parses stdin JSON with sed.
        DIR="$HOME/Library/Application Support/Kanban/attention"
        mkdir -p "$DIR"
        input=$(cat | tr -d '\\n')
        sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p')
        event=$(printf '%s' "$input" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p')
        [ -z "$sid" ] && exit 0
        case "$event" in
          Notification) : > "$DIR/$sid" ;;
          UserPromptSubmit|SessionEnd) rm -f "$DIR/$sid" ;;
        esac
        exit 0
        """
    }

    // MARK: - Status

    public static func isInstalled() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: scriptPath) else { return false }
        guard let root = loadSettings() else { return false }
        // Require the exact, correctly-quoted command — a stale/broken entry counts as not installed
        // so the UI offers a reinstall that repairs it.
        return hookedEvents.allSatisfy { event in
            hasExactCommand(in: root, event: event)
        }
    }

    // MARK: - Install / uninstall

    public static func install() throws {
        // 1. Write the script and mark it executable.
        let scriptURL = URL(fileURLWithPath: scriptPath)
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        // 2. Merge our hook entries into settings.json, preserving everything else. Remove any prior
        //    variant first (e.g. an older unquoted command) so reinstalling always writes the fix.
        var root = loadSettings() ?? .object([:])
        for event in hookedEvents {
            removeOurCommand(from: &root, event: event)
            addOurCommand(to: &root, event: event)
        }
        try writeSettings(root)
    }

    public static func uninstall() throws {
        if var root = loadSettings() {
            for event in hookedEvents { removeOurCommand(from: &root, event: event) }
            try writeSettings(root)
        }
        try? FileManager.default.removeItem(atPath: scriptPath)
    }

    // MARK: - settings.json plumbing (JSONValue round-trip)

    private static func loadSettings() -> JSONValue? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func writeSettings(_ root: JSONValue) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(root)
        let url = URL(fileURLWithPath: settingsPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: settingsPath) {
            let backup = settingsPath + ".bak"
            try? FileManager.default.removeItem(atPath: backup)
            try? FileManager.default.copyItem(atPath: settingsPath, toPath: backup)
        }
        try data.write(to: url, options: .atomic)
    }

    /// The command string written to settings.json. **Single-quoted** because the script path
    /// contains a space ("Application Support"); Claude Code runs the command via `/bin/sh -c`,
    /// which would otherwise split at the space ("No such file or directory").
    static var command: String {
        "'" + scriptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A single hook command object: `{ "type": "command", "command": "<quoted script>" }`.
    private static var ourCommandObject: JSONValue {
        .object(["type": .string("command"), "command": .string(command)])
    }

    /// settings.json shape: `hooks.<Event>` = array of matcher groups
    /// `{ "matcher": "", "hooks": [ {type,command}, … ] }`. We add one group carrying our command.
    private static func hookGroups(in root: JSONValue, event: String) -> [JSONValue] {
        root.value(at: ["hooks", event])?.arrayValue ?? []
    }

    /// Exact match against the current (correctly-quoted) command — used for `isInstalled`.
    private static func hasExactCommand(in root: JSONValue, event: String) -> Bool {
        hookGroups(in: root, event: event).contains { group in
            (group.value(at: ["hooks"])?.arrayValue ?? []).contains { cmd in
                cmd.value(at: ["command"])?.stringValue == command
            }
        }
    }

    /// Any variant of our command (quoted or an older unquoted path) — used for removal, so a stale
    /// entry gets cleaned up on reinstall/uninstall.
    private static func isOurs(_ cmd: JSONValue) -> Bool {
        guard let s = cmd.value(at: ["command"])?.stringValue else { return false }
        return s == command || s.contains(scriptPath)
    }

    private static func addOurCommand(to root: inout JSONValue, event: String) {
        guard !hasExactCommand(in: root, event: event) else { return }
        var groups = hookGroups(in: root, event: event)
        groups.append(.object(["matcher": .string(""), "hooks": .array([ourCommandObject])]))
        root.set(.array(groups), at: ["hooks", event])
    }

    private static func removeOurCommand(from root: inout JSONValue, event: String) {
        let cleaned: [JSONValue] = hookGroups(in: root, event: event).compactMap { group in
            let inner = (group.value(at: ["hooks"])?.arrayValue ?? []).filter { !isOurs($0) }
            if inner.isEmpty { return nil }   // drop a group that only held our command
            var g = group
            g.set(.array(inner), at: ["hooks"])
            return g
        }
        root.set(cleaned.isEmpty ? nil : .array(cleaned), at: ["hooks", event])
    }
}
