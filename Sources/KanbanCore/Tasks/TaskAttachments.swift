import Foundation

/// Was neben dem Task-File im **Task-Ordner** des Tickets liegt: die Bilder aus der Jira-Beschreibung,
/// `comments.json` samt `avatars/`, dazu Anhänge, die das Task-File nie verlinkt (Videos, Tabellen,
/// PDFs, exportierte Mails).
///
/// Das Task-File zeigt nur, was es selbst einbettet — ein `.mp4` wird dort zum Link, ein `.xlsx`
/// taucht gar nicht auf. Der Ordner ist deshalb die einzige Stelle, an der **alles** steht, was zu
/// dem Ticket geholt wurde.
public enum TaskAttachments {
    /// Die Ordner des Tickets im Tasks-Verzeichnis. Fast immer genau einer (`EVEN-3282`), auf dieser
    /// Maschine 192 von 193 — die Mehrzahl ist trotzdem nötig, siehe `belongsToTicket`.
    public static func folders(ticketKey: String, in tasksDirectory: String,
                               fileManager: FileManager = .default) -> [URL] {
        let dir = URL(fileURLWithPath: tasksDirectory)
        guard let names = try? fileManager.contentsOfDirectory(atPath: tasksDirectory) else { return [] }
        let prefix = ticketKey.uppercased()
        return names
            .filter { belongsToTicket($0, keyPrefix: prefix) }
            .filter { name in
                var isDirectory: ObjCBool = false
                let path = (tasksDirectory as NSString).appendingPathComponent(name)
                return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { dir.appendingPathComponent($0) }
    }

    /// Gehört ein **Ordnername** zu diesem Ticket? Der Schlüssel muss am Anfang stehen und darf nicht
    /// von einer weiteren Ziffer fortgesetzt werden — sonst zöge `EVEN-3282` auch `EVEN-32820` an
    /// sich, und die Bilder eines fremden Tickets stünden unter diesem.
    ///
    /// Bewusst lockerer als `TaskFileLoader.belongsToTicket` (dort muss `_` oder `.` folgen): die
    /// Ordner sind **nicht** so streng benannt wie die Dateien. Auf dieser Maschine heissen 191 von
    /// 193 schlicht `<KEY>`, einer trägt den ganzen Datei-Stamm
    /// (`EVEN-3457_fire_nachweisverfassung_…`) und einer eine angehängte Zahl (`EVEN-3282-1`, ein
    /// zweiter Export desselben Tickets). Mit der Datei-Regel fiele der letzte heraus, und seine vier
    /// Bilder wären nirgends zu sehen.
    static func belongsToTicket(_ name: String, keyPrefix: String) -> Bool {
        let upper = name.uppercased()
        guard upper.hasPrefix(keyPrefix) else { return false }
        guard let next = upper.dropFirst(keyPrefix.count).first else { return true }
        return !next.isNumber
    }

    /// Der Baum für die Ansicht. Gebaut mit `KnowledgebaseTree` — derselbe Leser wie in der
    /// Knowledgebase, also dieselben Regeln (Ordner zuerst, natürliche Sortierung, Verstecktes und
    /// Symlinks draussen, leere Ordner weg). Ein Task-Ordner ist flach bis auf `avatars/`, aber
    /// gebaut wird trotzdem rekursiv: ein Ordner, dessen Inhalt nicht auftaucht, wäre schlechter als
    /// eine Ebene, die niemand braucht.
    ///
    /// **Ein** Ordner steht als sein Inhalt da (der Ordnername ist die Ticketnummer und stünde sonst
    /// über jeder Zeile nochmal); bei **mehreren** bekommt jeder seine eigene Zeile — welches Bild
    /// aus welchem Export stammt, wäre flach nicht mehr zu sehen.
    public static func tree(ticketKey: String, in tasksDirectory: String,
                            fileManager: FileManager = .default) -> [KBNode] {
        let dirs = folders(ticketKey: ticketKey, in: tasksDirectory, fileManager: fileManager)
        if dirs.count == 1 {
            return KnowledgebaseTree.build(root: dirs[0].path, fileManager: fileManager)
        }
        return dirs.compactMap { url in
            let children = KnowledgebaseTree.build(root: url.path, fileManager: fileManager)
            guard !children.isEmpty else { return nil }
            return KBNode(path: url.path, name: url.lastPathComponent,
                          isDirectory: true, children: children)
        }
    }

    /// Dateien im ganzen Baum — die Zahl am Knopf.
    public static func fileCount(_ nodes: [KBNode]) -> Int {
        nodes.reduce(0) { $0 + $1.fileCount }
    }
}
