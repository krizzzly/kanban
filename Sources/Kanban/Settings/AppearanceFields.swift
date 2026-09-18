import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KanbanCore

/// Farbeingabe als **Hexcode**, und nur so: das `#` steht fest im Feld, getippt werden die sechs
/// Stellen dahinter.
///
/// Leer heisst „nicht gesetzt" — deshalb braucht es keinen Löschknopf, das Feld leer zu räumen ist
/// derselbe Weg. Gespeichert wird `#rrggbb` in Kleinschreibung.
///
/// Was hineingetippt werden **kann**, ist schon auf Hexziffern und sechs Stellen begrenzt; ein Feld,
/// das „blau" annimmt und stillschweigend verwirft, wäre eine Falle. Unvollständig (ein bis fünf
/// Stellen) bleibt trotzdem möglich — man tippt ja von links — und wird als solches angezeigt,
/// statt die Zeile schon nach dem ersten Zeichen einzufärben.
struct ColorField: View {
    let label: String
    @Binding var hex: String

    private var ziffern: String { hex.hasPrefix("#") ? String(hex.dropFirst()) : hex }
    private var vollstaendig: Bool { ziffern.count == 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(label)
                Spacer(minLength: 8)
                // Der Farbfleck ist kein Eingabeweg, sondern die Antwort auf „hat mein Code
                // gegriffen?" — ohne ihn sieht man das erst nach dem Speichern in der Kopfzeile.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: hex) ?? .clear)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
                    .frame(width: 22, height: 14)
                feld
            }
            if !ziffern.isEmpty && !vollstaendig {
                Text("Noch \(6 - ziffern.count) Stellen — bis dahin gilt die Farbe als nicht gesetzt.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    /// `#` und Eingabe in einem Rahmen, wie die Suchleiste der Markdown-Ansichten: das Zeichen
    /// gehört sichtbar zum Feld, ist aber nichts, was man tippt oder löschen könnte.
    private var feld: some View {
        HStack(spacing: 1) {
            Text("#")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField("", text: eingabe, prompt: Text("1a2b3c"))
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 62)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
        .fixedSize()
    }

    /// Nimmt entgegen, was jemand tippt **oder einfügt** — was davon durchkommt, entscheidet
    /// `ProjectAppearance.sanitizeHexInput`.
    private var eingabe: Binding<String> {
        Binding(
            get: { ziffern },
            set: { roh in
                let sauber = ProjectAppearance.sanitizeHexInput(roh)
                hex = sauber.isEmpty ? "" : "#" + sauber
            })
    }
}

/// Bildauswahl für ein Projekt: kopiert die gewählte Datei über `ProjectImageStore` in Kanbans
/// Datenordner und merkt sich den Pfad der **Kopie**.
///
/// Auch hier ist „nichts gesetzt" ein vollwertiger Zustand, und „Entfernen" führt zurück dorthin —
/// samt Löschen der Kopie, damit im Datenordner nichts liegen bleibt, auf das niemand mehr zeigt.
struct ProjectImageField: View {
    let label: String
    let projectKey: String
    @Binding var path: String

    @State private var fehler: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                Spacer(minLength: 8)
                if let bild = geladenesBild {
                    Image(nsImage: bild)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 24)
                    Button("Ersetzen…") { waehlen() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                    Button("Entfernen") { entfernen() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                } else {
                    Button("Bild wählen…") { waehlen() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                }
            }
            // Der Pfad steht in der Config und ist beim Nachsehen von aussen hilfreich — aber er ist
            // nichts, was man hier tippt, deshalb nur zum Lesen.
            if !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // Eine Datei, die fehlt, ist kein leeres Feld: die Einstellung steht, nur das Bild ist
            // weg. Das muss man sehen, sonst sucht man den Fehler in der Kopfzeile.
            if !path.isEmpty && geladenesBild == nil {
                Label("Datei nicht gefunden", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let fehler {
                Label(fehler, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var geladenesBild: NSImage? { .projectImage(atPath: path) }

    private func waehlen() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ProjectImageStore.allowedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            path = try ProjectImageStore.store(source: url, projectKey: projectKey)
            fehler = nil
        } catch {
            fehler = error.localizedDescription
        }
    }

    private func entfernen() {
        ProjectImageStore.remove(projectKey: projectKey)
        path = ""
        fehler = nil
    }
}

