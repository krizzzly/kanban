import AppKit
import SwiftUI
import KanbanCore

/// Die Skill-Set-Übersicht: welche Sets es gibt, welches Projekt an welchem hängt, und ob die
/// Verlinkung wirklich steht.
///
/// Sie zeigt und stellt her — mehr nicht. Bearbeitet werden die Sets in ihrem Ordner
/// (`claude.setsPath`, per Vorgabe das Kanban-Repo), und **genau dieser Ordner** ist das Ziel der
/// Symlinks: eine Änderung wirkt sofort, ohne Zutun dieses Fensters. Der frühere Editor mit
/// Anlegen, Einlesen, Zurücksetzen und Fassungen baute daneben ein zweites, schwächeres Git.
@Observable
final class ClaudeWorkflowModel {
    /// Ein Projekt an einem Set, mit dem Zustand seiner Verlinkung.
    struct Verlinkung: Identifiable {
        let project: ProjectConfig
        let state: ClaudeSymlinkState
        /// Das Projekt nennt ein Set, das es nicht (mehr) gibt — hier steht sein Name.
        let missingName: String?
        /// Kein Repo-Ordner: es gibt keinen Ort, an den verlinkt werden könnte.
        let repoMissing: Bool
        /// Andere Projekte, die sich dasselbe Repo teilen — sie teilen sich auch `<repo>/.claude/`.
        let sharesRepoWith: [String]

        var id: String { project.key }
    }

    private var store = ClaudeAssetStore.configured()

    private(set) var sets: [ClaudeAssetSet] = []
    /// Wo die Sets liegen — und ob der Ordner überhaupt da ist. Das ist der eine Preis der
    /// direkten Verlinkung: ein verschobenes Repo nimmt jedem Projekt seine Skills.
    private(set) var setsRoot = ""
    private(set) var setsRootMissing = false
    private(set) var verlinkungen: [String: [Verlinkung]] = [:]   // Set-Name → Projekte
    private(set) var defaultSetName: String?
    /// Steht kein Standard-Set in der Config, gilt trotzdem eins — aber entschieden hat das niemand.
    private(set) var defaultIsImplicit = false
    private(set) var message: String?

    func load() {
        let config = try? KanbanConfig.load()
        store = .configured()
        setsRoot = store.setsRoot.path
        setsRootMissing = !store.setsRootExists

        sets = store.sets()
        let standard = store.defaultSet(configured: config?.defaultSkillSet)
        defaultSetName = standard?.name
        defaultIsImplicit = config?.defaultSkillSet == nil && sets.count > 1

        let projects = config?.projects ?? []
        var gruppen: [String: [Verlinkung]] = [:]
        for project in projects {
            let resolution = store.resolve(skillSet: project.skillSet,
                                           default: config?.defaultSkillSet)
            guard let set = resolution.set else { continue }
            let repoDa = FileManager.default.fileExists(atPath: project.repoDir)
            let state = repoDa
                ? store.state(of: set, scope: .project(repoDir: project.repoDir,
                                                       agent: project.agent))
                : ClaudeSymlinkState.notInstalled
            gruppen[set.name, default: []].append(Verlinkung(
                project: project,
                state: state,
                missingName: resolution.missingName,
                repoMissing: !repoDa,
                sharesRepoWith: projects
                    .filter { $0.key != project.key && $0.repoDir == project.repoDir }
                    .map(\.key)))
        }
        verlinkungen = gruppen.mapValues { $0.sorted { $0.project.key < $1.project.key } }
    }

    func assetCount(_ set: ClaudeAssetSet, _ kind: ClaudeAssetKind) -> Int {
        store.assets(kind, in: set).count
    }

    func isDefault(_ set: ClaudeAssetSet) -> Bool { set.name == defaultSetName }

    // MARK: Verlinken

    /// Stellt die Verlinkung eines Projekts her. Fremde Zielorte werden gemeldet, nie überschrieben.
    func verlinke(_ verlinkung: Verlinkung) {
        let config = try? KanbanConfig.load()
        guard let report = ClaudeAssetFactory.link(verlinkung.project,
                                                   defaultSkillSet: config?.defaultSkillSet) else {
            message = "\(verlinkung.project.key): kein Repo-Ordner unter "
                    + "\(abbreviateHome(verlinkung.project.repoDir)) — nichts zu verlinken."
            return
        }
        message = melde([report], titel: verlinkung.project.key)
        load()
    }

