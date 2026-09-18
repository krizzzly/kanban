import AppKit
import Observation
import SwiftUI
import KanbanCore

/// Wer welches Projekt zeigt — die einzige Stelle, an der die App weiss, dass es **mehrere**
/// Board-Fenster gibt.
///
/// `KanbanApp` deklariert eine `WindowGroup(for: String.self)` über den Projekt-Key; jedes Fenster
/// hat sein eigenes `AppModel` — eigenes Board, eigene Auswahl, eigene Console. Neue Fenster kommen
/// über den +-Knopf der Kopfzeile (und ⌘N); das Projekt-Menü schaltet weiterhin **im** Fenster um,
/// dasselbe Projekt darf also auch zweimal dastehen. Deshalb hängt hier alles am Fenster und nicht
/// am Projekt-Key.
///
/// Drei Dinge gibt es nur einmal im Prozess, und genau die laufen hier zusammen:
///
/// - **`TerminalCache.onTerminalClick`** — eine Closure für die ganze App. Ohne Zuordnung tickte ein
///   Klick in Fenster A das Model von Fenster B.
/// - **`AttentionNotifier`** — Benachrichtigungen gibt es nur einmal; der Klick darauf muss das
///   Fenster des betroffenen Projekts finden (und nötigenfalls eines aufmachen).
/// - **die Liste der offenen Projekte** (`SelectionStore.openProjectKeys`), aus der der nächste
///   Start seine Fenster wieder aufmacht.
///
/// Das Muster „ein Fenster je Schlüssel, ein vorhandenes nach vorn" gibt es im Haus schon
/// (`MarkdownDocumentWindow`); hier kommt es über SwiftUIs `openWindow(value:)` dazu — mit derselben
/// Regel: erst nachsehen, dann öffnen.
///
/// `@Observable`, weil die Kopfzeile davon lebt: der +-Knopf weiss nur so, ob überhaupt noch ein
/// Projekt ohne Fenster übrig ist, und das Projekt-Menü nur so, welche schon woanders offen stehen.
@Observable
@MainActor
final class ProjectWindows {
    static let shared = ProjectWindows()

    /// Ein Fenster. Der Schlüssel ist das **Model**, nicht das Projekt: ein Fenster kann sein
    /// Projekt wechseln, und zwei Fenster dürfen dasselbe zeigen.
    private struct Eintrag {
        let id: ObjectIdentifier
        var key: String
        weak var model: AppModel?
        weak var window: NSWindow?
    }

    /// Ein Eintrag je offenem Board-Fenster, in der Reihenfolge, in der sie aufgingen — dieselbe
    /// Reihenfolge, in der der nächste Start sie wieder aufmacht.
    private var eintraege: [Eintrag] = []
    private var beobachter: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    /// Wie ein Fenster entsteht: `openWindow(value:)` der Szene. Die Aktion gibt es nur im
    /// SwiftUI-Environment, deshalb reicht sie das erste `ContentView` hier herein.
    private var fensterOeffner: ((String) -> Void)?
    private var wiederhergestellt = false
    /// Projekte, deren Fenster das Wiederherstellen noch erwartet. Solange etwas darin steht, ist
    /// der Start nicht fertig — und erst wenn er es ist, lässt sich das zuletzt benutzte Fenster
    /// nach vorn holen (vorher gibt es das Fenster schlicht noch nicht).
    private var wartetAufFenster: Set<String> = []
    /// Ticket, das ein gerade aufgehendes Fenster wählen soll (Klick auf eine Benachrichtigung für
    /// ein Projekt, das noch kein Fenster hatte).
    private var gewuenschteTickets: [String: String] = [:]
    /// Fenster, die sich melden, bevor ihr Model sein Projekt kennt — die Ansicht hängt früher im
    /// Fenster, als `bootstrap` gelaufen ist. Schwach gehalten: ein Fenster, das es nie bis zur
    /// Anmeldung schafft (Projekt aus der Config verschwunden), soll hier nicht liegenbleiben.
    private var vorAnmeldung: [ObjectIdentifier: SchwachesFenster] = [:]
    /// Die App beendet sich — ab jetzt wird die gemerkte Liste nicht mehr fortgeschrieben. Sonst
    /// hinge es an der Abbaureihenfolge, ob ⌘Q die offenen Fenster für den nächsten Start behält.
    private var beendetSich = false
    /// Was wir selbst ins Fenster-Menü gehängt haben — um es beim nächsten Mal wieder zu entfernen.
    private var eigeneEintraege: [NSMenuItem] = []
    /// Die Ziele der Einträge. `NSMenuItem.target` hält nicht, also halten wir.
    private var menueZiele: [MenueZiel] = []

