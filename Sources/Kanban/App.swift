import SwiftUI
import AppKit
import KanbanCore

/// When run as a bare SPM executable (`swift run`) there is no app bundle, so AppKit defaults
/// to an accessory activation policy and never shows/foregrounds the window. Force `.regular`
/// and activate, mirroring kanban-code's AppDelegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Die prozessweiten Rückkanäle (Terminal-Klick, Benachrichtigung) an die Fenster-Zuordnung
        // hängen — hier und nicht im Model: es gibt N Models, aber nur einen Prozess. Der Aufruf legt
        // zugleich `ProjectWindows.shared` an, solange die gemerkte Fensterliste noch unberührt ist.
        MainActor.assumeIsolated { ProjectWindows.shared.starten() }
    }

    /// Bleibt `true`, auch mit mehreren Fenstern: Kanban ist ein Board-Programm, kein
    /// Dokument-Programm — ist das letzte Brett zu, gibt es nichts mehr zu tun, und ein Programm
    /// ohne Fenster im Dock wäre nur ein Zustand, aus dem niemand herausfindet. `--select` und
    /// „Öffnen mit" starten die App ohnehin neu.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Beim Beenden die eigenen `claude -p`-Kinder mitnehmen. Ohne das überlebt ein laufender
    /// Watchdog-Scan die App als Waise (`ppid=1`, beobachtet: 5½ Minuten Restlaufzeit, 300 MB) —
    /// sein Zeitlimit lebte im Elternprozess und stirbt mit ihm.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { ProjectWindows.shared.endstandFesthalten() }
        _ = ClaudeHeadless.alleBeenden()
    }

    /// „Öffnen mit › Kanban" aus dem Finder (`CFBundleDocumentTypes` in der `Info.plist`) und alles
    /// andere, was macOS als Datei an die App reicht — jede in ihrem eigenen Fenster.
    ///
    /// Beim Start **mit** einer Datei kommt das hier nach `applicationDidFinishLaunching`, das
    /// Board-Fenster geht also ohnehin auf; läuft die App schon, erscheint nur das Dokumentfenster.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls where url.isFileURL {
                MarkdownDocumentWindow.shared.show(url: url)
            }
        }
    }
}

@main
struct KanbanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.runAndExit()
        }
        ClaudeAssetFactory.seedAtLaunch()
    }

    /// **Mehrere Board-Fenster, je eines mit eigenem Projekt.** Der Szenenwert ist der Projekt-Key;
    /// `openWindow(value:)` holt ein vorhandenes Fenster nach vorn, statt ein zweites danebenzustellen
    /// (siehe `ProjectWindows`). Aufgemacht werden sie über den +-Knopf der Kopfzeile und beim Start;
    /// das Projekt-Menü schaltet weiter im eigenen Fenster um.
    ///
    /// Ohne Wert kommt das Fenster, das der Programmstart und ⌘N aufmachen; welches Projekt es zeigt,
    /// entscheidet `ProjectWindows.vorschlag` — beim Start das zuletzt benutzte, danach das erste
    /// ohne Fenster.
    ///
    /// `restorationBehavior(.disabled)`: das Wiederherstellen macht Kanban selbst aus
    /// `SelectionStore.openProjectKeys`. Beides zusammen liefe auf zwei Quellen für dieselbe Frage
    /// hinaus — und damit auf zwei Fenster für dasselbe Projekt.
    var body: some Scene {
        WindowGroup(for: String.self) { $projektKey in
            ContentView(projectKey: projektKey)
                .frame(minWidth: 900, minHeight: 540)
        }
        .defaultSize(width: 1280, height: 800)
        .restorationBehavior(.disabled)
    }
}
