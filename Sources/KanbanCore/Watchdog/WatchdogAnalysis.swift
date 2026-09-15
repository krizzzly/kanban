import Foundation

/// Was eine Session zum Scan beiträgt — die vorgefilterten Signale plus das, was sie benennt.
public struct WatchdogDigest: Sendable, Equatable {
    public let sessionId: String
    public let titel: String?
    public let projekt: String?
    public let geaendert: Date
    public let signale: [WatchdogSignal]

    public init(sessionId: String, titel: String?, projekt: String?, geaendert: Date,
                signale: [WatchdogSignal]) {
        self.sessionId = sessionId
        self.titel = titel
        self.projekt = projekt
        self.geaendert = geaendert
        self.signale = signale
    }
}

/// Baut den Auswertungs-Prompt. Rein, damit der genaue Wortlaut nachlesbar und testbar ist, ohne
/// einen Token auszugeben.
public enum WatchdogPrompt {

    /// Obergrenze der Signale, die ans Modell gehen. Darüber kauft der Prompt keine Genauigkeit mehr,
    /// nur Laufzeit — also gewinnen die jüngsten Sessions: was wiederkehrt, kehrt auch dort wieder.
    public static let maxSignale = 160
    public static let maxBefunde = 12

    /// - Parameter bekannte: Was schon in der Liste steht. Das Modell formuliert denselben Befund
    ///   sonst bei jedem Lauf neu, und weil die Id aus dem **Titel** kommt, entsteht daraus ein
    ///   zweiter Eintrag — beobachtet an „iwf-CLI kennt Subcommand 'worktree' nicht" gegen
    ///   „iwf-CLI: Subkommando 'worktree' fehlt", zwei Einträge für dieselbe Sache, von denen einer
    ///   aussortiert war und der andere dadurch zurückkam.
    public static func bauen(digests: [WatchdogDigest], bekannte: [WatchdogFinding] = []) -> String {
        var prompt = """
        Du wertest Telemetrie aus den Claude-Code-Sessions eines Entwicklers aus und suchst \
        WIEDERKEHRENDE Probleme, die es wert sind, etwas zu ändern.

        Unten stehen automatisch vorgefilterte Signale: Stellen im Transcript, an denen ein Werkzeug \
        einen Fehler meldete, ein Build oder Test scheiterte, eine Freigabe verweigert wurde, \
        derselbe Werkzeugaufruf sich wiederholte, oder der Benutzer widersprochen hat.

        Melde zwei Sorten Befund:
        - "verhalten" — wie der Agent gearbeitet hat: ignorierte Vorgaben, immer gleiche falsche \
        Annahmen, Arbeit, die der Benutzer korrigieren oder zweimal verlangen musste.
        - "technik" — was die Werkzeuge sagen: Kommandos, Builds oder Tests, die immer wieder \
        scheitern, verweigerte Freigaben, Umgebungsprobleme.

        Regeln:
        - Nur Muster mit mindestens zwei unabhängigen Vorkommen. Einzelfälle überspringen.
        - Konkret sein. „Bearbeitet Dateien, ohne sie vorher zu lesen" ist brauchbar, \
        „macht Fehler" nicht.
        - `empfehlung` ist ein Schritt, den der Entwickler tun kann — eine Regel für CLAUDE.md, \
        ein Werkzeug, eine Konfiguration. Weglassen, wenn du keinen hast.
        - `zitat` wörtlich aus einem der Ausschnitte unten übernehmen.
        - Ein normaler, aufgefangener Fehler ist kein Befund.
        - Höchstens \(maxBefunde) Befunde, wichtigste zuerst.
        - Titel, Beschreibung und Empfehlung auf Deutsch.

        Antworte ausschliesslich mit JSON. Kein Fliesstext, keine Code-Zäune.
        {"befunde":[{"id":"nur bei einem bekannten Muster, sonst weglassen",\
        "titel":"kurzes Schlagwort","beschreibung":"was passiert und warum es zählt",\
        "kategorie":"verhalten|technik","schwere":"niedrig|mittel|hoch",\
        "empfehlung":"nächster Schritt oder null",\
        "belege":[{"sessionId":"...","zitat":"wörtlicher Ausschnitt"}]}]}

        Wenn nichts wiederkehrt, antworte genau: {"befunde":[]}

        """
        prompt += bekannteAbschnitt(bekannte)
        prompt += """

        === SIGNALE ===

        """

        // Jüngste Sessions zuerst, dann global abschneiden: ein gekappter Schwanz kostet am wenigsten,
        // weil die ältesten Signale am unwahrscheinlichsten noch wiederkehren.
        var budget = maxSignale
        for digest in digests.sorted(by: { $0.geaendert > $1.geaendert }) {
            guard budget > 0, !digest.signale.isEmpty else { continue }
            let genommen = Array(digest.signale.prefix(budget))
            budget -= genommen.count

            prompt += "\n## session \(digest.sessionId)"
            prompt += "\nprojekt: \(digest.projekt ?? "unbekannt")"
            if let titel = digest.titel, !titel.isEmpty {
                prompt += "\naufgabe: \(titel.prefix(160))"
            }
            for signal in genommen {
                let betreff = signal.betreff.map { " [\($0)]" } ?? ""
                prompt += "\n- (\(signal.art.rawValue))\(betreff) \(signal.ausschnitt)"
            }
            prompt += "\n"
        }

        return prompt
    }

