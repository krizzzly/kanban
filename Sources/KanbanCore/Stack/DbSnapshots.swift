import Foundation

/// Ein DB-Snapshot, wie `iwf db snapshot` ihn ablegt.
public struct DbSnapshot: Sendable, Equatable, Identifiable {
    /// Der Dateiname — genau das, was `iwf db snapshot restore -f …` erwartet (Basename genügt).
    public let name: String
    public let path: String
    public let bytes: Int64
    public let modified: Date

    public var id: String { name }

    /// Der Snapshot, den ein `create` ohne Flag überschreibt und ein `restore` ohne `-f` nimmt.
    public var isLatest: Bool { name.hasSuffix("-latest.tar") }

    /// Der Teil hinter `<volume>-` ohne `.tar` — „latest", ein Zeitstempel oder ein eigener Name.
    public func label(volume: String) -> String {
        let stripped = name.hasPrefix("\(volume)-") ? String(name.dropFirst(volume.count + 1)) : name
        return stripped.hasSuffix(".tar") ? String(stripped.dropLast(4)) : stripped
    }

    public init(name: String, path: String, bytes: Int64, modified: Date) {
        self.name = name
        self.path = path
        self.bytes = bytes
        self.modified = modified
    }
}

/// Die Snapshots eines Stacks — gelesen **aus dem Ordner**, nicht aus der Ausgabe von
/// `iwf db snapshot list`.
///
/// Warum direkt: der Befehl druckt „`<datei> (<n> MB)`" plus eine i18n-Hinweiszeile, und aus einer
/// gerundeten MB-Zahl lässt sich weder sortieren noch das Alter ablesen. Der Ordner liefert Grösse
/// und mtime exakt — und ist dieselbe Wahrheit, denn iwf globt dort ebenfalls `*.tar`
/// (`project_compose.db_list_snapshots`).
public enum DbSnapshots {
    /// `~/.iwf-dev/snapshots` (`DB_SNAPSHOTS_DIR` in iwfs `constants.py`).
    public static var root: String {
        (("~/.iwf-dev/snapshots") as NSString).expandingTildeInPath
    }

    /// Der Ordner eines Stacks. Der Stack-Name ist iwfs `Project().name()` — bei uns immer der
    /// Ordnername (`even`, `even-3963`), also derselbe Wert wie beim Docker-Status.
    /// `root` ist injizierbar, damit der Test nicht am echten Ordner dieser Maschine hängt.
    public static func directory(stack: String, root: String = DbSnapshots.root) -> String {
        (root as NSString).appendingPathComponent(stack)
    }

    /// Das Volume, das `create`/`restore` ohne `--volume` benutzen: `<stack>_dbdata`.
    public static func defaultVolume(stack: String) -> String { "\(stack)_dbdata" }

    /// Neueste zuerst. `latest` steht trotzdem oben, wenn es das jüngste ist — sonst wäre die
    /// Reihenfolge eine Behauptung über Wichtigkeit statt über Aktualität.
    public static func list(stack: String, root: String = DbSnapshots.root) -> [DbSnapshot] {
        let dir = directory(stack: stack, root: root)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names
            .filter { $0.hasSuffix(".tar") }
            .compactMap { name in
                let path = (dir as NSString).appendingPathComponent(name)
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                return DbSnapshot(name: name, path: path,
                                  bytes: (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
                                  modified: (attributes?[.modificationDate] as? Date) ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// Dateiname für einen benannten Snapshot. `iwf` selbst kennt nur `latest` und `-t`
    /// (Zeitstempel) — ein eigener Name ist trotzdem gefahrlos, weil `restore -f` jeden Basename im
    /// Ordner annimmt und `list` alles globt. Deshalb: mit `-t` erzeugen und danach umbenennen.
    public static func fileName(volume: String, label: String) -> String {
        "\(volume)-\(slug(label)).tar"
    }

    /// Was als Name durchgeht: Buchstaben, Ziffern, `.`, `_`, `-`. Alles andere wird zu `-`, damit
    /// kein Pfadtrenner und kein Leerzeichen in den Dateinamen gerät.
    public static func slug(_ label: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let mapped = label.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "snapshot" : collapsed
    }

    /// Der Snapshot, den ein `create -t` gerade geschrieben hat: der einzige, den es vorher nicht
    /// gab. Über die Differenz statt über den erratenen Zeitstempel — iwfs Format
    /// (`YYYY-M-D--H-M-S`, ohne führende Nullen) nachzubauen wäre eine Wette auf fremden Code.
    public static func added(before: [DbSnapshot], after: [DbSnapshot]) -> DbSnapshot? {
        let known = Set(before.map(\.name))
        return after.first { !known.contains($0.name) }
    }
}
