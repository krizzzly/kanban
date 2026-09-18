import Foundation
import Observation
import KanbanCore

/// A board card = a ticket plus its derived column + badges.
struct CardVM: Identifiable, Hashable {
    let ticket: Ticket
    let column: KanbanColumn
    let badges: [CardBadge]
    let statusMarker: TaskStatusMarker?   // Claude's task-file status (shown as a dot, separate from column)
    /// Von welcher Forge die Requests dieser Karte stammen — entscheidet allein über die
    /// **Beschriftung** („MR !42" gegen „PR #42") und die Badge-Farben, nicht über die Logik.
    var forge: ForgeKind = .gitlab
    var unresolvedMRComments: Int = 0     // open (unresolved) review discussions of the opened MR
    var resolvedMRComments: Int = 0       // the settled ones — together they give the forge's "x of y"
    var mrReviewState: MRReviewState = .none  // approved / resolved verdict shown flush right
    var approvedBy: [String] = []         // approvers, for the Approved badge's tooltip
    var mergeRequestURL: String?          // web URL of the MR in the 🔀/🚧 badge — the badge opens it
    var commentsURL: String?              // web URL of the MR the open-comment count belongs to
    var needsAttention: Bool = false      // the ticket's Claude console is waiting for an answer
    var claudeSeconds: TimeInterval = 0       // cumulated prompt→answer time of this ticket's session
    var claudeBaseSeconds: TimeInterval = 0   // the same total without the running turn (live badge ticks on top)
    var claudeRunningSince: Date?             // start of the turn running right now, else nil
    var bookedSeconds: TimeInterval = 0       // ⏱ time already booked to Jira (local ledger)
    var openToBookSeconds: TimeInterval = 0   // rounded-up cumulative minus booked — what a booking would log
    var id: String { ticket.key }

    /// True once every measured second is booked (used for the card's ✓). False while nothing was
    /// measured, so a Jira-only ticket shows no booking state at all.
    var fullyBooked: Bool { claudeSeconds > 0 && openToBookSeconds == 0 }

    /// All review threads of the opened MR — the "of y" in the card's thread counter.
    var totalMRComments: Int { resolvedMRComments + unresolvedMRComments }

    /// The iid printed on the 🔀/🚧 badge. Not always `primaryMR`: the badge prefers a *merged* MR,
    /// `WorkflowStatus.primaryMR` the newest *opened* one — so the badge links via this iid.
    var badgeMergeRequestIid: Int? {
        for badge in badges { if case .mergeRequest(let iid, _) = badge { return iid } }
        return nil
    }

    /// Wie die Forge die Nummer des Badge-Requests schreibt — `!42` bzw. `#42`.
    var badgeRequestLabel: String? {
        badgeMergeRequestIid.map { "\(forge.numberPrefix)\($0)" }
    }

    /// The iid of the opened, review-ready MR (the 🔀 badge) — nil for drafts and merged MRs.
    /// Feeds the context menu's `review-merge <!|#><nummer>` entry on Review cards.
    var openMergeRequestIid: Int? {
        guard column == .review else { return nil }
        for badge in badges { if case .mergeRequest(let iid, false) = badge { return iid } }
        return nil
    }
}

/// Ein Command, der auf die PROD-Daten-Bestätigung wartet (`get-task`/`start-task`). Trägt den
/// fertigen Console-Text mit, damit die Bestätigung nichts neu zusammenbauen muss — und die
/// Schreibweise, die der Agent dieses Projekts versteht (`/get-task …` bzw. `$get-task …`).
struct PendingProdConfirmation: Identifiable {
    let commandName: String
    let ticketKey: String
    let invocation: String
    let text: String

    var id: String { "\(commandName)|\(ticketKey)" }
}

/// Das Ergebnis der Jira-Nachführung vor `solve-task`, als eine Zeile für die Toolbar.
/// `isWarning` heisst: etwas ist **nicht** passiert — die Meldung bleibt dann stehen, statt sich
/// nach ein paar Sekunden selbst wegzuräumen.
struct StartWorkNotice: Equatable {
    let text: String
    let isWarning: Bool
}

@MainActor
@Observable
final class AppModel {
    // Config
    private(set) var config: AppConfig?
    private(set) var configError: String?

    /// Das Projekt, für das dieses Fenster aufgegangen ist (der Szenenwert bzw. das beim Start
    /// aufgelöste). Gemerkt, damit `reloadConfig` dasselbe Fenster beim selben Projekt lässt.
    private var szenenProjektKey: String?
    /// Gesetzt, wenn das Projekt dieses Fensters nicht mehr in der Config steht — dann zeigt das
    /// Fenster das statt eines Boards (siehe `ProjectGoneView`).
    private(set) var fehlendesProjekt: String?
    /// Nothing configured yet (fresh install, no Hermes to adopt from) — the app shows its setup
    /// screen. Deliberately separate from `configError`: an empty config is a starting point, the
    /// user did nothing wrong.
    private(set) var needsSetup = false
    private(set) var projects: [ProjectConfig] = []
    private(set) var selectedProject: ProjectConfig?

    // Sprints
    private(set) var sprints: [JiraSprint] = []
    /// Die Jira-Quelle des Boards: ein Sprint oder das Board als Ganzes (`SprintChoice`).
    /// nil, solange die Sprintliste nicht geladen ist.
    private(set) var selectedChoice: SprintChoice?
    /// Das Agile-Board des Projekts — gebraucht für die Board-Wahl, die keinen Sprint hat.
    private(set) var board: JiraBoard?

    /// Der gewählte Sprint, wo einer gewählt ist. Bleibt als eigene Eigenschaft bestehen, weil das
    /// halbe UI danach fragt; bei Board-Wahl ist er nil.
    var selectedSprint: JiraSprint? { selectedChoice?.sprint }

    /// Sprint- oder freier Modus. Je Projekt gemerkt (`SelectionStore`), Default Sprint.
    private(set) var boardMode: BoardMode = .sprint

    // Board
    private(set) var cards: [CardVM] = []
    private(set) var columns: [(column: KanbanColumn, cards: [CardVM])] = []

    /// Die Sucheingabe aus der Leiste — siehe `visibleColumns`. Reiner Anzeigezustand: sie siebt,
    /// was links steht, und rührt weder an `cards` noch an der Auswahl. Ein Ticket, das gerade
    /// rechts offen ist, bleibt offen, auch wenn die Suche es links ausblendet.
    var ticketSearch: String = ""

    /// Die Spalten, wie sie links stehen: `columns`, durch `ticketSearch` gesiebt.
    ///
    /// Spalten ohne Treffer fallen ganz weg statt als leere Überschriften stehenzubleiben — bei der
    /// Suche nach *einem* Ticket wäre eine Liste aus vier leeren Spaltenköpfen nur Rauschen.
    var visibleColumns: [(column: KanbanColumn, cards: [CardVM])] {
        guard !ticketSearch.trimmingCharacters(in: .whitespaces).isEmpty else { return columns }
        return columns.compactMap { entry in
            let treffer = entry.cards.filter {
                TicketFilter.matches(key: $0.ticket.key,
                                     summary: $0.ticket.summary,
                                     query: ticketSearch)
            }
            return treffer.isEmpty ? nil : (entry.column, treffer)
        }
    }
    private(set) var worktrees: [Worktree] = []
    private var lastMergeRequests: [MergeRequestRef] = []   // cached to re-derive a card locally

    // Detail
    private(set) var selectedTicketKey: String? {
        didSet { updateCurrentWorktree() }
    }
    private(set) var taskFile: TaskFile?
    private(set) var reviewMarkdowns: [String] = []   // full content of each <KEY>_review*.md → "Review" tab(s)
    private(set) var fallbackSections: [TaskSection] = []
    private(set) var detailLoading = false
    /// Der Inhalt des Task-Ordners (`<tasksPath>/<TICKET>/`) als Baum — siehe `TaskAttachments`.
    /// Leer heisst: es gibt nichts, und der Knopf in der Tableiste bleibt aus.
    private(set) var taskAttachments: [KBNode] = []
    /// Die Task-Ordner des Tickets auf der Platte (fast immer genau einer) — das Ziel des
    /// 📁-Knopfs. Getrennt von `taskAttachments` gehalten, weil der Baum leere Ordner wegwirft: ein
    /// Ticket-Ordner, in dem nur `avatars/` steht oder der gerade geleert wurde, gibt keinen Baum,
    /// existiert aber und soll sich öffnen lassen.
    private(set) var taskFolders: [URL] = []
    /// Die im Dateibaum gewählte Datei (absoluter Pfad). Nicht-nil heisst zugleich: rechts steht die
    /// Vorschau statt des Task-Tabs.
    var taskAttachmentSelection: String?

    // Terminal
    private(set) var activeTerminalSession: String?           // left: Claude, main-tree cwd
    private(set) var activeWorktreeTerminalSession: String?   // right: plain shell, worktree cwd
    /// Which ticket `activeTerminalSession` belongs to — guards typing against the *previous*
    /// ticket's session while a newly selected ticket's terminal is still being set up.
    private var terminalSessionTicket: String?
    /// Console text waiting for the ticket's terminal to come up (the board context menu selects
    /// the ticket first; typing happens once `setupTerminal` publishes the session).
    private var pendingConsoleText: (ticketKey: String, text: String)?
    // Ticket slash commands from the project's .claude/commands (header menu next to the ticket key).
    private(set) var claudeCommands: [ClaudeCommand] = []
    // Bumped when a command is typed into the Claude console, so the terminal pane shows that tab.
    private(set) var claudeTerminalFocusRequest = 0
    // Extra, user-spawned terminals, kept per ticket so they survive ticket switches.
    private var extraTerminalsByTicket: [String: [String]] = [:]

    // Worktree stack control panel (the "Worktree" tab)
    /// Derived state of the ticket's stack (image / seed / volume / containers) — the structured
    /// replacement for reading `iwf stack ps` as raw text.
    private(set) var stackStatus: WorktreeStackStatus?
    /// Branch, von dem der Feature-Branch abzweigt — aus der Historie abgeleitet, weil Git keinen
    /// Parent speichert und iwfs `baseBranch` nur ein globaler Default ist.
    private(set) var worktreeParentBranch: BranchBase?
    /// Hierarchie aller Worktree-Branches bis zur langlebigen Basis — nur fürs Popover, deshalb
    /// on demand statt bei jedem Tab-Besuch.
    private(set) var branchStack: BranchStackNode?
    private(set) var branchStackLoading = false
    private(set) var stackStatusLoading = false
    private(set) var worktreeStatusText: String = ""     // output of `iwf stack ps`
    private(set) var worktreeCommandOutput: String = ""  // stdout of the last lifecycle command
    private(set) var worktreeBusy = false
    private(set) var worktreeDbDump: StagedDbDump?       // staged DB seed file (path/size/age)

    // Derselbe Panel-Aufbau für den **Haupt-Repo-Stack**. Eigene Felder statt eines gemeinsamen
    // Zustands: beide Tabs stehen nebeneinander, ihre Ausgaben dürfen sich nicht überschreiben, und
    // ein laufender `iwf stack build` im Maintree darf den Worktree-Tab nicht sperren.
    private(set) var maintreeStackStatus: WorktreeStackStatus?
    private(set) var maintreeStatusLoading = false
    private(set) var maintreeStatusText: String = ""
    private(set) var maintreeCommandOutput: String = ""
    private(set) var maintreeBusy = false

    // DB-Snapshots (`iwf db snapshot`) — je Stack ein Ordner unter ~/.iwf-dev/snapshots.
    private(set) var worktreeSnapshots: [DbSnapshot] = []
    private(set) var maintreeSnapshots: [DbSnapshot] = []

    // Status
    private(set) var isLoadingSprints = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var lastRefresh: Date?

    // Jira-Feld „Lösung" des offenen Tickets: Stand, Ladezustand und der Editor.
    /// nil = noch nicht geladen **oder** das Ticket hat kein solches Feld (dann bleibt der Knopf weg).
    private(set) var solution: JiraSolution?
    private(set) var solutionLoading = false
    private(set) var solutionSaving = false
    private(set) var solutionError: String?
    /// Feld-Id je Projekt gemerkt: sie ist eine Eigenschaft der Instanz, nicht des Tickets, und der
    /// Edit-Screen-Aufruf ist der teuerste Teil des Ladens.
    private var solutionFieldIdByProject: [String: String] = [:]
    var solutionSheetPresented = false

    // Jira-Nachführung beim Absetzen von `solve-task` (Status „In Arbeit“ + Zuweisung an dich).
    /// Was dabei herauskam — nil, solange in dieser Sitzung nichts nachgeführt wurde.
    private(set) var startWorkNotice: StartWorkNotice?
    /// Der angemeldete Jira-Benutzer je Instanz: `/myself` ändert sich über die Sitzung nicht, und
    /// die Nachführung braucht die `accountId` bei jedem Aufruf. Das Board fragt dieselbe Stelle —
    /// „mir zugewiesen" entscheidet über die Spalte (siehe `WorkflowStatus`).
    private var jiraSelfByBaseUrl: [String: JiraUser] = [:]
    /// Zählt die Nachführungen, damit eine späte Antwort (oder das Aufräumen der Meldung) eine
    /// neuere Nachführung nicht überschreibt.
    private var startWorkGeneration = 0

    // Settings sheet (gear button); writable — bound to the sheet presentation.
    var settingsPresented = false
    /// „Task erstellen" im freien Modus — bound to the sheet presentation.
    var newTaskSheetPresented = false
    /// Vorbelegung für das Sheet. Gesetzt, wenn der Task aus einer **Karte ohne Nummer** entsteht:
    /// dann sind MR-Titel und Branch schon bekannt und niemand soll sie abtippen.
    var newTaskDraft = ""

    // MARK: Knowledgebase (📚 neben der Modus-Umschaltung)

    /// Die Knowledgebase des Projekts (`modules.knowledgebase.projects.<key>.path`) — Baum links,
    /// Ansicht rechts. Sie **ersetzt** Board und Detail im Fenster, statt sich als Sheet
    /// davorzulegen: sie ist selbst ein Zwei-Spalten-Bild und will die ganze Fläche.
    private(set) var knowledgebaseOpen = false
    private(set) var kbNodes: [KBNode] = []
    private(set) var kbLoading = false
    /// Pfad der gewählten Datei — die Auswahl der Liste, deshalb schreibbar.
    var kbSelection: String?

    // Attention: which tickets' Claude consoles are waiting for an answer (hook markers + pane
    // fallback). Which sections hold open questions is derived on demand (see questionSectionIDs).
    private(set) var attentionTickets: Set<String> = []
    private var sessionIdByTicket: [String: String] = [:]
    private var attentionWatcher: TaskFileWatcher?
    private var attentionWatchTask: Task<Void, Never>?

    // Claude time: per-turn (prompt → answer) measurements read out of Claude's own transcripts,
    // cumulated per ticket. See `ClaudeTimingStore`.
    private(set) var timingByTicket: [String: ClaudeSessionTiming] = [:]
    /// Tickets whose console is visibly mid-turn (tmux pane analysis) — the liveness signal a
    /// transcript cannot give: an interrupted turn also lacks its turn-end record.
    private(set) var workingTickets: Set<String> = []
    private var timingWatcher: TaskFileWatcher?
    private var timingWatchTask: Task<Void, Never>?
    /// Bumped on every arming of the transcript watch so a late, superseded arm can bail out.
    private var timingWatchGeneration = 0

    // Commit dialog (only offered for 🟢 Abgeschlossen tasks — see `canCommit`).
    var commitSheetPresented = false
    private(set) var commitState: GitWorkingState?
    private(set) var commitBusy = false
    private(set) var commitError: String?
    private(set) var commitLog: String = ""
    /// The file whose diff is shown in the right pane, and its parsed lines.
    private(set) var commitSelectedFile: GitChangedFile?
    private(set) var commitDiff: [DiffLine] = []
    private(set) var commitDiffLoading = false
    /// Editor mode: the file's content on disk, its diff pattern, and whether it was edited.
    var commitEditorMode = false
    var commitFileText: String = ""
    private(set) var commitFileHighlight = DiffHighlight(addedLines: [], deletionMarkers: [])
    private(set) var commitFileLoadedText: String = ""
    /// Bumped whenever the editor must reload its content (file switched, saved, reverted).
    private(set) var commitEditorReloadToken = 0
    private(set) var commitSaveError: String?

    var commitEditorDirty: Bool { commitFileText != commitFileLoadedText }
    /// Liegt die gewählte Datei überhaupt auf der Platte? Im Reiter „Diff" steht auch, was der
    /// Branch **gelöscht** hat — dort gibt es nichts zu bearbeiten, und ein Speichern würde die
    /// Datei wieder anlegen.
    private(set) var commitFileExists = true

    /// Dateien, die **nicht** mitcommittet werden (Pfade wie in `git status`). Der Haken je Zeile im
    /// Commit-Fenster schreibt hier hinein; `GitCommitController` nimmt sie nach dem `add -A` wieder
    /// aus dem Index.
    private(set) var commitExcluded: Set<String> = []

    func setCommitInclusion(_ included: Bool, path: String) {
        if included { commitExcluded.remove(path) } else { commitExcluded.insert(path) }
    }

    func isCommitIncluded(_ path: String) -> Bool { !commitExcluded.contains(path) }

    /// Was tatsächlich in den Commit geht — für die Zählung im Fenster und die Freigabe des Knopfs.
    var commitIncludedCount: Int {
        (commitState?.changedFiles ?? []).count { isCommitIncluded($0.path) }
    }

    /// Woher das Diff im rechten Feld stammt. Der Reiter „Diff" zeigt dieselbe Fläche, nur gegen die
    /// Abzweig-Basis statt gegen das Arbeitsverzeichnis — deshalb ein Schalter statt einer zweiten
    /// Ansicht.
    enum CommitDiffSource: Equatable { case working, branch }
    private(set) var commitDiffSource: CommitDiffSource = .working

    /// Was der Branch gegenüber seiner Abzweig-Basis geändert hat (Reiter „Diff").
    private(set) var branchDiff: GitBranchDiff?
    private(set) var branchDiffLoading = false
    /// Warum es kein Branch-Diff gibt — eine leere Liste und „keine Basis gefunden" sind zwei
    /// verschiedene Auskünfte und dürfen nicht gleich aussehen.
    private(set) var branchDiffError: String?

    /// Die Dateiliste, die zur gewählten Quelle gehört.
    var commitFiles: [GitChangedFile] {
        commitDiffSource == .branch ? (branchDiff?.files ?? []) : (commitState?.changedFiles ?? [])
    }

