import SwiftUI
import KanbanCore

/// Der Backlog als **eine Liste** in Jiras Rang-Reihenfolge, per Ziehen umsortierbar.
///
/// **Warum eine eigene Ansicht und nicht das Brett:** eine Reihenfolge ist eine Liste, kein Raster.
/// Das Board gruppiert in Spalten und sortiert darin nach Ticketnummer — eine Ordnung über *alle*
/// Karten hinweg liesse sich dort nur als Zahl auf jeder Karte zeigen, und das wäre eine zweite,
/// ständig veraltende Anzeige derselben Sortierung.
///
/// **Warum Ziehen hier erlaubt ist**, obwohl auf dem Brett keine Karte je von Hand bewegt wird: die
/// Regel schützt die *abgeleitete Spalte* — eine Karte nach „Review" zu ziehen wäre eine Behauptung
/// über Artefakte, die es nicht gibt. Der Rang ist das Gegenteil: eine menschliche Entscheidung,
/// für die Jira ein eigenes Feld führt. Ihn zu ziehen ist ehrlich, und es schreibt dorthin zurück.
struct ReihenfolgeView: View {
    var model: AppModel

    /// Die Auswahl der Liste. Über sie geht das Anwählen einer Zeile — **nicht** über ein
    /// `onTapGesture`: eine Tipp-Geste auf der Zeile verschluckt den Mausdruck, und damit kommt das
    /// Ziehen nie zustande. Das war der Grund, warum sich zuerst nichts verschieben liess.
    @State private var auswahl: CardVM.ID?

    var body: some View {
        VStack(spacing: 0) {
            kopf
            Divider()
            if model.kartenNachRang.isEmpty {
                leer
            } else {
                liste
            }
        }
    }

    private var kopf: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.number")
            Text("Reihenfolge")
                .font(.app(.headline))
            Text(model.reihenfolgeQuelle.beschreibung)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            Spacer()
            verschiebeKnoepfe
            if !model.reihenfolgeVerstoesse.isEmpty {
                Label("\(model.reihenfolgeVerstoesse.count) vorgezogen",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
                    .help("In Arbeit, obwohl noch gesperrt:\n"
                          + model.reihenfolgeVerstoesse.joined(separator: "\n"))
            }
            Button("Zum Board") { model.toggleReihenfolge() }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Verschieben ohne Ziehen.
    ///
    /// Nicht nur als Rückfalllösung: in einer Liste mit knapp hundert Zeilen ist „vierzig Plätze
    /// nach oben ziehen" ohnehin mühsam — ein Schritt je Tastendruck trifft genau, und die Auswahl
    /// wandert mit. Dieselbe Logik wie beim Ziehen (`TicketOrder.moveAnchor`), derselbe
    /// Schreibweg.
    private var verschiebeKnoepfe: some View {
        let karten = model.kartenNachRang
        let index = auswahl.flatMap { id in karten.firstIndex(where: { $0.id == id }) }
        return HStack(spacing: 2) {
            Button {
                if let i = index, i > 0 { model.verschiebeReihenfolge(from: IndexSet(integer: i), to: i - 1) }
            } label: { Image(systemName: "arrow.up") }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(index == nil || index == 0)
                .help("Auswahl eine Position nach oben (⌘↑)")

            Button {
                if let i = index, i < karten.count - 1 {
                    model.verschiebeReihenfolge(from: IndexSet(integer: i), to: i + 2)
                }
            } label: { Image(systemName: "arrow.down") }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(index == nil || index == karten.count - 1)
                .help("Auswahl eine Position nach unten (⌘↓)")
        }
        .buttonStyle(.borderless)
    }

    private var leer: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Nichts zu ordnen")
                .font(.app(.headline))
            Text(model.reihenfolgeQuelle == .jira
                 ? "Dieses Projekt holt seine Reihenfolge aus Jiras Backlog — dort steht gerade nichts."
                 : "Sobald es Task-Files, Worktrees oder Merge Requests gibt, stehen sie hier und "
                   + "lassen sich in die Reihenfolge ziehen, die du haben willst.")
                .font(.app(.callout))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var liste: some View {
        // Die Reihenfolge einmal festhalten: `kartenNachRang` rechnet bei jedem Zugriff neu, und
        // `ForEach` muss über **dieselbe** Sammlung laufen, auf die sich die Indizes von `onMove`
        // beziehen.
        let karten = model.kartenNachRang
        return List(selection: $auswahl) {
            ForEach(karten) { karte in
                ReihenfolgeZeile(karte: karte,
                                 position: (karten.firstIndex(of: karte) ?? 0) + 1)
            }
            .onMove { from, to in model.verschiebeReihenfolge(from: from, to: to) }
        }
        .listStyle(.inset)
        .onChange(of: auswahl) { _, neu in
            if let neu { model.selectTicket(neu) }
        }
    }
}

/// Eine Zeile: Position, Typ, Key, Titel — und **warum** sie wartet.
private struct ReihenfolgeZeile: View {
    let karte: CardVM
    let position: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(position)")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()

            IssueTypeIcon(type: karte.ticket.type, urlString: karte.ticket.typeIconUrl)

            Text(karte.ticket.key)
                .font(.app(.caption))
                .fontWeight(.bold)
                .frame(width: 118, alignment: .leading)
                .lineLimit(1)

            Text(karte.ticket.summary)
                .font(.app(.subheadline))
                .lineLimit(1)

            Spacer(minLength: 8)

            // Die Sperre steht hier **immer** — anders als auf dem Brett, wo sie nur im Auto-Modus
            // erscheint. In einer Reihenfolge ist „wartet auf" die eigentliche Auskunft.
            if !karte.blockedBy.isEmpty {
                Label(karte.blockedBy.map(\.key).joined(separator: ", "),
                      systemImage: "hand.raised.fill")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("Wartet auf:\n" + karte.blockedBy.map { ref in
                        ref.summary.isEmpty ? ref.key : "\(ref.key) — \(ref.summary)"
                    }.joined(separator: "\n"))
            }

            if let punkte = karte.ticket.storyPoints, punkte > 0 {
                Text(punkte == punkte.rounded() ? String(Int(punkte)) : String(punkte))
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                    .monospacedDigit()
            }

            Text(karte.column.rawValue)
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
