import SwiftUI
import KanbanCore

/// Die Suchleiste der gerenderten Markdown-Ansichten — **eine** für alle: Task-File-Tabs,
/// Dokumentfenster aus dem Finder, Knowledgebase und die Lese-Ansicht des Asset-Editors.
///
/// Reine Anzeige, ohne eigenen Zustand: wer sie einsetzt, hält ihn (das Task-File sucht über
/// **alle** Tabs und wechselt beim Sprung den Tab, ein Dokument sucht in sich selbst). Gemeinsam
/// sind Aussehen und Tastatur — ⏎ weiter, ⇧⏎ zurück, esc leert.
struct MarkdownFindBar: View {
    @Binding var query: String
    /// Wie viele Fundstellen es gibt und die wievielte gerade angesprungen ist (0-basiert).
    let treffer: Int
    let aktuell: Int
    /// nil heisst: noch zu kurz zum Suchen (siehe `TaskSearch.minQueryLength`).
    let zaehlbar: Bool
    let weiter: (Int) -> Void

    /// Fokus von aussen setzbar, damit ⌘F die Leiste erreicht.
    @FocusState.Binding var fokussiert: Bool

    var breite: CGFloat = 130

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Suchen", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: breite)
                .focused($fokussiert)
                .onSubmit { weiter(1) }
                .onKeyPress(.return, phases: .down) { druck in
                    guard druck.modifiers.contains(.shift) else { return .ignored }
                    weiter(-1)
                    return .handled
                }
                .onKeyPress(.escape, phases: .down) { _ in
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
            if !query.isEmpty {
                Text(trefferText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(treffer == 0 && zaehlbar ? Color.red : Color.secondary)
                    .fixedSize()
                if treffer > 0 {
                    knopf("chevron.up", "Vorheriger Treffer (⇧⏎)") { weiter(-1) }
                    knopf("chevron.down", "Nächster Treffer (⏎)") { weiter(1) }
                }
                knopf("xmark.circle.fill", "Suche leeren (esc)") { query = "" }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
        .fixedSize()
    }

    /// „3/12" — und der Grund, warum nichts markiert ist, wenn es nichts zu markieren gibt.
    private var trefferText: String {
        guard zaehlbar else { return "…" }
        return treffer == 0 ? "0" : "\(aktuell + 1)/\(treffer)"
    }

    private func knopf(_ symbol: String, _ hilfe: String,
                       _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hilfe)
    }
}

/// Der Suchzustand **einer** gerenderten Markdown-Datei.
///
/// Das Task-File braucht ihn nicht — dort spannt die Suche über alle Tabs und der Sprung wechselt
/// den Tab (siehe `TaskTabsView`). Für ein einzelnes Dokument ist der Fall einfacher: eine Sektion,
/// die Trefferliste ist die Fundstellenliste, und `MarkdownSearch.occurrence` ist der Index darin.
@MainActor
struct MarkdownFind {
    var query = ""

    private(set) var treffer = 0
    private(set) var index = 0
    private(set) var token = 0

    /// Der vorbereitete Text — wie im Task-File **faul** gebaut: `visibleText` schickt das Dokument
    /// durch cmark, und das soll nicht bei jedem Tastendruck passieren und nicht, solange niemand
    /// sucht.
    private var suchindex = TaskSearchIndex(sections: [])
    private var veraltet = true

    var zaehlbar: Bool {
        query.trimmingCharacters(in: .whitespaces).count >= TaskSearch.minQueryLength
    }

    /// Der Inhalt hat sich geändert (andere Datei, Datei neu geladen).
    mutating func inhaltGeaendert(_ markdown: String) {
        veraltet = true
        if !query.isEmpty { neuRechnen(markdown, springen: false) }
    }

    /// Es wurde getippt.
    mutating func eingabeGeaendert(_ markdown: String) {
        neuRechnen(markdown, springen: true)
    }

    mutating func weiter(_ schritt: Int) {
        guard treffer > 0 else { return }
        index = (index + schritt + treffer) % treffer
        token += 1
    }

    /// Was die Ansicht markieren und anspringen soll.
    var suche: MarkdownSearch? {
        guard !query.isEmpty else { return nil }
        return MarkdownSearch(query: treffer > 0 ? query : "", occurrence: index, token: token)
    }

    private mutating func neuRechnen(_ markdown: String, springen: Bool) {
        if veraltet {
            suchindex = TaskSearchIndex(sections: [TaskSection(id: 0, title: "", markdown: markdown)])
            veraltet = false
        }
        treffer = suchindex.hits(query: query).count
        if springen { index = 0 }
        index = min(index, max(treffer - 1, 0))
        // Auch „nichts gefunden" muss ankommen: sonst blieben die Markierungen der vorigen Eingabe
        // stehen und behaupteten einen Treffer.
        token += 1
    }
}
