import AppKit
import SwiftUI
import KanbanCore

/// Die Profil-Übersicht: welche Welten es gibt, welche gerade gilt, und der Weg von einer zur
/// anderen.
///
/// **Die Schriftgrössen sind die der Einstellungen — 13 pt ist die Obergrenze** (dieselbe Messung
/// wie in `ClaudeWorkflowSettingsView`: eine Zeile einer gruppierten `Form` rendert als `.body`).
/// Name und Erklärtexte 13, Pfade 11, das „aktiv"-Abzeichen 10.
///
/// Sie schreibt **sofort**, nicht über den Speichern-Fuss — wie die Skill-Sets daneben und aus
/// demselben Grund: ein Profilwechsel stellt Fenster um und hängt Symlinks um, das lässt sich nicht
/// vormerken.
struct ProfilesSettingsView: View {
    @State private var liste: [KanbanProfile] = []
    @State private var aktiv: String = ""
    @State private var fehler: String?
    @State private var neuerName = ""
    @State private var legtAn = false
    @State private var benenntUm: KanbanProfile?
    @State private var neuerAnzeigename = ""
    @State private var entfernt: KanbanProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hinweis
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let fehler { fehlerzeile(fehler) }
                    if let ladefehler = ProfileStore.lastError {
                        fehlerzeile("profiles.json ist unlesbar (\(ladefehler)) — es gilt das "
                                  + "Vorgabe-Profil.")
                    }
                    ForEach(liste) { profil in zeile(profil) }
                }
                .padding(12)
            }
            Divider()
            fuss
        }
        .onAppear(perform: laden)
        .alert("Profil umbenennen", isPresented: Binding(get: { benenntUm != nil },
                                                         set: { if !$0 { benenntUm = nil } })) {
            TextField("Name", text: $neuerAnzeigename)
            Button("Abbrechen", role: .cancel) { benenntUm = nil }
            Button("Umbenennen") { umbenennen() }
        } message: {
            Text("Der interne Kurzname bleibt unverändert — er steckt in gemerkten Auswahlen und in "
               + "den Namen laufender Terminal-Sitzungen.")
        }
        .alert("Profil entfernen?", isPresented: Binding(get: { entfernt != nil },
                                                         set: { if !$0 { entfernt = nil } })) {
            Button("Abbrechen", role: .cancel) { entfernt = nil }
            Button("Entfernen", role: .destructive) { entfernen() }
        } message: {
            Text("Entfernt wird nur der Eintrag. Der Ordner \(entfernt?.path ?? "") bleibt "
               + "unangetastet stehen — mit Config, Task-Files und gebuchten Zeiten.")
        }
    }

    // MARK: - Teile

    private var hinweis: some View {
        Label {
            Text("Ein Profil ist eine ganze Kanban-Welt: eigene Zugänge, Projekte, Task-Files und "
               + "Einstellungen. Änderungen hier wirken **sofort**.")
        } icon: {
            Image(systemName: "bolt.circle")
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func zeile(_ profil: KanbanProfile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: profil.slug == aktiv ? "person.crop.circle.fill" : "person.crop.circle")
                .foregroundStyle(profil.slug == aktiv ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profil.name).font(.body)
                    if profil.slug == aktiv { abzeichen("aktiv") }
                    if profil.isDefault { abzeichen("gewachsener Bestand") }
                }
                Text(kurz(profil.path)).font(.system(size: 11)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if profil.slug != aktiv {
                Button("Wechseln") { wechseln(profil) }
            }
            Menu {
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([profil.folder])
                }
                Button("Umbenennen…") {
                    neuerAnzeigename = profil.name
                    benenntUm = profil
                }
                Divider()
                Button("Aus der Liste entfernen…", role: .destructive) { entfernt = profil }
                    .disabled(liste.count < 2)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
    }

    private func abzeichen(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
    }

    private func fehlerzeile(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.body).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fuss: some View {
        HStack(spacing: 8) {
            if legtAn {
                TextField("Name des Profils", text: $neuerName)
                    .frame(width: 220)
                    .onSubmit(anlegen)
                Button("Anlegen", action: anlegen)
                    .disabled(neuerName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Abbrechen") { legtAn = false; neuerName = "" }
            } else {
                Button("Neues Profil…") { legtAn = true }
                Text("Startet leer — es wird nichts aus einem anderen Profil übernommen.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    // MARK: - Aktionen

    private func laden() {
        let stand = ProfileStore.load()
        liste = stand.profiles
        aktiv = stand.activeProfile?.slug ?? stand.active
    }

    private func anlegen() {
        let name = neuerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        tue { _ = try ProfileStore.create(name: name) }
        legtAn = false
        neuerName = ""
    }

    private func umbenennen() {
        guard let profil = benenntUm else { return }
        tue { try ProfileStore.rename(slug: profil.slug, to: neuerAnzeigename) }
        benenntUm = nil
    }

    private func entfernen() {
        guard let profil = entfernt else { return }
        tue { try ProfileStore.remove(slug: profil.slug) }
        entfernt = nil
    }

    private func wechseln(_ profil: KanbanProfile) {
        // Über das Model, nicht direkt: nur dort steht die Rückfrage, wenn irgendwo ein Turn läuft.
        ProjectWindows.shared.profilWechselnLassen(profil)
        laden()
    }

    /// Schreibt und liest neu — und hält den Fehler fest, statt ihn zu verschlucken.
    private func tue(_ aktion: () throws -> Void) {
        do {
            try aktion()
            fehler = nil
        } catch {
            fehler = error.localizedDescription
        }
        laden()
        ProjectWindows.shared.profileNeuLesen()
    }

    private func kurz(_ pfad: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return pfad.hasPrefix(home) ? "~" + pfad.dropFirst(home.count) : pfad
    }
}
