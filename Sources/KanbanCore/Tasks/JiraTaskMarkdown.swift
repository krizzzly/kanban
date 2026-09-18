import Foundation

/// Ein heruntergeladenes Bild bzw. ein Anhang, wie ihn das Task-File referenziert.
public struct SavedImage: Sendable, Equatable {
    public let filename: String
    /// `<TICKET>/<prozentkodierter Dateiname>` — relativ zum Tasks-Verzeichnis, also so, wie das
    /// Task-File selbst darauf zeigt.
    public let relativePath: String
    public let index: Int
    public let unreferenced: Bool

    public init(filename: String, relativePath: String, index: Int, unreferenced: Bool) {
        self.filename = filename
        self.relativePath = relativePath
        self.index = index
        self.unreferenced = unreferenced
    }
}

/// Der Verweis auf die Kommentar-Datei, statt der Kommentare im Task-File selbst.
public struct CommentsLink: Sendable, Equatable {
    public let path: String
    public let count: Int

    public init(path: String, count: Int) {
        self.path = path
        self.count = count
    }
}

/// Das Task-File aus einem Jira-Issue — Port von Hermes' `modules/jira/format.js`.
///
/// **Hermes' Fassung bleibt die Referenz.** Kanban folgt ihr; eine Änderung am Format gehört auf
/// beide Seiten, genau wie beim ADF-Konverter. Gehalten wird die Gleichheit durch einen Test gegen
/// einen realen Hermes-Export — ohne den driften die beiden Fassungen unsichtbar auseinander, weil
/// jede Seite nur gegen sich selbst prüft.
public enum JiraTaskMarkdown {
    /// Reihenfolge und Überschriften der Abschnitte. Fest, weil jeder Leser — Task-File-Tabs,
    /// Skills, der Commit-Dialog — sich darauf verlässt.
    static let sections: [(heading: String, field: KeyPath<JiraIssue, String?>)] = [
        ("Beschreibung", \.description),
        ("Ausgangslage", \.ausgangslage),
        ("Erwartetes Ergebnis / Verhalten", \.erwartetesErgebnis),
        ("Erweiterte Beschreibung", \.erweiterteBeschreibung),
        ("Akzeptanzkriterien", \.akzeptanzkriterien),
        ("Environment", \.environment),
    ]

    static let metaLines: [(label: String, value: (JiraIssueMeta) -> String?)] = [
        ("Status", { $0.status }),
        ("Priorität", { $0.priority }),
        ("Auflösung", { $0.resolution }),
        ("Auflösungsdatum", { $0.resolutionDate }),
        ("Story Points", { $0.storyPoints.map(number) }),
        ("Erstellt", { $0.created }),
        ("Aktualisiert", { $0.updated }),
        ("Fällig", { $0.dueDate }),
        ("Original Estimate", { $0.originalEstimate }),
        ("Remaining Estimate", { $0.remainingEstimate }),
        ("Time Spent", { $0.timeSpent }),
        ("Aggregat Original Estimate", { $0.aggregateOriginalEstimate }),
        ("Aggregat Remaining Estimate", { $0.aggregateRemainingEstimate }),
        ("Aggregat Time Spent", { $0.aggregateTimeSpent }),
    ]