    /// Der Abschnitt, der dem Modell die schon erfassten Muster nennt. Leer, solange es keine gibt.
    ///
    /// Zwei Anweisungen, weil zwei Dinge schiefgehen können: dieselbe Sache **neu benannt** (dann
    /// soll die Id wiederverwendet werden) und eine ausdrücklich **aussortierte** Sache erneut
    /// gemeldet (die gehört gar nicht mehr in die Antwort).
    static func bekannteAbschnitt(_ bekannte: [WatchdogFinding]) -> String {
        guard !bekannte.isEmpty else { return "" }
        var abschnitt = """

        === BEKANNTE BEFUNDE ===

        Diese Muster sind bereits erfasst. Beschreibt einer deiner Befunde dasselbe Muster wie einer \
        davon, gib **genau dessen `id`** im Feld `id` zurück, auch wenn du es anders formulieren \
        würdest — sonst entsteht ein zweiter Eintrag für dieselbe Sache.

        Was als `aussortiert` steht, hat der Entwickler ausdrücklich weggeworfen: melde es **nicht** \
        erneut, auch nicht unter anderem Namen. Hältst du es trotzdem für nötig, dann nur mit seiner \
        `id`.

        """
        for befund in bekannte {
            let zustand = befund.verworfen ? "aussortiert" : (befund.erledigt ? "erledigt" : "offen")
            abschnitt += "\n- \(befund.id) | \(zustand) | \(befund.titel)"
        }
        return abschnitt + "\n"
    }
}

/// Liest die JSON-Antwort des Modells in Befunde ein.
public enum WatchdogParser {

    public enum Fehler: Error, LocalizedError, Equatable {
        case keinJSON(String)

        public var errorDescription: String? {
            switch self {
            case .keinJSON(let roh):
                return "Antwort des Modells war kein lesbares JSON: \(roh.prefix(200))"
            }
        }
    }

    /// - Parameter sessionInfo: sessionId → (Titel, Projekt). Das Modell kennt nur die IDs; die
    ///   Belege bekommen ihre menschenlesbare Herkunft erst hier.
    /// - Parameter bekannteIds: Ids, die das Modell wiederverwenden darf. **Nur** diese werden
    ///   übernommen: eine erfundene Id würde zwei verschiedene Befunde zu einem verschmelzen, und
    ///   das ist schlimmer als ein doppelter Eintrag.
    public static func lies(_ text: String,
                           sessionInfo: [String: (titel: String?, projekt: String?)] = [:],
                           bekannteIds: Set<String> = [],
                           jetzt: Date = Date()) throws -> [WatchdogFinding] {
        guard let data = ClaudeHeadless.jsonObjekt(aus: text),
              let wurzel = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Fehler.keinJSON(text)
        }

