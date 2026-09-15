import SwiftUI
import KanbanCore

/// Editor for a per-project map (`modules.<m>.projects.<key>.{…}`) with user-defined keys:
/// one disclosure per project, add/remove, and the module's sub-fields inside.
struct ProjectMapEditor: View {
    let spec: ProjectMapSpec
    let settings: SettingsModel
    @State private var newKey = ""

    var body: some View {
        Section(spec.title) {
            ForEach(settings.projectKeys(at: spec.path), id: \.self) { key in
                DisclosureGroup {
                    ForEach(spec.fields) { field in
                        VStack(alignment: .leading, spacing: 3) {
                            fieldControl(field, key: key)
                            if let help = field.help {
                                Text(help).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Projekt entfernen", role: .destructive) {
                        settings.removeProject(at: spec.path, key: key)
                    }
                } label: {
                    Text(key)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            }

            HStack(spacing: 8) {
                TextField("Neues Projekt", text: $newKey, prompt: Text(spec.keyPlaceholder))
                    .onSubmit(add)
                Button("Hinzufügen", action: add)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func fieldControl(_ field: ProjectFieldSpec, key: String) -> some View {
        let path = spec.path + [key, field.key]
        switch field.kind {
        case .string:
            TextField(label(for: field), text: settings.stringBinding(path),
                      prompt: field.placeholder.map(Text.init))
        case .secret:
            SecretField(label: label(for: field), text: settings.stringBinding(path))
        case .stringList:
            StringListField(label: label(for: field), path: path,
                            placeholder: field.placeholder, settings: settings)
        case .choice(let options):
            // Wie beim gleichnamigen Feld auf Modul-Ebene: „Standard" schreibt den Schlüssel nicht.
            Picker(label(for: field), selection: settings.stringBinding(path)) {
                Text("Standard").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private func add() {
        settings.addProject(at: spec.path, key: newKey)
        newKey = ""
    }

    private func label(for field: ProjectFieldSpec) -> String {
        field.required ? field.label : "\(field.label) (optional)"
    }
}
