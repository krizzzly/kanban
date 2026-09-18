import Foundation

/// Eine gespeicherte Fassung einer Asset-Datei.
public struct ClaudeAssetVersion: Sendable, Hashable, Identifiable {
    public let url: URL
    public let datum: Date
    /// Vom Menschen vergeben — der Grund, warum man eine Fassung später wiederfindet.
    public let bezeichnung: String?
    public let bytes: Int

    public var id: String { url.path }

    public init(url: URL, datum: Date, bezeichnung: String?, bytes: Int) {
        self.url = url
        self.datum = datum
        self.bezeichnung = bezeichnung
        self.bytes = bytes
    }
}

/// Die Versionsgeschichte des kanonischen Bestands: jedes Speichern legt eine Fassung ab, jede
/// Fassung lässt sich wieder aktivieren.
///
/// Bis hierher gab es **eine** Fassung — die Datei selbst — und daneben nur den Auslieferungsstand
/// als Notausgang. Wer einen Skill umbaute und den alten Wortlaut wiederhaben wollte, konnte nur
/// ganz auf Werk zurück und damit auch alle anderen eigenen Änderungen wegwerfen.
///
/// Abgelegt wird **neben** dem Bestand, in `<bestand>/.versions/<pfad der datei>/`:
///
/// ```
/// claude/.versions/skills/solve-task/SKILL.md/2026-09-15 17-40-00 · vor dem Umbau.md
/// ```
///
/// Der Ordner heisst wie die Datei (`SKILL.md` als Verzeichnisname sieht ungewohnt aus, ist aber
/// eindeutig und braucht keine Übersetzungstabelle), und der Zeitstempel steht **im Dateinamen**
/// statt in einem Index: das bleibt im Finder lesbar, und eine Datei, die jemand von Hand
/// dazulegt oder wegwirft, macht nichts kaputt. Ein Index daneben wäre eine zweite Wahrheit.
///
/// `.versions` beginnt mit einem Punkt und liegt neben `commands`/`skills`/`rules` — `assets(_:)`
/// sieht nur in diese drei Ordner, die Historie taucht also nie als Asset auf.
public struct ClaudeAssetVersionStore: Sendable {
    public let canonicalRoot: URL

    /// So viele **unbenannte** Fassungen je Datei bleiben stehen. Benannte werden nie
    /// weggeräumt — sie sind genau die, die jemand behalten wollte.
    public static let maxAutomatisch = 50

    public init(canonicalRoot: URL = ClaudeAssetStore.defaultRoot) {
        self.canonicalRoot = canonicalRoot
    }

    public var root: URL { canonicalRoot.appendingPathComponent(".versions", isDirectory: true) }

    /// Der Versionsordner einer Datei: ihr Pfad relativ zum Bestand, unter `.versions`.
    public func verzeichnis(fuer datei: URL) -> URL {
        let basis = canonicalRoot.standardizedFileURL.path
        let voll = datei.standardizedFileURL.path
        let relativ = voll.hasPrefix(basis + "/")
            ? String(voll.dropFirst(basis.count + 1))
            : datei.lastPathComponent
        return root.appendingPathComponent(relativ, isDirectory: true)
    }

    // MARK: - Lesen

    /// Alle Fassungen einer Datei, **neueste zuerst**.
    public func versionen(von datei: URL) -> [ClaudeAssetVersion] {
        let dir = verzeichnis(fuer: datei)
        guard let eintraege = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
        else { return [] }

        return eintraege
            .filter { $0.pathExtension == "md" }
            .compactMap { url in
                let stamm = url.deletingPathExtension().lastPathComponent
                guard let (datum, bezeichnung) = Self.zerlegt(stamm) else { return nil }
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return ClaudeAssetVersion(url: url, datum: datum, bezeichnung: bezeichnung, bytes: bytes)
            }
            .sorted { $0.datum > $1.datum }
    }

    public func inhalt(_ version: ClaudeAssetVersion) -> String? {
        try? String(contentsOf: version.url, encoding: .utf8)
    }

    // MARK: - Schreiben

