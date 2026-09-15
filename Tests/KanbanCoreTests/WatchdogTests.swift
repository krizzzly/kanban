import XCTest
@testable import KanbanCore

/// Baut eine Transcript-Zeile in der Form, die Claude Code wirklich schreibt.
private func zeile(_ objekt: [String: Any]) -> String {
    var mit = objekt
    mit["timestamp"] = mit["timestamp"] ?? "2026-09-15T10:00:00.000Z"
    let data = try! JSONSerialization.data(withJSONObject: mit)
    return String(decoding: data, as: UTF8.self)
}

private func benutzerText(_ text: String, cwd: String = "/Users/x/code/even") -> String {
    zeile(["type": "user", "cwd": cwd, "message": ["role": "user", "content": text]])
}

private func werkzeugErgebnis(_ inhalt: String, fehler: Bool = false) -> String {
    zeile(["type": "user", "message": ["role": "user", "content": [
        ["type": "tool_result", "content": inhalt, "is_error": fehler],
    ]]])
}

private func werkzeugAufruf(_ name: String, _ eingabe: [String: Any]) -> String {
    zeile(["type": "assistant", "message": ["role": "assistant", "content": [
        ["type": "tool_use", "name": name, "input": eingabe],
    ]]])
}

final class WatchdogScannerTests: XCTestCase {

    func testWiderspruchWirdErkannt() {
        let signale = WatchdogTranscriptScanner.scan(
            lines: [benutzerText("Nein, das war nicht gemeint — bitte zurück auf den alten Stand")],
            sessionId: "s1")
        XCTAssertEqual(signale.count, 1)
        XCTAssertEqual(signale.first?.art, .korrektur)
        XCTAssertTrue(signale.first?.art.istVerhalten ?? false)
    }

    func testLangeNachrichtIstKeinWiderspruch() {
        let lang = "Nein, " + String(repeating: "und weitere Details zur Aufgabe. ", count: 40)
        XCTAssertTrue(WatchdogTranscriptScanner.scan(lines: [benutzerText(lang)], sessionId: "s1").isEmpty)
    }

    func testEigeneEinschuebeZaehlenNicht() {
        // `<task-notification>` schreibt Claude Code selbst — das hat nie jemand getippt.
        let einschub = benutzerText("<task-notification>nein, das ist falsch</task-notification>")
        XCTAssertTrue(WatchdogTranscriptScanner.scan(lines: [einschub], sessionId: "s1").isEmpty)
    }

    func testSubagentVerkehrWirdUebersprungen() {
        let sidechain = zeile(["type": "user", "isSidechain": true,
                               "message": ["role": "user", "content": "nein, falsch"]])
        XCTAssertTrue(WatchdogTranscriptScanner.scan(lines: [sidechain], sessionId: "s1").isEmpty)
    }

    func testWerkzeugErgebnisseNachSpezifitaetEingeordnet() {
        let signale = WatchdogTranscriptScanner.scan(lines: [
            werkzeugErgebnis("The user doesn't want to proceed with this tool use", fehler: true),
            werkzeugErgebnis("npm ERR! Tests failed", fehler: true),
            werkzeugErgebnis("etwas ging schief", fehler: true),
            werkzeugErgebnis("alles gut, 42 Dateien geändert"),
        ], sessionId: "s1")
        XCTAssertEqual(signale.map(\.art), [.freigabeVerweigert, .buildOderTest, .werkzeugFehler])
    }

    func testIsErrorAlleinReichtFuerEinSignal() {
        // Kein Stichwort im Text — `is_error` ist die einzige Aussage, und sie ist nicht geraten.
        let signale = WatchdogTranscriptScanner.scan(
            lines: [werkzeugErgebnis("¯\\_(ツ)_/¯", fehler: true)], sessionId: "s1")
        XCTAssertEqual(signale.map(\.art), [.werkzeugFehler])
    }

    func testDreiGleicheAufrufeGebenGenauEinSignal() {
        let zeilen = (0..<5).map { _ in werkzeugAufruf("Bash", ["command": "swift build"]) }
        let wiederholungen = WatchdogTranscriptScanner.scan(lines: zeilen, sessionId: "s1")
            .filter { $0.art == .wiederholung }
        XCTAssertEqual(wiederholungen.count, 1)
        XCTAssertEqual(wiederholungen.first?.betreff, "Bash")
    }