    /// Alle Projekte auf einmal — plus das Standard-Set in die Agent-Homes, damit auch eine Console
    /// ausserhalb eines Projekts etwas sieht.
    func verlinkeAlle() {
        let config = try? KanbanConfig.load()
        var reports: [ClaudeLinkReport] = []
        for project in config?.projects ?? [] {
            if let report = ClaudeAssetFactory.link(project,
                                                    defaultSkillSet: config?.defaultSkillSet) {
                reports.append(report)
            }
        }
        if let standard = store.defaultSet(configured: config?.defaultSkillSet) {
            reports += store.link(standard, toHomes: AgentKind.allCases).values
        }
        message = melde(reports, titel: "Alle Projekte")
        load()
    }

    private func melde(_ reports: [ClaudeLinkReport], titel: String) -> String {
        let verlinkt = reports.reduce(0) { $0 + $1.linked.count }
        let fremd = reports.flatMap(\.foreign).count
        let weg = reports.reduce(0) { $0 + $1.removed.count }
        var text = "\(titel): \(verlinkt) verlinkt"
        if weg > 0 { text += ", \(weg) aus einem früheren Set aufgeräumt" }
        if fremd > 0 { text += " — \(fremd) Zielort(e) übersprungen, dort liegt etwas Fremdes" }
        return text + "."
    }

    // MARK: Wege nach draussen

    func zeigeImFinder(_ set: ClaudeAssetSet) {
        NSWorkspace.shared.activateFileViewerSelecting([set.url])
    }

    func zeigeSetsOrdner() {
        NSWorkspace.shared.activateFileViewerSelecting([store.setsRoot])
    }

