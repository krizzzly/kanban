import SwiftUI
import KanbanCore

/// Der eine Ort, an dem ein Projekt **angelegt** wird (HERMES-043).
///
/// Gepflegt wird danach in den Modul-Bereichen. Zentral ist nur, was verstreut wehtut: ein neues
/// Projekt in mehreren `projects`-Sections eintragen, ohne eine zu vergessen. Die Werte kommen
/// vorausgefüllt aus den Mustern der bestehenden Projekte.
///
/// Warum hier auch Confluence, Vertec, Jenkins und DockerHub stehen, obwohl Kanban nur Jira und
/// GitLab betreibt: `HermesSync` projiziert die Projektliste in eine vorhandene Hermes-Config, und
/// dort gibt es diese Module. Ohne Hermes bleiben die Felder einfach leer.
struct ProjectsEditor: View {
    let settings: SettingsModel

    @State private var newKey = ""
    @State private var draft = ProjectRecord()
    /// Was ein abgeschaltetes Modul zuletzt enthielt. Ohne das wäre ein versehentlich umgelegter
    /// Schalter ein Datenverlust — so kommt beim Wiedereinschalten zurück, was dastand (Vorschlag
    /// oder selbst getippt), statt eines leeren Blocks.
    @State private var geparkt = ProjectRecord()
    @State private var removalCandidate: String?

    var body: some View {
        Form {
            Section {
                Text("Ein neues Projekt wird hier einmal erfasst und landet in allen betroffenen "
                     + "Modul-Bereichen. Zum Ändern einzelner Werte den jeweiligen Bereich nutzen. "
                     + "Confluence, Vertec, Jenkins und DockerHub kennt nur Hermes — diese Werte "
                     + "wandern beim Speichern dorthin (siehe Bereich „Hermes“).")
                    .font(.callout).foregroundStyle(.secondary)
            }

            existingSection
            newProjectSection
        }
        .formStyle(.grouped)
        .confirmationDialog("Projekt entfernen?",
                            isPresented: Binding(get: { removalCandidate != nil },
                                                 set: { if !$0 { removalCandidate = nil } }),
                            presenting: removalCandidate) { key in
            Button("„\(key)“ überall entfernen", role: .destructive) {
                settings.removeProjectEverywhere(key: key)
                removalCandidate = nil
            }
            Button("Abbrechen", role: .cancel) { removalCandidate = nil }
        } message: { key in
            Text("Entfernt „\(key)“ aus allen Modul-Bereichen. Task-Files und Repos bleiben "
                 + "unangetastet.")
        }
    }

    // MARK: - Bestand