    // Worklog booking: how much ⏱ time is already booked per ticket (local ledger), plus the state
    // of an in-flight booking. Writing to Jira is explicit (a button), never automatic.
    private(set) var bookedByTicket: [String: TimeInterval] = [:]
    /// Der ganze Ledger-Stand im Speicher. Nötig, weil die Tagesposten je Karte gerechnet werden und
    /// `applyTimingsToCards` bei jedem Timing-Tick über alle Karten läuft — von der Platte gelesen
    /// wäre das ein Datei-Zugriff je Karte und Tick.
    private var ledgerByTicket: [String: WorklogLedger.Entry] = [:]
    private(set) var bookingBusy = false
    private(set) var bookingError: String?
    var bookingSheetPresented = false   // the "Alle offenen buchen" confirmation sheet

    /// Ids of the selected task file's sections that hold open questions (tab-pill ❓) or record
    /// decisions (tab-pill green ✓). **Cached** — recomputed only when the detail content changes
    /// (see `refreshSectionSignals`), never per view render, so switching tabs stays instant.
    private(set) var questionSectionIDs: Set<Int> = []
    private(set) var decisionSectionIDs: Set<Int> = []

    /// Rebuilds the cached `displaySections` and the per-section pill signals. Call whenever the
    /// detail content (task file / reviews / fallback / selection) changes.
    private func refreshSectionSignals() {
        displaySections = computeDisplaySections()
        questionSectionIDs = TaskQuestions.openQuestionSectionIDs(displaySections)
        decisionSectionIDs = TaskQuestions.decisionSectionIDs(displaySections)
    }

    private var jira: JiraClient?
    /// Die Forge-Clients, je einer pro Plattform — welcher ein Projekt bedient, sagt dessen
    /// `forge`-Eintrag. Beide dürfen nil sein: eine Forge ist optional, wie GitLab es immer war.
    private var forgeClients: [ForgeKind: any ForgeClient] = [:]
    private var pollTask: Task<Void, Never>?
    private var watcher: TaskFileWatcher?
    private var watchTask: Task<Void, Never>?
    private var reviewWatcher: TaskFileWatcher?
    private var reviewWatchTask: Task<Void, Never>?

    // Preferred tab order; everything else follows in file order.
    private static let preferredOrder = [
        "beschreibung", "kommentare", "analyse", "impact", "history",
        "umsetzungsplan", "lösungsplan", "loesungsplan", "stages",
        "fragen", "lösung", "loesung", "commit", "abschluss-checkliste",
    ]

    /// Fährt das Fenster hoch: Config lesen, Clients bauen — und das Projekt wählen, für das dieses
    /// Fenster aufgegangen ist.
    ///
    /// `projectKey` ist der Wert der Szene. nil heisst „Fenster ohne Wert" (Programmstart, ⌘N);
    /// dann entscheidet `ProjectWindows.vorschlag`. Die gemerkte Auswahl bestimmt seit „ein Fenster
    /// je Projekt" nicht mehr, **welches** Projekt ein Fenster zeigt, sondern nur noch, **welche**
    /// Fenster beim Start aufgehen.
    ///
    /// Die prozessweiten Rückkanäle (Terminal-Klick, Benachrichtigung) hängen nicht mehr hier: mit
    /// mehreren Fenstern gewänne sonst das zuletzt gestartete Model, und ein Klick in Fenster A
    /// landete in Fenster B. Sie laufen über `ProjectWindows`.
    func bootstrap(projectKey: String?) {
        guard config == nil, configError == nil else { return }
        do {
            // First start on a machine that has Hermes: adopt its Jira/GitLab config once. Without
            // Hermes this does nothing at all — Kanban is standalone, the setup screen takes over.
            HermesImport.runIfNeeded()
            let cfg = try KanbanConfig.load()
            config = cfg
            guard cfg.isConfigured else {
                needsSetup = true
                return
            }
            projects = cfg.projects
            // project.json und Skill-Set für ALLE Projekte herstellen, nicht nur fürs gewählte:
            // beides liest ein Agent in seinem Repo, unabhängig davon, was das Board gerade zeigt.
            for project in cfg.projects where FileManager.default.fileExists(atPath: project.repoDir) {
                linkSkillSet(for: project, defaultSkillSet: cfg.defaultSkillSet)
            }
            jira = JiraClient(config: cfg)
            forgeClients = Self.makeForgeClients(cfg)   // leer, solange keine Forge konfiguriert ist
            let creds = Data("\(cfg.jiraEmail):\(cfg.jiraApiToken)".utf8).base64EncodedString()
            AvatarCache.shared.configure(
                authHeader: "Basic \(creds)",
                jiraBaseUrls: [cfg.jiraDefaultBaseUrl] + cfg.projects.map(\.jiraBaseUrl))
            // Optional deep-link: `Kanban --select BFEZVM-4259` opens that ticket on launch — und
            // bestimmt beim Fenster ohne Wert zugleich, welches Projekt es zeigt.
            let deepLink = Self.launchArg("--select")
            guard let project = projekt(fuer: projectKey, deepLink: deepLink) else {
                // Szenenwert gesetzt, Projekt weg: das Fenster gehörte diesem einen Projekt.
                fehlendesProjekt = projectKey
                return
            }
            szenenProjektKey = project.key
            selectProject(project)
            if let deepLink, TicketRouting.projekt(fuerTicket: deepLink, in: [project]) != nil {
                selectTicket(deepLink)
            } else if let gewuenscht = ProjectWindows.shared.gewuenschtesTicket(fuer: project.key) {
                // Das Fenster ist auf Klick einer Benachrichtigung aufgegangen — mit Ticket.
                selectTicket(gewuenscht)
            }
            startPolling()
            startAttentionWatch()
        } catch {
            configError = error.localizedDescription
        }
    }

    /// Welches Projekt dieses Fenster zeigt: der Szenenwert, sonst das Projekt des Deep-Links,
    /// sonst der Vorschlag der Fenster-Zuordnung (beim Start das zuletzt benutzte, bei ⌘N das erste
    /// ohne Fenster). Ein gesetzter, aber unbekannter Szenenwert gibt nil — das Projekt ist weg.
    private func projekt(fuer projectKey: String?, deepLink: String?) -> ProjectConfig? {
        if let projectKey { return projects.first { $0.key == projectKey } }
        if let deepLink, let project = TicketRouting.projekt(fuerTicket: deepLink, in: projects) {
            return project
        }
        return ProjectWindows.shared.vorschlag(projekte: projects)
    }

    /// Ist überhaupt eine Forge konfiguriert? Ohne sie bleiben Review und Done leer.
    var hasForge: Bool { !forgeClients.isEmpty }

    /// Hat das **gewählte** Projekt eine Forge, die auch konfiguriert ist? Erst das beantwortet die
    /// Frage, die der Hinweis in der Leiste stellt — ein Projekt ohne Zuordnung nützt der beste
    /// Token nichts.
    var selectedProjectHasForge: Bool {
        guard let kind = selectedProject?.forge?.kind else { return false }
        return forgeClients[kind] != nil
    }

    /// Plattform, Web-Basis und Projekt-Pfad des gewählten Projekts — die Quelle aller Branch-Links.
    var forgeLocation: ForgeLocation? { config?.forgeLocation(for: selectedProject) }

    /// Wie das gewählte Projekt einen Request nennt: „MR" bzw. „PR". Ohne Forge bleibt es bei „MR" —
    /// die Beschriftung, die die App seit jeher trägt.
    var forgeKind: ForgeKind { selectedProject?.forge?.kind ?? .gitlab }

    private static func makeForgeClients(_ cfg: AppConfig) -> [ForgeKind: any ForgeClient] {
        var clients: [ForgeKind: any ForgeClient] = [:]
        if let gitlab = GitLabClient(config: cfg) { clients[.gitlab] = gitlab }
        if let github = GitHubClient(config: cfg) { clients[.github] = github }
        return clients
    }

    /// Re-reads the config after the settings sheet saved it: rebuilds clients + project list via
    /// `bootstrap()` and restores the previous selection where it still exists.
    ///
    /// Die Darstellung hängt mit dran: `KanbanSettingsStore.reload()` holt den neuen Stand, die
    /// laufenden Terminals ziehen nach, und die gerenderten Markdown-Ansichten zeichnen über die
    /// Benachrichtigung neu. Ohne das wäre jede Farbe hier eine Einstellung, die erst beim nächsten
    /// Start sichtbar wird.
    func reloadConfig() {
        KanbanSettingsStore.reload()
        TerminalCache.shared.reapplyAppearance()
        let previousProject = selectedProject?.key
        let previousTicket = selectedTicketKey
        pollTask?.cancel()
        pollTask = nil
        config = nil
        configError = nil
        needsSetup = false
        jira = nil
        forgeClients = [:]
        projects = []
        selectedProject = nil
        fehlendesProjekt = nil
        // Mit dem Projekt dieses Fensters, nicht mit der gemerkten Auswahl: ein Speichern in den
        // Einstellungen lädt **alle** Fenster neu, und jedes bleibt bei seinem Projekt.
        bootstrap(projectKey: szenenProjektKey ?? previousProject)
        if let previousProject,
           let project = projects.first(where: { $0.key == previousProject }),
           project.id != selectedProject?.id {
            selectProject(project)
        }
        if let previousTicket, selectedProject != nil {
            selectTicket(previousTicket)
        }
    }

    // MARK: - Selection

    /// Die Reihenfolge, in der die Workflow-Skills vorn stehen — der Weg, den ein Ticket nimmt.
    /// Alles andere, was das Set anbietet, folgt dahinter alphabetisch: welche Skills ein Projekt
    /// hat, entscheidet sein Skill-Set, nicht eine Liste im Code.
    private static let ticketCommandOrder = ["get-task", "start-task", "solve-task", "review-task"]

    func selectProject(_ project: ProjectConfig) {
        guard project.id != selectedProject?.id else { return }
        selectedProject = project
        // Das Fenster gehört ab jetzt diesem Projekt — auch über ein `reloadConfig` hinweg.
        szenenProjektKey = project.key
        // Die Knowledgebase gehört dem Projekt: der Baum des alten Projekts wäre nach dem Wechsel
        // schlicht falsch. Offen bleibt die Ansicht, wenn das neue Projekt auch eine hat.
        kbNodes = []
        kbSelection = nil
        if knowledgebaseOpen {
            if project.kbPathAbsolute == nil { knowledgebaseOpen = false }
            else { loadKnowledgebase() }
        }
        SelectionStore.projectKey = project.key   // zuletzt benutzt: Rückfallebene beim nächsten Start
        // Ein Projekt ohne Jira kennt nur den freien Modus — auch wenn für den Key noch eine alte
        // Sprint-Wahl gespeichert ist (die Anbindung kann nachträglich abgeschaltet worden sein).
        boardMode = project.usesJira
            ? (SelectionStore.boardMode(forProject: project.key) ?? .sprint)
            : .free
        sprints = []
        selectedChoice = nil
        board = nil
        cards = []
        columns = []
        // Sonst stünde das neue Projekt hinter dem Filter des alten und sähe aus, als wäre es leer.
        ticketSearch = ""
        newTaskConsoleSession = nil
        claudeCommands = Self.commands(for: project, defaultSkillSet: config?.defaultSkillSet)
        // Projektwerte und den Satz Skills bereitstellen, den dieses Projekt sehen soll.
        // Still: ein fehlendes Repo darf den Projektwechsel nicht stören.
        linkSkillSet(for: project, defaultSkillSet: config?.defaultSkillSet)
        clearDetail()
        Task { await loadForCurrentMode() }
    }

    /// Was im Command-Menü des Tickets steht: **alles**, was das Skill-Set dieses Projekts anbietet,
    /// die Workflow-Skills vorn.
    ///
    /// Gibt es kein Set (Sets-Ordner verschoben, Bestand leer), fällt es auf den Scan der Zielorte
    /// zurück — dann steht dort, was tatsächlich verlinkt ist. Ein leeres Menü wäre die schlechtere
    /// Antwort: die Symlinks von gestern funktionieren ja weiter.
    private static func commands(for project: ProjectConfig,
                                 defaultSkillSet: String?) -> [ClaudeCommand] {
        let store = ClaudeAssetStore.configured()
        if let set = store.resolve(skillSet: project.skillSet, default: defaultSkillSet).set {
            return ClaudeCommandScanner.commands(in: set, first: ticketCommandOrder)
        }
        return ClaudeCommandScanner.scan(repoDir: project.repoDir, agent: project.agent)
    }

    /// Stellt für ein Projekt her, was ein Agent in seinem Repo vorfinden soll: die generierten
    /// Projektwerte und das Skill-Set, das dieses Projekt sehen soll.
    ///
    /// Beides an einer Stelle, weil beides dieselbe Auflösung braucht — in `.claude/project.json`
    /// steht der Name des Sets, mit dem das Projekt wirklich läuft. Still: ein fehlendes Repo oder
    /// ein belegter Zielort darf den Projektwechsel nicht stören; was nicht ging, zeigt die
    /// Skill-Set-Übersicht.
    private func linkSkillSet(for project: ProjectConfig, defaultSkillSet: String?) {
        let set = ClaudeAssetFactory.resolvedSetName(for: project, defaultSkillSet: defaultSkillSet)
        _ = try? ClaudeProjectFile.write(for: project, skillSet: set)
        ClaudeAssetFactory.link(project, defaultSkillSet: defaultSkillSet)
    }

    /// Sprint-Modus braucht erst die Sprintliste (die dann `refresh` auslöst); der freie Modus liest
    /// direkt lokal.
    private func loadForCurrentMode() async {
        switch boardMode {
        case .sprint: await loadSprints()
        case .free: await refresh()
        }
    }

    /// Umschalten zwischen Sprint- und freiem Modus. Die Wahl gilt je Projekt und überlebt den
    /// Neustart — genau wie der gewählte Sprint.
    func setBoardMode(_ mode: BoardMode) {
        guard mode != boardMode else { return }
        // Die Leiste bietet den Sprint-Modus ohne Jira gar nicht erst an; hier steht der Riegel
        // trotzdem, damit kein anderer Weg (wiederhergestellte Wahl, späterer Aufrufer) Sprints
        // für ein Projekt lädt, das keine hat.
        guard mode == .free || selectedProject?.usesJira == true else { return }
        boardMode = mode
        if let project = selectedProject {
            SelectionStore.setBoardMode(mode, forProject: project.key)
        }
        cards = []
        columns = []
        ticketSearch = ""   // wie beim Projektwechsel: der alte Filter passt zum neuen Inhalt nicht
        Task { await loadForCurrentMode() }
    }

    /// Sprint **oder** Board wählen — beides kommt aus demselben Picker, weil es dieselbe Frage
    /// beantwortet: welche Jira-Tickets stehen auf dem Brett?
    func selectChoice(_ choice: SprintChoice) {
        guard choice != selectedChoice else { return }
        selectedChoice = choice
        if let project = selectedProject {
            SelectionStore.setSprintChoice(choice.id, forProject: project.key)  // beim nächsten Start wieder da
        }
        Task { await refresh() }
    }

    func selectTicket(_ key: String) {
        if pendingConsoleText?.ticketKey != key { pendingConsoleText = nil }
        newTaskConsoleSession = nil   // die Projekt-Console tritt hinter das Ticket zurück
        selectedTicketKey = key
        loadDetail(for: key)
        setupTerminal(for: key)
        startTimingWatch(for: key)
    }

    // MARK: - Loading

