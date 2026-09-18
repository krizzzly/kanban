import SwiftUI
import KanbanCore

struct ContentView: View {
    /// Das Projekt dieses Fensters — der Wert der Szene (`WindowGroup(for: String.self)`).
    ///
    /// nil beim Fenster, das der Programmstart bzw. ⌘N aufmacht: dann sagt `ProjectWindows`, welches
    /// Projekt es zeigt. Bewusst ein Wert und keine Bindung: der Szenenwert wird gelesen, nicht
    /// zurückgeschrieben — welches Fenster welches Projekt zeigt, führt `ProjectWindows`.
    let projectKey: String?

    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let fehlend = model.fehlendesProjekt {
                ProjectGoneView(key: fehlend,
                                openSettings: { model.settingsPresented = true },
                                close: { ProjectWindows.shared.schliessen(model: model) })
            } else if let error = model.configError {
                ConfigErrorView(message: error) { model.settingsPresented = true }
            } else if model.needsSetup {
                SetupView { model.settingsPresented = true }
            } else if model.knowledgebaseOpen {
                // Die Knowledgebase bringt ihre eigene Zweiteilung mit (Baum | Inhalt) und tritt
                // deshalb an die Stelle von Board und Detail, statt sich in eine der Spalten zu
                // quetschen. Die Leiste bleibt — über sie geht es zurück.
                KnowledgebaseView(model: model)
                    .toolbar { TopBarToolbar(model: model) }
                    .headerChrome(model.selectedProject?.appearance ?? .none)
            } else {
                HSplitView {
                    BoardSidebar(model: model)
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
                    DetailView(model: model)
                        .frame(minWidth: 460)
                }
                .toolbar { TopBarToolbar(model: model) }
                // Hintergrund und unterer Rand der Kopfzeile — beides nur, wo konfiguriert. Die
                // Knowledgebase bekommt es ebenso: sie tauscht das Board aus, nicht die Leiste.
                .headerChrome(model.selectedProject?.appearance ?? .none)
            }
        }
        // Leerer Titel, und er bleibt leer: über dem Board soll kein Text stehen (welches Projekt
        // ein Fenster zeigt, sagt das Projekt-Menü der Kopfzeile), und das leere Titel-Element
        // hält zugleich den Zwischenraum, der die Knöpfe der `primaryAction` nach rechts drückt.
        //
        // Dass die Fenster im **Fenster-Menü** von macOS trotzdem ihr Projekt tragen, macht
        // `ProjektFensterMenue` mit eigenen Einträgen — nicht der Fenstertitel. Drei Wege dorthin
        // wurden gemessen und verworfen, alle drei an echtem AppKit (900-pt-Fenster, Knöpfe in
        // `.navigation` und `.primaryAction`; der rechteste endet bei sichtbarem Titel bei 894):
        //
        // - `toolbar(removing: .title)` — der ursprüngliche Versuch: nimmt das Element samt
        //   Zwischenraum, die Knöpfe kleben links.
        // - `titleVisibility = .hidden` — blendet den Text aus, lässt das Element aber auf Breite 0
        //   schrumpfen: rechtester Knopf bei 207 statt 894, also derselbe Fehler.
        // - Titel setzen und die Anzeige unterdrücken — geht nicht gegeneinander: SwiftUI schreibt
        //   `title` **und** `titleVisibility` bei jeder Aktualisierung zurück (gemessen: eine
        //   Sekunde nach dem eigenen Schreiben stand wieder „Kanban" da, sichtbar in der Mitte).
        //   Ein eigener Schreiber auf denselben beiden Feldern gewinnt bestenfalls zufällig.
        .navigationTitle("")
        .background(WindowAccessor { ProjectWindows.shared.fensterMerken($0, model: model) })
        .task {
            ProjectWindows.shared.merkeOeffner { openWindow(value: $0) }
            model.bootstrap(projectKey: projectKey)
            if let key = model.selectedProject?.key {
                ProjectWindows.shared.anmelden(model: model, key: key)
            }
            // Erst anmelden, dann wiederherstellen: das eigene Projekt steht dann schon in der
            // Liste der offenen und geht nicht ein zweites Mal auf.
            ProjectWindows.shared.wiederherstellen(projekte: model.projects)
            // Prozessweit einer für alle Fenster — der Scan startet `claude -p` und kostet Geld.
            await WatchdogModel.shared.uebernehmen(config: model.config)
        }
        // Das Projekt-Menü schaltet im Fenster um — die Zuordnung zieht mit, sonst liefen
        // Terminal-Klick und Benachrichtigung ins alte Projekt.
        .onChange(of: model.selectedProject?.key) { _, key in
            if let key { ProjectWindows.shared.anmelden(model: model, key: key) }
        }
        .sheet(isPresented: $model.settingsPresented) {
            // Die Config gehört allen Fenstern, nicht nur dem, in dem gespeichert wurde.
            SettingsSheet { ProjectWindows.shared.configNeuLaden() }
        }
        .sheet(isPresented: $model.bookingSheetPresented) {
            BookingSheet(model: model)
        }
        .sheet(isPresented: $model.stackSweepPresented) {
            StackSweepSheet(model: model)
        }
        .sheet(isPresented: $model.newTaskSheetPresented) {
            NewTaskSheet(model: model)
        }
        // get-task/start-task holen Jira-Inhalte in die KI — davor steht die PROD-Bestätigung.
        // Hier oben, weil beide Wege dorthin führen: Board-Kontextmenü und Detail-Header.
        .sheet(item: $model.prodConfirmation) { pending in
            ProdDataConfirmSheet(model: model, pending: pending)
        }
        // Eigenes Fenster statt Sheet: ein Sheet hängt am Board-Fenster und erscheint dort, wo das
        // gerade steht — der Commit-Dialog soll mittig auf dem Bildschirm aufgehen.
        .onChange(of: model.commitSheetPresented) { _, presented in
            if presented { CommitWindow.shared.show(model: model) }
            else { CommitWindow.shared.close(model: model) }
        }
    }

}

