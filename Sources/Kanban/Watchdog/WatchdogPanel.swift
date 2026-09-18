import AppKit
import SwiftUI
import KanbanCore

/// Was hinter dem Knopf rechts in der Leiste steht: die Liste dessen, was in den Sessions immer
/// wieder schiefgeht.
struct WatchdogPanel: View {
    @Bindable var watchdog: WatchdogModel

    @State private var filter: Filter = .offen
    @State private var aufgeklappt: Set<String> = []

    enum Filter: String, CaseIterable, Identifiable {
        case offen = "Offen"
        case verhalten = "Verhalten"
        case technik = "Technik"
        case erledigt = "Erledigt"
        case papierkorb = "Papierkorb"

        var id: String { rawValue }

        /// Der Papierkorb trägt sein Symbol statt seines Namens: fünf ausgeschriebene Segmente
        /// passen nicht in die Panelbreite, und ein Papierkorb ist als Bild eindeutig.
        var symbol: String? { self == .papierkorb ? "trash" : nil }
    }

    private var sichtbare: [WatchdogFinding] {
        switch filter {
        case .offen: return watchdog.offene
        case .verhalten: return watchdog.offene.filter { $0.kategorie == .verhalten }
        case .technik: return watchdog.offene.filter { $0.kategorie == .technik }
        case .erledigt: return watchdog.erledigte
        case .papierkorb: return watchdog.verworfene
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kopf
            Divider()

            if let hinweis = sperrHinweis {
                leer(hinweis)
            } else if sichtbare.isEmpty {
                leer(leerText)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sichtbare) { befund in
                            WatchdogZeile(
                                befund: befund,
                                istNeu: watchdog.neueIds.contains(befund.id),
                                offen: aufgeklappt.contains(befund.id),
                                umschalten: { umschalten(befund.id) },
                                setzeErledigt: { erledigt in
                                    Task { await watchdog.setzeErledigt(erledigt, id: befund.id) }
                                },
                                setzeVerworfen: { verworfen in
                                    Task { await watchdog.setzeVerworfen(verworfen, id: befund.id) }
                                })
                            Divider()
                        }
                    }
                }
            }

            Divider()
            fuss
        }
        .frame(width: 460, height: 560)
        .onAppear { watchdog.alsGesehenMarkieren() }
    }

    // MARK: - Kopf / Fuss

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Session-Watchdog", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                // Ein Lauf dauert hier gemessen 5–6 Minuten. Ein Spinner, der nur dreht, sieht
                // dabei aus wie „hängt" — also steht daneben, seit wann, und ein ✕ beendet ihn.
                if watchdog.laeuft {
                    laufAnzeige
                } else {
                    Button {
                        Task { await watchdog.jetztScannen() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Sessions jetzt scannen — dauert einige Minuten")
                }
            }

            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { wahl in
                    if let symbol = wahl.symbol {
                        Image(systemName: symbol).tag(wahl).help(wahl.rawValue)
                    } else {
                        Text(wahl.rawValue).tag(wahl)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(12)
    }

    /// Läuft gerade: Spinner, verstrichene Zeit, Abbruch.
    private var laufAnzeige: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(dauer(seit: watchdog.laeuftSeit, bis: context.date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                watchdog.abbrechen()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Laufenden Scan abbrechen")
        }
        .help("Scan läuft — ein voller Lauf braucht einige Minuten")
    }

    private func dauer(seit: Date?, bis: Date) -> String {
        guard let seit else { return "…" }
        let sekunden = max(Int(bis.timeIntervalSince(seit)), 0)
        return String(format: "%d:%02d", sekunden / 60, sekunden % 60)
    }

    private var fuss: some View {
        HStack(spacing: 8) {
            Text(statusZeile)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if !watchdog.befunde.isEmpty {
                Menu {
                    if !watchdog.verworfene.isEmpty {
                        // Endgültig: danach darf derselbe Befund wiederkommen — er war ja nur
                        // deshalb draussen, weil er im Papierkorb stand.
                        Button("Papierkorb leeren (\(watchdog.verworfene.count))") {
                            Task { await watchdog.papierkorbLeeren() }
                        }
                        Divider()
                    }
                    Button("Liste leeren") { Task { await watchdog.leeren() } }
                    Button("Zurücksetzen und neu scannen") {
                        Task {
                            await watchdog.zuruecksetzen()
                            await watchdog.jetztScannen()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusZeile: String {
        if let fehler = watchdog.letzterFehler { return "Letzter Lauf gescheitert: \(fehler)" }
        if watchdog.laeuft { return "Scan läuft — Sessions werden ausgewertet." }
        guard let letzter = watchdog.letzterScan else { return "Noch kein Lauf." }
        var zeile = "Gescannt \(letzter.formatted(date: .omitted, time: .shortened))"
        if let sessions = watchdog.sessionsGescannt {
            zeile += " · \(sessions) Session\(sessions == 1 ? "" : "s")"
        }
        if let kosten = watchdog.letzteKostenUSD, kosten > 0 {
            zeile += String(format: " · $%.3f", kosten)
        }
        return zeile
    }

    /// Zustände, in denen die Liste nichts bedeutet. Ohne diesen Hinweis läse sich „nichts
    /// gefunden" wie ein Freispruch, obwohl gar nichts geprüft wurde.
    private var sperrHinweis: String? {
        if !watchdog.cliVerfuegbar {
            return "Die `claude`-CLI wurde nicht gefunden. Ohne sie kann der Watchdog nicht auswerten."
        }
        if watchdog.letzterScan == nil && watchdog.befunde.isEmpty {
            return "Noch kein Lauf. ↻ scannt die Sessions der letzten Tage — das dauert etwa eine "
                 + "Minute und kostet ein paar Cent.\n\nDauerhaft im Hintergrund: Einstellungen › Watchdog."
        }
        return nil
    }

    private var leerText: String {
        switch filter {
        case .erledigt: return "Nichts erledigt."
        case .verhalten: return "Keine wiederkehrenden Verhaltensmuster."
        case .technik: return "Keine wiederkehrenden technischen Probleme."
        case .offen: return "Nichts Wiederkehrendes in den gescannten Sessions."
        case .papierkorb: return "Papierkorb ist leer. Was du aussortierst, landet hier — und kommt "
                               + "beim nächsten Scan nicht wieder."
        }
    }

    private func leer(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func umschalten(_ id: String) {
        if aufgeklappt.contains(id) { aufgeklappt.remove(id) } else { aufgeklappt.insert(id) }
    }
}

/// Ein Befund: zugeklappt eine überfliegbare Zeile, aufgeklappt die Begründung, der Vorschlag und
/// die Transcript-Ausschnitte, die die Behauptung belegen.
private struct WatchdogZeile: View {
    let befund: WatchdogFinding
    let istNeu: Bool
    let offen: Bool
    let umschalten: () -> Void
    let setzeErledigt: (Bool) -> Void
    let setzeVerworfen: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Aufklappen und Aussortieren sind **zwei** Knöpfe nebeneinander, nicht einer
            // ineinander: die Liste sortiert man im Überfliegen aus, ohne jeden Eintrag vorher
            // aufzuklappen — und ein Papierkorb, der beim Lesen mitgeklickt wird, wäre eine Falle.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(action: umschalten) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(farbe)
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(befund.titel)
                                    .font(.callout.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                if istNeu {
                                    Text("NEU")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                                }
                            }

                            HStack(spacing: 6) {
                                Label(befund.kategorie.label, systemImage: befund.kategorie.icon)
                                Text("·")
                                Text("\(befund.anzahl)×")
                                if let projekt = befund.belege.first?.projekt {
                                    Text("·")
                                    Text(projekt)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: offen ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                papierkorbKnopf
            }

            if offen { rumpf }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(befund.erledigt || befund.verworfen ? 0.55 : 1)
        // Derselbe Griff per Rechtsklick, wie ihn das Board an seinen Karten hat.
        .contextMenu {
            if befund.verworfen {
                Button("Zurückholen") { setzeVerworfen(false) }
            } else {
                Button(befund.erledigt ? "Wieder öffnen" : "Erledigt") { setzeErledigt(!befund.erledigt) }
                Button("Aussortieren", role: .destructive) { setzeVerworfen(true) }
            }
        }
    }

    /// Im Papierkorb holt derselbe Platz den Befund zurück — ein zweites Wegwerfen gibt es dort
    /// nicht, und ein leerer Platz wäre ein Sprung in der Zeile.
    private var papierkorbKnopf: some View {
        Button {
            setzeVerworfen(!befund.verworfen)
        } label: {
            Image(systemName: befund.verworfen ? "arrow.uturn.backward" : "trash")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(befund.verworfen
              ? "Zurück in die Liste"
              : "Aussortieren — kommt beim nächsten Scan nicht wieder")
    }

    private var rumpf: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !befund.beschreibung.isEmpty {
                Text(befund.beschreibung)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let empfehlung = befund.empfehlung, !empfehlung.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(empfehlung)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }

            if !befund.belege.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Belege")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(befund.belege) { beleg in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beleg.sessionTitel ?? String(beleg.sessionId.prefix(8)))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(beleg.zitat)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 6)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(.quaternary).frame(width: 2)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Als Regel kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(befund.alsRegel, forType: .string)
                }
                if befund.verworfen {
                    Button("Zurückholen") { setzeVerworfen(false) }
                } else {
                    Button(befund.erledigt ? "Wieder öffnen" : "Erledigt") {
                        setzeErledigt(!befund.erledigt)
                    }
                }
                Spacer()
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.leading, 15)
    }

    private var farbe: Color {
        switch befund.schwere {
        case .hoch: return .red
        case .mittel: return .orange
        case .niedrig: return .secondary
        }
    }
}

/// Der Knopf in der Leiste, mit Zähler.
struct WatchdogToolbarButton: View {
    @Bindable var watchdog: WatchdogModel

    var body: some View {
        Button {
            watchdog.panelOffen.toggle()
        } label: {
            Image(systemName: "waveform.path.ecg")
                .overlay(alignment: .topTrailing) {
                    if watchdog.offeneAnzahl > 0 {
                        Text(watchdog.offeneAnzahl > 99 ? "99+" : "\(watchdog.offeneAnzahl)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(zaehlerFarbe, in: Capsule())
                            .offset(x: 9, y: -7)
                            .fixedSize()
                    }
                }
        }
        .help(hilfe)
        .popover(isPresented: $watchdog.panelOffen, arrowEdge: .bottom) {
            WatchdogPanel(watchdog: watchdog)
        }
    }

    /// Rot nur, wenn etwas Schweres offen ist. Ein dauerhaft roter Punkt für eine Kleinigkeit
    /// erzieht dazu, den Zähler zu übersehen.
    private var zaehlerFarbe: Color {
        watchdog.offene.contains { $0.schwere == .hoch } ? .red : .orange
    }

    private var hilfe: String {
        watchdog.offeneAnzahl == 0
            ? "Session-Watchdog"
            : "Session-Watchdog — \(watchdog.offeneAnzahl) Befund\(watchdog.offeneAnzahl == 1 ? "" : "e")"
    }
}
