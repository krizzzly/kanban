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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Beim Beenden die eigenen `claude -p`-Kinder mitnehmen. Ohne das überlebt ein laufender
    /// Watchdog-Scan die App als Waise (`ppid=1`, beobachtet: 5½ Minuten Restlaufzeit, 300 MB) —
    /// sein Zeitlimit lebte im Elternprozess und stirbt mit ihm.
    func applicationWillTerminate(_ notification: Notification) {
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
        if CommandLine.arguments.contains("--migrate-jira-line") {
            JiraLineMigrationCLI.runAndExit()
        }
        ClaudeAssetFactory.seedAtLaunch()
    }

    var body: some Scene {
        Window("", id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 540)
        }
        .defaultSize(width: 1280, height: 800)
    }
}
