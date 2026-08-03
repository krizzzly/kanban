import XCTest
@testable import KanbanCore

/// Exercises the settings.json merge logic in isolation via the JSONValue round-trip, mirroring
/// what `ClaudeHookInstaller` does (the installer's own file paths are process-global, so the merge
/// itself is what we validate here).
final class ClaudeHookInstallerTests: XCTestCase {
    private let script = "/Users/x/Library/Application Support/Kanban/kanban-attention-hook.sh"

    private func ourGroup() -> JSONValue {
        .object(["matcher": .string(""),
                 "hooks": .array([.object(["type": .string("command"),
                                           "command": .string(script)])])])
    }

    func testAddPreservesExistingHooks() {
        var root = JSONValue.object([
            "model": .string("opus"),
            "hooks": .object([
                "Notification": .array([
                    .object(["matcher": .string(""),
                             "hooks": .array([.object(["type": .string("command"),
                                                       "command": .string("osascript -e beep")])])])
                ])
            ]),
        ])
        // Simulate addOurCommand for Notification.
        var groups = root.value(at: ["hooks", "Notification"])?.arrayValue ?? []
        groups.append(ourGroup())
        root.set(.array(groups), at: ["hooks", "Notification"])

        // Existing user hook survives …
        let commands = (root.value(at: ["hooks", "Notification"])?.arrayValue ?? [])
            .flatMap { ($0.value(at: ["hooks"])?.arrayValue ?? []) }
            .compactMap { $0.value(at: ["command"])?.stringValue }
        XCTAssertTrue(commands.contains("osascript -e beep"))
        XCTAssertTrue(commands.contains(script))
        // … and unrelated top-level keys are untouched.
        XCTAssertEqual(root.value(at: ["model"])?.stringValue, "opus")
    }

    func testCommandIsSingleQuotedForTheSpaceInAppSupport() {
        // The script lives under "Application Support" (has a space); the command written to
        // settings.json must be single-quoted or /bin/sh -c splits it ("No such file or directory").
        let cmd = ClaudeHookInstaller.command
        XCTAssertTrue(cmd.hasPrefix("'"), cmd)
        XCTAssertTrue(cmd.hasSuffix("'"), cmd)
        XCTAssertTrue(cmd.contains("kanban-attention-hook.sh"), cmd)
    }

    func testRemoveDropsOnlyOurGroup() {
        var root = JSONValue.object([:])
        root.set(.array([ourGroup()]), at: ["hooks", "SessionEnd"])

        // Simulate removeOurCommand: filter out our command, drop empty groups, then empty event.
        let cleaned: [JSONValue] = (root.value(at: ["hooks", "SessionEnd"])?.arrayValue ?? []).compactMap { group in
            let inner = (group.value(at: ["hooks"])?.arrayValue ?? []).filter {
                $0.value(at: ["command"])?.stringValue != script
            }
            return inner.isEmpty ? nil : group
        }
        root.set(cleaned.isEmpty ? nil : .array(cleaned), at: ["hooks", "SessionEnd"])

        XCTAssertNil(root.value(at: ["hooks", "SessionEnd"]))
    }
}