    func loadSprints() async {
        guard let project = selectedProject, let jira else { return }
        isLoadingSprints = true
        errorMessage = nil
        defer { isLoadingSprints = false }
        do {
            guard let board = try await jira.board(prefix: project.prefix, baseUrl: project.jiraBaseUrl) else {
                errorMessage = "Kein Board für \(project.prefix) gefunden."
                return
            }
            self.board = board
            let all = try await jira.sprints(boardId: board.id, baseUrl: project.jiraBaseUrl,
                                             states: "active,future,closed")
            sprints = SprintSelection.ordered(all)
            // Stellt die zuletzt getroffene Wahl wieder her (siehe `SprintSelection.resolve`). Ein
            // Board ohne aktiven Sprint landet auf `.board` — früher stand hier „Keine Sprints für
            // dieses Board" und das Brett blieb leer.
            selectedChoice = SprintSelection.resolve(
                sprints: sprints, storedId: SelectionStore.sprintChoice(forProject: project.key))
            await refresh()
        } catch {
            errorMessage = "Sprints laden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard let project = selectedProject else { return }
        guard boardMode == .free || selectedChoice != nil else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }
        do {
            async let mrsTask = fetchMergeRequests(for: project)
            async let worktreesTask = WorktreeScanner.scan(repoDir: project.repoDir)
            let mrs = await mrsTask
            let worktrees = await worktreesTask

            let issues = try await tickets(for: project, worktrees: worktrees, mergeRequests: mrs)
            self.worktrees = worktrees
            self.lastMergeRequests = mrs

            let dir = project.tasksPathAbsolute
            // Wer bin ich auf dieser Instanz? Einmal je Sitzung geholt; ohne Auskunft ist eben kein
            // Ticket „meins" und die Ableitung bleibt, wie sie war. Ohne Jira-Anbindung wird gar
            // nicht erst gefragt: die Karten kommen dann aus Task-Files und Branches, die keinen
            // Bearbeiter kennen — die Anfrage wäre nur eine Verzögerung ohne Antwortnutzen.
            let myAccountId = project.usesJira
                ? await jiraSelf(baseUrl: project.jiraBaseUrl)?.accountId
                : nil
            var sessionMap: [String: String] = [:]
            cards = issues.map { ticket in
                var info = TaskFileLoader.statusMarker(ticketKey: ticket.key, in: dir)
                // Ein Ticket ohne Nummer wird über seinen Branch erkannt, nicht über den Key —
                // `!139` steht in keinem Branchnamen (siehe `TicketMatching.matches`).
                let branch = ticket.sourceBranch
                let wt = WorktreeScanner.worktree(for: ticket.key, in: worktrees, branch: branch)
                // A ticket can carry two recorded ids that disagree; the one with a transcript is the
                // real conversation (see ClaudeSessionResolution). Read-only here — the file is only
                // corrected when the ticket is actually opened.
                if let sid = ClaudeSessionResolution.resolve(
                    taskFileId: TaskFileLoader.peekSessionId(ticketKey: ticket.key, in: dir),
                    storeId: SessionIdStore.peek(forTicket: ticket.key),
                    cwd: project.repoDir) {
                    sessionMap[ticket.key] = sid
                }

                let mr = WorkflowStatus.primaryMR(ticketKey: ticket.key, mergeRequests: mrs, branch: branch)

                // Rename the task file to match the MR's feature branch. First, so the writes below
                // re-find the renamed file. Safe: only when the new name still belongs to the ticket.
                if info.exists, let branch = mr?.sourceBranch,
                   let currentURL = TaskFileLoader.find(ticketKey: ticket.key, in: dir) {
                    TaskFileLoader.renameToMatchBranch(currentURL: currentURL, branch: branch, ticketKey: ticket.key)
                }

                // Auto-advance the persisted task-file status marker, idempotently, to match reality:
                //   • ✅ Done   when Jira says Erledigt/Geschlossen (statusCategory "done"), or
                //   • 🔵 Review when an MR is open for this ticket.
                // Done wins (higher precedence); neither overrides an existing ✅ Done — **ausser** das
                // Ticket ist wieder aufgemacht (Jira ausdrücklich nicht erledigt + neuerer offener MR),
                // dann ist das ✅ ein Fossil und wird auf 🔵 zurückgesetzt. Keeps the dot/marker in sync
                // with the derived column so Claude and other tools see it too.
                if WorkflowStatus.shouldAutoSetDone(hasTaskFile: info.exists, currentMarker: info.marker,
                                                    jiraDone: ticket.isDoneInJira),
                   let url = TaskFileLoader.find(ticketKey: ticket.key, in: dir),
                   TaskFileLoader.writeStatus(.done, url: url) {
                    info.marker = .done
                } else if WorkflowStatus.shouldAutoSetReview(ticketKey: ticket.key, hasTaskFile: info.exists,
                                                             currentMarker: info.marker, mergeRequests: mrs,
                                                             jiraState: ticket.jiraDoneState),
                          let url = TaskFileLoader.find(ticketKey: ticket.key, in: dir),
                          TaskFileLoader.writeStatus(.review, url: url) {
                    info.marker = .review
                }

                // Sync the MR's feature branch (🌿 BRANCH line) and URL (Merge Request line) in.
                if info.exists, let mr, let url = TaskFileLoader.find(ticketKey: ticket.key, in: dir) {
                    TaskFileLoader.writeBranch(mr.sourceBranch, url: url)
                    TaskFileLoader.writeMergeRequest(url: mr.webUrl, file: url)
                }

                let res = WorkflowStatus.resolve(
                    ticketKey: ticket.key,
                    hasTaskFile: info.exists,
                    statusMarker: info.marker,
                    worktree: wt,
                    mergeRequests: mrs,
                    jiraState: ticket.jiraDoneState,
                    isAssignedToMe: Self.isAssigned(ticket, to: myAccountId),
                    branch: branch
                )
                var card = CardVM(ticket: ticket, column: res.column, badges: res.badges, statusMarker: info.marker)
                card.forge = project.forge?.kind ?? .gitlab
                // Review state of the ticket's opened MR (merged MRs always carry the blank one).
                card.unresolvedMRComments = mr?.unresolvedDiscussions ?? 0
                card.resolvedMRComments = mr?.resolvedDiscussions ?? 0
                card.mrReviewState = mr?.reviewState ?? .none
                card.approvedBy = mr?.approvedBy ?? []
                card.commentsURL = mr?.webUrl
                card.mergeRequestURL = card.badgeMergeRequestIid
                    .flatMap { iid in mrs.first { $0.iid == iid }?.webUrl }
                return card
            }
            sessionIdByTicket = sessionMap
            reloadLedger()
            // Der Worktree des offenen Tickets hängt an beidem, was hier gerade neu wurde: der
            // Worktree-Liste und den Tickets (der Branch der `!<iid>`-Karten).
            updateCurrentWorktree()
            applyTimingsToCards()               // carry the cached ⏱ over, so badges don't blink per poll
            regroupColumns()                    // build columns from cards (always)
            recomputeAttention(notify: false)   // paint the ❓ where a console is waiting
            Task { await refreshPaneAttention() }
            Task { await loadStackSweep() }   // Toolbar-Zähler „N Stacks stoppen“
            Task { await refreshTimings() }     // ⏱ cumulated Claude time per card
            // If the selected ticket's file was renamed under it (branch sync), reload the detail
            // on the new path so the tabs/watcher don't go stale.
            if let key = selectedTicketKey,
               let found = TaskFileLoader.find(ticketKey: key, in: dir),
               taskFile != nil, taskFile?.url != found {
                loadDetail(for: key)
            }
            errorMessage = nil
            // Open a ticket (and its terminal) automatically on first load, so the terminal is
            // visible from the start instead of only after the user clicks a card. Ausnahme: die
            // Projekt-Console steht gerade im Detail — die darf ein Poll nicht wegschieben.
            if selectedTicketKey == nil, newTaskConsoleSession == nil, let first = firstBoardTicket() {
                selectTicket(first)
            }
        } catch {
            errorMessage = "Aktualisieren fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Woher die Ticketliste kommt — der einzige Unterschied zwischen den beiden Modi. Alles danach
    /// (Task-File, Worktree, MR, Statuslogik) ist identisch.
    /// Der angemeldete Jira-Benutzer der Instanz — aus dem Cache, sonst einmal geholt. Ein
    /// Fehlschlag ist hier **kein** Board-Fehler (anders als bei `solve-task`, wo ohne `accountId`
    /// nichts zugewiesen werden kann): dann weiss die App nur nicht, welche Tickets meine sind.
    private func jiraSelf(baseUrl: String) async -> JiraUser? {
        if let cached = jiraSelfByBaseUrl[baseUrl] { return cached }
        guard let jira, let me = try? await jira.currentUser(baseUrl: baseUrl) else { return nil }
        jiraSelfByBaseUrl[baseUrl] = me
        return me
    }

    /// „Gehört mir": verglichen wird die `accountId`, nicht der Anzeigename — der ist nicht eindeutig
    /// und je Instanz anders geschrieben. Ohne bekannte eigene Id gehört nichts mir.
    private static func isAssigned(_ ticket: Ticket, to accountId: String?) -> Bool {
        guard let accountId, let mine = ticket.assigneeAccountId else { return false }
        return mine == accountId
    }

    private func tickets(for project: ProjectConfig, worktrees: [Worktree],
                         mergeRequests: [MergeRequestRef]) async throws -> [Ticket] {
        switch boardMode {
        case .sprint:
            guard let choice = selectedChoice, let jira else { return [] }
            // Sub-tasks are not shown as standalone cards — the story carries the work. Filter them
            // before building cards. (Epic inheritance stays for parity with the self-test; on the
            // board it is a no-op now, since the sub-tasks that would inherit are gone.)
            let issues: [Ticket]
            switch choice {
            case .sprint(let sprint):
                issues = try await jira.sprintIssues(sprintId: sprint.id, baseUrl: project.jiraBaseUrl)
            case .board:
                guard let board else { return [] }
                issues = try await jira.boardIssues(boardId: board.id, baseUrl: project.jiraBaseUrl)
            }
            return EpicResolution.inheritFromParents(issues).filter { !$0.isSubtask }
        case .free:
            return LocalTickets.discover(tasksDirectory: project.tasksPathAbsolute,
                                         prefix: project.prefix,
                                         worktrees: worktrees,
                                         mergeRequests: mergeRequests)
        }
    }

    /// Die Requests des Projekts von **seiner** Forge. Die eine Aufrufstelle, an der die App eine
    /// Forge überhaupt anspricht — deshalb reicht hier das Protokoll.
    private func fetchMergeRequests(for project: ProjectConfig) async -> [MergeRequestRef] {
        guard let forge = project.forge, let client = forgeClients[forge.kind] else { return [] }
        return (try? await client.openedAndMergedRequests(projectPath: forge.path)) ?? []
    }

    /// The first card in board order (Sprint → Offen → In Bearbeitung → Review → Done), preferring
    /// active work: In Bearbeitung, then Offen, then the rest.
    private func firstBoardTicket() -> String? {
        let priority: [KanbanColumn] = [.inBearbeitung, .offen, .review, .sprint, .done]
        for col in priority {
            if let card = columns.first(where: { $0.column == col })?.cards.first {
                return card.ticket.key
            }
        }
        return cards.first?.ticket.key
    }

    /// Karten in Spalten. Sortiert wird **numerisch** (`TicketNumber`) statt lexikografisch — sonst
    /// stünde EVEN-999 hinter EVEN-1000. In „Done" absteigend: dort landet im freien Modus die ganze
    /// Historie, und das zuletzt Fertige gehört nach oben.
    private func regroupColumns() {
        columns = boardMode.columns.map { col in
            let inColumn = cards.filter { $0.column == col }
            let sorted = col == .done
                ? inColumn.sorted { TicketNumber.isAscending($1.ticket.key, $0.ticket.key) }
                : inColumn.sorted { TicketNumber.isAscending($0.ticket.key, $1.ticket.key) }
            return (col, sorted)
        }
    }

    // MARK: - Detail

    /// The tabs shown for the selected ticket. **Cached** — `linkify` + ordering ran on every access,
    /// and the tab bar reads it O(N) times per render (once per pill via `current`), so recomputing
    /// on access made tab rendering quadratic. Rebuilt only when the detail content changes
    /// (`refreshSectionSignals`).
    private(set) var displaySections: [TaskSection] = []

    private func computeDisplaySections() -> [TaskSection] {
        if let tf = taskFile {
            var result: [TaskSection] = []
            if !tf.preamble.isEmpty {
                // Synthetic first tab holding the file preamble (status + jira/worktree/branch/stack
                // block), with the block's values turned into clickable links. `usesJira` entscheidet,
                // ob eine fehlende JIRA-Zeile abgeleitet wird — ohne Jira-Anbindung gibt es kein Ticket,
                // auf das sie zeigen könnte.
                let linked = StatusLinks.linkify(
                    preamble: tf.preamble,
                    ticketKey: selectedTicketKey,
                    jiraBaseUrl: selectedProject?.jiraBaseUrl,
                    forge: forgeLocation,
                    usesJira: selectedProject?.usesJira ?? true)
                result.append(TaskSection(id: -1, title: "Status", markdown: linked))
            }
            // Each review file as its own tab (ids -2, -3, …), right after Status so they're easy to
            // find. Numbered "Review #1"… when there are several, plain "Review" when there's one.
            for (i, md) in reviewMarkdowns.enumerated() where !md.isEmpty {
                let title = reviewMarkdowns.count > 1 ? "Review #\(i + 1)" : "Review"
                result.append(TaskSection(id: -2 - i, title: title, markdown: md))
            }
            result.append(contentsOf: ordered(tf.sections))
            if !result.isEmpty { return result }
        }
        return fallbackSections
    }

    private func ordered(_ sections: [TaskSection]) -> [TaskSection] {
        sections.enumerated().sorted { lhs, rhs in
            let li = rank(lhs.element.title), ri = rank(rhs.element.title)
            if li != ri { return li < ri }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func rank(_ title: String) -> Int {
        let key = title.lowercased().trimmingCharacters(in: .whitespaces)
        return Self.preferredOrder.firstIndex(where: { key.hasPrefix($0) }) ?? Int.max
    }

    // MARK: - Status

    /// The selected ticket's current `### Status` marker (nil if there is no task file).
    var currentStatusMarker: TaskStatusMarker? { taskFile?.statusMarker }

    /// The epic of the selected ticket (nil when it belongs to none).
    var selectedEpic: EpicRef? {
        guard let key = selectedTicketKey else { return nil }
        return cards.first { $0.ticket.key == key }?.ticket.epic
    }

    /// Was der Kopier-Knopf in die Zwischenablage legt — Pfad relativ zum Repo (Claudes cwd), sonst
    /// absolut. Siehe `ClipboardPath`; dieselbe Regel gilt für jede Datei im Task-Ordner.
    func clipboardPath(for url: URL) -> String {
        ClipboardPath.forCopying(url, repoDir: selectedProject?.repoDir)
    }

    var relativeTaskFilePath: String? {
        guard let url = taskFile?.url else { return nil }
        return clipboardPath(for: url)
    }

    /// Status can only be set on tickets that have a task file (that's where the marker lives).
    var canEditStatus: Bool { taskFile != nil }

    /// Writes the `### Status` marker into the selected ticket's task file and moves its card. A real
    /// merge request still overrides the column (see `WorkflowStatus`), so the card may stay put.
    func setTaskStatus(_ marker: TaskStatusMarker) {
        guard let key = selectedTicketKey, let project = selectedProject,
              let url = TaskFileLoader.find(ticketKey: key, in: project.tasksPathAbsolute),
              TaskFileLoader.writeStatus(marker, url: url) else { return }
        taskFile = TaskFileLoader.load(url)               // refresh the detail (Status tab)
        reresolveCard(ticketKey: key, project: project)   // move the card locally, no network
    }

    /// Recomputes just one card's column/badges from the cached MRs + worktrees + fresh task-file
    /// marker, so a status change reflects immediately without a full Jira/GitLab refresh.
    private func reresolveCard(ticketKey key: String, project: ProjectConfig) {
        guard let idx = cards.firstIndex(where: { $0.ticket.key == key }) else { return }
        let info = TaskFileLoader.statusMarker(ticketKey: key, in: project.tasksPathAbsolute)
        let branch = cards[idx].ticket.sourceBranch
        let wt = WorktreeScanner.worktree(for: key, in: worktrees, branch: branch)
        let res = WorkflowStatus.resolve(
            ticketKey: key, hasTaskFile: info.exists, statusMarker: info.marker,
            worktree: wt, mergeRequests: lastMergeRequests, jiraState: cards[idx].ticket.jiraDoneState,
            isAssignedToMe: Self.isAssigned(cards[idx].ticket,
                                            to: jiraSelfByBaseUrl[project.jiraBaseUrl]?.accountId),
            branch: branch)
        var card = CardVM(ticket: cards[idx].ticket, column: res.column, badges: res.badges, statusMarker: info.marker)
        card.forge = project.forge?.kind ?? .gitlab
        // Rebuilt from the cached MRs, so the 💬-count, the review badge and the links survive a
        // local status change.
        let mr = WorkflowStatus.primaryMR(ticketKey: key, mergeRequests: lastMergeRequests, branch: branch)
        card.unresolvedMRComments = mr?.unresolvedDiscussions ?? 0
        card.resolvedMRComments = mr?.resolvedDiscussions ?? 0
        card.mrReviewState = mr?.reviewState ?? .none
        card.approvedBy = mr?.approvedBy ?? []
        card.commentsURL = mr?.webUrl
        card.mergeRequestURL = card.badgeMergeRequestIid
            .flatMap { iid in lastMergeRequests.first { $0.iid == iid }?.webUrl }
        cards[idx] = card
        regroupColumns()
    }

    private func clearDetail() {
        watcher?.cancel(); watcher = nil
        watchTask?.cancel(); watchTask = nil
        reviewWatcher?.cancel(); reviewWatcher = nil
        reviewWatchTask?.cancel(); reviewWatchTask = nil
        timingWatcher?.cancel(); timingWatcher = nil
        timingWatchTask?.cancel(); timingWatchTask = nil
        taskFile = nil
        reviewMarkdowns = []
        fallbackSections = []
        taskAttachments = []
        taskFolders = []
        taskAttachmentSelection = nil
        worktreeStatusText = ""
        worktreeCommandOutput = ""
        worktreeDbDump = nil
        selectedTicketKey = nil
        activeTerminalSession = nil
        activeWorktreeTerminalSession = nil
        terminalSessionTicket = nil
        pendingConsoleText = nil
    }

    // MARK: - Terminal

    /// Resolve and (if needed) create the ticket's tmux session, then publish its name so the
    /// detail pane attaches to it. Runs off the main actor because it shells out to tmux and may
    /// write the session-id marker to the task file. See `TerminalSessionResolver`.
    private func setupTerminal(for key: String) {
        guard let project = selectedProject else {
            activeTerminalSession = nil; activeWorktreeTerminalSession = nil; return
        }
        let repoDir = project.repoDir
        let tasksDir = project.tasksPathAbsolute
        let agent = project.agent
        let worktree = WorktreeScanner.worktree(for: key, in: worktrees)

        Task.detached { [weak self] in
            let tmux = TmuxController()
            guard tmux.isAvailable else {
                await MainActor.run {
                    guard let self, self.selectedTicketKey == key else { return }
                    self.activeTerminalSession = nil
                    self.activeWorktreeTerminalSession = nil
                    self.terminalSessionTicket = nil
                    self.pendingConsoleText = nil
                }
                return
            }

            // One id per ticket, written to both stores: the task-file marker (where it belongs) and
            // `sessions.json` (which also covers tickets that have no task file yet). Without the
            // write-through the two drift apart as soon as Claude creates the task file mid-session,
            // and the board then watches a conversation that never existed.
            //
            // Nur für Agents, die eine Id **annehmen** (`claude --session-id`). Codex erfindet sie
            // selbst; eine hier erzeugte Id in das Task-File zu schreiben würde eine Konversation
            // behaupten, die es nicht gibt — und die ⏱-Zeit auf ein Transcript zeigen lassen, das
            // nie entsteht. Lieber nichts als etwas Falsches.
            var sessionId: String?
            var hasTranscript = false
            if agent.supportsPresetSessionId {
                let taskFileURL = TaskFileLoader.find(ticketKey: key, in: tasksDir)
                let resolved = ClaudeSessionResolution.resolve(
                    taskFileId: taskFileURL.flatMap { TaskFileLoader.sessionId(in: $0) },
                    storeId: SessionIdStore.peek(forTicket: key),
                    cwd: repoDir) ?? UUID().uuidString.lowercased()
                if let taskFileURL { TaskFileLoader.writeSessionId(resolved, url: taskFileURL) }
                SessionIdStore.set(resolved, forTicket: key)
                sessionId = resolved
                hasTranscript = ClaudeTranscripts.transcriptExists(sessionId: resolved, cwd: repoDir)
            } else {
                // Codex: die Id gehört Codex, wir finden sie über den Thread-Namen (siehe
                // `CodexSessions`). `hasTranscript` heisst hier „es gibt einen Rollout" — und nur
                // dann kann `codex resume` gelingen: ohne Rollout bricht es sichtbar ab
                // („no rollout found for thread id …"), verifiziert gegen 0.147.
                let name = CodexSessions.threadName(forTicket: key)
                if let known = CodexSessions.sessionId(threadName: name) {
                    sessionId = known
                    hasTranscript = CodexSessions.rolloutURL(sessionId: known) != nil
                }
            }

            let plan = TerminalSessionResolver.resolve(
                ticketKey: key,
                repoDir: repoDir,
                worktree: worktree,
                sessionId: sessionId,
                hasTranscript: hasTranscript,
                agent: agent,
                existing: tmux.listSessions()
            )
            _ = tmux.run(plan: plan)
            tmux.setStatusBar(plan.name, visible: false)   // hide the green tmux status bar
            tmux.cancelCopyMode(plan.name)                 // clear any leftover copy-mode
            // Musste die Session angelegt werden, kann der Cache nur eine **tote** Ansicht dazu
            // halten (die Session war ja eben noch weg — etwa nach einem `exit` im Pane). Sie stehen
            // zu lassen hiesse, für immer „can't find session" zu zeigen statt der neuen Session.
            if plan.needsCreate { await MainActor.run { TerminalCache.shared.remove(plan.name) } }

            // Frische Codex-Console: Codex' eigenem `/rename` den Thread-Namen geben, unter dem
            // Kanban ihn wiederfindet. Das ist ein **TUI**-Command — Enter schickt keinen Turn ab,
            // kostet also nichts und ist der einzige Weg zu einer stabilen Zuordnung, weil Codex
            // keine vorgegebene Session-Id annimmt.
            // Bedingung ist „neuer Thread", nicht „keine Id bekannt": eine Session, die einmal
            // umbenannt wurde, aber nie einen Turn hatte, hat einen Index-Eintrag **und** keinen
            // Rollout — sie wird also frisch gestartet und braucht den Namen wieder.
            if agent == .codex, plan.needsCreate, !hasTranscript {
                try? await Task.sleep(for: .seconds(2))    // Codex nimmt erst nach dem Start Eingaben
                tmux.sendText(plan.name, "/rename \(CodexSessions.threadName(forTicket: key))")
                tmux.sendKeys(plan.name, "Enter")
            }

            // Second (right) terminal: a plain shell opened in the worktree, if one exists.
            var worktreeSession: String? = nil
            if let worktree {
                let name = "kanban-\(key.uppercased())-wt"
                _ = tmux.createSession(name: name, cwd: worktree.path, command: nil)
                tmux.setStatusBar(name, visible: false)
                tmux.cancelCopyMode(name)
                worktreeSession = name
            }

            await MainActor.run {
                guard let self, self.selectedTicketKey == key else { return }
                self.activeTerminalSession = plan.name
                self.terminalSessionTicket = key
                self.activeWorktreeTerminalSession = worktreeSession
                // The id may have been created just now — arm the ⏱ transcript watch on it.
                if let sessionId { self.sessionIdByTicket[key] = sessionId }
                self.startTimingWatch(for: key)
                // Flush a command parked by the board context menu. A freshly created session is
                // still booting Claude — give it a moment before typing.
                if let pending = self.pendingConsoleText, pending.ticketKey == key {
                    self.pendingConsoleText = nil
                    Self.typeText(pending.text, session: plan.name,
                                  delaySeconds: plan.needsCreate ? 2.0 : 0)
                }
            }
        }
    }

    /// Types `/command <TICKET>` into the ticket's Claude console (without Enter, so the user can
    /// still edit/confirm) and switches the terminal pane to the Claude tab.
    func sendClaudeCommand(_ command: ClaudeCommand) {
        guard let key = selectedTicketKey else { return }
        dispatchClaudeCommand(name: command.name, argument: key, ticketKey: key)
    }

    /// Board context menu: run a command for *any* card — selects the ticket first (which opens
    /// its console), then types `/command <TICKET>`.
    func sendClaudeCommand(_ command: ClaudeCommand, ticketKey: String) {
        dispatchClaudeCommand(name: command.name, argument: ticketKey, ticketKey: ticketKey)
    }

    // MARK: - PROD-Daten-Bestätigung

    /// Commands, die Jira-Inhalte in die KI holen und deshalb erst nach ausdrücklicher Bestätigung
    /// in die Console gehen. `start-task` ist mit dabei, obwohl es selbst nichts lädt: fehlt das
    /// Task-File, ruft es `get-task` auf und holt das Ticket doch.
    static let prodConfirmCommands: Set<String> = ["get-task", "start-task"]

    /// Der Command, der auf die Bestätigung wartet — non-nil heisst: Dialog offen. Wird nur über
    /// `confirmProdCommand`/`cancelProdCommand` wieder leer, der Command selbst ist bis dahin
    /// nicht in der Console.
    var prodConfirmation: PendingProdConfirmation?

    /// Der Agent des aktuellen Projekts — Präfix, Startbefehl und Asset-Ort hängen daran.
    /// Ohne Projekt gilt der Fallback, damit nirgends ein Optional durchgeschleift werden muss.
    var agent: AgentKind { selectedProject?.agent ?? .fallback }

    /// Ein Command auf dem Weg in die Console: entweder direkt oder über die PROD-Bestätigung.
    private func dispatchClaudeCommand(name: String, argument: String, ticketKey: String) {
        let text = "\(agent.commandPrefix)\(name) \(argument) "
        guard Self.prodConfirmCommands.contains(name) else {
            deliver(commandName: name, text: text, ticketKey: ticketKey)
            return
        }
        prodConfirmation = PendingProdConfirmation(commandName: name, ticketKey: ticketKey,
                                                  invocation: "\(agent.commandPrefix)\(name) \(argument)",
                                                  text: text)
    }

    /// Der gemeinsame letzte Schritt beider Wege (direkt und bestätigt): erst die Jira-Nachführung
    /// anstossen, dann tippen. Ein abgebrochener Bestätigungsdialog kommt hier nie an — dann wird
    /// auch in Jira nichts geschrieben.
    private func deliver(commandName: String, text: String, ticketKey: String) {
        if Self.startWorkCommands.contains(commandName) { startJiraWork(ticketKey: ticketKey) }
        typeIntoConsole(text, ticketKey: ticketKey)
    }

    /// Bestätigt: der Command darf in die Console (getippt, nicht abgeschickt — wie immer).
    func confirmProdCommand() {
        guard let pending = prodConfirmation else { return }
        prodConfirmation = nil
        deliver(commandName: pending.commandName, text: pending.text, ticketKey: pending.ticketKey)
    }

    /// Abgebrochen: nichts wird getippt, das Ticket bleibt unangetastet.
    func cancelProdCommand() {
        prodConfirmation = nil
    }

    // MARK: - Arbeit aufnehmen (Jira-Status + Zuweisung)

    /// Commands, bei denen die Arbeit wirklich losgeht. Genau davor zieht Kanban das Jira-Ticket
    /// nach: Status „In Arbeit“ und Zuweisung an dich.
    ///
    /// Warum die App und nicht der Skill: Jira schreiben kann hier nur Kanban — es hält Zugang und
    /// Host-Guard, der Agent hat für Transition und Zuweisung kein Werkzeug. Und es ist der einzige
    /// Weg, der nicht davon abhängt, ob die KI den Schritt abarbeitet.
    static let startWorkCommands: Set<String> = ["solve-task"]

    /// Zieht das Jira-Ticket auf den Stand, den das Absetzen von `solve-task` bedeutet: Status
    /// „In Arbeit“, zugewiesen an dich. Läuft nebenher — der Command wird sofort getippt, eine
    /// hakende Jira-Antwort darf die Arbeit nicht aufhalten.
    ///
    /// Geschrieben wird nur, was fehlt (siehe `JiraClient.startWork`); ging etwas nicht, bleibt die
    /// Meldung in der Toolbar stehen, statt still zu verschwinden.
    private func startJiraWork(ticketKey: String) {
        guard let jira, let project = selectedProject else { return }
        let baseUrl = project.jiraBaseUrl
        startWorkGeneration += 1
        let generation = startWorkGeneration
        startWorkNotice = StartWorkNotice(text: "\(ticketKey): Jira wird nachgezogen…", isWarning: false)

        Task { [weak self] in
            let notice: StartWorkNotice
            var didWrite = false
            do {
                let me: JiraUser
                if let cached = self?.jiraSelfByBaseUrl[baseUrl] {
                    me = cached
                } else {
                    me = try await jira.currentUser(baseUrl: baseUrl)
                    self?.jiraSelfByBaseUrl[baseUrl] = me
                }
                guard let accountId = me.accountId else {
                    throw APIError.decode("Jira nennt keine accountId für \(me.displayName)")
                }
                let result = try await jira.startWork(issueKey: ticketKey, baseUrl: baseUrl,
                                                      accountId: accountId, displayName: me.displayName)
                notice = StartWorkNotice(text: result.summary, isWarning: result.isWarning)
                didWrite = result.didWrite
            } catch {
                notice = Self.startWorkFailureNotice(ticketKey: ticketKey, error: error)
            }

            guard let self, generation == self.startWorkGeneration else { return }
            self.startWorkNotice = notice
            // Geschrieben heisst: das Board stimmt nicht mehr. Die Zuweisung steht als Avatar auf
            // der Karte — sichtbar wird sie erst mit den neu geholten Issues.
            if didWrite { await self.refresh() }
            guard !notice.isWarning else { return }   // Warnungen bleiben stehen
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, generation == self.startWorkGeneration else { return }
                self.startWorkNotice = nil
            }
        }
    }

    /// Ein Ticket, das Jira nicht kennt (freier Modus, lokal erfundene Nummer), ist kein Fehler —
    /// dort gibt es schlicht nichts nachzuziehen. Alles andere ist eine Warnung.
    private static func startWorkFailureNotice(ticketKey: String, error: Error) -> StartWorkNotice {
        if case APIError.api(_, 404, _) = error {
            return StartWorkNotice(text: "\(ticketKey) steht nicht in Jira — nichts nachzuziehen.",
                                   isWarning: false)
        }
        return StartWorkNotice(text: "\(ticketKey): Jira nicht nachgezogen — \(error.localizedDescription)",
                               isWarning: true)
    }

    /// Board context menu on Review cards: `/review-merge !<iid>` bzw. `/review-merge #<nummer>` —
    /// the command wants the request number in **its forge's** notation, not the ticket key.
    func sendReviewMerge(ticketKey: String, mrIid: Int) {
        let number = "\(forgeKind.numberPrefix)\(mrIid)"
        typeIntoConsole("\(agent.commandPrefix)review-merge \(number) ", ticketKey: ticketKey)
    }

    /// Types text into the ticket's Claude console, selecting the ticket first if needed. While
    /// the terminal is not up yet, the text is parked and flushed by `setupTerminal`.
    private func typeIntoConsole(_ text: String, ticketKey: String) {
        claudeTerminalFocusRequest += 1
        if selectedTicketKey != ticketKey {
            pendingConsoleText = (ticketKey, text)   // before selectTicket — it drops foreign pendings
            selectTicket(ticketKey)
        } else if terminalSessionTicket == ticketKey, let session = activeTerminalSession {
            Self.typeText(text, session: session)
        } else {
            pendingConsoleText = (ticketKey, text)
        }
    }

    /// Ein frei verfasster Prompt aus dem Verfassen-Fenster geht in die Claude-Console des
    /// gewählten Tickets.
    ///
    /// **Gepastet, nicht getippt** (`TmuxController.pasteText`): mehrzeiliges Markdown würde als
    /// Tastendruck schon beim ersten Zeilenumbruch abgeschickt — die Bracketed-Paste-Marker
    /// verhindern genau das.
    ///
    /// `submit` ist die Ausnahme von der Hausregel „eingefügt, nicht abgeschickt": hier hat der
    /// Mensch den Text eben selbst geschrieben und gegengelesen, ein zweites Gegenlesen in der
    /// Console wäre nur ein Klick mehr. Der Weg ohne Absenden bleibt trotzdem daneben stehen.
    ///
    /// Das Enter kommt mit Abstand hinterher: Paste und Tastendruck sind zwei tmux-Aufrufe, und der
    /// TUI braucht einen Moment, um den eingefügten Block übernommen zu haben. Ohne die Pause ginge
    /// im ungünstigen Fall ein halber Prompt raus.
    func sendComposedPrompt(_ markdown: String, submit: Bool) {
        let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session = activeTerminalSession else { return }
        claudeTerminalFocusRequest += 1
        Task.detached {
            let tmux = TmuxController()
            guard tmux.isAvailable else { return }
            tmux.cancelCopyMode(session)
            tmux.pasteText(session, text)
            guard submit else { return }
            try? await Task.sleep(for: .milliseconds(250))
            tmux.sendKeys(session, "Enter")
        }
    }

    // MARK: - Task erstellen (freier Modus)

    /// Die Claude-Console des Projekts, in der `/create-task` läuft — nil, solange sie nie gebraucht
    /// wurde. Bewusst **nicht** an ein Ticket gebunden: das entsteht ja erst durch den Command.
    private(set) var newTaskConsoleSession: String?

    /// Öffnet „Task erstellen" mit dem, was die Karte schon weiss — Titel und Branch des MR. Der
    /// Branch steht bewusst mit dabei: `/create-task` soll den vorhandenen Branch weiterbenutzen,
    /// statt einen zweiten für dieselbe Arbeit anzulegen.
    func startTaskFromBranch(_ ticket: Ticket) {
        guard let branch = ticket.sourceBranch else { return }
        var lines = [ticket.summary]
        lines.append("")
        lines.append("Die Arbeit liegt schon auf dem Branch `\(branch)` "
                     + "(\(forgeKind.requestNoun) \(ticket.key)).")
        newTaskDraft = lines.joined(separator: "\n")
        newTaskSheetPresented = true
    }

    /// Beschreibung → `/create-task <text>` in der Projekt-Console.
    ///
    /// Der Text wird **gepastet, nicht getippt** (`TmuxController.pasteText`): eine mehrzeilige
    /// Beschreibung würde als Tastendruck beim ersten Zeilenumbruch abgeschickt. Enter drücken wir
    /// nicht — wie bei jedem anderen Command liest der Mensch gegen und schickt selbst ab.
    func createTask(description: String) {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let project = selectedProject else { return }

        // Die Console tritt an die Stelle des Ticket-Details, sonst sähe niemand Claudes Antwort.
        selectedTicketKey = nil
        clearDetail()

        let name = Self.newTaskSessionName(project: project)
        let repoDir = project.repoDir
        let storeKey = Self.newTaskSessionStoreKey(project: project)
        let agent = project.agent

        Task.detached { [weak self] in
            let tmux = TmuxController()
            guard tmux.isAvailable else { return }

            guard let setup = await Self.ensureNewTaskSession(name: name, repoDir: repoDir,
                                                              storeKey: storeKey, agent: agent,
                                                              tmux: tmux) else {
                await MainActor.run { self?.noteConsoleFailure(name: name, repoDir: repoDir) }
                return
            }
            tmux.cancelCopyMode(name)
            // Frisch gestartetes Claude braucht einen Moment, bis es Eingaben annimmt — dieselbe
            // Wartezeit wie beim Ticket-Terminal.
            if setup == .created { try? await Task.sleep(for: .seconds(2)) }
            tmux.pasteText(name, "\(agent.commandPrefix)create-task \(text)")

            await MainActor.run { self?.newTaskConsoleSession = name }
        }
    }

    /// Zeigt die Projekt-Console wieder an, ohne etwas zu tippen (nach einem Klick auf eine Karte,
    /// oder wenn es sie aus einer früheren Sitzung gibt).
    ///
    /// Sie wird dabei **angelegt, falls sie nicht läuft**: dass es den Knopf gibt, sagt nur, dass
    /// dieses Projekt schon einmal eine Console hatte (`SessionIdStore`, überlebt den Neustart) —
    /// die tmux-Session überlebt einen Rechner-Neustart dagegen nicht, und ein Attach auf eine
    /// verschwundene Session zeigte im Terminal nur „can't find session: kanban-<KEY>-new".
    /// Getippt wird nichts; `/create-task` kommt erst aus dem Sheet.
    func showNewTaskConsole() {
        guard let project = selectedProject else { return }
        selectedTicketKey = nil
        clearDetail()

        let name = Self.newTaskSessionName(project: project)
        let repoDir = project.repoDir
        let storeKey = Self.newTaskSessionStoreKey(project: project)
        let agent = project.agent

        Task.detached { [weak self] in
            let tmux = TmuxController()
            guard tmux.isAvailable else { return }
            guard await Self.ensureNewTaskSession(name: name, repoDir: repoDir, storeKey: storeKey,
                                                  agent: agent, tmux: tmux) != nil else {
                await MainActor.run { self?.noteConsoleFailure(name: name, repoDir: repoDir) }
                return
            }
            tmux.cancelCopyMode(name)
            await MainActor.run { self?.newTaskConsoleSession = name }
        }
    }

    /// Ob es für dieses Projekt schon eine Console gibt, die man wieder aufrufen kann.
    var hasNewTaskConsole: Bool {
        guard let project = selectedProject else { return false }
        return SessionIdStore.peek(forTicket: Self.newTaskSessionStoreKey(project: project)) != nil
    }

    /// Ergebnis von `ensureNewTaskSession` — `created` heisst „der Agent fährt gerade hoch" und ist
    /// der einzige Fall, in dem vor dem Tippen gewartet werden muss.
    private enum ConsoleSetup { case existing, created }

    /// Sorgt dafür, dass die Projekt-Console als tmux-Session **existiert**; nil heisst, dass sie
    /// nicht angelegt werden konnte (typisch: das Repo-Verzeichnis gibt es nicht — `tmux
    /// new-session -c` scheitert dann). Off-main aufzurufen, sie shellt nach tmux.
    private static func ensureNewTaskSession(name: String, repoDir: String, storeKey: String,
                                             agent: AgentKind, tmux: TmuxController) async -> ConsoleSetup? {
        if tmux.hasSession(name) { return .existing }

        // Eigene, stabile Session-Id je Projekt: die create-task-Gespräche laufen damit über
        // Neustarts hinweg in derselben Konversation weiter. Für Codex entfällt sie (siehe
        // `setupTerminal`) — die Console ist dann bei jedem Start eine frische.
        var sessionId: String?
        var hasTranscript = false
        if agent.supportsPresetSessionId {
            let resolved = await MainActor.run { SessionIdStore.peek(forTicket: storeKey) }
                ?? UUID().uuidString.lowercased()
            await MainActor.run { SessionIdStore.set(resolved, forTicket: storeKey) }
            sessionId = resolved
            hasTranscript = ClaudeTranscripts.transcriptExists(sessionId: resolved, cwd: repoDir)
        }

        guard tmux.createSession(
            name: name, cwd: repoDir,
            command: TerminalSessionResolver.launchCommand(agent: agent, sessionId: sessionId,
                                                           hasTranscript: hasTranscript))
        else { return nil }
        tmux.setStatusBar(name, visible: false)
        // Eine Session, die es eben noch nicht gab, kann keinen lebenden Terminal-View haben: ein
        // zwischenzeitlich gescheitertes Attach („can't find session") hängt sonst als tote Ansicht
        // im Cache und würde auch die frische Session nie zeigen.
        await MainActor.run { TerminalCache.shared.remove(name) }
        return .created
    }

    /// Die Console liess sich nicht anlegen — das muss man sehen, statt in ein totes Terminal zu
    /// schauen. Die Warnung bleibt stehen (wie bei der Jira-Nachführung).
    private func noteConsoleFailure(name: String, repoDir: String) {
        newTaskConsoleSession = nil
        startWorkGeneration += 1
        startWorkNotice = StartWorkNotice(
            text: "Console \(name) liess sich nicht starten — Verzeichnis \(repoDir) prüfen.",
            isWarning: true)
    }

    static func newTaskSessionName(project: ProjectConfig) -> String {
        "kanban-\(project.key.uppercased())-new"
    }

    /// Pseudo-Ticket-Key im `SessionIdStore` — kollidiert nicht mit echten Keys (`PREFIX-123`).
    static func newTaskSessionStoreKey(project: ProjectConfig) -> String {
        "new:\(project.key.lowercased())"
    }

    /// Off-main typing worker: exits copy-mode first (a scrolled-back pane would swallow the
    /// keystrokes), then types the text — no Enter, the user confirms manually.
    private static func typeText(_ text: String, session: String, delaySeconds: Double = 0) {
        Task.detached {
            if delaySeconds > 0 { try? await Task.sleep(for: .seconds(delaySeconds)) }
            let tmux = TmuxController()
            guard tmux.isAvailable else { return }
            tmux.cancelCopyMode(session)
            tmux.sendText(session, text)
        }
    }

    // MARK: - Extra terminals

    /// The selected ticket's extra (user-spawned) terminal sessions.
    var extraTerminalSessions: [String] {
        guard let key = selectedTicketKey else { return [] }
        return extraTerminalsByTicket[key] ?? []
    }

    /// Spawns another terminal for the current ticket (plain shell in the worktree, else the repo),
    /// registers its tab, and returns the new tmux session name so the caller can select it.
    @discardableResult
    func addExtraTerminal() -> String? {
        guard let key = selectedTicketKey, let project = selectedProject else { return nil }
        let cwd = WorktreeScanner.worktree(for: key, in: worktrees)?.path ?? project.repoDir
        let suffix = UUID().uuidString.prefix(6).lowercased()
        let name = "kanban-\(key.uppercased())-term-\(suffix)"
        extraTerminalsByTicket[key, default: []].append(name)
        Task.detached {
            let tmux = TmuxController()
            guard tmux.isAvailable else { return }
            _ = tmux.createSession(name: name, cwd: cwd, command: nil)
            tmux.setStatusBar(name, visible: false)
            tmux.cancelCopyMode(name)
        }
        return name
    }

    /// Closes an extra terminal: detaches the view, kills its tmux session, and drops the tab.
    func closeExtraTerminal(_ session: String) {
        guard let key = selectedTicketKey else { return }
        extraTerminalsByTicket[key]?.removeAll { $0 == session }
        if (extraTerminalsByTicket[key]?.isEmpty ?? false) { extraTerminalsByTicket[key] = nil }
        TerminalCache.shared.remove(session)
        Task.detached { TmuxController().killSession(session) }
    }

    // MARK: - Worktree stack

    /// The worktree of the currently selected ticket (nil if it has none yet).
    ///
    /// **Gespeichert, nicht bei jedem Lesen abgeleitet.** Die Ableitung las `cards` mit (für den
    /// `sourceBranch` der `!<iid>`-Karten), und damit hing jede View, die nach dem Worktree fragt,
    /// an der ganzen Kartenliste — die schreibt `applyTimingsToCards` alle ~1,5 s, solange Claude
    /// antwortet, und `setAttention` ebenso. Das Stack-Panel baute daraufhin jedes Mal seine ganze
    /// Ausgabe neu, ohne dass sich an ihr etwas geändert hätte.
    ///
    /// Neu berechnet wird bei den drei Dingen, die den Wert wirklich bestimmen: andere Auswahl
    /// (`didSet` auf `selectedTicketKey`), neue Worktree-Liste, neue Tickets (beides in `refresh`).
    private(set) var currentWorktree: Worktree?

    /// Nur schreiben, wenn sich etwas ändert: eine Zuweisung an eine `@Observable`-Eigenschaft
    /// benachrichtigt auch dann, wenn der Wert derselbe ist.
    private func updateCurrentWorktree() {
        let next = selectedTicketKey.flatMap {
            WorktreeScanner.worktree(for: $0, in: worktrees, branch: selectedTicket?.sourceBranch)
        }
        if next != currentWorktree { currentWorktree = next }
    }

    /// Das gewählte Ticket samt seiner Herkunft — für ein Ticket ohne Nummer steht dort der Branch,
    /// über den es überhaupt gefunden wird.
    var selectedTicket: Ticket? {
        guard let key = selectedTicketKey else { return nil }
        return cards.first { $0.ticket.key == key }?.ticket
    }

    /// The ticket's numeric id used by `iwf worktree create` (e.g. BFEZVM-4569 → "4569").
    private var worktreeId: String? {
        selectedTicketKey?.split(separator: "-").last.map(String.init)
    }

    private enum WtOutput { case status, command }

    /// Hat das gewählte Projekt einen eigenen Docker-Stack (`dockerStack` in der Config)?
    ///
    /// **Der eine Riegel vor jedem Docker-/`iwf`-Weg.** Ein Projekt ohne Stack hat kein `.iwf.yml`,
    /// keine Container und keine Stack-URL — jeder Aufruf dorthin wäre entweder ein Fehler oder,
    /// schlimmer, ein Treffer im Stack eines gleichnamigen Ordners. Ohne gewähltes Projekt lautet
    /// die Antwort ebenfalls nein: dann gibt es nichts anzusprechen.
    var hasStack: Bool { selectedProject?.usesDockerStack ?? false }

    func refreshWorktreeStatus() {
        guard hasStack, let cwd = currentWorktree?.path else { return }
        worktreeDbDump = WorktreeDbSeed.staged(worktreePath: cwd)
        runIwf(["stack", "ps"], cwd: cwd, into: .status)
        Task { await refreshStackStatus() }
    }

    /// Die Branch-URL auf der Forge des Projekts (nil ohne Zuordnung). GitLab schiebt sein `/-/`
    /// zwischen Projekt und Ressource, GitHub nicht — die Unterscheidung steht in `ForgeKind`.
    func branchURL(for branch: String) -> URL? {
        forgeLocation?.branchURL(branch).flatMap(URL.init(string:))
    }

    /// Die Branch-URL des Worktrees (nil ohne Forge-Zuordnung).
    var worktreeBranchURL: URL? {
        currentWorktree?.branch.flatMap(branchURL(for:))
    }

    /// Die Stack-URL des Worktrees (`https://<name>.test`) — dieselbe, die der Domain-Status prüft.
    var worktreeStackURL: URL? {
        guard hasStack, let path = currentWorktree?.path else { return nil }
        return URL(string: "https://\((path as NSString).lastPathComponent).test")
    }

    /// Runs the repair a status row offers (`iwf stack build`, `iwf cert create`, `iwf yarn dev`,
    /// `iwf worktree start|restart`) in the worktree and refreshes the derived status afterwards.
    /// Zeigt den Befehl so, wie er wirklich abgesetzt wird — Argumente mit Leerzeichen in
    /// Anführungszeichen. Ohne das las sich `iwf run "pkill -f yarn"` als vier lose Argumente.
    static func displayCommand(_ arguments: [String]) -> String {
        "iwf " + arguments.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    func repairStack(_ repair: StackPhase.Repair) {
        guard hasStack, !worktreeBusy, let cwd = currentWorktree?.path else { return }
        let commands = repair.commands
        guard !commands.isEmpty else { return }

        // Der Vite-Dev-Server endet nie von selbst. Ihn wie die anderen Befehle abzuwarten würde die
        // Oberfläche bis zum Abschuss sperren — also starten, Ausgabe weiter mitschreiben, und den
        // Status kurz darauf neu lesen (dann steht die Zeile auf „läuft").
        if repair.isLongRunning {
            worktreeCommandOutput = "$ \(Self.displayCommand(commands[0]))\n\n"
            Task.detached { [weak self] in
                _ = WorktreeStackController().run(iwfArgs: commands[0], cwd: cwd) { chunk in
                    Task { @MainActor [weak self] in self?.appendWorktree(chunk, into: .command) }
                }
                await self?.refreshStackStatus()   // beim Beenden zurück auf „nicht gestartet“
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self?.refreshStackStatus()
            }
            return
        }

        worktreeBusy = true
        worktreeCommandOutput = ""

        Task.detached { [weak self] in
            for command in commands {
                await MainActor.run { [weak self] in
                    self?.worktreeCommandOutput += "$ \(Self.displayCommand(command))\n\n"
                }
                let code = WorktreeStackController().run(iwfArgs: command, cwd: cwd) { chunk in
                    Task { @MainActor [weak self] in self?.appendWorktree(chunk, into: .command) }
                }
                await MainActor.run { [weak self] in
                    self?.worktreeCommandOutput += "\n— fertig (exit \(code)) —\n\n"
                }
                // Kette abbrechen: ein `yarn build` nach fehlgeschlagenem `install` scheitert nur
                // erneut und verdeckt die eigentliche Ursache.
                if code != 0 { break }
            }
            await MainActor.run { [weak self] in self?.worktreeBusy = false }
            await self?.refreshStackStatus()
        }
    }

    /// Stages a DB seed for the current worktree: either from a remote environment (dev/qa/prod) or
    /// from a local dump file. Requires the stack to be down — Docker will not release the data
    /// volume otherwise, and without dropping it MySQL ignores the new dump entirely.
    func seedDatabase(from source: StackSeeder.Source, importNow: Bool = false) {
        guard hasStack, !worktreeBusy, let worktree = currentWorktree?.path,
              let repoDir = selectedProject?.repoDir else { return }
        let projectName = (repoDir as NSString).lastPathComponent
        let running = stackStatus?.running.count ?? 0
        worktreeBusy = true
        worktreeCommandOutput = "$ \(importNow ? "Import" : "Seed"): \(source.label)\n\n"

        Task.detached { [weak self] in
            do {
                let seeder = StackSeeder()
                let emit: @Sendable (String) -> Void = { chunk in
                    Task { @MainActor [weak self] in self?.appendWorktree(chunk, into: .command) }
                }
                if importNow {
                    try seeder.importNow(source: source, worktreePath: worktree,
                                         projectName: projectName, runningContainers: running,
                                         onOutput: emit)
                } else {
                    try seeder.seed(source: source, worktreePath: worktree,
                                    projectName: projectName, runningContainers: running,
                                    onOutput: emit)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.worktreeCommandOutput += "\n✗ \(error.localizedDescription)\n"
                }
            }
            await MainActor.run { [weak self] in
                self?.worktreeBusy = false
                self?.worktreeDbDump = WorktreeDbSeed.staged(worktreePath: worktree)
            }
            await self?.refreshStackStatus()
        }
    }

    /// Derives the stack state from Docker + the worktree directory. Read-only, so it can run on
    /// every tab visit without side effects.
    func refreshStackStatus() async {
        guard hasStack, let cwd = currentWorktree?.path, let repoDir = selectedProject?.repoDir else {
            stackStatus = nil; return
        }
        let projectName = (repoDir as NSString).lastPathComponent
        stackStatusLoading = true
        defer { stackStatusLoading = false }
        let status = await Task.detached {
            DockerStatusScanner().scan(worktreePath: cwd, projectName: projectName)
        }.value
        let parent = await Task.detached { BranchParentScanner().parent(worktreePath: cwd) }.value
        guard currentWorktree?.path == cwd else { return }   // ticket switched meanwhile
        stackStatus = status
        worktreeParentBranch = parent
    }

    /// Leitet die Branch-Hierarchie ab, wenn das Popover sie braucht — ~1 s Git-Arbeit, deshalb
    /// nicht in `refreshStackStatus`.
    func loadBranchStack() async {
        guard let cwd = currentWorktree?.path else { branchStack = nil; return }
        branchStackLoading = true
        defer { branchStackLoading = false }
        let tree = await Task.detached { BranchStackScanner().scan(worktreePath: cwd) }.value
        guard currentWorktree?.path == cwd else { return }   // ticket switched meanwhile
        branchStack = tree
    }

    func worktreeStart()   { runWorktreeLifecycle(["worktree", "start"]) }
    func worktreeStop()    { runWorktreeLifecycle(["worktree", "stop"]) }
    func worktreeRestart() { runWorktreeLifecycle(["worktree", "restart"]) }
    func worktreeDestroy() { runWorktreeLifecycle(["worktree", "destroy", "-f"]) }

    // MARK: - Beide Stacks über ein Ziel angesprochen

    /// Das Verzeichnis, in dem die `iwf`-Befehle dieses Stacks laufen — **nil ohne Stack**.
    ///
    /// Hier statt an jedem Aufrufer, weil jeder Stack-Weg hier durchkommt: Lebenszyklus, Status,
    /// Snapshots, Reparaturen und die URL. Ein Projekt ohne Stack hat kein solches Verzeichnis, und
    /// das ist die ehrlichere Antwort als ein Pfad, in dem `iwf` nichts zu suchen hätte.
    func directory(for target: StackTarget) -> String? {
        guard hasStack else { return nil }
        switch target {
        case .worktree: return currentWorktree?.path
        case .maintree: return selectedProject?.repoDir
        }
    }

    /// Der Branch, der dort ausgecheckt ist. Beim Haupt-Repo steht er in derselben
    /// `git worktree list`-Ausgabe wie die Worktrees — es ist dort schlicht der erste Eintrag.
    func branch(for target: StackTarget) -> String? {
        switch target {
        case .worktree: return currentWorktree?.branch
        case .maintree:
            guard let repoDir = selectedProject?.repoDir else { return nil }
            let wanted = (repoDir as NSString).standardizingPath
            return worktrees.first { ($0.path as NSString).standardizingPath == wanted }?.branch
        }
    }

    /// `https://<ordnername>.<stackDomain>` — beim Haupt-Repo der Repo-Ordner, beim Worktree dessen.
    func stackURL(for target: StackTarget) -> URL? {
        guard let path = directory(for: target) else { return nil }
        return URL(string: "https://\((path as NSString).lastPathComponent).test")
    }

    func stackStatus(for target: StackTarget) -> WorktreeStackStatus? {
        target == .worktree ? stackStatus : maintreeStackStatus
    }

    func isLoadingStatus(for target: StackTarget) -> Bool {
        target == .worktree ? stackStatusLoading : maintreeStatusLoading
    }

    func isBusy(_ target: StackTarget) -> Bool {
        target == .worktree ? worktreeBusy : maintreeBusy
    }

    func statusText(for target: StackTarget) -> String {
        target == .worktree ? worktreeStatusText : maintreeStatusText
    }

    func commandOutput(for target: StackTarget) -> String {
        target == .worktree ? worktreeCommandOutput : maintreeCommandOutput
    }

    /// `iwf stack ps` + die abgeleitete Herleitung, für das gewählte Ziel.
    func refreshStatus(for target: StackTarget) {
        switch target {
        case .worktree:
            refreshWorktreeStatus()
        case .maintree:
            guard let cwd = directory(for: .maintree) else { return }
            runIwf(["stack", "ps"], cwd: cwd, into: .status, stack: .maintree)
            Task { await refreshDerivedStatus(for: .maintree) }
        }
    }

    /// Leitet den Zustand aus Docker ab — read-only, deshalb bei jedem Tab-Besuch. Für das
    /// Haupt-Repo ist der „Worktree-Pfad" schlicht das Repo selbst; der Stack-Name ist so oder so
    /// der Ordnername, deshalb reicht derselbe Scanner.
    func refreshDerivedStatus(for target: StackTarget) async {
        guard target == .maintree else { await refreshStackStatus(); return }
        guard hasStack, let repoDir = selectedProject?.repoDir else { maintreeStackStatus = nil; return }
        let projectName = (repoDir as NSString).lastPathComponent
        maintreeStatusLoading = true
        defer { maintreeStatusLoading = false }
        maintreeStackStatus = await Task.detached {
            DockerStatusScanner().scan(worktreePath: repoDir, projectName: projectName)
        }.value
    }

    /// Start/Stop/Neustart. Der Worktree läuft über `iwf worktree …` (iwf findet ihn über seine
    /// Nummer), das Haupt-Repo über `iwf stack …` im eigenen Verzeichnis — gegen `iwf stack --help`
    /// geprüft. **Destroy gibt es hier nicht**: aus dem Haupt-Repo nähme es wegen des
    /// Substring-Filters jedes `local/<projekt>-*`-Image mit.
    func lifecycle(_ action: StackLifecycle, for target: StackTarget) {
        guard let cwd = directory(for: target) else { return }
        let args: [String]
        switch (action, target) {
        case (.start, .worktree):   args = ["worktree", "start"]
        case (.stop, .worktree):    args = ["worktree", "stop"]
        case (.restart, .worktree): args = ["worktree", "restart"]
        case (.start, .maintree):   args = ["stack", "start"]
        case (.stop, .maintree):    args = ["stack", "stop"]
        case (.restart, .maintree): args = ["stack", "restart"]
        }
        runIwf(args, cwd: cwd, into: .command, stack: target, thenRefresh: true)
    }

    // MARK: - DB-Snapshots

    /// Der Stack-Name des Ziels — Ordnername des Worktrees bzw. des Repos. Derselbe Wert, den
    /// `DockerStatusScanner` benutzt und unter dem iwf seine Snapshots ablegt.
    func stackName(for target: StackTarget) -> String? {
        directory(for: target).map { ($0 as NSString).lastPathComponent }
    }

    func snapshots(for target: StackTarget) -> [DbSnapshot] {
        target == .worktree ? worktreeSnapshots : maintreeSnapshots
    }

    /// Liest den Snapshot-Ordner neu — read-only, kostet nichts, deshalb bei jedem Tab-Besuch.
    func refreshSnapshots(for target: StackTarget) {
        guard let stack = stackName(for: target) else { return }
        let list = DbSnapshots.list(stack: stack)
        switch target {
        case .worktree: worktreeSnapshots = list
        case .maintree: maintreeSnapshots = list
        }
    }

    /// Legt einen Snapshot an: ohne `label` als `latest` (überschreibt den vorhandenen), mit
    /// `label` über `-t` und anschliessendes Umbenennen — `iwf` selbst kennt keine Namen, aber
    /// `restore -f` nimmt jeden Basename aus dem Ordner.
    ///
    /// `iwf db snapshot create` **stoppt die Datenbank** und startet sie danach wieder; das dauert
    /// und steht deshalb in der Ausgabe.
    func createSnapshot(label: String?, for target: StackTarget) {
        guard !isBusy(target), let cwd = directory(for: target),
              let stack = stackName(for: target) else { return }
        let before = DbSnapshots.list(stack: stack)
        let timestamped = label != nil
        let args = ["db", "snapshot", "create"] + (timestamped ? ["-t"] : [])

        setBusy(true, target)
        setText("$ \(Self.displayCommand(args))\n\n", .command, target)
        Task.detached { [weak self] in
            let code = WorktreeStackController().run(iwfArgs: args, cwd: cwd) { chunk in
                Task { @MainActor [weak self] in self?.appendWorktree(chunk, into: .command, stack: target) }
            }
            var renameNote = ""
            if code == 0, let label {
                let after = DbSnapshots.list(stack: stack)
                if let fresh = DbSnapshots.added(before: before, after: after) {
                    let volume = DbSnapshots.defaultVolume(stack: stack)
                    let target = (DbSnapshots.directory(stack: stack) as NSString)
                        .appendingPathComponent(DbSnapshots.fileName(volume: volume, label: label))
                    do {
                        if FileManager.default.fileExists(atPath: target) {
                            try FileManager.default.removeItem(atPath: target)
                        }
                        try FileManager.default.moveItem(atPath: fresh.path, toPath: target)
                        renameNote = "\numbenannt: \((target as NSString).lastPathComponent)\n"
                    } catch {
                        renameNote = "\n✗ Umbenennen fehlgeschlagen: \(error.localizedDescription)\n"
                    }
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !renameNote.isEmpty { self.appendWorktree(renameNote, into: .command, stack: target) }
                self.appendWorktree("\n— fertig (exit \(code)) —\n", into: .command, stack: target)
                self.setBusy(false, target)
                self.refreshSnapshots(for: target)
            }
            await self?.refreshDerivedStatus(for: target)
        }
    }

    /// Spielt einen Snapshot zurück. **`-y` ist Pflicht**: `iwf db snapshot restore` fragt sonst im
    /// Terminal nach und bliebe hier für immer stehen — die Bestätigung holt Kanban vorher selbst.
    func restoreSnapshot(_ snapshot: DbSnapshot, for target: StackTarget) {
        guard !isBusy(target), let cwd = directory(for: target) else { return }
        let args = ["db", "snapshot", "restore", "-f", snapshot.name, "-y"]
        runIwf(args, cwd: cwd, into: .command, stack: target, thenRefresh: true)
    }

    /// Die Reparatur einer Status-Zeile, im Verzeichnis des gewählten Ziels.
    func repairStack(_ repair: StackPhase.Repair, for target: StackTarget) {
        guard target == .maintree else { repairStack(repair); return }
        guard !maintreeBusy, let cwd = directory(for: .maintree) else { return }
        let commands = repair.commands(for: .maintree)
        guard !commands.isEmpty else { return }

        if repair.isLongRunning {
            maintreeCommandOutput = "$ \(Self.displayCommand(commands[0]))\n\n"
            Task.detached { [weak self] in
                _ = WorktreeStackController().run(iwfArgs: commands[0], cwd: cwd) { chunk in
                    Task { @MainActor [weak self] in
                        self?.appendWorktree(chunk, into: .command, stack: .maintree)
                    }
                }
                await self?.refreshDerivedStatus(for: .maintree)
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                await self?.refreshDerivedStatus(for: .maintree)
            }
            return
        }

        maintreeBusy = true
        maintreeCommandOutput = ""
        Task.detached { [weak self] in
            for command in commands {
                await MainActor.run { [weak self] in
                    self?.appendWorktree("$ \(Self.displayCommand(command))\n\n",
                                         into: .command, stack: .maintree)
                }
                let code = WorktreeStackController().run(iwfArgs: command, cwd: cwd) { chunk in
                    Task { @MainActor [weak self] in
                        self?.appendWorktree(chunk, into: .command, stack: .maintree)
                    }
                }
                if code != 0 { break }
            }
            await MainActor.run { [weak self] in self?.maintreeBusy = false }
            await self?.refreshDerivedStatus(for: .maintree)
        }
    }

    // MARK: - Stack-Sweep („N Stacks stoppen" in der Toolbar)

    /// Welche Worktree-Stacks laufen und ob ihr Ticket sie noch braucht — bei jedem Refresh neu
    /// abgeleitet. Ein gemerkter „schon abgeräumt"-Zustand wäre falsch, sobald jemand den Stack von
    /// Hand wieder hochfährt; so ist ein gestoppter Stack einfach kein Kandidat mehr.
    private(set) var stackSweep: StackSweepPlan = .empty
    /// Auswahl im Sheet. Vorgewählt sind Review/Done ohne laufenden Turn; alles andere darf man
    /// dazuwählen — gestoppt ist reversibel (`iwf worktree start <NR>`).
    var stackSweepSelection: Set<String> = []
    /// Welche der gewählten Stacks **tief** abgeräumt werden (Volumes + Images dazu). Getrennt von
    /// der Auswahl, weil es die destruktive Hälfte ist: stoppen ist ein Knopfdruck rückgängig,
    /// gelöschte Volumes kommen nur über den bereitgestellten Dump zurück.
    var stackSweepDeep: Set<String> = []
    private(set) var stackSweepBusy = false
    private(set) var stackSweepOutput = ""
    var stackSweepPresented = false

    /// Ein `docker ps` für die ganze Maschine, dazu die schon geladenen Worktrees und Karten.
    /// Läuft bei jedem Board-Refresh mit, damit der Toolbar-Zähler ohne Klick stimmt.
    func loadStackSweep() async {
        guard hasStack, let repoDir = selectedProject?.repoDir else { stackSweep = .empty; return }
        let projectName = (repoDir as NSString).lastPathComponent
        let sweepCards = cards.map {
            StackSweepCard(key: $0.ticket.key, column: $0.column,
                           isWorking: $0.claudeRunningSince != nil
                               || workingTickets.contains($0.ticket.key))
        }
        let trees = worktrees
        // Ein Rutsch statt drei Runden über die Docker-CLI, und die Dump-Prüfung (nur ein
        // Verzeichnis-Listing je Worktree) gleich mit — sonst hätte die Tiefen-Stufe keine
        // Rückfahrkarte anzuzeigen.
        let probe = await Task.detached { () -> ([String], [String], [String], [String: String]) in
            let scanner = DockerStatusScanner()
            var dumps: [String: String] = [:]
            for tree in trees {
                if let dump = WorktreeDbSeed.staged(worktreePath: tree.path) {
                    dumps[tree.path] = dump.fileName
                }
            }
            return (scanner.runningContainerNames(), scanner.volumeNames(), scanner.imageTags(), dumps)
        }.value
        guard selectedProject?.repoDir == repoDir else { return }   // Projekt wechselte inzwischen
        stackSweep = StackSweep.plan(cards: sweepCards, worktrees: trees, repoDir: repoDir,
                                     runningContainers: probe.0, projectName: projectName,
                                     volumes: probe.1, imageTags: probe.2, stagedDumps: probe.3)
        // Was inzwischen kein Kandidat mehr ist, kann auch nicht mehr ausgewählt sein.
        let known = Set(stackSweep.candidates.map(\.stackName))
        stackSweepSelection.formIntersection(known)
        stackSweepDeep.formIntersection(Set(stackSweep.candidates.filter(\.canDeepClean).map(\.stackName)))
    }

    // MARK: - Knowledgebase

    /// 📚 auf/zu. Ohne konfigurierten Pfad gibt es den Knopf gar nicht, also auch hier nichts zu tun.
    func toggleKnowledgebase() {
        guard selectedProject?.kbPathAbsolute != nil else { return }
        knowledgebaseOpen.toggle()
        if knowledgebaseOpen && kbNodes.isEmpty { loadKnowledgebase() }
    }

    func closeKnowledgebase() {
        knowledgebaseOpen = false
    }

    /// Liest den Baum neu ein — beim Öffnen und über den Aktualisieren-Knopf der Ansicht.
    ///
    /// Der Scan läuft **detached**: eine Knowledgebase mit ein paar hundert Dateien ist in
    /// Millisekunden gelesen, aber der Ordner kann auch ein grosses Repo sein, und das Fenster soll
    /// dabei nicht stehen. Die Auswahl bleibt, wenn es die Datei noch gibt; sonst führt der Einstieg
    /// (`artefacts/index.html`, sonst README/index — siehe `KnowledgebaseTree.entryFile`) wieder
    /// irgendwohin statt ins Leere.
    func loadKnowledgebase() {
        guard let root = selectedProject?.kbPathAbsolute else {
            kbNodes = []
            return
        }
        kbLoading = true
        Task { [weak self] in
            let nodes = await Task.detached { KnowledgebaseTree.build(root: root) }.value
            guard let self, self.selectedProject?.kbPathAbsolute == root else { return }
            self.kbNodes = nodes
            self.kbLoading = false
            let stillThere = self.kbSelection.flatMap { KnowledgebaseTree.node(at: $0, in: nodes) }
            if stillThere == nil {
                self.kbSelection = KnowledgebaseTree.entryFile(nodes)?.path
            }
        }
    }

    func openStackSweep() {
        guard hasStack else { return }
        stackSweepOutput = ""
        stackSweepPresented = true
        stackSweepDeep = []     // die destruktive Stufe ist nie vorgewählt
        Task {
            await loadStackSweep()
            stackSweepSelection = stackSweep.preselected
        }
    }

    /// Stoppt die gewählten Stacks: `iwf worktree stop <NR>` je Stack, aus dem Haupt-Repo heraus
    /// (so, wie `worktree.md` es vorschreibt — und mit der Nummer, damit kein `cd` in einen Worktree
    /// nötig ist, den es vielleicht nicht mehr gibt).
    ///
    /// Der reversible Teil des Abräumens: Container und Netzwerk gehen, **Worktree, Branch, Image
    /// und DB-Volume bleiben** (`iwf worktree stop` = `compose down` ohne `--volumes`). Damit ist der
    /// Sweep RAM/CPU-Rückgewinnung, keine Datenlöschung — `destroy` wäre das und ist hier bewusst
    /// nicht verdrahtet.
    ///
    /// Sequenziell, nicht parallel: mehrere gleichzeitige `compose down` auf dieselbe Docker-Engine
    /// bringen nur Gedrängel, und die Ausgabe wäre nicht mehr lesbar zuzuordnen.
    func runStackSweep() {
        guard hasStack, !stackSweepBusy, let repoDir = selectedProject?.repoDir else { return }
        let targets = stackSweep.candidates.filter { stackSweepSelection.contains($0.stackName) }
        guard !targets.isEmpty else { return }
        // Nur was auch tief abgeräumt werden *darf* — die Auswahl kann älter sein als die Liste.
        let deep = stackSweepDeep.intersection(Set(targets.filter(\.canDeepClean).map(\.stackName)))
        stackSweepBusy = true
        stackSweepOutput = ""

        Task.detached { [weak self] in
            for target in targets {
                await MainActor.run { [weak self] in
                    self?.appendSweep("$ iwf worktree stop \(target.number)   → \(target.stackName)\n")
                }
                let code = WorktreeStackController()
                    .run(iwfArgs: ["worktree", "stop", target.number], cwd: repoDir) { chunk in
                        Task { @MainActor [weak self] in self?.appendSweep(chunk) }
                    }
                // „fertig", nicht „gestoppt": Exit 0 beweist es nicht — `iwf worktree stop` endet
                // auch mit 0, wenn es den Worktree gar nicht gefunden hat (dann steht der Grund im
                // Text darüber). Den Beweis liefert die neu gelesene Liste unten: ein Stack, der
                // noch läuft, steht danach wieder da.
                await MainActor.run { [weak self] in
                    self?.appendSweep(code == 0 ? "\n— fertig —\n\n"
                                                : "\n— fehlgeschlagen (exit \(code)) —\n\n")
                }
                // Tiefe Stufe nur nach erfolgreichem Stop: solange Container existieren, hält
                // Docker die Volumes fest („volume is in use"), und ein halb gelöschter Stack wäre
                // schlimmer als ein laufender.
                guard code == 0, deep.contains(target.stackName) else { continue }
                await self?.deepClean(target, cwd: repoDir)
            }
            await MainActor.run { [weak self] in self?.stackSweepBusy = false }
            await self?.loadStackSweep()        // Zähler und Liste gegen die neue Wirklichkeit
            await self?.refreshStackStatus()    // war der offene Ticket-Stack dabei, sagt es das Panel
        }
    }

    /// Volumes und Images eines gestoppten Stacks löschen — die Stufe, für die iwf keinen Befehl
    /// hat (siehe `WorktreeStackController.run(shellScript:)`).
    ///
    /// Gelöscht wird nur, was der Scan **gefunden** hat: ein Stack hat hier zwei Volumes
    /// (`_dbdata` und, grösser, `_appcache`) und zwei Image-Tags (`local/<name>:latest` und
    /// `local/<name>-base:latest`). Geratene Namen hätten je die Hälfte liegen lassen.
    ///
    /// Erwartungsmanagement, gemessen auf dieser Maschine: die Volumes bringen ~0,85 GB je Stack
    /// (24,1 GB in 41 `appcache`, 9,9 GB in 41 `dbdata`), die Images fast nichts — `local/even-3563`
    /// zeigt 1,51 GB, davon sind 1,32 GB **geteilte** Layer und nur 187 MB exklusiv. Das Image
    /// fliegt trotzdem mit, weil ein Tag ohne Stack nur noch Verwirrung ist.
    private func deepClean(_ candidate: StackSweepCandidate, cwd: String) async {
        let controller = WorktreeStackController()
        for command in StackSweep.deepCleanCommands(candidate) {
            await MainActor.run { appendSweep("$ \(command)\n") }
            let code = controller.run(shellScript: command, cwd: cwd) { chunk in
                Task { @MainActor [weak self] in self?.appendSweep(chunk) }
            }
            await MainActor.run {
                appendSweep(code == 0 ? "\n" : "\n— fehlgeschlagen (exit \(code)) —\n")
            }
        }
    }

    @MainActor
    private func appendSweep(_ chunk: String) {
        stackSweepOutput = LogText.appending(stackSweepOutput, chunk)
    }

    /// Creates the worktree + stack for a ticket that has none yet (run from the main repo).
    func worktreeCreate() {
        guard hasStack, let id = worktreeId, let repo = selectedProject?.repoDir else { return }
        runIwf(["worktree", "create", id, "--start"], cwd: repo, into: .command, thenRefresh: true)
    }

    private func runWorktreeLifecycle(_ args: [String]) {
        guard hasStack, let cwd = currentWorktree?.path else { return }
        runIwf(args, cwd: cwd, into: .command, thenRefresh: true)
    }

    private func runIwf(_ args: [String], cwd: String, into output: WtOutput,
                        stack: StackTarget = .worktree, thenRefresh: Bool = false) {
        guard !isBusy(stack) else { return }
        setBusy(true, stack)
        switch output {
        case .status:  setText("Lade Status…\n", output, stack)
        case .command: setText("$ iwf \(args.joined(separator: " "))\n\n", output, stack)
        }
        Task.detached { [weak self] in
            let code = WorktreeStackController().run(iwfArgs: args, cwd: cwd) { chunk in
                Task { @MainActor [weak self] in self?.appendWorktree(chunk, into: output, stack: stack) }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.setBusy(false, stack)
                if output == .command {
                    self.appendWorktree("\n— fertig (exit \(code)) —\n", into: .command, stack: stack)
                }
                if thenRefresh { self.refreshStatus(for: stack) }
            }
        }
    }

    @MainActor
    private func appendWorktree(_ chunk: String, into output: WtOutput,
                                stack: StackTarget = .worktree) {
        switch output {
        case .status:
            if statusText(for: stack) == "Lade Status…\n" { setText("", output, stack) }
            setText(statusText(for: stack) + chunk, output, stack)
        case .command:
            // `LogText` prüft die Grösse in **Bytes** und kappt in Blöcken auf Zeilengrenze;
            // `String.count` zählte hier die Graphemcluster des ganzen Puffers — bei einem Anhängen
            // je pty-Lesevorgang war das die teuerste Zeile des Streams.
            setText(LogText.appending(commandOutput(for: stack), chunk), output, stack)
        }
    }

    private func setBusy(_ value: Bool, _ stack: StackTarget) {
        switch stack {
        case .worktree: worktreeBusy = value
        case .maintree: maintreeBusy = value
        }
    }

    private func setText(_ value: String, _ output: WtOutput, _ stack: StackTarget) {
        switch (output, stack) {
        case (.status, .worktree):  worktreeStatusText = value
        case (.status, .maintree):  maintreeStatusText = value
        case (.command, .worktree): worktreeCommandOutput = value
        case (.command, .maintree): maintreeCommandOutput = value
        }
    }

    private func loadDetail(for key: String) {
        watcher?.cancel(); watcher = nil
        watchTask?.cancel(); watchTask = nil
        reviewWatcher?.cancel(); reviewWatcher = nil
        reviewWatchTask?.cancel(); reviewWatchTask = nil
        taskFile = nil
        reviewMarkdowns = []
        fallbackSections = []
        displaySections = []
        questionSectionIDs = []; decisionSectionIDs = []
        taskAttachments = []
        taskFolders = []
        taskAttachmentSelection = nil
        worktreeStatusText = ""
        worktreeCommandOutput = ""
        worktreeDbDump = nil
        solution = nil
        solutionError = nil
        guard let project = selectedProject else { return }
        let dir = project.tasksPathAbsolute
        loadSolution(for: key, project: project)
        // Unabhängig vom Task-File: ein Ticket kann Anhänge haben, bevor jemand ein Task-File
        // angelegt hat (`get-task` legt beides an, aber nicht in einem Zug).
        rescanAttachments(for: key, in: dir)

        if let url = TaskFileLoader.find(ticketKey: key, in: dir) {
            taskFile = TaskFileLoader.load(url)
            let w = TaskFileWatcher(path: url.path)
            watcher = w
            watchTask = Task { [weak self] in
                for await _ in w.events {
                    try? await Task.sleep(nanoseconds: 150_000_000)  // debounce
                    guard let self, self.selectedTicketKey == key else { return }
                    self.taskFile = TaskFileLoader.load(url)
                    self.refreshSectionSignals()
                }
            }
            loadReviews(for: key, in: dir)
            refreshSectionSignals()
        } else if let ticket = selectedTicket, ticket.isBranchOnly {
            // Ein Ticket ohne Nummer steht in keinem Jira — danach zu fragen gäbe einen 404 und die
            // Zeile „keine Beschreibung", und der freie Modus soll ohnehin ohne Jira auskommen.
            fallbackSections = [branchTicketSection(ticket)]
            refreshSectionSignals()
        } else {
            loadJiraFallback(for: key, project: project)
        }
    }

    /// Was ein Ticket ohne Nummer zu zeigen hat: seinen MR und seinen Branch — und den Hinweis, wie
    /// daraus ein richtiger Task wird. Mehr gibt es nicht; genau deshalb steht die Karte ja da.
    private func branchTicketSection(_ ticket: Ticket) -> TaskSection {
        let branch = ticket.sourceBranch ?? ""
        let card = cards.first { $0.ticket.key == ticket.key }
        let mr = card?.mergeRequestURL
        var lines = ["**\(ticket.summary)**", ""]
        lines.append("> 🌿 **BRANCH**: `\(branch)`")
        if let mr {
            lines.append("> 🔀 **\((card?.forge ?? forgeKind).requestNoun.uppercased())**: \(mr)")
        }
        lines.append("")
        lines.append("_Dieser Branch trägt keine Ticketnummer — es gibt kein Jira-Ticket und (noch) "
                     + "kein Task-File._")
        lines.append("")
        lines.append("Über **Task erstellen** im Kontextmenü der Karte wird daraus ein richtiger "
                     + "Task: `/create-task` erfindet die Nummer und legt das Task-File an.")
        return TaskSection(id: 0, title: "Branch", markdown: lines.joined(separator: "\n"))
    }

    /// Loads all `<KEY>_review*.md` (shown as numbered "Review" tabs). Watches the **tasks directory**
    /// so new/removed review files and their (atomic) content changes are all picked up live.
    private func loadReviews(for key: String, in dir: String) {
        rescanReviews(for: key, in: dir)
        let w = TaskFileWatcher(path: dir)
        reviewWatcher = w
        reviewWatchTask = Task { [weak self] in
            for await _ in w.events {
                try? await Task.sleep(nanoseconds: 200_000_000)  // debounce (the dir is chatty)
                guard let self, self.selectedTicketKey == key else { return }
                self.rescanReviews(for: key, in: dir)
            }
        }
    }

    private func rescanReviews(for key: String, in dir: String) {
        reviewMarkdowns = TaskFileLoader.reviewFiles(ticketKey: key, in: dir)
            .compactMap { TaskFileLoader.loadReviewMarkdown($0) }
        refreshSectionSignals()
        // Derselbe Wächter sieht auch, wenn der Task-Ordner des Tickets entsteht oder verschwindet
        // — er liegt im selben Verzeichnis. Was **innerhalb** des Ordners passiert, sieht er nicht;
        // dafür steht der Neu-Einlesen-Knopf im Panel.
        rescanAttachments(for: key, in: dir)
    }

    /// Liest den Task-Ordner neu ein. Eine Auswahl, deren Datei es nicht mehr gibt, fällt weg —
    /// sonst stünde rechts die Vorschau einer gelöschten Datei.
    private func rescanAttachments(for key: String, in dir: String) {
        taskFolders = TaskAttachments.folders(ticketKey: key, in: dir)
        taskAttachments = TaskAttachments.tree(ticketKey: key, in: dir)
        if let selection = taskAttachmentSelection,
           KnowledgebaseTree.node(at: selection, in: taskAttachments) == nil {
            taskAttachmentSelection = nil
        }
    }

    /// Neu einlesen auf Knopfdruck (Panel-Kopfzeile) — für Dateien, die *im* Task-Ordner dazukommen.
    // MARK: - Task-File aus dem Ticket erzeugen

    /// Läuft, während der Export arbeitet — die Aktion braucht eine Weile (Issue, Unteraufgaben,
    /// Kommentare, jedes Bild ein Download).
    private(set) var isGeneratingTaskFile = false

    /// Erzeugt den Task-Ordner zum gewählten Ticket nativ, ohne Umweg über Hermes' MCP-Server.
    ///
    /// Geschrieben wird `<TICKET>.md`. Die Umbenennung auf `<TICKET>_<english_title>.md` bleibt bei
    /// `get-task`: sie verlangt einen englischen Kurztitel, und den erzeugt ein Sprachmodell. Was
    /// die App dagegen nachholen kann und muss, ist der `### Status`-Block — ohne ihn hätte die
    /// Karte keinen Marker, denn der Generator schreibt bewusst genau Hermes' Bytes.
    ///
    /// **Der Export ist unredigiert.** Die Anonymisierung ist noch nicht portiert; bis dahin steht
    /// im Task-Ordner, was im Ticket steht. Für Hermes gilt mit abgeschalteter Anonymisierung
    /// dasselbe — der Unterschied entsteht erst, wenn dort jemand einschaltet.
    func generateTaskFile(for key: String) async {
        guard let project = selectedProject, let jira, !isGeneratingTaskFile else { return }
        isGeneratingTaskFile = true
        defer { isGeneratingTaskFile = false }

        let tasksDirectory = URL(fileURLWithPath: project.tasksPathAbsolute, isDirectory: true)
        let baseUrl = project.jiraBaseUrl
        let generator = jira.taskGenerator(baseUrls: [baseUrl])

        do {
            let output = try await generator.generate(ticketKey: key, baseUrl: baseUrl,
                                                      tasksDirectory: tasksDirectory)
            // Der Generator bleibt bei Hermes' Bytes; den Marker setzt der Aufrufer.
            _ = TaskFileLoader.writeStatus(.offen, url: output.path)
            errorMessage = nil
            if selectedTicketKey == key { loadDetail(for: key) }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadTaskAttachments() {
        guard let key = selectedTicketKey, let project = selectedProject else { return }
        rescanAttachments(for: key, in: project.tasksPathAbsolute)
    }

    /// Was der 📁-Knopf in der Tableiste im Finder aufmacht.
    ///
    /// Der **Task-Ordner** des Tickets, sobald es einen gibt — dort liegt alles, was `get-task`
    /// mitgeholt hat. Gibt es keinen (die Mehrheit der Tickets hat keine Anhänge), wird statt dessen
    /// das **Task-File** im Tasks-Verzeichnis ausgewählt: der Ordner ist derselbe, und „hier liegt
    /// deine Datei" ist eine bessere Antwort als ein toter Knopf. Gibt es beides nicht (reines
    /// Jira-Ticket), gibt es auch den Knopf nicht — er zeigte auf nichts.
    enum FinderTarget: Equatable {
        case folder(URL)   // wird geöffnet (man will die Dateien sehen)
        case file(URL)     // wird im Finder ausgewählt (der Ordner enthält 643 Task-Files)
    }

    var taskFinderTarget: FinderTarget? {
        if let folder = taskFolders.first { return .folder(folder) }
        if let url = taskFile?.url { return .file(url) }
        return nil
    }

    /// Der Ordner, gegen den relative Pfade in den Anhängen gelten: das Tasks-Verzeichnis, **nicht**
    /// der Ticket-Ordner. `comments.json` verweist auf seine Profilbilder als
    /// `CORETEST-4214/avatars/…` — eine Ebene höher, genau wie im Task-File.
    var taskAttachmentBaseDirectory: URL? {
        selectedProject.map { URL(fileURLWithPath: $0.tasksPathAbsolute) }
    }

    private func loadJiraFallback(for key: String, project: ProjectConfig) {
        detailLoading = true
        Task { [weak self] in
            guard let self else { return }
            var description = ""
            if let jira = self.jira,
               let desc = try? await jira.issueDescription(key: key, baseUrl: project.jiraBaseUrl) {
                description = desc
            }
            guard self.selectedTicketKey == key else { return }
            let summary = self.cards.first { $0.ticket.key == key }?.ticket.summary ?? key
            let header = "**\(summary)**\n\n_Kein Task-File vorhanden — Jira-Beschreibung:_\n\n"
            let body = description.isEmpty ? "_(keine Beschreibung)_" : description
            self.fallbackSections = [TaskSection(id: 0, title: "Beschreibung", markdown: header + body)]
            self.detailLoading = false
            self.refreshSectionSignals()
        }
    }

    // MARK: - Polling

    private static func launchArg(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)  // 45s
                guard let self else { return }
                // Im freien Modus gibt es keinen Sprint, an dem der Poll hängen könnte — dort ist
                // gerade das lokale Dateisystem die Quelle und will beobachtet werden.
                if self.boardMode == .free || self.selectedChoice != nil { await self.refresh() }
            }
        }
    }

    // MARK: - Attention (console waiting for an answer)

    /// Watches the hook marker directory so a `Notification`/`UserPromptSubmit` flips the card ❓
    /// within a moment, without waiting for the 45 s board poll.
    private func startAttentionWatch() {
        attentionWatchTask?.cancel()
        let watcher = TaskFileWatcher(path: AttentionMarkers.directory.path)
        attentionWatcher = watcher
        attentionWatchTask = Task { [weak self] in
            for await _ in watcher.events {
                guard let self else { return }
                self.recomputeAttention(notify: true)
            }
        }
    }

    /// Hook-marker view: tickets whose stored session id currently has an attention marker.
    private func hookAttentionTickets() -> Set<String> {
        let active = AttentionMarkers.activeSessionIds()
        return Set(sessionIdByTicket.compactMap { active.contains($0.value) ? $0.key : nil })
    }

    /// Recomputes attention from hook markers, repaints the cards, and (optionally) fires a macOS
    /// notification for tickets that just started waiting. The pane fallback augments this via
    /// `refreshPaneAttention()`.
    private func recomputeAttention(notify: Bool) {
        let next = hookAttentionTickets().union(attentionTickets.intersection(paneOnlyTickets))
        setAttention(next, notify: notify)
    }

    /// Tickets flagged purely by the pane fallback (no hook marker) — kept across hook recomputes so
    /// a picker detected on a pre-hook session doesn't flicker off.
    private var paneOnlyTickets: Set<String> = []

    private func setAttention(_ next: Set<String>, notify: Bool) {
        if notify {
            for key in next.subtracting(attentionTickets) { notifyAttention(ticketKey: key) }
        }
        // A ticket that stopped waiting can re-notify immediately next time.
        for key in attentionTickets.subtracting(next) { AttentionNotifier.shared.clearThrottle(ticketKey: key) }
        AttentionNotifier.shared.updateBadge(count: next.count)   // red Dock badge = # waiting
        guard next != attentionTickets || cards.contains(where: { $0.needsAttention != next.contains($0.ticket.key) }) else { return }
        attentionTickets = next
        cards = cards.map { var c = $0; c.needsAttention = next.contains($0.ticket.key); return c }
        regroupColumns()
    }

    /// tmux-pane fallback: catches consoles started before the hook was installed and self-heals
    /// stale markers (a session visibly working again gets its marker cleared). Runs off-main.
    private func refreshPaneAttention() async {
        let map = sessionIdByTicket
        let tickets = Array(map.keys)
        let scan: (waiting: Set<String>, working: Set<String>, resumed: [String]) = await Task.detached {
            let tmux = TmuxController()
            guard tmux.isAvailable else { return ([], [], []) }
            let live = Set(tmux.listSessions().map(\.name))
            var waiting: Set<String> = []
            var working: Set<String> = []
            var resumed: [String] = []
            for ticket in tickets {
                let session = TerminalSessionResolver.sessionName(forTicket: ticket)
                guard live.contains(session), let pane = tmux.capturePane(session) else { continue }
                if PaneAttention.showsQuestion(pane) {
                    waiting.insert(ticket)
                } else if PaneAttention.isWorking(pane) {
                    working.insert(ticket)                             // ⏱ its turn clock is running
                    if let sid = map[ticket] { resumed.append(sid) }   // clear a stale marker: Claude is busy again
                }
            }
            return (waiting, working, resumed)
        }.value

        for sid in scan.resumed { AttentionMarkers.clear(sessionId: sid) }
        workingTickets = scan.working
        applyTimingsToCards()   // a turn that just started/ended flips the running flag
        paneOnlyTickets = scan.waiting.subtracting(hookAttentionTickets())
        setAttention(hookAttentionTickets().union(scan.waiting), notify: true)
    }

    /// Posts a click-to-select macOS notification when a ticket's console starts waiting.
    private func notifyAttention(ticketKey: String) {
        let summary = cards.first { $0.ticket.key == ticketKey }?.ticket.summary
        AttentionNotifier.shared.post(ticketKey: ticketKey, summary: summary)
    }

    // MARK: - Claude time (⏱ per prompt+answer, cumulated)

    /// The selected ticket's session timing (nil when Claude never ran for it).
    var selectedTiming: ClaudeSessionTiming? {
        selectedTicketKey.flatMap { timingByTicket[$0] }
    }

    /// Start of the turn that is running right now for a ticket, or nil when nothing runs. The rule
    /// itself is pure logic in `LiveTurn` (testable there); the app only supplies the pane verdict.
    func runningTurnStart(ticketKey: String) -> Date? {
        guard let timing = timingByTicket[ticketKey] else { return nil }
        return LiveTurn.start(timing: timing, isWorking: workingTickets.contains(ticketKey))
    }

    /// Cumulated Claude time across every card of the current sprint.
    var sprintClaudeSeconds: TimeInterval {
        cards.reduce(0) { $0 + $1.claudeSeconds }
    }

    // MARK: - Prompt timeline

    /// Which prompts of the selected ticket are still in the tmux scrollback (turn indices). Empty
    /// until `refreshPromptReachability` ran; everything not in here is read from the transcript.
    private(set) var reachablePrompts: Set<Int> = []

    /// Bumped on every click inside a terminal, so the prompt timeline can get out of the way when
    /// the user goes back to typing. A counter rather than a flag — consecutive clicks must each
    /// trigger `onChange`.
    private(set) var terminalClickTick = 0

    /// Ein Klick in ein Terminal **dieses** Fensters. Die Zuordnung macht `ProjectWindows`: den
    /// Klick meldet der prozessweite `TerminalCache`, und er gehört dem Fenster, in dem die
    /// Terminal-Ansicht gerade hängt.
    func noteTerminalClick() { terminalClickTick &+= 1 }

    /// Steht das Ticket auf dem Board dieses Fensters? Die Frage stellt die Benachrichtigung, bevor
    /// sie ein Ticket auswählt — im falschen Fenster wäre die Auswahl nur Unruhe.
    func zeigtTicket(_ ticketKey: String) -> Bool {
        cards.contains { $0.ticket.key == ticketKey }
    }

    /// The selected ticket's prompts, oldest first — the timeline's bubbles.
    var selectedPrompts: [ClaudeTurn] { selectedTiming?.turns ?? [] }

    /// Re-checks which prompts the terminal can still scroll to. Cheap (one `capture-pane`), but not
    /// free, so it runs when the timeline opens and when the transcript grew — not per render.
    func refreshPromptReachability() async {
        guard let session = activeTerminalSession, !selectedPrompts.isEmpty else {
            reachablePrompts = []
            return
        }
        let prompts = selectedPrompts.map(\.prompt)
        reachablePrompts = await TerminalCache.shared.reachablePrompts(session: session, prompts: prompts)
    }

    /// Scrolls the Claude terminal to where the turn's prompt was sent. False when it has scrolled
    /// out of the history — the caller then expands the turn from the transcript instead.
    func jumpToPrompt(turnIndex: Int) async -> Bool {
        guard let session = activeTerminalSession else { return false }
        let prompts = selectedPrompts.map(\.prompt)
        let jumped = await TerminalCache.shared.jump(session: session, prompts: prompts, turnIndex: turnIndex)
        // Keep the bubble's icon honest about what just happened, without a second scan.
        if jumped { reachablePrompts.insert(turnIndex) } else { reachablePrompts.remove(turnIndex) }
        return jumped
    }

    /// Reads one turn back out of the transcript (prose + tool summary) — the fallback for prompts
    /// the scrollback no longer holds.
    func turnContent(turnIndex: Int) async -> ClaudeTurnContent? {
        guard let key = selectedTicketKey, let sessionId = sessionIdByTicket[key],
              let repoDir = selectedProject?.repoDir,
              let url = ClaudeTimingStore.transcriptURL(sessionId: sessionId, cwd: repoDir,
                                                        agent: agent)
        else { return nil }
        let agent = self.agent
        return await Task.detached(priority: .userInitiated) {
            switch agent {
            case .claude: return ClaudeTurnReader.content(turnIndex: turnIndex, transcript: url)
            case .codex:  return CodexTurnReader.content(turnIndex: turnIndex, rollout: url)
            }
        }.value
    }

    /// Re-derives the timings of every card from the transcripts. Cheap after the first pass: the
    /// store only reads what Claude appended since (see `ClaudeTimingStore`).
    private func refreshTimings() async {
        guard let repoDir = selectedProject?.repoDir, !sessionIdByTicket.isEmpty else { return }
        let map = sessionIdByTicket
        let timings = await ClaudeTimingStore.shared.timings(sessionIds: map, cwd: repoDir,
                                                            agent: agent)
        timingByTicket = timings
        applyTimingsToCards()
    }

    /// Re-derives just one ticket's timing — used by the live transcript watcher, so the counter of
    /// the open ticket follows Claude's answer instead of waiting for the 45 s board poll.
    private func refreshTiming(for key: String) async {
        guard let repoDir = selectedProject?.repoDir, let sessionId = sessionIdByTicket[key] else { return }
        let timing = await ClaudeTimingStore.shared.timing(sessionId: sessionId, cwd: repoDir,
                                                          agent: agent)
        timingByTicket[key] = timing
        applyTimingsToCards()
    }

    private func applyTimingsToCards() {
        let updated = cards.map { card -> CardVM in
            var copy = card
            let key = card.ticket.key
            let timing = timingByTicket[key]
            let runningSince = runningTurnStart(ticketKey: key)
            copy.claudeSeconds = timing?.total(runningSince: runningSince) ?? 0
            copy.claudeBaseSeconds = timing?.totalExcludingOpenTurn ?? 0
            copy.claudeRunningSince = runningSince
            copy.bookedSeconds = bookedByTicket[key] ?? 0
            copy.openToBookSeconds = openToBookSeconds(ticketKey: key)
            return copy
        }
        guard updated != cards else { return }
        cards = updated
        regroupColumns()
    }

    /// Watches the selected ticket's transcript so its counter moves while Claude answers. The file
    /// grows with every assistant/tool entry, so the debounce keeps the board from re-rendering
    /// dozens of times per turn.
    ///
    /// Both `selectTicket` and the terminal setup arm this (the session id may only exist once the
    /// console was created), so arming is generation-guarded: a later call always wins and the
    /// earlier one drops its watcher instead of leaking it.
    private func startTimingWatch(for key: String) {
        timingWatchTask?.cancel(); timingWatchTask = nil
        timingWatcher?.cancel(); timingWatcher = nil
        timingWatchGeneration += 1
        let generation = timingWatchGeneration
        guard let repoDir = selectedProject?.repoDir else { return }

        Task { [weak self] in
            guard let self else { return }
            let known = self.sessionIdByTicket[key]
            let agent = self.agent
            // Off-main: the fallback store reads a file and locating the transcript may scan every
            // project directory (bei Codex die Datums-Ordner der Rollouts).
            let resolved: (id: String, url: URL)? = await Task.detached {
                let fallback = agent == .codex
                    ? CodexSessions.sessionId(threadName: CodexSessions.threadName(forTicket: key))
                    : SessionIdStore.peek(forTicket: key)
                guard let id = known ?? fallback,
                      let url = ClaudeTimingStore.transcriptURL(sessionId: id, cwd: repoDir,
                                                                agent: agent)
                else { return nil }
                return (id, url)
            }.value
            guard let resolved, self.timingWatchGeneration == generation,
                  self.selectedTicketKey == key else { return }
            self.sessionIdByTicket[key] = resolved.id
            await self.refreshTiming(for: key)

            let watcher = TaskFileWatcher(path: resolved.url.path)
            self.timingWatcher = watcher
            self.timingWatchTask = Task { [weak self] in
                for await _ in watcher.events {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)   // debounce a streaming answer
                    guard let self, self.timingWatchGeneration == generation,
                          self.selectedTicketKey == key else { return }
                    await self.refreshTiming(for: key)
                }
            }
        }
    }

    // MARK: - Commit (🟢 Abgeschlossen)

    /// The Commit button is offered wherever there is real work to commit — a task file or a worktree.
    /// Deliberately **not** gated on the status marker: nachbessern happens in Review just as much as
    /// in 🟢 Abgeschlossen, and mid-work commits are normal too. The gate that remains keeps the button
    /// off pure Jira tickets, where `commitDirectory` would fall back to the main repo and `add -A`
    /// could sweep up unrelated changes.
    var canCommit: Bool { taskFile != nil || currentWorktree != nil }

    // MARK: - Jira-Feld „Lösung"

    /// Liest den Stand des Lösungsfelds für das offene Ticket. Still: hat das Ticket kein solches
    /// Feld oder scheitert die Anfrage, bleibt `solution` nil und der Knopf weg — ein Ladefehler
    /// darf das Detail nicht kaputtmachen.
    private func loadSolution(for key: String, project: ProjectConfig) {
        guard let jira else { return }
        solutionLoading = true
        Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.solutionLoading = false } }
            do {
                let cached = await MainActor.run { self?.solutionFieldIdByProject[project.key] }
                let loaded = try await jira.solution(issueKey: key, baseUrl: project.jiraBaseUrl,
                                                     knownFieldId: cached)
                await MainActor.run {
                    guard let self, self.selectedTicketKey == key else { return }
                    self.solution = loaded
                    if let loaded { self.solutionFieldIdByProject[project.key] = loaded.fieldId }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.selectedTicketKey == key else { return }
                    self.solution = nil
                }
            }
        }
    }

