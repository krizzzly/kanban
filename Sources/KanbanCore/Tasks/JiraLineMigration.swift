import Foundation

/// Trägt die `🎫 **JIRA**`-Zeile in **bestehende** Task-Files nach.
///
/// `StatusLinks.linkify` leitet die Zeile beim Rendern ab, wenn sie fehlt — das rettet die Anzeige,
/// nicht aber die Datei: wer sie im Editor öffnet oder mit `grep` liest (Claude tut genau das), sieht
/// weiterhin keinen Weg zum Ticket. Diese Migration schreibt sie deshalb einmalig hinein, mit
/// derselben Einfüge-Regel (`StatusLinks.withJiraLine`), die auch das Rendern benutzt.
///
/// Übersprungen werden: Projekte ohne Jira-Anbindung oder ohne Basis-URL, `!<iid>`-Karten (kein
/// Jira-Issue), Review-Files (Tabs am Ticket, keine eigenen Karten) und jede Datei, die die Zeile
/// bereits führt.
public enum JiraLineMigration {
    public struct FileChange: Equatable, Sendable {
        public let fileName: String
        public let key: String
        public let url: String
    }

    public struct Report: Sendable {
        public let projectKey: String
        /// Warum für dieses Projekt gar nichts passiert ist — nil, wenn migriert wurde.
        public let skippedReason: String?
        public let changed: [FileChange]
        /// Dateien, die die Zeile schon führen — die Datei gewinnt, sie wird nicht angefasst.
        public let alreadyPresent: Int
        /// Dateien ohne H1: es gibt keine Stelle, unter die der Block gehört.
        public let withoutHeading: Int
        /// Kein Ticket-Key des Projekts, Review-File, `!<iid>`-Karte oder nicht lesbar/schreibbar.
        public let ignored: Int
    }

    /// Läuft über die Task-Files eines Projekts. `apply: false` ist der Trockenlauf — er liest nur
    /// und meldet, was er schriebe.
    public static func run(for project: ProjectConfig, apply: Bool) -> Report {
        guard project.usesJira else {
            return Report(projectKey: project.key, skippedReason: "useJira: false",
                          changed: [], alreadyPresent: 0, withoutHeading: 0, ignored: 0)
        }
        guard !project.jiraBaseUrl.isEmpty else {
            return Report(projectKey: project.key, skippedReason: "keine Jira-Basis-URL",
                          changed: [], alreadyPresent: 0, withoutHeading: 0, ignored: 0)
        }
        let directory = project.tasksPathAbsolute
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return Report(projectKey: project.key, skippedReason: "Task-Ordner fehlt: \(directory)",
                          changed: [], alreadyPresent: 0, withoutHeading: 0, ignored: 0)
        }

        let url = URL(fileURLWithPath: directory)
        var changed: [FileChange] = []
        var alreadyPresent = 0
        var withoutHeading = 0
        var ignored = 0

        for name in names.sorted() where name.hasSuffix(".md") {
            // Ein Ordner kann zwei Projekten gehören (`tp1` und `zvmsupport` teilen sich einen) —
            // die Zuordnung läuft deshalb über den Präfix im Dateinamen, nicht über den Ordner.
            guard let key = LocalTickets.key(inFileName: name, prefix: project.prefix),
                  !TaskFileLoader.isReviewFilename(name, keyPrefix: key),
                  let jiraURL = StatusLinks.jiraURL(ticketKey: key, base: project.jiraBaseUrl) else {
                ignored += 1
                continue
            }
            let file = url.appendingPathComponent(name)
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                ignored += 1
                continue
            }
            let migrated = StatusLinks.withJiraLine(content, url: jiraURL)
            guard migrated != content else {
                if StatusLinks.hasJiraLine(content) { alreadyPresent += 1 } else { withoutHeading += 1 }
                continue
            }
            if apply {
                guard (try? migrated.write(to: file, atomically: true, encoding: .utf8)) != nil else {
                    ignored += 1
                    continue
                }
            }
            changed.append(FileChange(fileName: name, key: key, url: jiraURL))
        }

        return Report(projectKey: project.key, skippedReason: nil, changed: changed,
                      alreadyPresent: alreadyPresent, withoutHeading: withoutHeading, ignored: ignored)
    }
}
