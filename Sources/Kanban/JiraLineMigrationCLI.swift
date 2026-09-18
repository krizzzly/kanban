import Foundation
import KanbanCore

/// Trägt die `🎫 **JIRA**`-Zeile in bestehende Task-Files nach — headless, wie `--selftest`:
///
///     Kanban --migrate-jira-line [--dry-run] [--project <key>]
///
/// Ohne `--dry-run` wird geschrieben. Ohne `--project` laufen alle Projekte der Config.
/// Beendet den Prozess; die UI startet nie.
enum JiraLineMigrationCLI {
    static func runAndExit() -> Never {
        exit(run())
    }

    static func run() -> Int32 {
        let apply = !CommandLine.arguments.contains("--dry-run")
        do {
            HermesImport.runIfNeeded()
            let cfg = try KanbanConfig.load()
            let wanted = argValue("--project")
            let projects = wanted.map { key in cfg.projects.filter { $0.key == key } } ?? cfg.projects
            guard !projects.isEmpty else {
                print("✗ kein Projekt \(wanted.map { "„\($0)“ " } ?? "")in der Config")
                return 1
            }
            print(apply ? "→ Migration (schreibend)" : "→ Trockenlauf (es wird nichts geschrieben)")

            var total = 0
            for project in projects {
                let report = JiraLineMigration.run(for: project, apply: apply)
                if let reason = report.skippedReason {
                    print("  \(project.key): übersprungen — \(reason)")
                    continue
                }
                total += report.changed.count
                print("  \(project.key) (\(project.prefix)) @ \(project.tasksPathAbsolute)")
                print("    \(apply ? "geschrieben" : "würde schreiben"): \(report.changed.count)"
                      + " · schon vorhanden: \(report.alreadyPresent)"
                      + " · ohne H1: \(report.withoutHeading)"
                      + " · nicht zuständig: \(report.ignored)")
                for change in report.changed { print("      + \(change.fileName) → \(change.url)") }
            }
            print(apply ? "✓ \(total) Task-Files migriert" : "✓ \(total) Task-Files würden migriert")
            return 0
        } catch {
            print("✗ \(error)")
            return 1
        }
    }

    private static func argValue(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