    /// Ob der Lösungs-Knopf angezeigt wird: nur mit Jira-Ticket und vorhandenem Feld.
    var canEditSolution: Bool { solution != nil && selectedTicketKey != nil }

    /// **Der Alarm**: das Ticket ist so weit, dass jemand die Lösung liest — Spalte **Review** oder
    /// **Done** — aber das Feld ist leer. Genau dann muss die Lösung nachgetragen werden, und der
    /// Knopf wird rot umrandet. Done gehört dazu, weil ein gemergter MR das Versäumnis nicht heilt:
    /// das Task-File wird nicht mitcommittet, das Jira-Feld ist danach die einzige Spur.
    /// Nil = kein Alarm; sonst die Spalte, damit die Anzeige sie benennen kann.
    var solutionMissingColumn: KanbanColumn? {
        guard let solution, solution.isEmpty, let key = selectedTicketKey else { return nil }
        guard let column = cards.first(where: { $0.ticket.key == key })?.column,
              column == .review || column == .done else { return nil }
        return column
    }

    /// Was das Task-File für das Feld anbietet: `## JIRA Lösungsfeld` → `### Für Kunde` (siehe
    /// `SolutionDraft`) — die Prosa, die in Jira gehört, samt Entscheidungen, Abweichungen von den AK
    /// und Annahmen. Nicht `## Lösung`: das ist der interne Abschnitt mit Commit-Message und
    /// Test-URL. Gelesen wird die Datei roh, nicht `displaySections` — dort wären Bilder schon als
    /// base64 eingebettet.
    var taskFileSolutionSuggestion: (text: String, source: SolutionDraft.Source)? {
        taskFile
            .flatMap { try? String(contentsOf: $0.url, encoding: .utf8) }
            .flatMap { SolutionDraft.suggestion(in: $0) }
    }

