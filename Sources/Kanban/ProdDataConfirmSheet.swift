import SwiftUI
import KanbanCore

/// Bestätigung vor `/get-task` und `/start-task`: beide holen den Jira-Inhalt in die KI, und was
/// dabei mitkommt, weiss nur der Mensch. Deshalb hängt der Command an einer bewussten Zusicherung
/// statt an einem Klick — die Checkbox muss gesetzt sein, sonst bleibt der Knopf aus (und damit
/// auch Enter, das sonst reflexhaft durchgeht).
///
/// `start-task` ist mit dabei, obwohl es selbst nichts lädt: fehlt das Task-File, ruft es
/// `get-task` auf und holt das Ticket doch (siehe `AppModel.prodConfirmCommands`).
struct ProdDataConfirmSheet: View {
    let model: AppModel
    let pending: PendingProdConfirmation

    @State private var confirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keine PROD-Daten verarbeiten")
                        .font(.app(.headline))
                    Text(pending.invocation)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("Der Command holt den Ticket-Inhalt aus Jira in die Claude-Console. Prüfe "
                         + "vorher, dass darin — auch in Beschreibung, Kommentaren und Anhängen — "
                         + "keine Produktivdaten stehen.")
                        .font(.app(.callout))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: $confirmed) {
                Text("Ich bestätige, dass ich keine PROD-Daten von der KI verarbeiten lasse.")
                    .font(.app(.callout))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            Text("Der Command wird nur in die Console eingetragen, nicht abgeschickt — Enter drückst "
                 + "du dort selbst.")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Abbrechen") { model.cancelProdCommand() }
                    .keyboardShortcut(.cancelAction)
                Button("Bestätigen und eintragen") { model.confirmProdCommand() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!confirmed)
            }
        }
        .padding(18)
        .frame(width: 520)
    }
}
