import AppKit
import SwiftUI

/// Präsentiert die Skill-Set-Übersicht als eigenständiges, zentriertes Fenster. Ein Sheet am
/// Board-Fenster ginge auch — aber die Liste wird mit jedem Projekt länger, und sie steht oft
/// neben dem Board offen, während man eine Verlinkung herstellt. Die übrigen Einstellungen bleiben
/// bewusst ein Sheet.
///
/// **Eines für die ganze App**, anders als der Commit-Dialog: Sets und ihre Verlinkung sind
/// projektunabhängig — zwei Übersichten auf denselben Ordnern wären zwei Stände derselben Sache.
/// Wer es aufgemacht hat, merkt sich der Besitzer, damit ein zweites Board-Fenster es nach vorn
/// holt, statt es dem ersten zuzuklappen.
@MainActor
final class ClaudeWorkflowWindow {
    static let shared = ClaudeWorkflowWindow()

    private var window: NSWindow?
    private weak var besitzer: AppModel?

    private init() {}

    func show(model: AppModel) {
        if let window {                     // bereits offen → nur nach vorn holen
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Der Schalter des anfragenden Fensters geht zurück: das Fenster gehört weiter dem
            // ersten, und nur dessen Schalter darf es wieder zumachen (siehe `close`).
            if besitzer !== model { model.claudeWorkflowPresented = false }
            return
        }
        besitzer = model
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
                self?.besitzer = nil
                model.claudeWorkflowPresented = false
            }
        }
        self.window = window
    }

    /// Zumachen darf nur, wer aufgemacht hat — sonst schlösse der zurückgesetzte Schalter eines
    /// zweiten Fensters den Editor des ersten.
    func close(model: AppModel) {
        guard besitzer == nil || besitzer === model else { return }
        window?.close()
        window = nil
        besitzer = nil
        model.claudeWorkflowPresented = false
    }
}