    /// Vorbelegung des Editors: der bestehende Jira-Inhalt, sonst der Vorschlag aus dem Task-File.
    var solutionDraft: String {
        if let solution, !solution.isEmpty { return solution.markdown }
        return taskFileSolutionSuggestion?.text ?? ""
    }

    /// Schreibt das Feld und liest es danach zurück, damit die Anzeige dem entspricht, was in Jira
    /// steht (und nicht dem, was wir gesendet haben).
    func saveSolution(_ markdown: String) async {
        guard let key = selectedTicketKey, let project = selectedProject, let jira,
              let fieldId = solution?.fieldId ?? solutionFieldIdByProject[project.key] else { return }
        solutionSaving = true
        solutionError = nil
        defer { solutionSaving = false }
        do {
            try await jira.setSolution(issueKey: key, fieldId: fieldId, markdown: markdown,
                                       baseUrl: project.jiraBaseUrl)
            solution = try await jira.solution(issueKey: key, baseUrl: project.jiraBaseUrl)
            solutionSheetPresented = false
        } catch {
            solutionError = error.localizedDescription
        }
    }

    /// Where the commit runs: the ticket's worktree, else the main repo (`--no-worktree` tasks).
    var commitDirectory: String? { currentWorktree?.path ?? selectedProject?.repoDir }

