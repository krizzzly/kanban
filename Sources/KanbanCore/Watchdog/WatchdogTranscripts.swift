import Foundation

/// Ein Transcript auf der Platte, bevor es gelesen wurde.
public struct WatchdogTranscript: Sendable, Equatable {
    public let sessionId: String
    public let url: URL
    public let geaendert: Date
    /// Ordnername unter `~/.claude/projects` — der Slug des Arbeitsverzeichnisses.
    public let projektSlug: String

    public init(sessionId: String, url: URL, geaendert: Date, projektSlug: String) {
        self.sessionId = sessionId
        self.url = url
        self.geaendert = geaendert
        self.projektSlug = projektSlug
    }
}

/// Findet **alle** Claude-Transcripts, nicht nur die von Kanban gestarteten.
///
/// Absicht: „wiederkehrend" braucht Datenpunkte. Eine Auffälligkeit, die in einer Kanban-Session und
/// zweimal in einer frei gestarteten auftaucht, ist dasselbe Muster — und wäre bei einer Filterung
/// auf Kanban-Karten unsichtbar geblieben.
public enum WatchdogTranscripts {

    public static var projectsDir: String {
        ("~/.claude/projects" as NSString).expandingTildeInPath
    }

    /// Alle Transcripts, neueste zuerst. `seit` schneidet alles Ältere weg, bevor irgendetwas
    /// gelesen wird — der Scan kostet sonst auf einer gewachsenen Platte unnötig Zeit.
    public static func alle(seit: Date? = nil, projectsDir: String = WatchdogTranscripts.projectsDir)
        -> [WatchdogTranscript]
    {
        let fm = FileManager.default
        guard let ordner = try? fm.contentsOfDirectory(atPath: projectsDir) else { return [] }

        var ergebnis: [WatchdogTranscript] = []
        for slug in ordner {
            let ordnerPfad = (projectsDir as NSString).appendingPathComponent(slug)
            var istOrdner: ObjCBool = false
            guard fm.fileExists(atPath: ordnerPfad, isDirectory: &istOrdner), istOrdner.boolValue,
                  let dateien = try? fm.contentsOfDirectory(atPath: ordnerPfad) else { continue }

            for datei in dateien where datei.hasSuffix(".jsonl") {
                let pfad = (ordnerPfad as NSString).appendingPathComponent(datei)
                guard let attrs = try? fm.attributesOfItem(atPath: pfad),
                      let mtime = attrs[.modificationDate] as? Date else { continue }
                if let seit, mtime < seit { continue }

                ergebnis.append(WatchdogTranscript(
                    sessionId: String(datei.dropLast(".jsonl".count)),
                    url: URL(fileURLWithPath: pfad),
                    geaendert: mtime,
                    projektSlug: slug))
            }
        }
        return ergebnis.sorted { $0.geaendert > $1.geaendert }
    }
}