    /// `1` und `1.0` sind in Jira dasselbe Feld; ohne diese Unterscheidung stünde „1.0" im Task-File.
    private static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
    }

    static func renderMeta(_ meta: JiraIssueMeta) -> String {
        var lines: [String] = []
        for (label, value) in metaLines {
            guard let text = value(meta), !text.isEmpty else { continue }
            lines.append("\(label): \(text)")
        }
        for (label, list) in [("Labels", meta.labels), ("Komponenten", meta.components),
                              ("Fix-Versionen", meta.fixVersions), ("Versionen", meta.affectedVersions)]
        where !list.isEmpty {
            lines.append("\(label): \(list.joined(separator: ", "))")
        }
        if let parent = meta.parent {
            var line = "Parent: \(parent.key)"
            if let summary = parent.summary { line += " — \(summary)" }
            lines.append(line)
        }
        if meta.watchers > 0 { lines.append("Watchers: \(meta.watchers)") }
        if meta.votes > 0 { lines.append("Votes: \(meta.votes)") }
        return lines.joined(separator: "\n")
    }

    /// `{{IMG_n}}` durch den Dateipfad ersetzen — und eine Bildzeile, deren Platzhalter nichts
    /// gefunden hat, ganz entfernen: ein Anhang ohne `content`-URL wird übersprungen, und ein
    /// gebrochenes Bild im Task-File wäre schlechter als gar keins.
    public static func replacePlaceholders(_ text: String, savedImages: [SavedImage]) -> String {
        var result = text
        for image in savedImages {
            result = result.replacingOccurrences(of: "{{IMG_\(image.index)}}", with: image.relativePath)
        }
        return result.replacingOccurrences(of: #"!\[[^\]]*\]\(\{\{IMG_\d+\}\}\)\n?"#,
                                           with: "", options: .regularExpression)
    }

    public static func format(issue: JiraIssue,
                              savedImages: [SavedImage] = [],
                              subtaskContents: [JiraSubtaskContent] = [],
                              commentsLink: CommentsLink? = nil,
                              includeExtraFields: Bool = true) -> String {
        func placeholders(_ text: String) -> String {
            savedImages.isEmpty ? text : replacePlaceholders(text, savedImages: savedImages)
        }

        let title = issue.summary.isEmpty ? "[Titel]" : issue.summary
        var md = "# \(issue.key) - \(title)"

        if let type = issue.issueType { md += "\nTyp: \(type)" }

        let meta = renderMeta(issue.meta)
        if !meta.isEmpty { md += "\n\(meta)" }

        // Reporter-Zeile, wie sie das Service-Desk zeigt („X hat diese Anfrage erstellt"). Nur wenn
        // der Melder von aussen kommt (Mailadresse als Anzeigename) oder ein anderer ist als der
        // Ersteller — bei einem internen Ticket, wo beide dieselbe Person sind, wäre sie Rauschen.
        if let reporter = issue.reporter?.displayName, !reporter.isEmpty {
            let isEmail = reporter.contains("@")
            if isEmail || reporter != (issue.creator?.displayName ?? reporter) {
                md += "\n\n\(reporter) hat diese Anfrage erstellt"
            }
        }

        for (heading, field) in sections {
            guard let content = issue[keyPath: field], !content.isEmpty else { continue }
            md += "\n\n## \(heading)\n\(placeholders(content))"
        }

        // Custom Fields, die in Jira jemand angelegt hat (z. B. „Lösung"), je mit eigener H2.
        for field in issue.customFields {
            md += "\n\n## \(field.name)\n\(placeholders(field.value))"
        }

        if !issue.linkedIssues.isEmpty {
            md += "\n\n## Verwandte Tasks\n"
            md += issue.linkedIssues.map { linked in
                var line = "- **\(linked.key)**: \(linked.summary ?? "")"
                if let relation = linked.relation { line += " _(\(relation))_" }
                if let status = linked.status { line += " [\(status)]" }
                return line
            }.joined(separator: "\n")
        }

        // Unteraufgaben: kurz, solange nur die Titel bekannt sind — lang, sobald ihr Inhalt geholt
        // wurde. Nie beides.
        if !issue.subtasks.isEmpty && subtaskContents.isEmpty {
            md += "\n\n## Sub-Tasks\n"
            md += issue.subtasks.map { "- \($0.key): \($0.summary ?? "")" }.joined(separator: "\n")
        }

        if !subtaskContents.isEmpty {
            md += "\n\n## Sub-Tasks"
            for subtask in subtaskContents {
                md += "\n\n### \(subtask.key) - \(subtask.summary ?? "")"
                if let description = subtask.description, !description.isEmpty {
                    md += "\n\n\(placeholders(description))"
                }
                if let criteria = subtask.akzeptanzkriterien, !criteria.isEmpty {
                    md += "\n\n#### Akzeptanzkriterien\n\(placeholders(criteria))"
                }
                for field in subtask.customFields {
                    md += "\n\n#### \(field.name)\n\(placeholders(field.value))"
                }
            }
        }

        if let link = commentsLink {
            md += "\n\n## Kommentare\n\n[Kommentar-Diskussion (JSON)](\(link.path)) — \(link.count) Kommentare"
        }

        let unreferenced = savedImages.filter(\.unreferenced)
        if !unreferenced.isEmpty {
            md += "\n\n## Anhänge\n"
            for image in unreferenced {
                md += "![\(image.filename)](\(image.relativePath))\n\n"
            }
        }

        if includeExtraFields && !issue.extraFields.isEmpty {
            md += "\n\n## Weitere Felder\n"
            md += issue.extraFields.map { "- **\($0.name)**: \($0.value)" }.joined(separator: "\n")
        }

        return md
    }
}
