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
    /// Alle konfigurierten Projekte — die Auswahlliste am Set.
    private(set) var alleProjekte: [ProjectConfig] = []
    private(set) var defaultSetName: String?
    /// Steht kein Standard-Set in der Config, gilt trotzdem eins — aber entschieden hat das niemand.
    private(set) var defaultIsImplicit = false
    private(set) var message: String?

    /// Liest den Stand — und stellt her, was fehlt.
    ///
    /// Es gibt keinen „Verlinken"-Knopf mehr: ein Projekt, das an einem Set hängt, ist verlinkt,
    /// sonst wäre die Zuordnung eine Behauptung. Hergestellt wird beim Zuordnen, beim App-Start,
    /// beim Projektwechsel — und hier, damit auch ein von Hand aufgelöster Zielort ohne Knopfdruck
    /// nachzieht. Der Aufruf ist idempotent: steht alles, passiert nichts.
    func load(herstellen: Bool = true) {
        let config = try? KanbanConfig.load()
        // Frühere Wurzeln nur behalten, solange sie noch gebraucht werden: nach dem Aufräumen zeigt
        // kein Symlink mehr dorthin, und ein alter Pfad im Store wäre ab da nur noch irreführend.
        store = .configured(formerRoots: store.formerRoots.filter(zeigtNochEtwasDorthin))
        setsRoot = store.setsRoot.path
        setsRootMissing = !store.setsRootExists

        sets = store.sets()
        let standard = store.defaultSet(configured: config?.defaultSkillSet)
        defaultSetName = standard?.name
        defaultIsImplicit = config?.defaultSkillSet == nil && sets.count > 1

        let projects = config?.projects ?? []
        alleProjekte = projects
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

        if herstellen, verlinkungen.values.contains(where: { $0.contains { $0.state != .linked } }) {
            stelleHer(projects, defaultSkillSet: config?.defaultSkillSet, melden: false)
            load(herstellen: false)
        }
    }

    /// Verlinkt jedes Projekt auf sein Set und legt das Standard-Set in die Agent-Homes.
    @discardableResult
    private func stelleHer(_ projects: [ProjectConfig], defaultSkillSet: String?,
                           melden: Bool) -> [ClaudeLinkReport] {
        var reports: [ClaudeLinkReport] = []
        for project in projects {
            if let report = ClaudeAssetFactory.link(project, defaultSkillSet: defaultSkillSet,
                                                   store: store) {
                reports.append(report)
            }
        }
        if let standard = store.defaultSet(configured: defaultSkillSet) {
            reports += store.link(standard, toHomes: AgentKind.allCases).values
        }
        if melden { message = melde(reports, titel: "Verlinkt") }
        return reports
    }

    /// Hängt irgendwo noch ein Symlink an dieser früheren Wurzel? Geprüft wird an den Agent-Homes
    /// und den Projekt-Ordnern — den einzigen Orten, an die Kanban je verlinkt hat.
    private func zeigtNochEtwasDorthin(_ wurzel: URL) -> Bool {
        let praefix = wurzel.standardizedFileURL.path + "/"
        var ziele = AgentKind.allCases.map { store.homeDir($0).appendingPathComponent("skills") }
        for gruppe in verlinkungen.values {
            for v in gruppe {
                let repo = URL(fileURLWithPath: v.project.repoDir)
                ziele += AgentKind.allCases.map {
                    repo.appendingPathComponent("\($0.projectDirName)/skills")
                }
                ziele.append(repo.appendingPathComponent(".claude/rules"))
            }
        }
        return ziele.contains { dir in
            guard let eintraege = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: []) else { return false }
            return eintraege.contains { url in
                guard let ziel = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                else { return false }
                return URL(fileURLWithPath: ziel, relativeTo: dir).standardizedFileURL.path
                    .hasPrefix(praefix)
            }
        }
    }

    func assetCount(_ set: ClaudeAssetSet, _ kind: ClaudeAssetKind) -> Int {
        store.assets(kind, in: set).count
    }

    func isDefault(_ set: ClaudeAssetSet) -> Bool { set.name == defaultSetName }

    // MARK: Verlinken

    /// Nach einer Änderung: Config neu lesen, alles herstellen, Ansicht auffrischen.
    private func herstellenUndAuffrischen() {
        let config = try? KanbanConfig.load()
        store = .configured(formerRoots: store.formerRoots)
        stelleHer(config?.projects ?? [], defaultSkillSet: config?.defaultSkillSet, melden: true)
        load(herstellen: false)
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

    /// Ein Set anlegen: Name plus Ordner. Der Ordner muss `skills/` oder `rules/` enthalten —
    /// sonst wäre es kein Set, sondern irgendein Verzeichnis.
    func legeSetAn(name roh: String, ordner: URL) -> String? {
        let name = ClaudeAssetName.normalisiert(roh)
        do { try ClaudeAssetName.pruefen(name) } catch { return error.localizedDescription }
        guard !sets.contains(where: { $0.name == name }) else {
            return ClaudeAssetName.Fehler.belegt(name).errorDescription
        }
        guard ClaudeAssetStore.hasAnyKindDir(ordner) else {
            return "In \(ordner.lastPathComponent) liegt weder ein skills/- noch ein rules/-Ordner."
        }
        do {
            try schreibeConfig { $0.set(.string(ordner.path), at: ["claude", "sets", name, "path"]) }
        } catch {
            return error.localizedDescription
        }
        load()
        message = "Set „\(name)" + "“ angelegt — \(abbreviateHome(ordner.path))"
        return nil
    }

    /// Ein Set aus der Registrierung nehmen. Der Ordner bleibt liegen: entfernt wird die Zuordnung,
    /// nicht die Arbeit. Projekte, die daran hingen, fallen sichtbar aufs Standard-Set zurück.
    func entferneSet(_ set: ClaudeAssetSet) {
        do {
            try schreibeConfig { $0.set(nil, at: ["claude", "sets", set.name]) }
            message = "Set „\(set.name)" + "“ entfernt — der Ordner \(abbreviateHome(set.url.path)) "
                    + "bleibt, wo er ist."
        } catch {
            message = "Nicht entfernt: \(error.localizedDescription)"
        }
        store = .configured(formerRoots: [set.url])
        herstellenUndAuffrischen()
    }

    /// Den Ordner eines Sets auf einen anderen zeigen lassen.
    func waehleOrdner(fuer set: ClaudeAssetSet) {
        guard let neu = ordnerDialog(titel: "Ordner für „\(set.name)" + "“ wählen",
                                     start: set.url) else { return }
        guard ClaudeAssetStore.hasAnyKindDir(neu) else {
            message = "In \(neu.lastPathComponent) liegt weder ein skills/- noch ein rules/-Ordner."
            return
        }
        do {
            try schreibeConfig { $0.set(.string(neu.path), at: ["claude", "sets", set.name, "path"]) }
        } catch {
            message = "Ordner nicht gespeichert: \(error.localizedDescription)"
            return
        }
        store = .configured(formerRoots: [set.url])
        herstellenUndAuffrischen()
    }

    /// Welche Projekte dieses Set benutzen — die Auswahl am Set statt am Projekt.
    func nutzen(_ set: ClaudeAssetSet, projekte: Set<String>) {
        let vorher = Set((verlinkungen[set.name] ?? []).map(\.project.key))
        guard vorher != projekte else { return }
        do {
            try schreibeConfig { doc in
                for key in projekte.subtracting(vorher) {
                    doc.set(.string(set.name), at: ["modules", "jira", "projects", key, "skillSet"])
                }
                // Abgewählte bekommen kein anderes Set aufgedrängt: sie fallen auf das Standard-Set
                // zurück, und das ist genau die Bedeutung von „kein Eintrag".
                for key in vorher.subtracting(projekte) {
                    doc.set(nil, at: ["modules", "jira", "projects", key, "skillSet"])
                }
            }
        } catch {
            message = "Zuordnung nicht gespeichert: \(error.localizedDescription)"
            return
        }
        herstellenUndAuffrischen()
    }

    func ordnerDialog(titel: String, start: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = titel
        panel.message = "Der Ordner mit skills/ und/oder rules/ — genau dorthin zeigen die Symlinks."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Wählt den Sammelordner, aus dem nicht registrierte Sets kommen.
    ///
    /// Der alte Ordner wird dabei als `formerRoots` mitgegeben: die Symlinks, die noch dorthin
    /// zeigen, sind **unsere** und werden umgehängt statt als fremd liegengelassen. Die Zuordnungen
    /// selbst stehen als Name in der Config und überleben den Wechsel ohnehin — ein Name, den der
    /// neue Ordner nicht führt, fällt sichtbar aufs Standard-Set zurück, statt still zu verschwinden.
    func waehleSetsOrdner() {
        guard let neu = ordnerDialog(titel: "Sammelordner für Skill-Sets wählen",
                                     start: store.setsRoot.deletingLastPathComponent()) else { return }
        let alt = store.setsRoot
        guard neu.standardizedFileURL != alt.standardizedFileURL else { return }
        do {
            try schreibeConfig { $0.set(.string(neu.path), at: ["claude", "setsPath"]) }
        } catch {
            message = "Ordner nicht gespeichert: \(error.localizedDescription)"
            return
        }
        store = .configured(formerRoots: [alt])
        herstellenUndAuffrischen()
    }

    private func schreibeConfig(_ aendern: (inout JSONValue) -> Void) throws {
        let datei = ConfigStore()
        var dokument = try datei.load()
        aendern(&dokument.root)
        try datei.save(dokument)
    }

    func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct ClaudeWorkflowSettingsView: View {
    @State private var model = ClaudeWorkflowModel()
    @State private var neuesSet = false

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
        .sheet(isPresented: $neuesSet) {
            NeuesSetSheet(model: model) { neuesSet = false }
        }
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
                .help("Im Finder zeigen — hier werden die Sets gepflegt")
                Button("Ordner wählen…") { model.waehleSetsOrdner() }
                    .controlSize(.small)
                    .help("Einen anderen Ordner als Quelle der Skill-Sets wählen. Bestehende "
                          + "Zuordnungen bleiben: sie stehen als Set-Name in der Config. Die "
                          + "Symlinks der Projekte werden auf den neuen Ordner umgehängt.")
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
            Menu {
                Button("Im Finder zeigen") { model.zeigeImFinder(set) }
                Button("Anderen Ordner wählen…") { model.waehleOrdner(fuer: set) }
                Divider()
                Button("Aus der Liste nehmen", role: .destructive) { model.entferneSet(set) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Ordner: \(model.abbreviateHome(set.url.path))")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func setInhalt(_ set: ClaudeAssetSet) -> some View {
        if !set.description.isEmpty {
            Text(set.description).font(.caption).foregroundStyle(.secondary)
        }
        Text(model.abbreviateHome(set.url.path))
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            .lineLimit(1).truncationMode(.middle)

        // Die Zuordnung wird hier getroffen: am Set, für alle Projekte auf einmal. Vorher stand sie
        // nur in den Einstellungen unter dem jeweiligen Jira-Projekt — eine Zeile pro Projekt, ohne
        // Blick darauf, wer sonst noch an diesem Set hängt.
        let benutzt = Set((model.verlinkungen[set.name] ?? []).map(\.project.key))
        Fluss(abstand: 5, zeilenabstand: 5) {
            ForEach(model.alleProjekte) { projekt in
                ProjektChip(key: projekt.key, an: benutzt.contains(projekt.key)) {
                    model.nutzen(set, projekte: benutzt.contains(projekt.key)
                                 ? benutzt.subtracting([projekt.key])
                                 : benutzt.union([projekt.key]))
                }
            }
        }
        .padding(.vertical, 2)

        let probleme = (model.verlinkungen[set.name] ?? []).filter {
            $0.repoMissing || $0.missingName != nil || $0.state != .linked
                || !$0.sharesRepoWith.isEmpty
        }
        ForEach(probleme) { problemZeile($0) }
    }


    /// Eine Zeile je Projekt, an dem etwas **nicht** stimmt.
    ///
    /// Im Normalfall sagt der Chip oben schon alles: er ist an, also ist das Projekt verlinkt.
    /// Eine zweite Liste, die dasselbe noch einmal aufzählt, wäre Lärm — hier steht nur, was
    /// Aufmerksamkeit braucht.
    private func problemZeile(_ verlinkung: ClaudeWorkflowModel.Verlinkung) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            zustand(verlinkung)
            Text(verlinkung.project.key).font(.system(size: 12, design: .monospaced))
            if let hinweis = hinweis(verlinkung) {
                Text(hinweis).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
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
                    .help("Zeigt noch auf \(ziel) — wird beim nächsten Herstellen umgehängt")
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
                Text("Ein Klick auf ein Projekt verlinkt es sofort: Skills nach .claude/skills bzw. "
                     + ".codex/skills, Rules nach .claude/rules — Symlinks auf den Ordner des Sets. "
                     + "Das Standard-Set hängt zusätzlich in ~/.claude und ~/.codex.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Set anlegen…") { neuesSet = true }
                    .help("Ein Set ist ein Ordner mit skills/ und/oder rules/ — irgendwo auf der "
                          + "Platte, nicht zwingend im Sammelordner")
            }
        }
        .padding(12)
    }
}

/// „Set anlegen": ein Name und der Ordner, in dem es liegt.
///
/// Angelegt wird nichts auf der Platte — das Set **existiert** schon als Ordner, hier bekommt es
/// nur seinen Namen in Kanban. Genau deshalb steht die Ordnerwahl gleichberechtigt neben dem Namen
/// und nicht hinter einem „Erweitert".
private struct NeuesSetSheet: View {
    let model: ClaudeWorkflowModel
    let onClose: () -> Void

    @State private var name = ""
    @State private var ordner: URL?
    @State private var fehler: String?

    private var normalisiert: String { ClaudeAssetName.normalisiert(name) }
    private var bereit: Bool { !normalisiert.isEmpty && ordner != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Skill-Set anlegen").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                TextField("name-in-kebab-case", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit { if bereit { anlegen() } }
                Text(normalisiert.isEmpty
                     ? "Kleinbuchstaben, Ziffern, Bindestriche — unter diesem Namen wählen ihn die Projekte."
                     : "wird zu `\(normalisiert)`")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button("Ordner wählen…") {
                        if let url = model.ordnerDialog(titel: "Ordner des Sets wählen", start: nil) {
                            ordner = url
                            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                                name = url.lastPathComponent
                            }
                            fehler = nil
                        }
                    }
                    if let ordner {
                        Text(model.abbreviateHome(ordner.path))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Text("Der Ordner muss `skills/` und/oder `rules/` enthalten. Er bleibt, wo er ist — "
                     + "Kanban verlinkt ihn nur in die Projekte.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let fehler {
                Text(fehler).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Anlegen") { anlegen() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!bereit)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    private func anlegen() {
        guard let ordner else { return }
        if let meldung = model.legeSetAn(name: name, ordner: ordner) { fehler = meldung }
        else { onClose() }
    }
}

/// Ein Projekt als anklickbarer Chip — an oder aus.
///
/// Statt Ankreuzfeldern, weil die Frage hier nicht „welche Häkchen sind gesetzt" lautet, sondern
/// **„welche Projekte gehören zu diesem Set"**: eine Menge, keine Liste von Schaltern. Gesetzte
/// Chips sind gefüllt und lesen sich als Aufzählung, die übrigen stehen blass daneben und laden
/// zum Dazunehmen ein. Dieselbe Kapsel-Optik wie die Epic-Chips auf den Karten.
private struct ProjektChip: View {
    let key: String
    let an: Bool
    let tippen: () -> Void

    @State private var drueber = false

    var body: some View {
        Button(action: tippen) {
            Text(key)
                .font(.system(size: 11, weight: an ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(an ? Color.accentColor : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(fuellung, in: Capsule())
                .overlay(Capsule().strokeBorder(rand, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { drueber = $0 }
        .help(an ? "\(key) benutzt dieses Set — klicken nimmt es heraus"
                 : "\(key) auf dieses Set legen")
    }

    private var fuellung: Color {
        an ? Color.accentColor.opacity(drueber ? 0.24 : 0.16)
           : Color.secondary.opacity(drueber ? 0.16 : 0.08)
    }

    private var rand: Color {
        an ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(drueber ? 0.35 : 0.2)
    }
}

/// Fliessender Umbruch: so viele Chips je Zeile, wie hineinpassen.
///
/// Ein `LazyVGrid` mit fester Spaltenbreite wäre das Naheliegende, gibt aber ein Raster — bei
/// Schlüsseln von `tp1` bis `iwf-local-dev` stünde überall Luft. Das `Layout`-Protokoll misst jeden
/// Chip einzeln und bricht um, wenn die Zeile voll ist.
private struct Fluss: Layout {
    var abstand: CGFloat = 6
    var zeilenabstand: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? .infinity
        let zeilen = umbrechen(subviews: subviews, breite: breite)
        let hoehe = zeilen.reduce(0) { $0 + $1.hoehe } +
            CGFloat(max(0, zeilen.count - 1)) * zeilenabstand
        return CGSize(width: proposal.width ?? zeilen.map(\.breite).max() ?? 0, height: hoehe)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var y = bounds.minY
        for zeile in umbrechen(subviews: subviews, breite: bounds.width) {
            var x = bounds.minX
            for index in zeile.indizes {
                let groesse = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(groesse))
                x += groesse.width + abstand
            }
            y += zeile.hoehe + zeilenabstand
        }
    }

    private struct Zeile {
        var indizes: [Int] = []
        var breite: CGFloat = 0
        var hoehe: CGFloat = 0
    }

    private func umbrechen(subviews: Subviews, breite: CGFloat) -> [Zeile] {
        var zeilen: [Zeile] = []
        var aktuell = Zeile()
        for index in subviews.indices {
            let groesse = subviews[index].sizeThatFits(.unspecified)
            let benoetigt = aktuell.indizes.isEmpty ? groesse.width : aktuell.breite + abstand + groesse.width
            if !aktuell.indizes.isEmpty, benoetigt > breite {
                zeilen.append(aktuell)
                aktuell = Zeile()
            }
            aktuell.breite = aktuell.indizes.isEmpty ? groesse.width
                                                     : aktuell.breite + abstand + groesse.width
            aktuell.hoehe = max(aktuell.hoehe, groesse.height)
            aktuell.indizes.append(index)
        }
        if !aktuell.indizes.isEmpty { zeilen.append(aktuell) }
        return zeilen
    }
}
