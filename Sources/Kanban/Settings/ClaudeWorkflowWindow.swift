import AppKit
import SwiftUI

/// Präsentiert die Skill-Set-Übersicht als eigenständiges, zentriertes Fenster. Ein Sheet am
/// Board-Fenster ginge auch — aber die Liste wird mit jedem Projekt länger, und sie steht oft
/// neben dem Board offen, während man eine Verlinkung herstellt. Die übrigen Einstellungen bleiben
/// bewusst ein Sheet.
@MainActor
final class ClaudeWorkflowWindow {
    static let shared = ClaudeWorkflowWindow()

    private var window: NSWindow?

    private init() {}

    func show(model: AppModel) {
        if let window {                     // bereits offen → nur nach vorn holen
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = ClaudeWorkflowSettingsView()
            .frame(minWidth: 620, minHeight: 420)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Skill-Sets"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.minSize = NSSize(width: 620, height: 420)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Schliessen über den roten Punkt zurück ins Model spiegeln.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window = nil
                model.claudeWorkflowPresented = false
            }
        }
        self.window = window
    }

    func close(model: AppModel) {
        window?.close()
        window = nil
        model.claudeWorkflowPresented = false
    }
}