    /// The message `solve-task` wrote under `## Lösung`, else a `TICKET | ` stub to complete.
    var suggestedCommitMessage: String {
        let fromFile = taskFile
            .flatMap { try? String(contentsOf: $0.url, encoding: .utf8) }
            .flatMap { CommitMessage.suggestion(in: $0) }
        return fromFile ?? CommitMessage.fallback(ticketKey: selectedTicketKey ?? "")
    }

    /// Einmal beim Öffnen des Commit-Fensters: Abwahl zurücksetzen und die Vorgabe anwenden.
    ///
    /// Bewusst **nicht** in `loadCommitState` — das läuft auch nach jedem Speichern und nach dem
    /// Commit. Dort erneut abzuwählen hiesse, die Wahl des Menschen bei jedem Neuladen zu
    /// überschreiben; wer `.claude/project.json` bewusst dazuwählt, will das behalten.
    func prepareCommitDialog() async {
        commitExcluded = []
        commitDiffSource = .working
        await loadCommitState()
        if config?.excludeClaudeProjectFileFromCommit ?? true,
           (commitState?.changedFiles ?? []).contains(where: { $0.path == AppConfig.claudeProjectFilePath }) {
            commitExcluded.insert(AppConfig.claudeProjectFilePath)
        }
    }

    /// Reads branch / pending files / HEAD subject for the dialog. Off-main: it shells out to git.
    /// Preselects the first changed file so the diff pane is never empty on open.
    func loadCommitState() async {
        guard let dir = commitDirectory else { return }
        commitError = nil
        commitLog = ""
        let state = await Task.detached { GitCommitController().state(dir: dir) }.value
        commitState = state
        // Eine abgewählte Datei, die es nicht mehr gibt, darf nicht als Geist weiterleben — sonst
        // stünde sie beim nächsten Commit als unbekannter Pfad in `restore --staged`.
        commitExcluded.formIntersection(state.changedFiles.map(\.path))
        // Steht der Reiter „Diff" vorn, gehört die Auswahl dem Branch-Diff — die Statusliste darf
        // sie dann nicht überschreiben (`saveCommitFile` und `performCommit` laufen hier durch).
        guard commitDiffSource == .working else { return }
        let stillThere = commitSelectedFile.flatMap { previous in
            state.changedFiles.first { $0.path == previous.path }
        }
        await selectCommitFile(stillThere ?? state.changedFiles.first)
    }