    /// Der gemerkte Stand, **bevor** das erste Fenster ihn fortschreibt. Als gespeicherte
    /// Eigenschaft gelesen: sie steht, sobald es die Instanz gibt — und die entsteht beim Start
    /// (`starten()`), vor jedem `anmelden`.
    private let gemerkteProjekte: [String]? = SelectionStore.openProjectKeys
    private let zuletztBenutzt: String? = SelectionStore.projectKey

    private init() {}

    // MARK: - Prozessweite Verdrahtung

    /// Einmal beim Programmstart (`AppDelegate`): die beiden prozessweiten Rückkanäle an die
    /// Fenster-Zuordnung hängen — und die Instanz anlegen, solange die gemerkte Liste noch steht.
    func starten() {
        TerminalCache.shared.onTerminalClick = { [weak self] window in
            // Der Klick gehört dem Fenster, in dem die Terminal-Ansicht gerade hängt — nicht dem
            // zuletzt gestarteten Model.
            self?.modell(zu: window)?.noteTerminalClick()
        }
        AttentionNotifier.shared.configure { [weak self] ticketKey in
            self?.ticketZeigen(ticketKey)
        }
    }

    /// Der Weg zu `openWindow(value:)`; jedes Fenster meldet ihn, das erste gewinnt.
    func merkeOeffner(_ oeffner: @escaping (String) -> Void) {
        guard fensterOeffner == nil else { return }
        fensterOeffner = oeffner
    }

    // MARK: - An- und Abmelden

    /// Dieses Fenster zeigt jetzt dieses Projekt — beim Aufgehen und nach jedem Projektwechsel darin.
    func anmelden(model: AppModel, key: String) {
        let id = ObjectIdentifier(model)
        if let index = eintraege.firstIndex(where: { $0.id == id }) {
            guard eintraege[index].key != key else { return }
            eintraege[index].key = key
        } else {
            eintraege.append(Eintrag(id: id, key: key, model: model, window: nil))
        }
        listeSchreiben()
        menueNachfuehren()
        if let frueh = vorAnmeldung.removeValue(forKey: id)?.window {
            fensterMerken(frueh, model: model)
        }
    }

