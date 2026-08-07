import AppKit
import SwiftUI

/// Presents the commit dialog in its own window, centred on the screen.
///
/// It used to be a `.sheet`, which macOS attaches to the parent window and drops in from its title
/// bar — so it sat wherever the board window happened to be, and could not exceed it. A standalone
/// window can be centred, resized freely and moved to a second display.
@MainActor
final class CommitWindow {
    static let shared = CommitWindow()

    private var window: NSWindow?

    private init() {}

    func show(model: AppModel) {
        if let window {                     // bereits offen → nur nach vorn holen
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = CommitSheet(model: model, onClose: { [weak self] in self?.close(model: model) })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1060),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Commit"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.minSize = NSSize(width: 1100, height: 700)
        window.center()                     // mittig auf dem Bildschirm
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Schliessen über den roten Punkt zurück ins Model spiegeln.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window = nil
                model.commitSheetPresented = false
            }
        }
        self.window = window
    }

    func close(model: AppModel) {
        window?.close()
        window = nil
        model.commitSheetPresented = false
    }
}
