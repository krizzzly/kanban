import Foundation
import Observation
import KanbanCore

/// Die UI-Seite des Watchdogs: hält den angezeigten Stand und treibt den Hintergrund-Lauf.
/// Die eigentliche Arbeit macht `WatchdogScanner` (Actor) — hier läuft nichts, was blockiert.
///
/// Der Takt ist bewusst kurz und entscheidet **selbst**, ob ein Lauf fällig ist, statt das ganze
/// Intervall zu verschlafen: so wirkt das Ausschalten in den Einstellungen nach Sekunden und nicht
/// erst nach einer Stunde.
///
/// **Einer für den ganzen Prozess** (`shared`), nicht einer je Fenster: seit „ein Fenster je
/// Projekt" gibt es N `AppModel`s, und jedes eigene hätte seinen eigenen Takt — der Scan startet
/// `claude -p` und kostet Geld, N-fach also N-mal so viel. Er arbeitet ohnehin projektübergreifend
/// (alle Sessions, eine Datei), deshalb zeigen alle Fenster denselben Stand.
@Observable
@MainActor
final class WatchdogModel {
    static let shared = WatchdogModel()

    private(set) var befunde: [WatchdogFinding] = []
    private(set) var laeuft = false
    /// Seit wann der laufende Scan läuft — der Spinner soll sagen, worauf er wartet, statt nur zu
    /// drehen. Ein Lauf dauert hier gemessen 5–6 Minuten.
    private(set) var laeuftSeit: Date?
    /// Wurde der laufende Scan von Hand abgebrochen? Dann ist sein Ende kein Fehler.
    private var abbruchGewollt = false
    private(set) var letzterScan: Date?
    private(set) var letzterFehler: String?
    private(set) var letzteKostenUSD: Double?
    private(set) var sessionsGescannt: Int?
    private(set) var cliVerfuegbar = true
    /// Befunde aus dem jüngsten Lauf — das Panel markiert sie als neu.
    private(set) var neueIds: Set<String> = []

    var panelOffen = false

    /// Verworfenes ist aus allen drei Listen draussen ausser dem Papierkorb — es soll ja weg sein.
    var offene: [WatchdogFinding] {
        WatchdogMerge.sortiert(befunde.filter { !$0.erledigt && !$0.verworfen })
    }
    var erledigte: [WatchdogFinding] {
        WatchdogMerge.sortiert(befunde.filter { $0.erledigt && !$0.verworfen })
    }
    var verworfene: [WatchdogFinding] { WatchdogMerge.sortiert(befunde.filter(\.verworfen)) }
    var offeneAnzahl: Int { befunde.count { !$0.erledigt && !$0.verworfen } }

    private var settings = WatchdogSettings()
    private let scanner = WatchdogScanner()
    private var schleife: Task<Void, Never>?

    /// Taktlänge der Schleife — kurz genug, dass der Schalter sich sofort anfühlt, lang genug, dass
    /// das Aufwachen nichts kostet.
    private let takt: Duration = .seconds(20)

    /// Wurde schon übernommen? Jedes aufgehende Fenster ruft `uebernehmen` — beim zweiten gibt es
    /// nichts mehr zu tun, und ein zweiter Takt wäre genau der doppelte Scan, der hier nicht
    /// entstehen darf.
    private var uebernommen = false

    init() {}

    /// Gespeicherte Befunde laden, damit das Panel schon vor dem ersten Lauf etwas zeigt.
    ///
    /// Beim zweiten und jedem weiteren Fenster absichtlich wirkungslos: Befunde und Einstellungen
    /// sind prozessweit dieselben, und der Takt liest die Config ohnehin bei jedem Durchgang neu.
    func uebernehmen(config: AppConfig?) async {
        guard !uebernommen else { return }
        uebernommen = true
        settings = config?.watchdog ?? WatchdogSettings()
        cliVerfuegbar = ClaudeHeadless.verfuegbar
        anwenden(await scanner.state())
        starten()
    }