    /// Lädt das Branch-Diff: erst die Abzweig-Basis ableiten (`BranchParent`, derselbe Weg wie beim
    /// ←-Chip im Worktree-Panel), dann den Dreipunkt-Vergleich dagegen. Off-main, es sind mehrere
    /// git-Aufrufe.
    func loadBranchDiff() async {
        guard let dir = commitDirectory else { return }
        branchDiffLoading = true
        defer { branchDiffLoading = false }
        branchDiffError = nil
        let found: (diff: GitBranchDiff?, base: BranchBase?) = await Task.detached {
            guard let base = BranchParentScanner().parent(worktreePath: dir) else { return (nil, nil) }
            return (GitCommitController().branchDiff(dir: dir, baseRef: base.ref), base)
        }.value
        guard commitDiffSource == .branch else { return }   // Reiter zwischenzeitlich gewechselt
        branchDiff = found.diff
        if found.base == nil {
            branchDiffError = "Keine Abzweig-Basis gefunden — ohne sie gibt es keinen Vergleich."
        } else if found.diff == nil {
            branchDiffError = "Kein gemeinsamer Vorfahre mit \(found.base!.ref)."
        }
        let stillThere = commitSelectedFile.flatMap { previous in
            found.diff?.files.first { $0.path == previous.path }
        }
        await selectCommitFile(stillThere ?? found.diff?.files.first)
    }

