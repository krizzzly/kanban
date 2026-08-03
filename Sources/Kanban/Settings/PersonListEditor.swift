import SwiftUI
import KanbanCore

/// Editor for `modules.{whatsapp,telegram}.people[]` — contacts with optional per-contact
/// assistant name and an auto-reply toggle + prompt. The identifier field (number/username)
/// is module-specific (see `PersonListSpec`).
struct PersonListEditor: View {
    let spec: PersonListSpec
    let settings: SettingsModel

    var body: some View {
        Section("Kontakte") {
            ForEach(0..<settings.arrayCount(spec.path), id: \.self) { index in
                DisclosureGroup {
                    TextField(spec.identifierLabel,
                              text: settings.elementStringBinding(spec.path, index, [spec.identifierKey]),
                              prompt: Text(spec.identifierPlaceholder))
                    aliasesField(index: index)
                    TextField("Assistent-Name (optional)",
                              text: settings.elementStringBinding(spec.path, index, ["assistantName"]))

                    Toggle("Auto-Reply aktiv",
                           isOn: settings.elementBoolBinding(spec.path, index, ["autoReply", "enabled"],
                                                             defaultOn: false))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Auto-Reply-Prompt").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: settings.elementStringBinding(spec.path, index, ["autoReply", "prompt"]))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 54)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
                    }

                    Button("Kontakt entfernen", role: .destructive) {
                        settings.removeArrayObject(spec.path, at: index)
                    }
                } label: {
                    Text(nameOrPlaceholder(index)).font(.system(size: 13, weight: .medium))
                }
            }

            Button {
                settings.appendArrayObject(spec.path, .object(["name": .string("")]))
            } label: {
                Label("Kontakt hinzufügen", systemImage: "plus")
            }
        }
    }

    private func aliasesField(index: Int) -> some View {
        // Aliases live as a string array on the element; reuse the comma-separated editor.
        AliasesField(
            get: { settings.elementStringListText(spec.path, index, ["aliases"]) },
            set: { settings.setElementStringList(spec.path, index, ["aliases"], from: $0) })
    }

    private func nameOrPlaceholder(_ index: Int) -> String {
        let name = settings.elementStringBinding(spec.path, index, ["name"]).wrappedValue
        return name.isEmpty ? "(neuer Kontakt)" : name
    }
}

/// The "Name" DisclosureGroup label needs the live name; contacts also carry a comma-separated
/// alias list. Kept as a tiny stateful field so trailing commas aren't normalized mid-typing.
private struct AliasesField: View {
    let get: () -> String
    let set: (String) -> Void
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField("Aliase (kommagetrennt)", text: $text, prompt: Text("chef, boss"))
            .onAppear { if !loaded { text = get(); loaded = true } }
            .onChange(of: text) { set(text) }
    }
}
