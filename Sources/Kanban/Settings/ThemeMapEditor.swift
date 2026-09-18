import SwiftUI
import KanbanCore

/// Editor für eine Map benannter Fassungen — `terminal.themes.<name>` und `markdown.themes.<name>`
/// teilen sich dieses eine Bauteil.
///
/// Der Unterschied zwischen den beiden ist die Feldliste, nicht die Bedienung: auswählen tut man
/// oben im Formular, ändern hier, und angelegt wird eine Fassung als **Kopie** — leer angelegt
/// fiele sie beim Laden stumm wieder aus der Auswahl (`RawTheme.resolved` wirft eine Fassung ohne
/// Pflichtfarben oder mit ≠ 16 ANSI-Farben weg, ohne ein Wort).
struct ThemeMapEditor: View {
    let spec: ThemeMapSpec
    let settings: SettingsModel

    @State private var neuerName = ""
    @State private var umbenennen: [String: String] = [:]

    var body: some View {
        Section(spec.title) {
            ForEach(settings.keys(at: spec.path), id: \.self) { name in
                DisclosureGroup {
                    inhalt(name)
                } label: {
                    kopfzeile(name)
                }
            }

            HStack(spacing: 8) {
                TextField("Neue Fassung", text: $neuerName, prompt: Text(spec.keyPlaceholder))
                    .onSubmit(anlegen)
                Button("Als Kopie anlegen", action: anlegen)
                    .disabled(neuerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Eine neue Fassung startet als Kopie der aktiven — so ist sie von Anfang an "
               + "vollständig und steht sofort in der Auswahl.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Eine Fassung

    private func kopfzeile(_ name: String) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: 13, weight: .medium, design: .monospaced))
            if settings.activeTheme(spec) == name {
                Text("aktiv")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            if fehler(name) != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func inhalt(_ name: String) -> some View {
        // Die Warnung gehört an die Fassung, nicht in eine Fussnote: wer sie nicht sieht, sucht
        // später eine Fassung, die es aus Sicht des Laders nie gab.
        if let fehler = fehler(name) {
            Label(fehler, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }

        ForEach(spec.fields) { feld in
            SchemaFieldView(spec: ConfigFieldSpec(spec.path + [name] + feld.subpath, feld.label,
                                                  kind: feld.kind, placeholder: feld.placeholder,
                                                  help: feld.help),
                            settings: settings)
        }

        if let ansiKey = spec.ansiKey {
            ansiRaster(pfad: spec.path + [name, ansiKey])
        }

        HStack(spacing: 8) {
            TextField("Name", text: nameBinding(name), prompt: Text(name))
                .onSubmit { uebernimmNamen(name) }
            Button("Umbenennen") { uebernimmNamen(name) }
                .disabled(!nameGeaendert(name))
            Spacer()
            Button("Fassung entfernen", role: .destructive) {
                settings.removeTheme(spec, key: name)
                umbenennen[name] = nil
            }
            .disabled(settings.keys(at: spec.path).count <= 1)
        }
        .padding(.top, 4)
    }

    /// Die 16 ANSI-Farben mit ihren üblichen Namen statt mit ihrer Nummer: „3 Gelb" findet man,
    /// „ANSI 3" muss man nachschlagen. Reihenfolge ist Pflicht (0–7 normal, 8–15 hell), deshalb
    /// stehen sie als Liste und nicht als Felder mit eigenen Schlüsseln.
    private func ansiRaster(pfad: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ANSI-Farben").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            ForEach(0..<16, id: \.self) { index in
                ColorField(label: "\(index) \(Self.ansiNamen[index])",
                           hex: settings.ansiBinding(pfad, index: index))
            }
        }
    }

    private static let ansiNamen = [
        "Schwarz", "Rot", "Grün", "Gelb", "Blau", "Magenta", "Cyan", "Weiss",
        "Schwarz (hell)", "Rot (hell)", "Grün (hell)", "Gelb (hell)",
        "Blau (hell)", "Magenta (hell)", "Cyan (hell)", "Weiss (hell)",
    ]

    // MARK: - Aktionen

    private func fehler(_ name: String) -> String? {
        spec.fehler(in: settings.themeValues(spec, key: name))
    }

    private func anlegen() {
        settings.addTheme(spec, key: neuerName)
        neuerName = ""
    }

    private func nameBinding(_ name: String) -> Binding<String> {
        Binding(get: { umbenennen[name] ?? name }, set: { umbenennen[name] = $0 })
    }

    private func nameGeaendert(_ name: String) -> Bool {
        let neu = (umbenennen[name] ?? name).trimmingCharacters(in: .whitespaces)
        return !neu.isEmpty && neu != name
    }

    private func uebernimmNamen(_ name: String) {
        guard nameGeaendert(name) else { return }
        settings.renameTheme(spec, from: name, to: umbenennen[name] ?? name)
        umbenennen[name] = nil
    }
}
