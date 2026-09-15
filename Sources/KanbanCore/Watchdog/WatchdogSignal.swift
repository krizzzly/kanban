import Foundation

/// Eine billige, lokal erkannte Auffälligkeit aus einem Transcript. Signale sind **keine** Befunde —
/// sie sind das Rohmaterial, das der Modell-Durchgang zu wiederkehrenden Mustern verdichtet.
///
/// Die Zweiteilung hält die Kosten im Griff: jedes Transcript durch ein Modell zu schicken wäre
/// langsam und teuer, während Regex allein nie erkennt, *warum* jemand dreimal nachfassen musste.
/// Also filtert der Scanner vor, und das Modell deutet.
public struct WatchdogSignal: Sendable, Equatable {
    public enum Art: String, Sendable, CaseIterable {
        /// Werkzeug meldete einen Fehler (`is_error` im Transcript — kein Ratespiel).
        case werkzeugFehler
        /// Der Benutzer hat widersprochen, korrigiert oder sich wiederholt.
        case korrektur
        /// Freigabe verweigert bzw. Abbruch durch den Benutzer.
        case freigabeVerweigert
        /// Build, Test oder Lint ist in einem Werkzeug-Ergebnis gescheitert.
        case buildOderTest
        /// Dasselbe Werkzeug mehrfach mit identischer Eingabe.
        case wiederholung

        public var istVerhalten: Bool {
            switch self {
            case .korrektur, .freigabeVerweigert: return true
            case .werkzeugFehler, .buildOderTest, .wiederholung: return false
            }
        }
    }

    public let art: Art
    public let sessionId: String
    /// Wörtlicher Ausschnitt, bereits gekürzt.
    public let ausschnitt: String
    /// Werkzeugname, wo vorhanden — das Modell gruppiert danach.
    public let betreff: String?
    public let zeitpunkt: Date?

    public init(art: Art, sessionId: String, ausschnitt: String,
                betreff: String? = nil, zeitpunkt: Date? = nil) {
        self.art = art
        self.sessionId = sessionId
        self.ausschnitt = ausschnitt
        self.betreff = betreff
        self.zeitpunkt = zeitpunkt
    }
}

/// Der heuristische Durchgang über ein Transcript — Zeile für Zeile, wie `ClaudeTurnAccumulator`,
/// damit ein wachsendes Transcript genauso gefüttert werden kann.
///
/// Alles hier ist bewusst zurückhaltend: ein verpasstes Signal kostet Trefferquote auf einer Session,
/// ein falsches kostet Tokens und verwässert die Eingabe des Modells. Die Phrasenlisten decken
/// Deutsch und Englisch ab, weil die Sessions beides mischen.
public struct WatchdogTranscriptScanner: Sendable {

    /// Längster Ausschnitt je Signal — genug zum Beurteilen, klein genug, dass ein paar hundert
    /// Signale noch in einen Prompt passen.
    public static let ausschnittLimit = 320

    /// Ab wie vielen identischen Aufrufen desselben Werkzeugs ein Wiederholungs-Signal entsteht.
    public static let wiederholungsSchwelle = 3

    private let sessionId: String
    private var signale: [WatchdogSignal] = []
    private var werkzeugZaehler: [String: Int] = [:]
    private var gemeldeteWiederholungen: Set<String> = []

    /// Im selben Durchgang mitgenommen, statt die Datei ein zweites Mal zu öffnen: das
    /// Arbeitsverzeichnis benennt das Projekt, der erste getippte Prompt gibt der Session einen
    /// Titel — beides braucht das Panel, um einen Beleg zuzuordnen.
    public private(set) var cwd: String?
    public private(set) var ersterPrompt: String?

    public init(sessionId: String) {
        self.sessionId = sessionId
    }

    public func ergebnis() -> [WatchdogSignal] { signale }

