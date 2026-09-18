import Foundation

/// Einstellungen des Watchdogs, aufgelöst aus der Config.
public struct WatchdogSettings: Sendable, Equatable {
    public var aktiv: Bool
    /// Wie oft der Hintergrund-Lauf scannt. Auswerten kostet Tokens, also ist die Vorgabe träge.
    public var intervallMinuten: Int
    /// Sessions, die länger nicht angefasst wurden, zählen nicht — „wiederkehrend" meint jetzt.
    public var rueckblickStunden: Int
    /// Obergrenze je Scan, damit ein Rückstau nicht zu einem Riesenlauf wird.
    public var maxSessions: Int
    /// Unter so vielen Signalen wird das Modell gar nicht erst gefragt — es gäbe nichts zu
    /// verdichten, und der Aufruf wäre bezahlte Leerlaufzeit.
    public var minSignale: Int
    public var modell: String
    /// Wie lange der Auswertungsaufruf dauern darf.
    ///
    /// Stand auf **240 s** und war damit zu knapp: ein echter Lauf (25 Sessions, 160 Signale,
    /// Sonnet) braucht hier gemessen **5½ bis 6 Minuten**. Das Zeitlimit schlug also jedes Mal zu,
    /// warf die bezahlte Antwort weg und hinterliess „claude hat nach 240s nicht geantwortet" —
    /// vier Minuten Spinner für nichts. Die Vorgabe hat jetzt Luft; wem das zu lange dauert, der
    /// stellt ein schnelleres Modell ein, nicht ein kürzeres Limit.
    public var timeoutSekunden: Int

    public static let modellVorgabe = "claude-sonnet-5"

    public init(aktiv: Bool = false, intervallMinuten: Int = 60, rueckblickStunden: Int = 72,
                maxSessions: Int = 25, minSignale: Int = 4,
                modell: String = WatchdogSettings.modellVorgabe, timeoutSekunden: Int = 900) {
        self.aktiv = aktiv
        self.intervallMinuten = intervallMinuten
        self.rueckblickStunden = rueckblickStunden
        self.maxSessions = maxSessions
        self.minSignale = minSignale
        self.modell = modell
        self.timeoutSekunden = timeoutSekunden
    }
}

