import SwiftUI
import KanbanCore

/// Editor for `modules.vertec.presence[]` — a list of {from, to, text?} work-hour blocks.
struct PresenceListEditor: View {
    let spec: PresenceListSpec
    let settings: SettingsModel

    var body: some View {
        Section("Präsenz-Blöcke") {
            ForEach(0..<settings.arrayCount(spec.path), id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        timeField("Von", index: index, key: "from")
                        timeField("Bis", index: index, key: "to")
                        Spacer()
                        Button(role: .destructive) {
                            settings.removeArrayObject(spec.path, at: index)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    TextField("Beschreibung (optional)",
                              text: settings.elementStringBinding(spec.path, index, ["text"]))
                }
                .padding(.vertical, 2)
            }

            Button {
                settings.appendArrayObject(spec.path, .object(["from": .string("09:00"), "to": .string("12:00")]))
            } label: {
                Label("Block hinzufügen", systemImage: "plus")
            }
        }
    }

    private func timeField(_ label: String, index: Int, key: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            TextField("HH:MM", text: settings.elementStringBinding(spec.path, index, [key]))
                .frame(width: 64)
                .multilineTextAlignment(.center)
        }
    }
}