    /// Letztes Pfadsegment des Arbeitsverzeichnisses — der Projektname, wie ihn das Panel zeigt.
    public var projekt: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    public mutating func consume(line: String) {
        // Gleicher Vorfilter wie beim Timing: Zeilen ohne Zeitstempel (Datei-Snapshots, Mode-Records)
        // sind die grössten der Datei und können nie beitragen.
        guard line.contains("\"timestamp\"") else { return }
        guard let data = line.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        // Subagent-Verkehr ist nicht das Gespräch, das der Benutzer geführt hat.
        guard entry["isSidechain"] as? Bool != true else { return }

        if cwd == nil, let eintragsCwd = entry["cwd"] as? String, !eintragsCwd.isEmpty {
            cwd = eintragsCwd
        }

        let zeitpunkt = (entry["timestamp"] as? String).flatMap(TranscriptTime.parse)
        let typ = entry["type"] as? String
        guard typ == "user" || typ == "assistant" else { return }
        guard let message = entry["message"] as? [String: Any] else { return }

        if let text = message["content"] as? String {
            // Reiner Text-Eintrag: nur beim Benutzer interessant.
            if typ == "user" {
                merkeErstenPrompt(text)
                pruefeKorrektur(text, zeitpunkt: zeitpunkt)
            }
            return
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return }

        for block in blocks {
            switch block["type"] as? String {
            case "text" where typ == "user":
                let text = block["text"] as? String ?? ""
                merkeErstenPrompt(text)
                pruefeKorrektur(text, zeitpunkt: zeitpunkt)

            case "tool_use":
                pruefeWiederholung(block, zeitpunkt: zeitpunkt)

            case "tool_result":
                pruefeWerkzeugErgebnis(block, zeitpunkt: zeitpunkt)

            default:
                continue
            }
        }
    }

    // MARK: - Einzelprüfungen

    /// Der erste Text, den der Benutzer wirklich getippt hat — Claude Codes eigene Einschübe und
    /// Slash-Command-Rümpfe zählen nicht (dieselbe Unterscheidung wie beim Timing).
    private mutating func merkeErstenPrompt(_ text: String) {
        guard ersterPrompt == nil else { return }
        let getrimmt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !getrimmt.isEmpty, !getrimmt.hasPrefix("<"),
              !getrimmt.hasPrefix(Self.abbruchMarker) else { return }
        ersterPrompt = String(getrimmt.prefix(160))
    }

    private mutating func pruefeKorrektur(_ text: String, zeitpunkt: Date?) {
        let getrimmt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !getrimmt.isEmpty else { return }
        // Claude Codes eigene Einschübe (`<task-notification>`, `<local-command-stdout>`, …) kommen
        // als Tag, nie als Prosa — dieselbe Unterscheidung wie `ClaudeTurnAccumulator.isTypedPrompt`.
        guard !getrimmt.hasPrefix("<"), !getrimmt.hasPrefix("/") else { return }
        guard !getrimmt.hasPrefix(Self.abbruchMarker) else { return }
        // Lange Nachrichten sind neue Aufträge, keine Korrekturen. Der Widerspruch, auf den es
        // ankommt, ist kurz und kommt sofort.
        guard getrimmt.count <= 600 else { return }
        guard let treffer = ersterTreffer(getrimmt.lowercased(), Self.korrekturPhrasen) else { return }

        signale.append(WatchdogSignal(art: .korrektur, sessionId: sessionId,
                                      ausschnitt: kuerzen(getrimmt), betreff: treffer,
                                      zeitpunkt: zeitpunkt))
    }

    private mutating func pruefeWiederholung(_ block: [String: Any], zeitpunkt: Date?) {
        guard let name = block["name"] as? String else { return }
        let eingabe = (block["input"] as? [String: Any])
            .map { dict in
                dict.keys.sorted()
                    .map { "\($0)=\(String(describing: dict[$0] ?? "").prefix(120))" }
                    .joined(separator: "&")
            } ?? ""
        let fingerabdruck = name + "|" + eingabe

        let anzahl = (werkzeugZaehler[fingerabdruck] ?? 0) + 1
        werkzeugZaehler[fingerabdruck] = anzahl
        guard anzahl == Self.wiederholungsSchwelle,
              !gemeldeteWiederholungen.contains(fingerabdruck) else { return }
        gemeldeteWiederholungen.insert(fingerabdruck)

        signale.append(WatchdogSignal(
            art: .wiederholung, sessionId: sessionId,
            ausschnitt: kuerzen("\(name) \(Self.wiederholungsSchwelle)× mit identischer Eingabe: \(eingabe)"),
            betreff: name, zeitpunkt: zeitpunkt))
    }