/// Führt einen Watchdog-Lauf aus: finden → vorfiltern → (ggf.) auswerten → vereinen → speichern.
///
/// Ein Actor, kein `@MainActor`-Typ: ein Lauf liest dutzende Transcripts von der Platte und wartet
/// auf einen Unterprozess — beides hat auf dem UI-Thread nichts verloren.
public actor WatchdogScanner {

    public struct Ergebnis: Sendable {
        public let state: WatchdogState
        /// Befunde, die es vor diesem Lauf noch nicht gab.
        public let neueIds: [String]
        public let sessionsGescannt: Int
        public let signale: Int
        /// Falsch, wenn der heuristische Durchgang zu wenig fand, um das Modell zu fragen.
        public let ausgewertet: Bool
    }

    private let store: WatchdogStore
    private let projectsDir: String
    private let macheClient: @Sendable (String) -> ClaudeHeadless

    public init(store: WatchdogStore = WatchdogStore(),
                projectsDir: String = WatchdogTranscripts.projectsDir,
                macheClient: @escaping @Sendable (String) -> ClaudeHeadless = { ClaudeHeadless(modell: $0) }) {
        self.store = store
        self.projectsDir = projectsDir
        self.macheClient = macheClient
    }

    public func state() -> WatchdogState { store.laden() }

    // MARK: - Scan

    /// `async`, damit der Modellaufruf den **Actor nicht blockiert**.
    ///
    /// Vorher war `scan` synchron: der Unterprozess lief minutenlang *im* Actor, und damit stand
    /// alles andere still, was über ihn geht — `state()`, „Erledigt", „Aussortieren", „Papierkorb
    /// leeren". Wer während eines Laufs etwas wegwarf, sah schlicht nichts passieren.
    public func scan(_ settings: WatchdogSettings, jetzt: Date = Date()) async throws -> Ergebnis {
        var state = store.laden()
        let bekannt = Set(state.befunde.map(\.id))

        let grenze = jetzt.addingTimeInterval(-Double(settings.rueckblickStunden) * 3600)
        let transcripts = WatchdogTranscripts.alle(seit: grenze, projectsDir: projectsDir)
            .prefix(settings.maxSessions)

        var digests: [WatchdogDigest] = []
        var sessionInfo: [String: (titel: String?, projekt: String?)] = [:]
        var frischeCursors: [String: WatchdogCursor] = [:]

        for transcript in transcripts {
            // Seit dem letzten Blick unverändert? Die Signale sind bereits verbucht, erneut lesen
            // bringt nichts.
            if let cursor = state.cursors[transcript.sessionId], cursor.geaendert >= transcript.geaendert {
                continue
            }

            guard let inhalt = try? String(contentsOf: transcript.url, encoding: .utf8) else { continue }
            var scanner = WatchdogTranscriptScanner(sessionId: transcript.sessionId)
            for zeile in inhalt.split(separator: "\n", omittingEmptySubsequences: true) {
                scanner.consume(line: String(zeile))
            }

            let signale = scanner.ergebnis()
            frischeCursors[transcript.sessionId] = WatchdogCursor(
                geaendert: transcript.geaendert, signale: signale.count)
            sessionInfo[transcript.sessionId] = (scanner.ersterPrompt, scanner.projekt)

            guard !signale.isEmpty else { continue }
            digests.append(WatchdogDigest(
                sessionId: transcript.sessionId, titel: scanner.ersterPrompt,
                projekt: scanner.projekt, geaendert: transcript.geaendert, signale: signale))
        }

        let signalZahl = digests.reduce(0) { $0 + $1.signale.count }

        // Unter der Schwelle gibt es nichts zu verdichten. Die Cursors rücken trotzdem vor, damit
        // der nächste Lauf hier weitermacht.
        guard signalZahl >= settings.minSignale else {
            state.cursors.merge(frischeCursors) { _, neu in neu }
            state.letzterScan = jetzt
            state.letzterFehler = nil
            state.sessionsGescannt = frischeCursors.count
            try store.speichern(state)
            return Ergebnis(state: state, neueIds: [], sessionsGescannt: frischeCursors.count,
                            signale: signalZahl, ausgewertet: false)
        }

        // Der Bestand geht mit in den Prompt: sonst benennt das Modell dasselbe Muster jedes Mal
        // neu, und aus der Titel-Id wird ein zweiter Eintrag — auch für das, was schon aussortiert
        // war.
        let prompt = WatchdogPrompt.bauen(digests: digests, bekannte: state.befunde)
        let antwort: ClaudeHeadless.Antwort
        do {
            // Ausserhalb des Actors: der Aufruf wartet minutenlang auf einen Unterprozess.
            let client = macheClient(settings.modell)
            let frist = TimeInterval(settings.timeoutSekunden)
            antwort = try await Task.detached { try client.frage(prompt, timeout: frist) }.value
        } catch {
            // Eine gescheiterte Auswertung darf die Cursors **nicht** vorrücken — sonst wären genau
            // diese Sessions beim nächsten Lauf stillschweigend übersprungen.
            state.letzterScan = jetzt
            state.letzterFehler = error.localizedDescription
            try? store.speichern(state)
            throw error
        }

        let neu = try WatchdogParser.lies(antwort.text, sessionInfo: sessionInfo,
                                          bekannteIds: bekannt, jetzt: jetzt)

        state.befunde = WatchdogMerge.vereinen(bestand: state.befunde, neu: neu)
        state.cursors.merge(frischeCursors) { _, neu in neu }
        state.letzterScan = jetzt
        state.letzterFehler = nil
        state.letzteKostenUSD = antwort.kostenUSD
        state.sessionsGescannt = frischeCursors.count
        try store.speichern(state)

        return Ergebnis(state: state, neueIds: neu.map(\.id).filter { !bekannt.contains($0) },
                        sessionsGescannt: frischeCursors.count, signale: signalZahl, ausgewertet: true)
    }

    // MARK: - Änderungen

    public func setzeErledigt(_ erledigt: Bool, id: String) -> WatchdogState {
        var state = store.laden()
        if let index = state.befunde.firstIndex(where: { $0.id == id }) {
            state.befunde[index].erledigt = erledigt
            try? store.speichern(state)
        }
        return state
    }

    /// Einen Befund aussortieren — oder aus dem Papierkorb zurückholen.
    ///
    /// Bewusst kein Entfernen aus der Liste: die Id ist stabil, der nächste Scan brächte das Muster
    /// sonst als neuen Befund zurück. Ein Eintrag im Papierkorb ist ausserdem nachschaubar; ein
    /// stiller Filter wäre es nicht.
    public func setzeVerworfen(_ verworfen: Bool, id: String) -> WatchdogState {
        var state = store.laden()
        if let index = state.befunde.firstIndex(where: { $0.id == id }) {
            state.befunde[index].verworfen = verworfen
            try? store.speichern(state)
        }
        return state
    }

    /// Den Papierkorb endgültig leeren. Danach kann derselbe Befund wiederkommen — er ist ja nur
    /// deshalb draussen, weil er dort steht.
    public func papierkorbLeeren() -> WatchdogState {
        var state = store.laden()
        state.befunde.removeAll(where: \.verworfen)
        try? store.speichern(state)
        return state
    }

    /// Befunde weg, Cursors behalten: der Benutzer will eine leere Liste, keine erneute Auswertung
    /// von Transcripts, für die schon gezahlt wurde.
    public func leeren() -> WatchdogState {
        var state = store.laden()
        state.befunde = []
        try? store.speichern(state)
        return state
    }

    /// Alles zurück — Befunde und Cursors — damit der nächste Lauf den ganzen Rückblick neu liest.
    public func zuruecksetzen() -> WatchdogState {
        let state = WatchdogState()
        try? store.speichern(state)
        return state
    }
}
