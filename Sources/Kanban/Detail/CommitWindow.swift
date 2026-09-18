import AppKit
import SwiftUI

/// Presents the commit dialog in its own window, centred on the screen.
///
/// It used to be a `.sheet`, which macOS attaches to the parent window and drops in from its title
/// bar — so it sat wherever the board window happened to be, and could not exceed it. A standalone
/// window can be centred, resized freely and moved to a second display.
///
/// **Je Board-Fenster eines**: der Dialog gehört zum auslösenden Fenster, und zwei Projekte dürfen
/// gleichzeitig committen — ein einzelnes Fenster für die ganze App zeigte sonst dem einen Projekt
/// die Änderungen des anderen. Der Schlüssel ist deshalb das `AppModel`, wie bei
/// `MarkdownDocumentWindow` der aufgelöste Dateipfad.
@MainActor
final class CommitWindow {
    static let shared = CommitWindow()

    private var windows: [ObjectIdentifier: NSWindow] = [:]
    private var beobachter: [ObjectIdentifier: NSObjectProtocol] = [:]

    private init() {}

    func show(model: AppModel) {
        let id = ObjectIdentifier(model)
        if let window = windows[id] {       // bereits offen → nur nach vorn holen
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = CommitSheet(model: model, onClose: { [weak self] in self?.close(model: model) })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1060),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        // Mit dem Projekt im Titel: bei zwei offenen Dialogen ist sonst nicht zu sehen, welcher
        // welchem Board gehört.
        window.title = model.selectedProject.map { "Commit — \($0.key.uppercased())" } ?? "Commit"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.minSize = NSSize(width: 1100, height: 700)
        // Nicht stapeln, wenn schon einer offen ist — sonst liegen zwei Dialoge deckungsgleich.
        if windows.isEmpty { window.center() } else { window.cascadeTopLeft(from: NSPoint(x: 60, y: 60)) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Schliessen über den roten Punkt zurück ins Model spiegeln.
        beobachter[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.aufraeumen(id)
                    model.commitSheetPresented = false
                }
            }
        windows[id] = window
    }

    func close(model: AppModel) {
        let id = ObjectIdentifier(model)
        windows[id]?.close()
        aufraeumen(id)
        model.commitSheetPresented = false
    }

    private func aufraeumen(_ id: ObjectIdentifier) {
        if let token = beobachter.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(token)
        }
        windows[id] = nil
    }
}
