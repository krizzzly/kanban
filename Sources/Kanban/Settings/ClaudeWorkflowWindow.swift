import AppKit
import SwiftUI

/// Präsentiert den Claude-Workflow-Editor (Commands/Skills/Rules) als eigenständiges, zentriertes
/// Fenster in Commit-Dialog-Grösse — der Markdown-Editor braucht Fläche, die ein Sheet am
/// Board-Fenster nicht hergibt. Die übrigen Einstellungen bleiben bewusst ein Sheet.
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
            .frame(minWidth: 1100, minHeight: 700)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1060),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Claude-Workflow"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.minSize = NSSize(width: 1100, height: 700)
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
