import AppKit
import SwiftUI
import KanbanCore

/// Renders one `ConfigFieldSpec` as the matching form control, with its help text beneath.
struct SchemaFieldView: View {
    let spec: ConfigFieldSpec
    let settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            control
            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let help = spec.help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch spec.kind {
        case .string:
            TextField(spec.label, text: settings.stringBinding(spec.path), prompt: prompt)
        case .secret:
            SecretField(label: spec.label, text: settings.stringBinding(spec.path))
        case .bool(let defaultOn):
            Toggle(spec.label, isOn: settings.boolBinding(spec.path, defaultOn: defaultOn))
        case .path:
            PathField(label: spec.label, text: settings.stringBinding(spec.path), prompt: prompt)
        case .stringList:
            StringListField(label: spec.label, path: spec.path,
                            placeholder: spec.placeholder, settings: settings)
        case .choice(let options):
            Picker(spec.label, selection: settings.stringBinding(spec.path)) {
                Text("Standard").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        case .color:
            ColorField(label: spec.label, hex: settings.stringBinding(spec.path))
        case .number(let min, let max):
            NumberField(label: spec.label, path: spec.path, min: min, max: max,
                        placeholder: spec.placeholder, settings: settings)
        case .choiceFromKeys(let keysPath):
            // Die Optionen stehen in der Datei, nicht im Schema. Ein Name, den es dort nicht (mehr)
            // gibt, bleibt trotzdem in der Liste — sonst stünde die Auswahl leer da, obwohl in der
            // Config etwas steht, und niemand sähe, was.
            let gesetzt = settings.stringValue(at: spec.path)
            let namen = settings.keys(at: keysPath)
            Picker(spec.label, selection: settings.stringBinding(spec.path)) {
                Text("Standard").tag("")
                ForEach(namen, id: \.self) { Text($0).tag($0) }
                if !gesetzt.isEmpty && !namen.contains(gesetzt) {
                    Text("\(gesetzt) — gibt es nicht mehr").tag(gesetzt)
                }
            }
        }
    }

    private var prompt: Text? { spec.placeholder.map(Text.init) }

    /// Reads the current value (tracked, so the warning updates live) and validates it.
    private var validationError: String? {
        switch spec.kind {
        case .string, .path, .secret:
            return spec.validation.error(for: settings.stringValue(at: spec.path))
        default:
            return nil
        }
    }
}

/// Zahl mit Grenzen, geschrieben als JSON-**Zahl**.
///
/// Eigenes Bauteil, weil so ein Feld drei Zustände hat: leer (= Vorgabe), unfertig getippt und
/// fertig. Deshalb hält es seinen Text selbst und zieht erst beim Verlassen auf die Grenzen — wer
/// „1" tippt, um „16" zu schreiben, soll nicht nach dem ersten Zeichen bei 8 stehen.
struct NumberField: View {
    let label: String
    let path: [String]
    let min: Double
    let max: Double
    var placeholder: String?
    let settings: SettingsModel

    @State private var text = ""
    @State private var geladen = false
    @FocusState private var fokussiert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(label)
                Spacer(minLength: 8)
                TextField("", text: $text, prompt: placeholder.map(Text.init))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .focused($fokussiert)
                    .onSubmit(uebernehmen)
                Text("pt").font(.caption).foregroundStyle(.secondary)
            }
            if let hinweis {
                Text(hinweis).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear {
            guard !geladen else { return }
            text = settings.numberText(at: path)
            geladen = true
        }
        .onChange(of: text) { settings.setNumber(path, from: text) }
        .onChange(of: fokussiert) { _, jetzt in if !jetzt { uebernehmen() } }
    }

    private var hinweis: String? {
        let getrimmt = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !getrimmt.isEmpty else { return nil }
        guard let zahl = Double(getrimmt) else { return "Keine Zahl — der Wert wird nicht übernommen." }
        guard zahl < min || zahl > max else { return nil }
        return "Ausserhalb \(SettingsModel.zahlText(min))–\(SettingsModel.zahlText(max)) — "
             + "wird beim Verlassen darauf gezogen."
    }

    private func uebernehmen() {
        settings.clampNumber(path, min: min, max: max)
        text = settings.numberText(at: path)
    }
}

/// SecureField with a reveal toggle for API tokens.
struct SecretField: View {
    let label: String
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 6) {
            if revealed {
                TextField(label, text: $text)
            } else {
                SecureField(label, text: $text)
            }
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(revealed ? "Token verbergen" : "Token anzeigen")
        }
    }
}

/// Text field for a filesystem path plus a directory picker.
struct PathField: View {
    let label: String
    @Binding var text: String
    var prompt: Text?

    var body: some View {
        HStack(spacing: 6) {
            TextField(label, text: $text, prompt: prompt)
            Button("Wählen…") { choose() }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !text.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = url.path
        if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
        text = path
    }
}

/// Comma-separated editor for a JSON string array. Keeps its own text state so typing a trailing
/// comma isn't normalized away mid-keystroke; the model is updated on every change.
struct StringListField: View {
    let label: String
    let path: [String]
    var placeholder: String?
    let settings: SettingsModel
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField(label, text: $text, prompt: placeholder.map(Text.init))
            .onAppear {
                guard !loaded else { return }
                text = settings.stringListText(path)
                loaded = true
            }
            .onChange(of: text) {
                settings.setStringList(path, from: text)
            }
    }
}