    func testVerschiedeneEingabeIstKeineWiederholung() {
        let zeilen = ["ls", "pwd", "date"].map { werkzeugAufruf("Bash", ["command": $0]) }
        XCTAssertTrue(WatchdogTranscriptScanner.scan(lines: zeilen, sessionId: "s1").isEmpty)
    }

    func testProjektUndErsterPromptWerdenMitgelesen() {
        var scanner = WatchdogTranscriptScanner(sessionId: "s1")
        scanner.consume(line: benutzerText("<local-command-caveat>ignorier mich</local-command-caveat>"))
        scanner.consume(line: benutzerText("Bitte die Suche reparieren"))
        XCTAssertEqual(scanner.projekt, "even")
        XCTAssertEqual(scanner.ersterPrompt, "Bitte die Suche reparieren")
    }

    func testAusschnitteWerdenGekuerztUndEinzeilig() {
        let laut = "error: " + String(repeating: "x", count: 900) + "\nzweite Zeile"
        let signale = WatchdogTranscriptScanner.scan(lines: [werkzeugErgebnis(laut)], sessionId: "s1")
        XCTAssertEqual(signale.count, 1)
        XCTAssertFalse(signale[0].ausschnitt.contains("\n"))
        XCTAssertLessThanOrEqual(signale[0].ausschnitt.count,
                                 WatchdogTranscriptScanner.ausschnittLimit + 1)
    }
}

final class WatchdogFindingTests: XCTestCase {

    func testZeichensetzungFaelltFuerDieIdWeg() {
        XCTAssertEqual(
            WatchdogFinding.stabileId(kategorie: .verhalten, titel: "Bearbeitet Dateien ungelesen"),
            WatchdogFinding.stabileId(kategorie: .verhalten, titel: "Bearbeitet Dateien, ungelesen!"))
    }

    func testKategorieGehoertZurIdentitaet() {
        XCTAssertNotEqual(
            WatchdogFinding.stabileId(kategorie: .verhalten, titel: "Build kaputt"),
            WatchdogFinding.stabileId(kategorie: .technik, titel: "Build kaputt"))
    }

    func testRegelZeileNimmtDieEmpfehlung() {
        let befund = WatchdogFinding(id: "x", titel: "Tests überspringen", beschreibung: "…",
                                     kategorie: .verhalten, schwere: .hoch,
                                     empfehlung: "Nach jeder Änderung swift test laufen lassen")
        XCTAssertEqual(befund.alsRegel,
                       "- **Tests überspringen** — Nach jeder Änderung swift test laufen lassen")
    }
}

final class WatchdogParsingTests: XCTestCase {

    func testHuelleLiefertDasErgebnisFeld() throws {
        let stdout = """
        [{"type":"system","subtype":"init"},\
        {"type":"result","subtype":"success","is_error":false,"result":"{\\"befunde\\":[]}",\
        "duration_ms":1910,"total_cost_usd":0.0027}]
        """
        let antwort = try ClaudeHeadless.leseHuelle(stdout)
        XCTAssertEqual(antwort.text, "{\"befunde\":[]}")
        XCTAssertEqual(antwort.dauerMs, 1910)
        XCTAssertEqual(antwort.kostenUSD, 0.0027)
    }

    func testFehlerHuelleWirftStattLeererListe() {
        let stdout = #"[{"type":"result","subtype":"error_max_turns","is_error":true,"result":"limit"}]"#
        XCTAssertThrowsError(try ClaudeHeadless.leseHuelle(stdout))
    }