/// Das Projekt dieses Fensters steht nicht mehr in der Config (in den Einstellungen entfernt,
/// während das Fenster offen war). Bewusst kein stiller Wechsel auf irgendein anderes Projekt: das
/// Fenster gehörte diesem einen, und ein Board, das plötzlich etwas anderes zeigt, wäre die
/// unangenehmere Überraschung.
struct ProjectGoneView: View {
    let key: String
    let openSettings: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("Projekt „\(key.uppercased())“ gibt es nicht mehr")
                .font(.headline)
            Text("Es steht nicht mehr in der Config. Dieses Fenster zeigte es — deshalb bleibt es "
                 + "leer, statt ungefragt ein anderes Projekt anzuzeigen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 10) {
                Button("Einstellungen öffnen…", action: openSettings)
                Button("Fenster schliessen", action: close)
            }
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Erststart: die Config ist leer (oder hat noch kein Projekt). Bewusst **kein** Fehlerbild —
/// Kanban läuft ohne Hermes und ohne Vorwissen, hier fängt die Einrichtung an. Lag eine
/// Hermes-Config bereit, hat `HermesImport` sie schon übernommen und dieser Schirm erscheint gar nicht.
struct SetupView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
            Text("Willkommen bei Kanban")
                .font(.headline)
            Text("Noch nichts konfiguriert. Trage in den Einstellungen deine Jira-Zugangsdaten ein "
                 + "und lege mindestens ein Projekt an — GitLab oder GitHub ist optional und "
                 + "ergänzt nur die Spalten Review und Done.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Einstellungen öffnen…", action: openSettings)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nur für echte Fehler: die Config-Datei existiert, ist aber kein gültiges JSON. Fehlende Werte
/// führen hierher nicht — dafür gibt es `SetupView`.
struct ConfigErrorView: View {
    let message: String
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("Config konnte nicht geladen werden")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(abbreviated(KanbanConfig.path))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Einstellungen öffnen…", action: openSettings)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
