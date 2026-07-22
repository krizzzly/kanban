import SwiftUI
import AppKit

/// When run as a bare SPM executable (`swift run`) there is no app bundle, so AppKit defaults
/// to an accessory activation policy and never shows/foregrounds the window. Force `.regular`
/// and activate, mirroring kanban-code's AppDelegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct KanbanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.runAndExit()
        }
    }

    var body: some Scene {
        Window("Kanban", id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 540)
        }
        .defaultSize(width: 1280, height: 800)
    }
}
