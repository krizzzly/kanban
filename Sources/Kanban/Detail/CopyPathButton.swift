import AppKit
import SwiftUI

/// Legt einen Dateipfad in die Zwischenablage und sagt es kurz mit einem grünen Haken — derselbe
/// Knopf für das Task-File in der Tableiste und für jede Datei im Task-Ordner.
///
/// Schrift und Grösse kommen von aussen (`.font(…)` am Aufrufer wirkt auf das Label): in der
/// Tableiste steht er neben 12-pt-Symbolen, in der Kopfzeile der Vorschau neben der Caption-Zeile.
struct CopyPathButton: View {
    let path: String?
    let help: String

    @State private var copied = false

    var body: some View {
        Button {
            guard let path else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(path == nil)
        .help(path.map { "\(help): \($0)" } ?? help)
    }
}