    /// Reiterwechsel: Quelle umstellen und die passende Liste laden.
    ///
    /// Der Editor gilt in **beiden** Reitern. Im Branch-Diff war er zunächst gesperrt, weil er den
    /// heutigen Dateiinhalt neben einer Einfärbung gegen HEAD zeigte; das ist behoben — die
    /// Editor-Einfärbung kommt jetzt aus dem Vergleich gegen den Arbeitsstand
    /// (`GitCommitController.diffWorktree`). Was man hier ändert und speichert, steht danach als
    /// Änderung im Arbeitsverzeichnis und damit in „Neuer Commit"/„Amend".
    func setCommitDiffSource(_ source: CommitDiffSource) async {
        guard source != commitDiffSource else { return }
        commitDiffSource = source
        commitSelectedFile = nil
        commitDiff = []
        if source == .branch {
            await loadBranchDiff()
        } else {
            await selectCommitFile(commitState?.changedFiles.first)
        }
    }

    /// Loads and parses one file's diff for the right pane, plus the file itself for the editor.
    func selectCommitFile(_ file: GitChangedFile?) async {
        commitSelectedFile = file
        commitSaveError = nil
        guard let file, let dir = commitDirectory else {
            commitDiff = []; commitFileText = ""; commitFileLoadedText = ""
            return
        }
        commitDiffLoading = true
        defer { commitDiffLoading = false }
        let path = (dir as NSString).appendingPathComponent(file.path)
        // Gegen den **einmal aufgelösten** Merge-Base, nicht gegen `base...HEAD`: so vergleicht jede
        // Datei gegen denselben Stand, auch wenn sich die Basis zwischendurch bewegt.
        let base = commitDiffSource == .branch ? branchDiff?.mergeBase : nil
        let loaded: (diff: String, editorDiff: String, text: String, exists: Bool) = await Task.detached {
            let git = GitCommitController()
            // Gezeigt wird, was der Reiter verspricht: im Arbeitsverzeichnis gegen HEAD, im Reiter
            // „Diff" der Dreipunkt-Vergleich des Branches.
            let raw = base.map { git.diff(dir: dir, file: file, against: $0) }
                ?? git.diff(dir: dir, file: file)
            // Die **Editor**-Einfärbung dagegen gilt immer der Datei auf der Platte — das ist es ja,
            // was im Editor steht. Im Arbeitsverzeichnis ist das schon dasselbe Diff; im Branch-Diff
            // braucht es dafür den Vergleich ohne `HEAD`.
            let forEditor = base.map { git.diffWorktree(dir: dir, file: file, against: $0) } ?? raw
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            return (raw, forEditor, text, FileManager.default.fileExists(atPath: path))
        }.value
        guard commitSelectedFile?.path == file.path else { return }   // a newer selection won
        commitDiff = DiffParser.parse(loaded.diff)
        commitFileHighlight = DiffHighlight.from(
            loaded.editorDiff == loaded.diff ? commitDiff : DiffParser.parse(loaded.editorDiff))
        commitFileText = loaded.text
        commitFileLoadedText = loaded.text
        commitFileExists = loaded.exists
        // Eine Datei, die es nicht (mehr) gibt, hat nichts zu bearbeiten — der Editor bliebe leer
        // und ein Speichern legte sie wieder an.
        if !loaded.exists { commitEditorMode = false }
        commitEditorReloadToken += 1
    }

    /// Writes the edited file back to disk and refreshes diff + status from it.
    func saveCommitFile() async {
        guard let file = commitSelectedFile, let dir = commitDirectory, commitEditorDirty else { return }
        let path = (dir as NSString).appendingPathComponent(file.path)
        let text = commitFileText
        let error: String? = await Task.detached {
            do {
                try text.write(toFile: path, atomically: true, encoding: .utf8)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        commitSaveError = error
        guard error == nil else { return }
        commitFileLoadedText = text
        // Die Statusliste zuerst: dort taucht die eben bearbeitete Datei jetzt als Änderung auf —
        // das ist der Weg, auf dem sie in „Neuer Commit"/„Amend" landet.
        await loadCommitState()
        // Im Reiter „Diff" hält `loadCommitState` bewusst die Finger von der Auswahl (die gehört
        // dort dem Branch-Diff) — die Einfärbung des Editors muss trotzdem nachziehen, sonst zeigt
        // sie den Stand vor dem Speichern.
        if commitDiffSource == .branch { await selectCommitFile(commitSelectedFile) }
    }

    /// Drops the edits and reloads the file from disk.
    func revertCommitFile() async {
        await selectCommitFile(commitSelectedFile)
    }

    /// Commits (message required) or amends HEAD (`--no-edit`, so no message is needed), optionally
    /// pushing afterwards. A push after an amend must be forced — always `--force-with-lease`.
    func performCommit(message: String, amend: Bool, push: Bool) async {
        guard !commitBusy, let dir = commitDirectory else { return }
        commitBusy = true
        commitError = nil
        defer { commitBusy = false }

        let needsUpstream = commitState?.hasUpstream == false
        let excluded = Array(commitExcluded).sorted()
        let result: Result<String, Error> = await Task.detached {
            let git = GitCommitController()
            do {
                var log = amend ? try git.amend(dir: dir, excluding: excluded)
                                : try git.commit(dir: dir, message: message, excluding: excluded)
                if push {
                    log += try git.push(dir: dir, force: amend, setUpstream: needsUpstream)
                }
                return .success(log)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let log):
            commitLog = log
            await loadCommitState()          // reflect the new HEAD / clean tree
            commitSheetPresented = false
        case .failure(let error):
            commitError = error.localizedDescription
        }
    }

    // MARK: - Worklog booking (Jira-Zeit buchen)

    /// Liest den Ledger einmal in den Speicher — nach dem Start und nach jeder Buchung.
    private func reloadLedger() {
        ledgerByTicket = WorklogLedger.load()
        bookedByTicket = ledgerByTicket.mapValues(\.bookedSeconds)
    }

    /// ⏱ time already booked to Jira for a ticket.
    func bookedSeconds(ticketKey key: String) -> TimeInterval { bookedByTicket[key] ?? 0 }

    /// Die offenen Tagesposten eines Tickets, chronologisch — je Kalendertag einer, weil auf den
    /// Arbeitstag gebucht wird und nicht auf heute.
    func dailyBookings(ticketKey key: String) -> [DailyBooking] {
        guard let turns = timingByTicket[key]?.turns, !turns.isEmpty else { return [] }
        let entry = ledgerByTicket[key]
        return WorklogBooking.dailyBookings(turns: turns,
                                            bookedByDay: entry?.byDay ?? [:],
                                            unattributedBooked: entry?.unattributedSeconds ?? 0,
                                            settledThrough: entry?.lastBookedAt)
    }

    /// What a booking would log now: die Summe der offenen Tagesposten. 0 heisst nichts Neues zu
    /// buchen (und der Knopf bleibt aus — das ist die Sperre gegen Doppelbuchung).
    func openToBookSeconds(ticketKey key: String) -> TimeInterval {
        dailyBookings(ticketKey: key).reduce(0) { $0 + $1.seconds }
    }

    /// When this ticket was last booked (nil if never).
    func lastBookedAt(ticketKey key: String) -> Date? { ledgerByTicket[key]?.lastBookedAt }

    /// One line of the batch-booking confirmation: a ticket with open (unbooked) time.
    struct OpenBooking: Identifiable {
        let key: String
        let summary: String
        let seconds: TimeInterval
        /// Die Tagesposten, aus denen sich `seconds` zusammensetzt — jeder wird einzeln gebucht.
        let days: [DailyBooking]
        var id: String { key }

        /// „19.–20.08." bzw. „20.08." — damit im Sheet sichtbar ist, worauf gebucht wird.
        var dayLabel: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_CH")
            formatter.dateFormat = "dd.MM."
            guard let first = days.first, let last = days.last else { return "" }
            let start = formatter.string(from: first.day)
            return days.count == 1 ? start : "\(start)–\(formatter.string(from: last.day))"
        }
    }

    /// Every card that has unbooked ⏱ time, most first — the list the "Alle offenen buchen" sheet
    /// shows and books.
    ///
    /// Ohne Jira-Anbindung ist die Liste leer, und damit verschwindet auch der Buchen-Knopf in der
    /// Leiste: gebucht würde in ein Jira, das dieses Projekt nicht hat. Die Zeit wird trotzdem
    /// weiter gemessen und angezeigt — nur eben nirgends hingeschrieben.
    var openBookings: [OpenBooking] {
        guard selectedProject?.usesJira == true else { return [] }
        return cards.compactMap { card in
            let days = dailyBookings(ticketKey: card.ticket.key)
            guard !days.isEmpty else { return nil }
            return OpenBooking(key: card.ticket.key, summary: card.ticket.summary,
                               seconds: days.reduce(0) { $0 + $1.seconds }, days: days)
        }.sorted { $0.seconds > $1.seconds }
    }

    var totalOpenToBookSeconds: TimeInterval { openBookings.reduce(0) { $0 + $1.seconds } }

    /// Books one ticket's open time to Jira.
    func bookTime(ticketKey key: String) async { await book(ticketKeys: [key]) }

    /// Books every ticket with open time (the batch action). Continues past a failing ticket and
    /// reports which ones failed.
    func bookAllOpenTime() async { await book(ticketKeys: openBookings.map(\.key)) }

    /// Posts **one worklog per ticket and day** and, only on success, records that day's delta in the
    /// ledger — so a rejected write never marks time as booked. `started` ist der erste Turn des
    /// Tages, damit Jira die Zeit auf den Arbeitstag legt und nicht auf heute.
    ///
    /// Ein fehlgeschlagener Tag lässt die anderen laufen: sonst würde ein einzelner Ausfall (Ticket
    /// gesperrt, Netz weg) eine ganze Woche Nachbuchung verhindern.
    private func book(ticketKeys keys: [String]) async {
        guard !bookingBusy, let project = selectedProject, let jira else { return }
        bookingBusy = true
        bookingError = nil
        defer { bookingBusy = false }

        var failures: [String] = []
        for key in keys {
            for day in dailyBookings(ticketKey: key) {
                do {
                    try await jira.addWorklog(issueKey: key, timeSpentSeconds: Int(day.seconds),
                                              started: day.startedAt, comment: nil,
                                              baseUrl: project.jiraBaseUrl)
                    WorklogLedger.record(day.seconds, dayKey: day.dayKey, at: Date(), forTicket: key)
                } catch {
                    failures.append("\(key) (\(day.dayKey)): \(error.localizedDescription)")
                }
            }
        }
        reloadLedger()
        applyTimingsToCards()
        bookingError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}