    func zeigeProjektOrdner(_ verlinkung: Verlinkung) {
        let dir = URL(fileURLWithPath: verlinkung.project.repoDir)
            .appendingPathComponent(verlinkung.project.agent.projectDirName, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct ClaudeWorkflowSettingsView: View {
    @State private var model = ClaudeWorkflowModel()

    var body: some View {
        VStack(spacing: 0) {
            kopf
            Divider()
            if model.sets.isEmpty {
                leer
            } else {
                List {
                    ForEach(model.sets) { set in
                        Section { setInhalt(set) } header: { setKopf(set) }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            fuss
        }
        .onAppear { model.load() }
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skill-Sets").font(.headline)
            Text("Die Projekte verlinken **direkt** auf diese Ordner — keine Kopie, kein Sync. "
                 + "Eine Änderung an einem SKILL.md wirkt sofort in jedem verlinkten Projekt. "
                 + "Dieses Fenster zeigt nur, was womit verbunden ist, und stellt es her.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button { model.zeigeSetsOrdner() } label: {
                    Label(model.abbreviateHome(model.setsRoot), systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .lineLimit(1).truncationMode(.middle)
                .help("Der gepflegte Ordner — einzustellen unter Einstellungen › Allgemein")
                if model.setsRootMissing {
                    Label("gibt es nicht", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var leer: some View {
        VStack(spacing: 6) {
            Text(model.setsRootMissing ? "Den Sets-Ordner gibt es nicht" : "Kein Skill-Set gefunden")
                .foregroundStyle(.secondary)
            Text(model.setsRootMissing
                 ? "Erwartet unter \(model.abbreviateHome(model.setsRoot)) — der Pfad steht in den "
                   + "Einstellungen unter „Allgemein\u{201C} (claude.setsPath)."
                 : "Ein Set ist ein Unterordner mit skills/ oder rules/ und kebab-case-Namen.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private func setKopf(_ set: ClaudeAssetSet) -> some View {
        HStack(spacing: 8) {
            Text(set.displayName).font(.system(size: 13, weight: .semibold))
            if set.displayName != set.name {
                Text(set.name).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if model.isDefault(set) {
                Text(model.defaultIsImplicit ? "Standard (nicht gesetzt)" : "Standard")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                    .help(model.defaultIsImplicit
                          ? "Es sind mehrere Sets da, aber keins ist als Standard gesetzt — es gilt "
                            + "das erste. Zu setzen in den Einstellungen unter „Allgemein“."
                          : "Gilt für jedes Projekt ohne eigene Wahl und in ~/.claude, ~/.codex")
            }
            Text("\(model.assetCount(set, .skill)) Skills · \(model.assetCount(set, .rule)) Rules")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { model.zeigeImFinder(set) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .help("Im Finder zeigen: \(model.abbreviateHome(set.url.path)) — hier wird das Set "
                      + "gepflegt, und genau hierhin zeigen die Symlinks")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func setInhalt(_ set: ClaudeAssetSet) -> some View {
        if !set.description.isEmpty {
            Text(set.description).font(.caption).foregroundStyle(.secondary)
        }
        let projekte = model.verlinkungen[set.name] ?? []
        if projekte.isEmpty {
            Text("Kein Projekt hängt an diesem Set.")
                .font(.caption).foregroundStyle(.tertiary)
        } else {
            ForEach(projekte) { projektZeile($0) }
        }
    }

    private func projektZeile(_ verlinkung: ClaudeWorkflowModel.Verlinkung) -> some View {
        HStack(spacing: 8) {
            zustand(verlinkung)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verlinkung.project.key).font(.system(size: 12, design: .monospaced))
                    Text(verlinkung.project.agent.projectDirName)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
                if let hinweis = hinweis(verlinkung) {
                    Text(hinweis).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button { model.zeigeProjektOrdner(verlinkung) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .disabled(verlinkung.repoMissing)
                .help("Im Finder zeigen: \(model.abbreviateHome(verlinkung.project.repoDir))/"
                      + verlinkung.project.agent.projectDirName)
            Button("Verlinkung herstellen") { model.verlinke(verlinkung) }
                .disabled(verlinkung.repoMissing)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func zustand(_ verlinkung: ClaudeWorkflowModel.Verlinkung) -> some View {
        if verlinkung.repoMissing {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                .help("Kein Repo-Ordner — es gibt keinen Ort, an den verlinkt werden könnte")
        } else {
            switch verlinkung.state {
            case .linked:
                Image(systemName: "link").foregroundStyle(.green).help("Verlinkt")
            case .notInstalled:
                Image(systemName: "link").foregroundStyle(.quaternary)
                    .help("Nicht (vollständig) verlinkt")
            case .otherSet(let ziel):
                Image(systemName: "link").foregroundStyle(.orange)
                    .help("Zeigt noch auf \(ziel) — „Verlinkung herstellen“ hängt es um")
            case .foreign(let was):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .help("Zielort belegt: \(was)")
            }
        }
    }

    /// Was an dieser Zeile erklärungsbedürftig ist — und zwar nur das.
    private func hinweis(_ verlinkung: ClaudeWorkflowModel.Verlinkung) -> String? {
        var teile: [String] = []
        if verlinkung.repoMissing {
            teile.append("kein Repo unter \(model.abbreviateHome(verlinkung.project.repoDir))")
        }
        if let fehlend = verlinkung.missingName {
            teile.append("gewähltes Set „\(fehlend)“ gibt es nicht — das Standard-Set gilt")
        }
        if !verlinkung.sharesRepoWith.isEmpty {
            teile.append("teilt das Repo mit \(verlinkung.sharesRepoWith.joined(separator: ", "))"
                         + " — es gilt das zuletzt verlinkte Set")
        }
        if case .foreign(let was) = verlinkung.state { teile.append(was) }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }

    private var fuss: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text("Skills liegen im Projekt unter .claude/skills bzw. .codex/skills, Rules unter "
                     + ".claude/rules — beides gitignored, und beides Symlinks auf den gepflegten "
                     + "Ordner. Das Standard-Set hängt zusätzlich in ~/.claude und ~/.codex.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Alle verlinken") { model.verlinkeAlle() }
                    .help("Jedes Projekt auf sein Set bringen und das Standard-Set in die "
                          + "Agent-Homes legen")
            }
        }
        .padding(12)
    }
}