    /// Das `NSWindow` zum Model. Kann vor **oder** nach `anmelden` kommen: die Ansicht hängt im
    /// Fenster, sobald SwiftUI sie aufbaut, das Projekt steht erst nach `bootstrap` fest.
    func fensterMerken(_ window: NSWindow?, model: AppModel) {
        guard let window else { return }
        let id = ObjectIdentifier(model)
        guard let index = eintraege.firstIndex(where: { $0.id == id }) else {
            vorAnmeldung[id] = SchwachesFenster(window: window)
            return
        }
        guard eintraege[index].window !== window else { return }
        eintraege[index].window = window
        menueNachfuehren()
        abmeldenVonBeobachtern(id)
        let zentrale = NotificationCenter.default
        beobachter[id] = [
            // Zumachen meldet ab: `onDisappear` bleibt bei geschlossenen Fenstern nicht verlässlich,
            // das Fenster selbst schon.
            zentrale.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                 queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.abmelden(id) }
            },
            // „Zuletzt benutzt" heisst mit mehreren Fenstern: das, in dem zuletzt gearbeitet wurde —
            // nicht das, das zuletzt aufgegangen ist. Ohne das stünde nach dem Wiederherstellen das
            // zuletzt gestartete Fenster in der Rückfallebene, und die ist genau dann gefragt, wenn
            // die Liste leer ist.
            zentrale.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                 queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let key = self?.eintraege.first(where: { $0.id == id })?.key else { return }
                    SelectionStore.projectKey = key
                }
            },
        ]
        pruefeStartFertig()
    }

    private func abmelden(_ id: ObjectIdentifier) {
        abmeldenVonBeobachtern(id)
        eintraege.removeAll { $0.id == id }
        listeSchreiben()
        menueNachfuehren()
    }

    private func abmeldenVonBeobachtern(_ id: ObjectIdentifier) {
        for token in beobachter.removeValue(forKey: id) ?? [] {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Das Fenster dieses Models zumachen — der Ausweg, wenn sein Projekt aus der Config verschwand.
    func schliessen(model: AppModel) {
        let id = ObjectIdentifier(model)
        (eintraege.first { $0.id == id }?.window ?? vorAnmeldung[id]?.window)?.close()
    }

    /// Die App geht: die gemerkte Liste steht jetzt fest. Fenster, die beim Abbau noch zugehen,
    /// sollen sie nicht mehr leeren — sonst käme der nächste Start mit einem Fenster hoch, weil beim
    /// letzten ⌘Q zufällig alle vier abgemeldet wurden.
    func endstandFesthalten() {
        beendetSich = true
    }

    // MARK: - Öffnen und nach vorn holen

    /// Ein Fenster für dieses Projekt: das vorhandene nach vorn, sonst ein neues.
    func oeffnen(_ key: String) {
        if nachVorn(key) { return }
        fensterOeffner?(key)
    }

    /// True, wenn ein Fenster dieses Projekt zeigt (dann steht es jetzt vorn).
    @discardableResult
    func nachVorn(_ key: String) -> Bool {
        guard let eintrag = eintraege.first(where: { $0.key == key && $0.model != nil }) else {
            return false
        }
        if let window = eintrag.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    /// Die Projekte mit Fenster, in Öffnungsreihenfolge und jedes nur einmal — zwei Fenster auf
    /// dasselbe Projekt sind erlaubt, brauchen beim nächsten Start aber nicht zwei Fenster.
    var offeneKeys: [String] {
        var gesehen: Set<String> = []
        return eintraege.filter { $0.model != nil && gesehen.insert($0.key).inserted }.map(\.key)
    }

    func zeigtProjekt(_ key: String) -> Bool { eintraege.contains { $0.key == key && $0.model != nil } }

    // MARK: - Start

    /// Welches Projekt ein Fenster **ohne** Szenenwert zeigt.
    ///
    /// Zwei Fälle, eine Regel: beim Start (noch kein Fenster angemeldet) ist es das erste der
    /// gemerkten Liste; später — ⌘N „Neues Fenster", das SwiftUI ohne Wert aufmacht — das erste
    /// Projekt, das noch keines hat.
    func vorschlag(projekte: [ProjectConfig]) -> ProjectConfig? {
        if offeneKeys.isEmpty {
            let liste = OpenProjects.wiederherstellen(gespeichert: gemerkteProjekte,
                                                      zuletzt: zuletztBenutzt,
                                                      vorhanden: projekte.map(\.key))
            if let erster = liste.first, let projekt = projekte.first(where: { $0.key == erster }) {
                return projekt
            }
        }
        return naechstesOhneFenster(projekte: projekte) ?? projekte.first
    }

    /// Das erste Projekt, das noch kein Fenster hat — was der +-Knopf der Kopfzeile aufmacht (und
    /// was ⌘N bekommt). nil heisst: jedes Projekt steht schon irgendwo.
    func naechstesOhneFenster(projekte: [ProjectConfig]) -> ProjectConfig? {
        let offen = Set(offeneKeys)
        return projekte.first { !offen.contains($0.key) }
    }

    /// Beim Start die übrigen gemerkten Projekte aufmachen — einmal je Programmlauf, gerufen vom
    /// ersten Fenster, sobald es sein eigenes Projekt kennt (deshalb steht es schon in `offeneKeys`
    /// und geht nicht doppelt auf).
    func wiederherstellen(projekte: [ProjectConfig]) {
        guard !wiederhergestellt else { return }
        wiederhergestellt = true
        let liste = OpenProjects.wiederherstellen(gespeichert: gemerkteProjekte,
                                                  zuletzt: zuletztBenutzt,
                                                  vorhanden: projekte.map(\.key))
        wartetAufFenster = Set(liste)
        for key in liste where !zeigtProjekt(key) { fensterOeffner?(key) }
        pruefeStartFertig()
    }

    /// Sind alle wiederhergestellten Fenster da, kommt das zuletzt benutzte nach vorn — dort wurde
    /// gearbeitet, und in welcher Reihenfolge die Fenster aufgegangen sind, ist dafür belanglos.
    ///
    /// Gerufen wird das, sobald ein Fenster sein `NSWindow` meldet: `openWindow` legt sie nicht
    /// sofort an, und ein Nach-vorn-Holen unmittelbar nach dem Aufruf ginge ins Leere.
    private func pruefeStartFertig() {
        guard !wartetAufFenster.isEmpty else { return }
        let mitFenster = Set(eintraege.filter { $0.window != nil }.map(\.key))
        guard wartetAufFenster.isSubset(of: mitFenster) else { return }
        wartetAufFenster = []
        if let zuletztBenutzt { nachVorn(zuletztBenutzt) }
    }

    /// Das Ticket, das ein frisch aufgegangenes Fenster wählen soll (einmalig).
    func gewuenschtesTicket(fuer key: String) -> String? {
        gewuenschteTickets.removeValue(forKey: key)
    }

    /// Nach dem Speichern der Einstellungen: **alle** Fenster lesen die Config neu. Vorher gab es
    /// nur eines, und „neu laden" hiess dasselbe wie „die App liest neu".
    func configNeuLaden() {
        for eintrag in eintraege { eintrag.model?.reloadConfig() }
    }

    // MARK: - Fenster-Menü

    /// Die offenen Boards im **Fenster-Menü** von macOS, jedes unter dem Namen seines Projekts.
    ///
    /// Ohne sie steht dort nichts: macOS listet ein Fenster über seinen Titel, und der ist hier
    /// leer — mit Absicht (siehe `.navigationTitle("")` in `ContentView`). Seit jedes Projekt sein
    /// eigenes Fenster hat, ist das eine Lücke: wer vier Boards offen hat, findet das gesuchte nur
    /// durch Probieren.
    ///
    /// **Über AppKit und nicht über SwiftUIs `.commands`.** `CommandGroup(after: .windowList)` war
    /// der naheliegende Weg und erzeugte nachweislich **gar keinen** Eintrag: die Menüs werden beim
    /// Start einmal gebaut, da ist noch kein Fenster angemeldet, und auf die Änderung der
    /// `@Observable`-Liste hin baut SwiftUI sie nicht neu (gemessen: zehn Sekunden nach dem Start,
    /// mit zwei angemeldeten Fenstern, war das Menü unverändert leer). Hier dagegen steht die
    /// Liste, die sich ohnehin bei jedem An- und Abmelden ändert — sie führt die Einträge gleich
    /// selbst nach.
    private func menueNachfuehren() {
        guard let menue = NSApp.windowsMenu else { return }
        for eintrag in eigeneEintraege where menue.items.contains(eintrag) {
            menue.removeItem(eintrag)
        }
        eigeneEintraege = []
        menueZiele = []

        // Fenster ohne eigenes `NSWindow` bleiben draussen — ein Eintrag, der nichts nach vorn
        // holen kann, ist schlimmer als keiner. Die **ohne Projekt** stehen dagegen drin (der
        // Setup-Schirm, ein Fenster, dessen Projekt aus der Config verschwand): erreichbar sein
        // müssen sie gerade dann, wenn daneben drei Boards stehen. `WindowTitles` nennt sie
        // „Kanban", und sie kommen ans Ende — welches Projekt sie einmal zeigen werden, ist noch
        // nicht entschieden.
        var offene: [(key: String?, window: NSWindow)] = eintraege.compactMap {
            guard let window = $0.window else { return nil }
            return ($0.key, window)
        }
        offene += vorAnmeldung.values.compactMap { schwach in
            schwach.window.map { (nil, $0) }
        }
        guard !offene.isEmpty else { return }
        let titel = WindowTitles.titel(fuer: offene.map(\.key))

        let trenner = NSMenuItem.separator()
        menue.addItem(trenner)
        eigeneEintraege.append(trenner)
        for (index, paar) in zip(offene, titel).enumerated() {
            let (fenster, name) = paar
            let ziel = MenueZiel { [weak window = fenster.window] in
                guard let window else { return }
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            // ⌘1…⌘9 in Öffnungsreihenfolge — Kurzbefehle, die die eingebaute Fensterliste von
            // macOS gar nicht vergibt. Ab dem zehnten Fenster bleibt der Eintrag ohne.
            let item = NSMenuItem(title: name, action: #selector(MenueZiel.ausloesen),
                                  keyEquivalent: index < 9 ? "\(index + 1)" : "")
            item.target = ziel
            menue.addItem(item)
            // `NSMenuItem.target` ist **schwach**: ohne diese Liste wäre das Ziel sofort wieder weg
            // und der Eintrag täte nichts.
            menueZiele.append(ziel)
            eigeneEintraege.append(item)
        }
    }

    // MARK: - Zuordnung
    // MARK: - Zuordnung
    // MARK: - Zuordnung

    private func modell(zu window: NSWindow?) -> AppModel? {
        guard let window else { return nil }
        return eintraege.first { $0.window === window }?.model
    }

    /// Klick auf eine Benachrichtigung: das Ticket im Fenster **seines** Projekts zeigen — und das
    /// Fenster dabei nach vorn holen. Hat das Projekt noch keines, geht eines auf und wählt das
    /// Ticket, sobald es steht.
    private func ticketZeigen(_ ticketKey: String) {
        if let eintrag = eintraege.first(where: { $0.model?.zeigtTicket(ticketKey) == true }) {
            eintrag.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            eintrag.model?.selectTicket(ticketKey)
            return
        }
        // Kein Board zeigt das Ticket — dann entscheidet der Prefix, welchem Projekt es gehört.
        let projekte = eintraege.compactMap(\.model).first?.projects ?? []
        guard let projekt = TicketRouting.projekt(fuerTicket: ticketKey, in: projekte) else { return }
        if let eintrag = eintraege.first(where: { $0.key == projekt.key }) {
            nachVorn(projekt.key)
            eintrag.model?.selectTicket(ticketKey)
        } else {
            gewuenschteTickets[projekt.key] = ticketKey
            oeffnen(projekt.key)
        }
    }

    /// Die gemerkte Liste ist immer der Stand von **jetzt**: welche Projekte gerade ein Fenster
    /// haben, in der Reihenfolge, in der sie aufgingen. Wer alle Fenster zumacht, beendet Kanban und
    /// findet beim nächsten Start ein Fenster mit dem zuletzt benutzten Projekt vor — geschlossen
    /// ist geschlossen.
    private func listeSchreiben() {
        guard !beendetSich else { return }
        SelectionStore.openProjectKeys = offeneKeys
    }
}

/// Was ein Eintrag des Fenster-Menüs tut. `NSMenuItem` will ein Ziel mit Selektor; eine Closure
/// darin zu verpacken ist der kürzeste Weg, der ohne eine zweite Zuordnung „Eintrag → Fenster"
/// auskommt.
@MainActor
private final class MenueZiel: NSObject {
    private let aktion: () -> Void
    init(_ aktion: @escaping () -> Void) { self.aktion = aktion; super.init() }
    @objc func ausloesen() { aktion() }
}

/// Ein Fenster, das noch keinem Eintrag gehört — ohne es am Leben zu halten.
private struct SchwachesFenster {
    weak var window: NSWindow?
}

/// Reicht das `NSWindow` einer SwiftUI-Ansicht nach aussen — die Zuordnung „Fenster → Model" in
/// `ProjectWindows` braucht es, und SwiftUI gibt es nicht her.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    /// Auch beim Aktualisieren: beim ersten Aufbau hängt die Ansicht noch in keinem Fenster.
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}


