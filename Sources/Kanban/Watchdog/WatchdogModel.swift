import Foundation
import Observation
import KanbanCore

/// Die UI-Seite des Watchdogs: hält den angezeigten Stand und treibt den Hintergrund-Lauf.
/// Die eigentliche Arbeit macht `WatchdogScanner` (Actor) — hier läuft nichts, was blockiert.
///
/// Der Takt ist bewusst kurz und entscheidet **selbst**, ob ein Lauf fällig ist, statt das ganze
/// Intervall zu verschlafen: so wirkt das Ausschalten in den Einstellungen nach Sekunden und nicht
/// erst nach einer Stunde.
@Observable
@MainActor
final class WatchdogModel {

    private(set) var befunde: [WatchdogFinding] = []
    private(set) var laeuft = false
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

    init() {}

    /// Gespeicherte Befunde laden, damit das Panel schon vor dem ersten Lauf etwas zeigt.
    func uebernehmen(config: AppConfig?) async {
        settings = config?.watchdog ?? WatchdogSettings()
        cliVerfuegbar = ClaudeHeadless.verfuegbar
        anwenden(await scanner.state())
        starten()
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
        defer { laeuft = false }

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
            letzterFehler = error.localizedDescription
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