    func testCodeZaeuneWerdenEntfernt() {
        let data = ClaudeHeadless.jsonObjekt(aus: "```json\n{\"befunde\":[]}\n```")
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "{\"befunde\":[]}")
    }

    func testBefundeBekommenHerkunftAusDenSessionDaten() throws {
        let json = """
        {"befunde":[
          {"titel":"Tests werden übersprungen","beschreibung":"…","kategorie":"verhalten",
           "schwere":"hoch","empfehlung":"Regel ergänzen",
           "belege":[{"sessionId":"s1","zitat":"du hast die Tests nicht laufen lassen"}]},
          {"titel":"Tests, werden übersprungen!","beschreibung":"Dublette","kategorie":"verhalten",
           "schwere":"niedrig"}
        ]}
        """
        let befunde = try WatchdogParser.lies(
            json, sessionInfo: ["s1": (titel: "Suche reparieren", projekt: "even")])
        // Der zweite Eintrag ist dasselbe Muster anders formuliert — einer bleibt übrig.
        XCTAssertEqual(befunde.count, 1)
        XCTAssertEqual(befunde[0].schwere, .hoch)
        XCTAssertEqual(befunde[0].belege.first?.projekt, "even")
        XCTAssertEqual(befunde[0].belege.first?.sessionTitel, "Suche reparieren")
    }

    func testEnglischeSchwereWirdUebersetzt() throws {
        let befunde = try WatchdogParser.lies(
            #"{"befunde":[{"titel":"X","kategorie":"technik","schwere":"high"}]}"#)
        XCTAssertEqual(befunde.first?.schwere, .hoch)
    }

    /// Die Id aus dem Prompt wird übernommen — das ist der Weg, auf dem ein neu formulierter
    /// Befund derselbe Eintrag bleibt.
    func testBekannteIdWirdUebernommen() throws {
        let json = "{\"befunde\":[{\"id\":\"technik:alt-und-bekannt\","
            + "\"titel\":\"Ganz neu benannt\",\"kategorie\":\"technik\",\"schwere\":\"hoch\"}]}"
        let befunde = try WatchdogParser.lies(json, bekannteIds: ["technik:alt-und-bekannt"])
        XCTAssertEqual(befunde.first?.id, "technik:alt-und-bekannt")
        XCTAssertEqual(befunde.first?.titel, "Ganz neu benannt")
    }

    func testUnbekannteIdWirdVerworfen() throws {
        let befunde = try WatchdogParser.lies(
            #"{"befunde":[{"id":"frei:erfunden","titel":"Titel","kategorie":"technik"}]}"#,
            bekannteIds: ["technik:etwas-anderes"])
        XCTAssertEqual(befunde.first?.id,
                       WatchdogFinding.stabileId(kategorie: .technik, titel: "Titel"))
    }

    func testOhneIdGiltWeiterDieTitelId() throws {
        let befunde = try WatchdogParser.lies(
            #"{"befunde":[{"titel":"Titel","kategorie":"technik"}]}"#)
        XCTAssertEqual(befunde.first?.id,
                       WatchdogFinding.stabileId(kategorie: .technik, titel: "Titel"))
    }

    func testUnlesbaresWirftStattStillZuLeeren() {
        XCTAssertThrowsError(try WatchdogParser.lies("Das konnte ich nicht auswerten."))
    }
}

final class WatchdogMergeTests: XCTestCase {

    private func befund(_ titel: String, schwere: WatchdogSeverity = .niedrig, anzahl: Int = 1,
                        belege: [WatchdogEvidence] = [], erledigt: Bool = false,
                        verworfen: Bool = false) -> WatchdogFinding {
        WatchdogFinding(id: WatchdogFinding.stabileId(kategorie: .verhalten, titel: titel),
                        titel: titel, beschreibung: "", kategorie: .verhalten, schwere: schwere,
                        anzahl: anzahl, belege: belege, erledigt: erledigt, verworfen: verworfen)
    }

    func testWiedergesehenesMusterSammeltAnStattSichZuVerdoppeln() {
        let vereint = WatchdogMerge.vereinen(
            bestand: [befund("Tests überspringen", anzahl: 2)],
            neu: [befund("Tests überspringen", schwere: .hoch, anzahl: 3)])
        XCTAssertEqual(vereint.count, 1)
        XCTAssertEqual(vereint[0].anzahl, 5)
        XCTAssertEqual(vereint[0].schwere, .hoch)
    }

    func testErledigtBleibtErledigt() {
        let vereint = WatchdogMerge.vereinen(
            bestand: [befund("Tests überspringen", erledigt: true)],
            neu: [befund("Tests überspringen")])
        XCTAssertTrue(vereint[0].erledigt)
    }

    /// Der Kern des Papierkorbs: die Id ist stabil, also findet der nächste Scan dasselbe Muster
    /// wieder — es darf dadurch nicht zurück in die Liste rutschen.
    func testVerworfenBleibtVerworfen() {
        let vereint = WatchdogMerge.vereinen(
            bestand: [befund("Zu viele Subagenten", verworfen: true)],
            neu: [befund("Zu viele Subagenten", schwere: .hoch)])
        XCTAssertEqual(vereint.count, 1)
        XCTAssertTrue(vereint[0].verworfen)
    }

    /// Es bleibt aber ein Befund: Anzahl und Belege laufen weiter, damit im Papierkorb steht, wie
    /// oft das aussortierte Muster seither noch auftrat.
    func testVerworfenesZaehltWeiter() {
        let vereint = WatchdogMerge.vereinen(
            bestand: [befund("Zu viele Subagenten", anzahl: 2, verworfen: true)],
            neu: [befund("Zu viele Subagenten", anzahl: 3)])
        XCTAssertEqual(vereint[0].anzahl, 5)
    }

    // MARK: - Dasselbe Muster, neu benannt

    private func mitBeleg(_ titel: String, zitat: String, kategorie: WatchdogCategory = .verhalten,
                          erledigt: Bool = false, verworfen: Bool = false) -> WatchdogFinding {
        WatchdogFinding(id: WatchdogFinding.stabileId(kategorie: kategorie, titel: titel),
                        titel: titel, beschreibung: "", kategorie: kategorie, schwere: .mittel,
                        belege: [WatchdogEvidence(sessionId: "s1", zitat: zitat)],
                        erledigt: erledigt, verworfen: verworfen)
    }

    /// Der gemeldete Fall: das Modell formuliert den Titel neu, die Id kommt aus dem Titel — und
    /// ein aussortierter Befund stand als neuer wieder da. An den echten Daten dieser Maschine
    /// waren das vier Paare, alle mit gemeinsamem Beleg.
    func testAussortiertesKommtUnterNeuemNamenNichtZurueck() {
        let zitat = "iwf: No such command 'worktree'"
        let vereint = WatchdogMerge.vereinen(
            bestand: [mitBeleg("iwf-CLI: Subkommando 'worktree' fehlt", zitat: zitat,
                               kategorie: .technik, verworfen: true)],
            neu: [mitBeleg("iwf-CLI kennt Subcommand 'worktree' nicht", zitat: zitat,
                           kategorie: .technik)])
        XCTAssertEqual(vereint.count, 1, "kein zweiter Eintrag für dieselbe Sache")
        XCTAssertTrue(vereint[0].verworfen)
    }

    func testErledigtesEbenso() {
        let zitat = "PHPUnit: DataProvider signature mismatch"
        let vereint = WatchdogMerge.vereinen(
            bestand: [mitBeleg("Tests scheitern am DataProvider", zitat: zitat, erledigt: true)],
            neu: [mitBeleg("DataProvider-Signatur passt nicht", zitat: zitat)])
        XCTAssertEqual(vereint.count, 1)
        XCTAssertTrue(vereint[0].erledigt)
    }

    /// Nur bei gleicher Kategorie: ein Verhaltensmuster darf nicht in einem aussortierten
    /// technischen Befund verschwinden, bloss weil derselbe Ausschnitt beides belegt.
    func testAndereKategorieWirdNichtVerschluckt() {
        let zitat = "Error: permission denied"
        let vereint = WatchdogMerge.vereinen(
            bestand: [mitBeleg("Freigabe fehlt", zitat: zitat, kategorie: .technik, verworfen: true)],
            neu: [mitBeleg("Agent versucht es trotz Ablehnung erneut", zitat: zitat,
                           kategorie: .verhalten)])
        XCTAssertEqual(vereint.count, 2)
        XCTAssertFalse(vereint.first { !$0.verworfen }!.verworfen)
    }

    /// Ein **offener** Befund legt nichts zusammen. Dort ist ein doppelter Eintrag lästig, ein
    /// stillschweigend verschluckter wäre schlimmer — zusammengelegt wird nur, wo der Mensch schon
    /// entschieden hat.
    func testOffenerBefundLegtNichtsZusammen() {
        let zitat = "npm ERR! missing script: build"
        let vereint = WatchdogMerge.vereinen(
            bestand: [mitBeleg("Build-Skript fehlt", zitat: zitat)],
            neu: [mitBeleg("npm build nicht vorhanden", zitat: zitat)])
        XCTAssertEqual(vereint.count, 2)
    }

    func testOhneGemeinsamesZitatBleibtEsEinNeuerBefund() {
        let vereint = WatchdogMerge.vereinen(
            bestand: [mitBeleg("Alt", zitat: "ein Zitat", verworfen: true)],
            neu: [mitBeleg("Neu", zitat: "ganz anderes Zitat")])
        XCTAssertEqual(vereint.count, 2)
    }

    func testBefundOhneBelegeLegtNichtsZusammen() {
        let ohne = WatchdogFinding(id: "verhalten:neu", titel: "Neu", beschreibung: "",
                                   kategorie: .verhalten, schwere: .mittel, belege: [])
        let vereint = WatchdogMerge.vereinen(
            bestand: [mitBeleg("Alt", zitat: "ein Zitat", verworfen: true)], neu: [ohne])
        XCTAssertEqual(vereint.count, 2)
    }

    /// Dasselbe Zitat kommt aus zwei Läufen gelegentlich mit anderem Umbruch zurück.
    func testWeissraumImZitatStoertNicht() {
        let vereint = WatchdogMerge.vereinen(
            bestand: [mitBeleg("Alt", zitat: "mv: rename failed\n  no such file", verworfen: true)],
            neu: [mitBeleg("Neu", zitat: "mv: rename failed no such file")])
        XCTAssertEqual(vereint.count, 1)
        XCTAssertTrue(vereint[0].verworfen)
    }

    func testZurueckgeholtesIstWiederOffen() {
        var b = befund("Zu viele Subagenten", verworfen: true)
        b.verworfen = false
        let vereint = WatchdogMerge.vereinen(bestand: [b], neu: [befund("Zu viele Subagenten")])
        XCTAssertFalse(vereint[0].verworfen)
        XCTAssertFalse(vereint[0].erledigt)
    }

    func testBelegeWerdenEntdoppeltUndGedeckelt() {
        let bestand = befund("X", belege: (0..<8).map {
            WatchdogEvidence(sessionId: "s\($0)", zitat: "z\($0)")
        })
        let neu = befund("X", belege: [
            WatchdogEvidence(sessionId: "s0", zitat: "z0"),
            WatchdogEvidence(sessionId: "s9", zitat: "z9"),
        ])
        let vereint = WatchdogMerge.vereinen(bestand: [bestand], neu: [neu])
        XCTAssertEqual(vereint[0].belege.count, WatchdogMerge.maxBelege)
        XCTAssertEqual(vereint[0].belege.last?.sessionId, "s9")
    }

    func testSortierungOffenVorErledigtDannSchwere() {
        let sortiert = WatchdogMerge.sortiert([
            befund("a", schwere: .hoch, erledigt: true),
            befund("b", schwere: .niedrig, anzahl: 9),
            befund("c", schwere: .hoch, anzahl: 1),
        ])
        XCTAssertEqual(sortiert.map(\.titel), ["c", "b", "a"])
    }
}

final class WatchdogPromptTests: XCTestCase {

    private func digest(_ id: String, _ anzahl: Int, _ datum: Date) -> WatchdogDigest {
        WatchdogDigest(sessionId: id, titel: nil, projekt: "even", geaendert: datum,
                       signale: (0..<anzahl).map {
                           WatchdogSignal(art: .werkzeugFehler, sessionId: id, ausschnitt: "e\($0)")
                       })
    }

    func testSignalbudgetGedeckeltUndJuengsteGewinnen() {
        let prompt = WatchdogPrompt.bauen(digests: [
            digest("alt", 200, Date(timeIntervalSince1970: 0)),
            digest("neu", 10, Date(timeIntervalSince1970: 10_000)),
        ])
        // Die jüngere Session muss vorkommen, obwohl die ältere allein das Budget füllen würde.
        XCTAssertTrue(prompt.contains("session neu"))
        XCTAssertEqual(prompt.components(separatedBy: "\n- (").count - 1, WatchdogPrompt.maxSignale)
    }

    /// Ohne den Bestand im Prompt benennt das Modell dasselbe Muster jedes Mal neu — und aus der
    /// Titel-Id wird ein zweiter Eintrag.
    func testBekannteBefundeStehenImPrompt() {
        let bekannte = [
            WatchdogFinding(id: "technik:a", titel: "Alpha", beschreibung: "", kategorie: .technik,
                            schwere: .mittel, verworfen: true),
            WatchdogFinding(id: "verhalten:b", titel: "Beta", beschreibung: "",
                            kategorie: .verhalten, schwere: .mittel, erledigt: true),
            WatchdogFinding(id: "verhalten:c", titel: "Gamma", beschreibung: "",
                            kategorie: .verhalten, schwere: .mittel),
        ]
        let prompt = WatchdogPrompt.bauen(digests: [], bekannte: bekannte)
        XCTAssertTrue(prompt.contains("technik:a | aussortiert | Alpha"), prompt)
        XCTAssertTrue(prompt.contains("verhalten:b | erledigt | Beta"))
        XCTAssertTrue(prompt.contains("verhalten:c | offen | Gamma"))
        XCTAssertTrue(prompt.contains("BEKANNTE BEFUNDE"))
    }

    func testOhneBestandKeinAbschnitt() {
        XCTAssertFalse(WatchdogPrompt.bauen(digests: []).contains("BEKANNTE BEFUNDE"))
    }

    func testLeereEingabeErgibtTrotzdemGueltigenPrompt() {
        let prompt = WatchdogPrompt.bauen(digests: [])
        XCTAssertTrue(prompt.contains("=== SIGNALE ==="))
        XCTAssertTrue(prompt.contains(#"{"befunde":[]}"#))
    }
}

final class WatchdogConfigTests: XCTestCase {

    func testVorgabenOhneAbschnitt() throws {
        let config = try KanbanConfig.resolve(Data("{}".utf8), docsRoot: "/tmp/docs")
        XCTAssertFalse(config.watchdog.aktiv)
        XCTAssertEqual(config.watchdog.intervallMinuten, 60)
        XCTAssertEqual(config.watchdog.modell, WatchdogSettings.modellVorgabe)
    }

    func testWerteWerdenGelesenUndBegrenzt() throws {
        let json = """
        {"watchdog":{"enabled":true,"intervalMinutes":"15","lookbackHours":"9999",
         "maxSessions":"0","minSignals":"nonsense","model":"claude-haiku-4-5-20251001"}}
        """
        let config = try KanbanConfig.resolve(Data(json.utf8), docsRoot: "/tmp/docs")
        XCTAssertTrue(config.watchdog.aktiv)
        XCTAssertEqual(config.watchdog.intervallMinuten, 15)
        XCTAssertEqual(config.watchdog.rueckblickStunden, 720)  // auf das Maximum begrenzt
        XCTAssertEqual(config.watchdog.maxSessions, 1)          // auf das Minimum angehoben
        XCTAssertEqual(config.watchdog.minSignale, 4)           // unlesbar → Vorgabe
        XCTAssertEqual(config.watchdog.modell, "claude-haiku-4-5-20251001")
    }
}

final class WatchdogStoreTests: XCTestCase {

    func testSpeichernUndLadenUeberlebtDenUmweg() throws {
        let pfad = NSTemporaryDirectory() + "watchdog-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: pfad) }
        let store = WatchdogStore(path: pfad)

        var state = WatchdogState()
        state.befunde = [WatchdogFinding(id: "a", titel: "T", beschreibung: "B",
                                         kategorie: .technik, schwere: .mittel, erledigt: true)]
        state.cursors = ["s1": WatchdogCursor(geaendert: Date(timeIntervalSince1970: 100), signale: 3)]
        try store.speichern(state)

        let geladen = store.laden()
        XCTAssertEqual(geladen.befunde.count, 1)
        XCTAssertTrue(geladen.befunde[0].erledigt)
        XCTAssertEqual(geladen.cursors["s1"]?.signale, 3)
    }

    func testVerworfenUeberlebtDenUmweg() throws {
        let pfad = NSTemporaryDirectory() + "watchdog-trash-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: pfad) }
        let store = WatchdogStore(path: pfad)

        var state = WatchdogState()
        state.befunde = [WatchdogFinding(id: "a", titel: "T", beschreibung: "", kategorie: .technik,
                                         schwere: .mittel, verworfen: true)]
        try store.speichern(state)
        XCTAssertTrue(store.laden().befunde[0].verworfen)
    }

    /// Eine Datei aus der Zeit vor dem Papierkorb kennt das Feld nicht — dort ist nichts verworfen,
    /// und die Liste darf davon nicht leer werden.
    func testAlteDateiOhneFeldIstNichtVerworfen() throws {
        let pfad = NSTemporaryDirectory() + "watchdog-alt-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: pfad) }
        let alt = """
        {"befunde":[{"id":"a","titel":"T","beschreibung":"","kategorie":"technik",\
        "schwere":"mittel","anzahl":1,"belege":[],"zuerst":"2026-09-01T10:00:00Z",\
        "zuletzt":"2026-09-01T10:00:00Z","erledigt":false}],"cursors":{}}
        """
        try alt.write(toFile: pfad, atomically: true, encoding: .utf8)
        let geladen = WatchdogStore(path: pfad).laden()
        XCTAssertEqual(geladen.befunde.count, 1)
        XCTAssertFalse(geladen.befunde[0].verworfen)
    }

    func testKaputteDateiFaelltAufLeerenStandZurueck() throws {
        let pfad = NSTemporaryDirectory() + "watchdog-broken-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: pfad) }
        try "{ kein json".write(toFile: pfad, atomically: true, encoding: .utf8)
        XCTAssertTrue(WatchdogStore(path: pfad).laden().befunde.isEmpty)
    }
}