    private var existingSection: some View {
        Section("Projekte") {
            let overview = settings.projectOverview
            if overview.keys.isEmpty {
                Text("Noch keine Projekte konfiguriert.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(overview.keys, id: \.self) { key in
                if let record = overview[key] { row(key: key, record: record) }
            }
        }
    }

    private func row(key: String, record: ProjectRecord) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(key).font(.system(size: 13, weight: .medium, design: .monospaced))
                    if let prefix = record.prefix {
                        Text(prefix).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(badges(for: record), id: \.self) { badge in
                        Text(badge)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
            Spacer()
            Button {
                removalCandidate = key
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("„\(key)“ aus allen Modul-Bereichen entfernen")
        }
        .padding(.vertical, 2)
    }

    /// Auf einen Blick, in welchen Modulen das Projekt überhaupt konfiguriert ist — das war bisher
    /// nur durch Blättern durch sechs Bereiche zu sehen.
    private func badges(for record: ProjectRecord) -> [String] {
        var badges: [String] = []
        // Der Präfix allein sagt nicht mehr „Jira": ein Projekt ohne Anbindung hat ihn auch, nur
        // steht dahinter kein Board. „lokal" ist hier die ehrlichere Auskunft.
        if record.prefix != nil { badges.append(record.usesJira == false ? "lokal" : "Jira") }
        if record.gitlab != nil { badges.append("GitLab") }
        if record.github != nil { badges.append("GitHub") }
        if record.confluence != nil { badges.append("Confluence") }
        if record.vertec != nil { badges.append("Vertec") }
        if record.jenkins != nil { badges.append("Jenkins") }
        if record.dockerhub != nil { badges.append("DockerHub") }
        return badges
    }

    // MARK: - Neues Projekt

    private var trimmedKey: String { newKey.trimmingCharacters(in: .whitespaces) }
    private var keyTaken: Bool { settings.isProjectKeyTaken(trimmedKey) }

    private var newProjectSection: some View {
        Section("Neues Projekt") {
            TextField("Projekt-Key", text: $newKey, prompt: Text("even"))
                .onChange(of: newKey) { _, key in
                    draft = settings.projectSuggestion(for: key)
                    geparkt = ProjectRecord()   // die Parkplätze gehören zum alten Key
                }
            if keyTaken {
                Label("Diesen Key gibt es schon.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            if !trimmedKey.isEmpty && !keyTaken {
                Text("Vorgeschlagen aus den Mustern der bestehenden Projekte — bitte prüfen. "
                     + "Leere Felder werden nicht geschrieben.")
                    .font(.caption).foregroundStyle(.secondary)

                group("Grunddaten") {
                    // Steht vor allem anderen, weil es die Felder darunter umdeutet: aus ist das
                    // Projekt rein lokal, und der Jira-Host darunter läuft ins Leere.
                    Toggle("An Jira angebunden", isOn: Binding(
                        get: { draft.usesJira ?? true },
                        set: { draft.usesJira = $0 ? nil : false }))
                    if draft.usesJira == false {
                        Text("Ohne Jira: kein Board, keine Sprints, keine Worklog-Buchung. Das "
                             + "Board zeigt nur den freien Modus aus Task-Files, Worktrees und "
                             + "Merge Requests. Der Ticket-Präfix wird trotzdem gebraucht — er "
                             + "benennt Task-Files und Branches.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Ticket-Präfix", text: binding(\.prefix), prompt: Text("EVEN"))
                    TextField("Tasks-Pfad", text: binding(\.tasksPath),
                              prompt: Text("…/Kanban/tasks/even"))
                    TextField("Repo-Ordner (optional)", text: binding(\.repoDir),
                              prompt: Text("leer = erstes Segment des Tasks-Pfads"))
                    TextField("Jira-Host (nur bei Abweichung)", text: binding(\.jiraBaseUrl),
                              prompt: Text("https://andere-instanz.atlassian.net"))
                }

                // Genau **eine** Forge je Projekt: den jeweils anderen Block gibt es nur, solange
                // dieser leer ist. Ein Projekt in beiden Abschnitten lehnt `KanbanConfig` beim Laden
                // ab — es hier gar nicht erst anlegen zu lassen ist die freundlichere Fassung
                // derselben Regel.
                if draft.github == nil {
                    modul("GitLab", \.gitlab, leer: .init(path: "")) {
                        TextField("Projekt-Pfad", text: optional(
                            get: { $0.gitlab?.path },
                            set: { record, value in record.gitlab = .init(path: value ?? "") }),
                                  prompt: Text("applications/even"))
                    }
                }

                if draft.gitlab == nil {
                    modul("GitHub", \.github, leer: .init(path: "")) {
                        TextField("Repository", text: optional(
                            get: { $0.github?.path },
                            set: { record, value in record.github = .init(path: value ?? "") }),
                                  prompt: Text("owner/repo"))
                    }
                }

                modul("Confluence", \.confluence, leer: .init()) {
                    TextField("Space-Key", text: optional(
                        get: { $0.confluence?.space },
                        set: { record, value in
                            record.confluence = adjust(record.confluence, .init()) { $0.space = value }
                        }), prompt: Text("EVEN"))
                    TextField("Wissens-Pfad", text: optional(
                        get: { $0.confluence?.path },
                        set: { record, value in
                            record.confluence = adjust(record.confluence, .init()) { $0.path = value }
                        }), prompt: Text("…/Kanban/docs/even"))
                }

                modul("Vertec", \.vertec, leer: .init()) {
                    TextField("Projekt", text: optional(
                        get: { $0.vertec?.project },
                        set: { record, value in
                            record.vertec = adjust(record.vertec, .init()) { $0.project = value }
                        }), prompt: Text("8100 - EVEN Basisprodukt"))
                    TextField("Phase", text: optional(
                        get: { $0.vertec?.phase },
                        set: { record, value in
                            record.vertec = adjust(record.vertec, .init()) { $0.phase = value }
                        }), prompt: Text("WEITERENTWICKLUNGEN 2026"))
                    TextField("Task", text: optional(
                        get: { $0.vertec?.task },
                        set: { record, value in
                            record.vertec = adjust(record.vertec, .init()) { $0.task = value }
                        }), prompt: Text("PROGRAMMIERUNG"))
                }

                modul("Jenkins", \.jenkins, leer: .init(jobs: [])) {
                    TextField("Jobs (kommagetrennt)", text: Binding(
                        get: { draft.jenkins?.jobs.joined(separator: ", ") ?? "" },
                        set: { text in
                            let jobs = text.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            draft.jenkins = jobs.isEmpty ? nil : .init(jobs: jobs)
                        }), prompt: Text("even - DEV - Build"))
                }

                modul("DockerHub", \.dockerhub, leer: .init()) {
                    TextField("Namespace", text: optional(
                        get: { $0.dockerhub?.namespace },
                        set: { record, value in
                            record.dockerhub = adjust(record.dockerhub, .init()) { $0.namespace = value }
                        }), prompt: Text("iwfwebsolutions"))
                    TextField("Repository", text: optional(
                        get: { $0.dockerhub?.repository },
                        set: { record, value in
                            record.dockerhub = adjust(record.dockerhub, .init()) { $0.repository = value }
                        }), prompt: Text("even"))
                }

                HStack {
                    Spacer()
                    Button("Projekt anlegen") {
                        settings.createProject(key: trimmedKey,
                                               record: draft.strippingEmptyModules())
                        newKey = ""
                        draft = ProjectRecord()
                        geparkt = ProjectRecord()
                    }
                    .disabled(draft.strippingEmptyModules().isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(.top, 4)
    }

    /// Eine Modulgruppe mit Schalter: an heisst „dieses Projekt hat den Block", aus heisst „gar
    /// nicht erst anlegen".
    ///
    /// Vorher entschied das die Frage, ob zufällig ein Feld ausgefüllt war — und weil die Vorschläge
    /// aus den bestehenden Projekten **alle** Module vorfüllen, musste man wegräumen, was man nicht
    /// wollte. Der Schalter dreht das um: er steht von sich aus so, wie der Vorschlag es meint, und
    /// ein Klick nimmt das ganze Modul heraus.
    ///
    /// Die Felder verschwinden mit — ein abgeschaltetes Modul, das noch Eingabefelder zeigt, wäre
    /// eine Einladung, ins Leere zu tippen.
    @ViewBuilder
    private func modul<T, Content: View>(_ title: String,
                                         _ keyPath: WritableKeyPath<ProjectRecord, T?>,
                                         leer: T,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { draft[keyPath: keyPath] != nil },
                set: { an in
                    if an {
                        draft[keyPath: keyPath] = geparkt[keyPath: keyPath] ?? leer
                    } else {
                        geparkt[keyPath: keyPath] = draft[keyPath: keyPath]
                        draft[keyPath: keyPath] = nil
                    }
                })) {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            if draft[keyPath: keyPath] != nil { content() }
        }
        .padding(.top, 4)
    }

    // MARK: - Bindings auf den Entwurf

    private func binding(_ keyPath: WritableKeyPath<ProjectRecord, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = normalize($0) })
    }

    /// Für verschachtelte Felder: Getter/Setter statt Key-Path, weil Swift keine schreibbaren
    /// Key-Paths durch Optional-Chaining kennt.
    private func optional(get: @escaping (ProjectRecord) -> String?,
                          set: @escaping (inout ProjectRecord, String?) -> Void) -> Binding<String> {
        Binding(
            get: { get(draft) ?? "" },
            set: { text in set(&draft, normalize(text)) })
    }

    private func normalize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Ändert einen Modul-Block. Ob es ihn **gibt**, entscheidet seit den Modulschaltern allein der
    /// Schalter — deshalb wird hier nichts mehr weggeworfen, auch kein leer getippter Block.
    ///
    /// Täte er es weiter, spränge der Schalter beim Leeren des letzten Feldes von selbst auf „aus"
    /// und das halb ausgefüllte Modul wäre verschwunden. Leere Blöcke fängt stattdessen
    /// `strippingEmptyModules()` beim Anlegen ab — einmal, am Ende, statt bei jedem Tastendruck.
    private func adjust<T: Equatable>(_ block: T?, _ empty: T,
                                      _ change: (inout T) -> Void) -> T? {
        var value = block ?? empty
        change(&value)
        return value
    }
}
