import AppKit
import KanbanCore

/// Was „dieses Profil gilt jetzt" im laufenden Prozess bedeutet — und wie man von einem zum
/// nächsten kommt.
///
/// Die Pfad-Ebene allein genügt dafür nicht. Kanban hält eine Handvoll prozessweiter Dinge, die
/// einen Wechsel sonst überleben würden und dann auf die falsche Welt zeigen: die gemerkte Auswahl,
/// die tmux-Namen, die Symlinks in den Agent-Homes, der Watchdog und die lebenden Terminal-Ansichten.
/// Sie laufen hier zusammen, damit ein Profilwechsel **eine** Stelle ist und nicht sechs.
@MainActor
enum ProfileRuntime {
    /// Läuft gerade ein Wechsel? Zwei Stellen fragen das, und beide aus ernstem Grund:
    ///
    /// - `applicationShouldTerminateAfterLastWindowClosed` — sonst beendet sich die App in dem
    ///   Moment, in dem das letzte Fenster des alten Profils zugeht. Die Entscheidung von
    ///   KANBAN-006 („ist das letzte Brett zu, gibt es nichts mehr zu tun") bleibt, sie gilt nur
    ///   nicht für einen Zwischenschritt, der per Definition gleich wieder Fenster aufmacht.
    /// - `ProjectWindows.listeSchreiben` — sonst schriebe der Abbau der alten Fenster erst deren
    ///   Liste und dann eine leere in die Schlüssel des **neuen** Profils und löschte damit genau
    ///   die Erinnerung, die gleich wiederhergestellt werden soll.
    private(set) static var wechselLaeuft = false

    /// Das Profil, das gerade gilt.
    private(set) static var aktiv: KanbanProfile?

    // MARK: - Start

    /// Einmal beim Programmstart, **vor** allem anderen: `profiles.json` anlegen, falls es sie noch
    /// nicht gibt, und das aktive Profil anwenden.
    ///
    /// Muss in `KanbanApp.init()` laufen, nicht im `AppDelegate`: Selftest, Task-File-Migration und
    /// die Verlinkung der Skill-Sets in die Agent-Homes hängen alle schon dort am Datenordner.
    static func beimStart() {
        ProfileStore.migrateIfNeeded()
        anwenden(ProfileStore.active())
    }

    /// Ab jetzt gilt dieses Profil — Pfade, gemerkte Auswahl, tmux-Namensraum.
    ///
    /// Bewusst ohne Fenster und ohne Symlinks: das hier ist der Teil, den auch der Start braucht.
    static func anwenden(_ profil: KanbanProfile) {
        aktiv = profil
        KanbanPaths.setRoot(profil.folder)
        SelectionStore.keys = ProfileDefaults(profile: profil)
        // Das Vorgabe-Profil behält seine gewohnten Sitzungsnamen; alles andere bekommt den Slug.
        TerminalSessionResolver.profileSlug = profil.isDefault ? nil : profil.slug
    }

    // MARK: - Wechseln

    /// Tickets, an denen gerade ein Turn läuft — der Grund, vor einem Wechsel zu fragen.
    ///
    /// Die tmux-Sitzung läuft weiter, das Fenster geht zu; wer gerade auf eine Antwort wartet, soll
    /// das trotzdem erfahren, bevor sein Brett verschwindet.
    static func laufendeTurns() -> [String] {
        ProjectWindows.shared.modelle().compactMap(\.laufenderTurnTicket)
    }

    /// Der Wechsel. Die Reihenfolge ist die eigentliche Aussage dieser Methode.
    static func wechseln(zu slug: String) throws {
        guard !wechselLaeuft else { return }
        guard let ziel = ProfileStore.load().profiles.first(where: { $0.slug == slug }) else {
            throw ProfileError.unknownProfile(slug)
        }
        guard ziel.slug != aktiv?.slug else { return }

        wechselLaeuft = true
        defer { wechselLaeuft = false }

        // 1. In `profiles.json` festhalten, dann anwenden — wer jetzt abstürzt, startet im neuen
        //    Profil, nicht in einem halben.
        try ProfileStore.activate(slug: slug)
        anwenden(ziel)

        // 2. Alles, was am alten Profil hing, loslassen. Die Terminal-Ansichten zuerst: sie zeigen
        //    auf tmux-Sitzungen, die dem neuen Profil nicht gehören (die Sitzungen selbst laufen
        //    weiter, nur die Ansicht darauf ist hier zu Ende).
        TerminalCache.shared.leeren()
        KanbanSettingsStore.reload()
        TerminalCache.shared.reapplyAppearance()

        // 3. Die Skill-Sets des neuen Profils in die Agent-Homes — und die des alten dort weg,
        //    auch wenn das neue Profil gar keins hat.
        let config = try? KanbanConfig.load()
        ClaudeAssetFactory.linkDefaultSetIntoHomes(config?.defaultSkillSet)

        // 4. Der Watchdog liest eine Datei im Profilordner; sein Stand ist ab jetzt ein anderer.
        WatchdogModel.shared.profilGewechselt()

        // 5. Zuletzt die Fenster: erst jetzt steht die Welt, in die sie schauen sollen.
        ProjectWindows.shared.profilWechsel()

        // 6. Riegel lösen und den Stand festhalten — ab hier ist die Liste wieder die des
        //    laufenden Betriebs, und sie gehört dem neuen Profil.
        wechselLaeuft = false
        ProjectWindows.shared.listeJetztSchreiben()
    }
}
