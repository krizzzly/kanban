import AppKit
import SwiftUI

/// Präsentiert die Einstellungen als eigenständiges, zentriertes Fenster — aus demselben Grund wie
/// `CommitWindow`: ein Sheet hängt am Board-Fenster, kann nicht grösser werden als dieses und
/// erscheint dort, wo das Board gerade steht. Der Claude-Workflow-Editor braucht die volle Fläche.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    private init() {}

    func show(model: AppModel) {
        if let window {                     // bereits offen → nur nach vorn holen
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = SettingsSheet(onSaved: { model.reloadConfig() },
                                    onClose: { [weak self] in self?.close(model: model) })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1060),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Einstellungen"
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
                model.settingsPresented = false
            }
        }
        self.window = window
    }

    func close(model: AppModel) {
        window?.close()
        window = nil
        model.settingsPresented = false
    }
}