        let roh = (wurzel["befunde"] as? [[String: Any]]) ?? (wurzel["findings"] as? [[String: Any]]) ?? []
        var befunde: [WatchdogFinding] = []
        var gesehen: Set<String> = []

        for eintrag in roh {
            guard let titel = (eintrag["titel"] as? String ?? eintrag["title"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !titel.isEmpty else { continue }

            let kategorie = WatchdogCategory(rawValue: (eintrag["kategorie"] as? String ?? "")) ?? .verhalten
            let schwere = (eintrag["schwere"] as? String).flatMap(WatchdogSeverity.init(modellwert:)) ?? .mittel
            // Das Modell benennt dasselbe Muster bei jedem Lauf etwas anders; die vom Prompt
            // angebotene Id hält den Eintrag zusammen. Unbekanntes fällt auf die Titel-Id zurück.
            let gemeldeteId = (eintrag["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = (gemeldeteId.map { bekannteIds.contains($0) } ?? false)
                ? gemeldeteId!
                : WatchdogFinding.stabileId(kategorie: kategorie, titel: titel)
            // Dasselbe Muster kommt gelegentlich zweimal leicht anders formuliert; die stabile Id
            // fasst das schon innerhalb einer Antwort zusammen.
            guard gesehen.insert(id).inserted else { continue }

            let belege: [WatchdogEvidence] = ((eintrag["belege"] as? [[String: Any]]) ?? []).compactMap { b in
                guard let zitat = (b["zitat"] as? String ?? b["quote"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !zitat.isEmpty else { return nil }
                let sessionId = (b["sessionId"] as? String) ?? ""
                let info = sessionInfo[sessionId]
                return WatchdogEvidence(
                    sessionId: sessionId, sessionTitel: info?.titel, projekt: info?.projekt,
                    zitat: String(zitat.prefix(WatchdogTranscriptScanner.ausschnittLimit)))
            }

            let empfehlung = (eintrag["empfehlung"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            befunde.append(WatchdogFinding(
                id: id, titel: titel,
                beschreibung: (eintrag["beschreibung"] as? String) ?? "",
                kategorie: kategorie, schwere: schwere,
                empfehlung: (empfehlung?.isEmpty ?? true) ? nil : empfehlung,
                // Ohne Belege zählt der Befund einmal — das Modell wurde angewiesen, nur zu melden,
                // was es mindestens zweimal gesehen hat.
                anzahl: max(belege.count, 1),
                belege: belege, zuerst: jetzt, zuletzt: jetzt))
        }

        return befunde
    }
}

/// Faltet einen frischen Scan in die gespeicherte Liste.
public enum WatchdogMerge {

    /// Höchstens so viele Belege je Befund — genug zum Glauben, begrenzt, damit ein langlebiger
    /// Befund die Datei nicht unbegrenzt wachsen lässt.
    public static let maxBelege = 8

    /// Die Regeln stehen an einer Stelle, weil sie der ganze Vertrag eines wiederholten Scans sind:
    /// ein bekanntes Muster sammelt an (Anzahl, Belege, zuletzt) und **bleibt erledigt oder
    /// verworfen** — einen bewusst abgehakten oder aussortierten Befund wieder aufzumachen ist der
    /// schnellste Weg, so ein Werkzeug unglaubwürdig zu machen. Beides hängt am Bestand, nicht am
    /// neuen Befund: was zurückkommt, trägt die Entscheidung des Benutzers weiter.
    public static func vereinen(bestand: [WatchdogFinding],
                                neu: [WatchdogFinding]) -> [WatchdogFinding] {
        var nachId = Dictionary(bestand.map { ($0.id, $0) }, uniquingKeysWith: { erster, _ in erster })
        var reihenfolge = bestand.map(\.id)

        for befund in neu {
            // Kennt der Bestand die Id nicht, kann es trotzdem derselbe Befund sein — nur neu
            // benannt. Dann entscheidet der **Beleg** (siehe `entschiedenerMitGleichemBeleg`).
            let id = nachId[befund.id] != nil
                ? befund.id
                : (entschiedenerMitGleichemBeleg(befund, in: bestand) ?? befund.id)
            guard var aktuell = nachId[id] else {
                nachId[id] = befund
                reihenfolge.append(id)
                continue
            }

            aktuell.titel = befund.titel
            aktuell.beschreibung = befund.beschreibung
            aktuell.schwere = max(aktuell.schwere, befund.schwere)
            aktuell.empfehlung = befund.empfehlung ?? aktuell.empfehlung
            aktuell.anzahl += befund.anzahl
            aktuell.zuletzt = befund.zuletzt
            // `erledigt` und `verworfen` werden bewusst NICHT zurückgesetzt.

            var belege = aktuell.belege
            for beleg in befund.belege where !belege.contains(beleg) { belege.append(beleg) }
            aktuell.belege = Array(belege.suffix(maxBelege))

            nachId[id] = aktuell
        }

        return reihenfolge.compactMap { nachId[$0] }
    }

    /// Die Id eines bereits **entschiedenen** Befunds (erledigt oder aussortiert), der dasselbe
    /// wörtliche Zitat trägt — sonst nil.
    ///
    /// Das ist die Notbremse gegen den Fall, um den es hier eigentlich geht: die Id kommt aus dem
    /// **Titel**, und den formuliert das Modell bei jedem Lauf neu. Ein aussortierter Befund kam so
    /// unter neuem Namen zurück. In den echten Daten dieser Maschine standen vier solche Paare, und
    /// alle vier **teilen ihre Belege** — ein wörtlicher Transcript-Ausschnitt benennt denselben
    /// Vorfall, ein umformulierter Titel nicht.
    ///
    /// Bewusst nur für entschiedene Befunde und nur bei **gleicher Kategorie**: ein Zusammenlegen
    /// unterdrückt etwas, und das darf nur passieren, wo der Mensch schon entschieden hat. Ein
    /// offener Befund bleibt offen, auch wenn er denselben Beleg zitiert — dort ist ein zweiter
    /// Eintrag lästig, aber ein falsch verschluckter wäre schlimmer.
    static func entschiedenerMitGleichemBeleg(_ befund: WatchdogFinding,
                                              in bestand: [WatchdogFinding]) -> String? {
        let zitate = Set(befund.belege.map { belegSchluessel($0.zitat) })
        guard !zitate.isEmpty else { return nil }
        return bestand.first { alt in
            (alt.erledigt || alt.verworfen)
                && alt.kategorie == befund.kategorie
                && alt.belege.contains { zitate.contains(belegSchluessel($0.zitat)) }
        }?.id
    }

    /// Zitate werden wörtlich verglichen, nur der Weissraum wird vereinheitlicht — dasselbe Zitat
    /// kommt aus zwei Läufen gelegentlich mit anderem Zeilenumbruch zurück.
    static func belegSchluessel(_ zitat: String) -> String {
        zitat.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Anzeigereihenfolge: offen vor erledigt, dann Schwere, dann Häufigkeit, dann Aktualität.
    public static func sortiert(_ befunde: [WatchdogFinding]) -> [WatchdogFinding] {
        befunde.sorted { a, b in
            if a.erledigt != b.erledigt { return !a.erledigt }
            if a.schwere != b.schwere { return a.schwere > b.schwere }
            if a.anzahl != b.anzahl { return a.anzahl > b.anzahl }
            return a.zuletzt > b.zuletzt
        }
    }
}
