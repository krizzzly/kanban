import SwiftUI
import KanbanCore

/// Der eine Ort, an dem ein Projekt **angelegt** wird (HERMES-043).
///
/// Gepflegt wird weiter in den Modul-Bereichen — die bleiben die Wahrheit. Zentral ist nur, was
/// verstreut wehtut: ein neues Projekt in sechs `projects`-Sections eintragen, ohne eine zu
/// vergessen. Die Werte kommen vorausgefüllt aus den Mustern der bestehenden Projekte.
struct ProjectsEditor: View {
    let settings: SettingsModel

    @State private var newKey = ""
    @State private var draft = ProjectRecord()
    @State private var removalCandidate: String?

    var body: some View {
        Form {
            Section {
                Text("Ein neues Projekt wird hier einmal erfasst und landet in allen betroffenen "
                     + "Modul-Bereichen. Zum Ändern einzelner Werte den jeweiligen Bereich nutzen — "
                     + "Jira, GitLab, Confluence, Vertec, Jenkins, DockerHub.")
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
        if record.prefix != nil { badges.append("Jira") }
        if record.gitlab != nil { badges.append("GitLab") }
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
                    TextField("Ticket-Präfix", text: binding(\.prefix), prompt: Text("EVEN"))
                    TextField("Tasks-Pfad", text: binding(\.tasksPath),
                              prompt: Text("even/docs/tasks"))
                    TextField("Repo-Ordner (optional)", text: binding(\.repoDir),
                              prompt: Text("leer = erstes Segment des Tasks-Pfads"))
                    TextField("Jira-Host (nur bei Abweichung)", text: binding(\.jiraBaseUrl),
                              prompt: Text("https://andere-instanz.atlassian.net"))
                }

                group("GitLab") {
                    TextField("Projekt-Pfad", text: optional(
                        get: { $0.gitlab?.path },
                        set: { record, value in record.gitlab = value.map { .init(path: $0) } }),
                              prompt: Text("applications/even"))
                }

                group("Confluence") {
                    TextField("Space-Key", text: optional(
                        get: { $0.confluence?.space },
                        set: { record, value in
                            record.confluence = adjust(record.confluence, .init()) { $0.space = value }
                        }), prompt: Text("EVEN"))
                    TextField("Wissens-Pfad", text: optional(
                        get: { $0.confluence?.path },
                        set: { record, value in
                            record.confluence = adjust(record.confluence, .init()) { $0.path = value }
                        }), prompt: Text("even/docs/kb"))
                }

                group("Vertec") {
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

                group("Jenkins") {
                    TextField("Jobs (kommagetrennt)", text: Binding(
                        get: { draft.jenkins?.jobs.joined(separator: ", ") ?? "" },
                        set: { text in
                            let jobs = text.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            draft.jenkins = jobs.isEmpty ? nil : .init(jobs: jobs)
                        }), prompt: Text("even - DEV - Build"))
                }

                group("DockerHub") {
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
                        settings.createProject(key: trimmedKey, record: draft)
                        newKey = ""
                        draft = ProjectRecord()
                    }
                    .disabled(draft.isEmpty)
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

    /// Ändert einen Modul-Block und wirft ihn weg, sobald er leer ist — ein leerer Block würde sonst
    /// einen leeren Eintrag in der Config erzeugen. `empty` ist der Vergleichswert *und* der
    /// Startwert, wenn es den Block noch nicht gibt.
    private func adjust<T: Equatable>(_ block: T?, _ empty: T,
                                      _ change: (inout T) -> Void) -> T? {
        var value = block ?? empty
        change(&value)
        return value == empty ? nil : value
    }
}