    /// Profilwechsel: der Stand gehört ab jetzt einer anderen Datei.
    ///
    /// `WatchdogStore` rechnet seinen Pfad aus dem Datenordner, und der zeigt nach dem Wechsel
    /// woandershin — der Scanner muss ihn aber auch neu binden, sonst schriebe er die Befunde des
    /// privaten Profils weiter in die `watchdog.json` der Arbeit. Das wäre kein Schönheitsfehler,
    /// sondern ein Übertritt über die Profilgrenze: ein Befund trägt wörtliche
    /// Transcript-Ausschnitte.
    func profilGewechselt() {
        stoppen()
        uebernommen = false
        befunde = []
        neueIds = []
        letzterScan = nil
        letzterFehler = nil
        letzteKostenUSD = nil
        sessionsGescannt = nil
        Task { [weak self] in
            await self?.scanner.neuAufsetzen()
            await self?.uebernehmen(config: try? KanbanConfig.load())
        }
    }

    func starten() {
        guard schleife == nil else { return }
        schleife = Task { [weak self] in
            while !Task.isCancelled {
                await self?.takten()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func stoppen() {
        schleife?.cancel()
        schleife = nil
    }

    /// Den laufenden Scan beenden. Beendet den `claude -p`-Unterprozess; der Lauf endet daraufhin
    /// von selbst, und sein Abbruch zählt nicht als Fehler.
    func abbrechen() {
        guard laeuft else { return }
        abbruchGewollt = true
        _ = ClaudeHeadless.alleBeenden()
    }

    /// „Jetzt scannen" aus dem Panel — läuft auch, wenn der Watchdog ausgeschaltet ist. Der Schalter
    /// regelt den Hintergrund-Lauf, nicht den ausdrücklichen Wunsch des Benutzers.
    func jetztScannen() async {
        await scannen()
    }

    func setzeErledigt(_ erledigt: Bool, id: String) async {
        anwenden(await scanner.setzeErledigt(erledigt, id: id))
    }

    /// Aussortieren (in den Papierkorb) bzw. von dort zurückholen.
    func setzeVerworfen(_ verworfen: Bool, id: String) async {
        anwenden(await scanner.setzeVerworfen(verworfen, id: id))
        // Ein aussortierter Befund ist nicht mehr „neu" — sonst bliebe die Markierung am Eintrag
        // im Papierkorb kleben und der Zähler am Knopf spräche von etwas, das keiner sehen will.
        if verworfen { neueIds.remove(id) }
    }

    func papierkorbLeeren() async {
        anwenden(await scanner.papierkorbLeeren())
    }

    func leeren() async {
        anwenden(await scanner.leeren())
        neueIds = []
    }

    func zuruecksetzen() async {
        anwenden(await scanner.zuruecksetzen())
        neueIds = []
    }

    func alsGesehenMarkieren() {
        neueIds = []
    }

    // MARK: - Intern

    private func takten() async {
        // Die Config wird bei jedem Takt neu gelesen, damit ein Speichern in den Einstellungen
        // ohne Neustart greift.
        if let frisch = try? KanbanConfig.load().watchdog { settings = frisch }
        guard settings.aktiv, !laeuft else { return }

        let intervall = Double(max(settings.intervallMinuten, 1)) * 60
        if let letzterScan, Date().timeIntervalSince(letzterScan) < intervall { return }

        await scannen()
    }

    private func scannen() async {
        guard !laeuft else { return }
        laeuft = true
        laeuftSeit = Date()
        abbruchGewollt = false
        defer { laeuft = false; laeuftSeit = nil; abbruchGewollt = false }

        // Hier geprüft und nicht beim Start: die CLI kann während der Laufzeit kommen oder gehen,
        // und ein fehlendes Binary soll als klarer Satz im Panel stehen statt als Prozessfehler
        // bei jedem Takt.
        cliVerfuegbar = ClaudeHeadless.verfuegbar
        guard cliVerfuegbar else {
            letzterFehler = ClaudeHeadless.Fehler.cliFehlt.localizedDescription
            return
        }

        let aktuelle = settings
        do {
            let ergebnis = try await scanner.scan(aktuelle)
            anwenden(ergebnis.state)
            neueIds.formUnion(ergebnis.neueIds)
        } catch {
            // Ein selbst abgebrochener Lauf ist kein Fehlschlag — sonst stünde in der Fusszeile
            // „Letzter Lauf gescheitert", weil jemand auf ✕ gedrückt hat.
            letzterFehler = abbruchGewollt ? nil : error.localizedDescription
            letzterScan = Date()
        }
    }

    private func anwenden(_ state: WatchdogState) {
        befunde = state.befunde
        letzterScan = state.letzterScan
        letzterFehler = state.letzterFehler
        letzteKostenUSD = state.letzteKostenUSD
        sessionsGescannt = state.sessionsGescannt
    }
}