    private mutating func pruefeWerkzeugErgebnis(_ block: [String: Any], zeitpunkt: Date?) {
        let inhalt = Self.text(ausInhalt: block["content"])
        guard !inhalt.isEmpty else { return }
        let klein = inhalt.lowercased()

        // Ein Ergebnis erzeugt höchstens ein Signal; das spezifischste gewinnt, damit die Zählungen
        // etwas bedeuten. `is_error` ist dabei die einzige Aussage, die nicht geraten ist —
        // ausgewertet nach den Phasen, weil "verweigert" und "Build kaputt" beide als Fehler kommen.
        let art: WatchdogSignal.Art
        if ersterTreffer(klein, Self.freigabePhrasen) != nil {
            art = .freigabeVerweigert
        } else if ersterTreffer(klein, Self.fehlschlagPhrasen) != nil {
            art = .buildOderTest
        } else if block["is_error"] as? Bool == true || ersterTreffer(klein, Self.fehlerPhrasen) != nil {
            art = .werkzeugFehler
        } else {
            return
        }

        signale.append(WatchdogSignal(art: art, sessionId: sessionId, ausschnitt: kuerzen(inhalt),
                                      betreff: nil, zeitpunkt: zeitpunkt))
    }

    // MARK: - Phrasen

    static let abbruchMarker = "[Request interrupted by user"

    /// Widerspruch des Benutzers. Bewusst an Satzanfänge und Zeichensetzung gebunden, damit das
    /// blosse Vorkommen eines Wortes („der no-op-Fall", „behebe den error") nicht zählt.
    static let korrekturPhrasen: [String] = [
        "nein,", "nein ", "falsch", "nicht so", "das war nicht", "so nicht", "stimmt nicht",
        "ich hatte gesagt", "wie gesagt", "hatte ich doch", "warum hast du", "du sollst",
        "du solltest nicht", "bitte nicht", "vergiss", "rückgängig", "mach das weg",
        "nochmal:", "immer noch", "schon wieder", "das ist die falsche",
        "no,", "nope", "that's wrong", "thats wrong", "not what i", "i said", "i told you",
        "as i said", "you didn't", "you did not", "undo that", "revert that", "wrong again",
        "not correct", "still broken", "again:",
    ]

    static let fehlschlagPhrasen: [String] = [
        "build failed", "compilation failed", "compile error", "error:",
        "tests failed", "test failed", "failing tests", "assertion failed",
        "npm err!", "fatal error", "traceback (most recent call last)",
        "exit code 1", "exit status 1", "fatal:", "segmentation fault",
        "cannot find module", "module not found", "unresolved reference",
    ]

    static let freigabePhrasen: [String] = [
        "user doesn't want to proceed", "user does not want to proceed",
        "permission denied", "operation not permitted", "user rejected", "user denied",
        "requested permissions", "not allowed to",
    ]

    static let fehlerPhrasen: [String] = [
        "<tool_use_error>", "error executing tool", "tool execution failed",
        "invalid input", "inputvalidationerror", "no such file or directory",
        "command not found", "timed out",
    ]

    // MARK: - Hilfen

    /// Der Inhalt eines `tool_result` ist mal ein String, mal eine Blockliste.
    static func text(ausInhalt inhalt: Any?) -> String {
        if let text = inhalt as? String { return text }
        if let blocks = inhalt as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        return ""
    }

    private func ersterTreffer(_ heuhaufen: String, _ nadeln: [String]) -> String? {
        nadeln.first { heuhaufen.contains($0) }
    }

    private func kuerzen(_ text: String) -> String {
        let einzeilig = text
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ⏎ ")
        return einzeilig.count <= Self.ausschnittLimit
            ? einzeilig
            : String(einzeilig.prefix(Self.ausschnittLimit)) + "…"
    }

    /// Bequemlichkeit für Tests und für das Einlesen einer ganzen Datei.
    public static func scan(lines: [String], sessionId: String) -> [WatchdogSignal] {
        var scanner = WatchdogTranscriptScanner(sessionId: sessionId)
        for line in lines { scanner.consume(line: line) }
        return scanner.ergebnis()
    }
}
