import Foundation

/// Welche Projekte beim letzten Beenden ein Fenster hatten — die Liste, aus der der nächste Start
/// seine Fenster wieder aufmacht.
///
/// Reine Listenlogik, ohne `UserDefaults`: genau wie bei `SprintSelection` gehört das Ablegen der
/// App (`SelectionStore`), die Regel aber hierher, wo sie ohne UI prüfbar ist.
///
/// Vorher merkte sich Kanban **einen** Projekt-Key („das Projekt beim letzten Beenden"), weil es nur
/// ein Board-Fenster gab. Der alte Einzelwert bleibt gültig und wird als einelementige Liste
/// gelesen — niemand soll seine Auswahl verlieren, nur weil aus einem Fenster mehrere geworden sind.
public enum OpenProjects {

    /// Obergrenze für das Wiederherstellen. Bei 13 konfigurierten Projekten wäre „alle, die je offen
    /// waren" ein Bildschirm voller Fenster, von denen jedes sein Board lädt; was darüber steht,
    /// fällt weg — die Reihenfolge ist die Öffnungsreihenfolge, das zuletzt Benutzte bleibt also da.
    public static let maximum = 6

    /// Die Fenster, die beim Start aufgehen sollen.
    ///
    /// - Parameters:
    ///   - gespeichert: die gemerkte Liste (nil, solange nur der alte Einzelwert existiert)
    ///   - zuletzt: der alte Einzelwert `selectedProjectKey` — Rückfallebene und zugleich das
    ///     Projekt, das bei leerer Liste ein Fenster bekommt
    ///   - vorhanden: die Keys der konfigurierten Projekte, in Config-Reihenfolge
    ///
    /// Keys, die es nicht mehr gibt, fallen weg: ein aus der Config entferntes Projekt soll kein
    /// Phantom-Fenster öffnen. Bleibt nichts übrig, steht das erste konfigurierte Projekt da —
    /// Kanban startet nie ohne Board.
    public static func wiederherstellen(gespeichert: [String]?,
                                        zuletzt: String?,
                                        vorhanden: [String]) -> [String] {
        let bekannt = Set(vorhanden)
        let roh = gespeichert ?? zuletzt.map { [$0] } ?? []
        var liste = ohneDoppelte(roh.filter(bekannt.contains))
        if liste.isEmpty, let zuletzt, bekannt.contains(zuletzt) { liste = [zuletzt] }
        if liste.isEmpty, let erstes = vorhanden.first { liste = [erstes] }
        return Array(liste.prefix(maximum))
    }

    private static func ohneDoppelte(_ keys: [String]) -> [String] {
        var gesehen: Set<String> = []
        return keys.filter { gesehen.insert($0).inserted }
    }
}