    /// Legt den **aktuellen** Inhalt von `datei` als Fassung ab.
    ///
    /// Nil, wenn die Datei nicht lesbar ist oder die jüngste Fassung schon **denselben** Inhalt
    /// trägt: zweimal Speichern ohne Änderung soll keine zweite Fassung erzeugen, sonst ist die
    /// Liste nach einem Tag voller Wiederholungen. Eine **benannte** Fassung wird trotzdem
    /// geschrieben — der Name ist ja der Punkt.
    @discardableResult
    public func sichern(_ datei: URL, bezeichnung: String? = nil,
                        jetzt: Date = Date()) throws -> ClaudeAssetVersion? {
        guard let text = try? String(contentsOf: datei, encoding: .utf8) else { return nil }
        let vorhandene = versionen(von: datei)
        if bezeichnung == nil, let juengste = vorhandene.first, inhalt(juengste) == text {
            return nil
        }

        let dir = verzeichnis(fuer: datei)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ziel = dir.appendingPathComponent(Self.dateiname(datum: jetzt, bezeichnung: bezeichnung,
                                                             belegt: vorhandene.map(\.url)))
        try text.write(to: ziel, atomically: true, encoding: .utf8)
        aufraeumen(datei)
        return ClaudeAssetVersion(url: ziel, datum: jetzt, bezeichnung: bezeichnung,
                                  bytes: text.utf8.count)
    }

    /// Schreibt eine Fassung zurück in die Datei. Der bisherige Stand wird vorher gesichert —
    /// aktivieren muss selbst rückgängig zu machen sein, sonst ist es ein Verlust statt eines
    /// Wechsels.
    public func aktivieren(_ version: ClaudeAssetVersion, in datei: URL,
                           jetzt: Date = Date()) throws {
        guard let text = inhalt(version) else {
            throw ClaudeAssetError(message: "Die Fassung lässt sich nicht lesen.")
        }
        try sichern(datei, jetzt: jetzt)
        try text.write(to: datei, atomically: true, encoding: .utf8)
    }

    public func loeschen(_ version: ClaudeAssetVersion) throws {
        try FileManager.default.removeItem(at: version.url)
    }

    /// Ist diese Fassung das, was gerade in der Datei steht?
    public func istAktiv(_ version: ClaudeAssetVersion, in datei: URL) -> Bool {
        guard let aktuell = try? String(contentsOf: datei, encoding: .utf8) else { return false }
        return inhalt(version) == aktuell
    }

    /// Räumt die ältesten **unbenannten** Fassungen weg.
    private func aufraeumen(_ datei: URL) {
        let alle = versionen(von: datei)
        let automatisch = alle.filter { $0.bezeichnung == nil }
        guard automatisch.count > Self.maxAutomatisch else { return }
        for version in automatisch.dropFirst(Self.maxAutomatisch) {
            try? FileManager.default.removeItem(at: version.url)
        }
    }

    // MARK: - Dateiname ⇄ Fassung

    static let trenner = " · "

    static var formatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// `2026-09-15 17-40-00 · vor dem Umbau.md`. `belegt` verhindert, dass zwei Fassungen in
    /// derselben Sekunde einander überschreiben.
    static func dateiname(datum: Date, bezeichnung: String?, belegt: [URL]) -> String {
        let stempel = formatter.string(from: datum)
        var stamm = stempel
        if let bezeichnung = sauber(bezeichnung) { stamm += trenner + bezeichnung }
        var kandidat = stamm + ".md"
        var zaehler = 2
        let namen = Set(belegt.map(\.lastPathComponent))
        while namen.contains(kandidat) {
            kandidat = "\(stamm) (\(zaehler)).md"
            zaehler += 1
        }
        return kandidat
    }

    /// Bezeichnung auf das reduzieren, was in einem Dateinamen stehen darf — ein `/` würde sonst
    /// einen Unterordner aufmachen.
    static func sauber(_ bezeichnung: String?) -> String? {
        guard let roh = bezeichnung?.trimmingCharacters(in: .whitespacesAndNewlines), !roh.isEmpty
        else { return nil }
        let gesaeubert = roh
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        return String(gesaeubert.prefix(80))
    }

    static func zerlegt(_ stamm: String) -> (Date, String?)? {
        let laenge = 19   // yyyy-MM-dd HH-mm-ss
        guard stamm.count >= laenge else { return nil }
        let stempel = String(stamm.prefix(laenge))
        guard let datum = formatter.date(from: stempel) else { return nil }
        let rest = String(stamm.dropFirst(laenge))
        guard rest.hasPrefix(trenner) else { return (datum, nil) }
        let bezeichnung = String(rest.dropFirst(trenner.count))
        return (datum, bezeichnung.isEmpty ? nil : bezeichnung)
    }
}
