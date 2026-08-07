import Foundation
import Observation
import KanbanCore

/// A board card = a ticket plus its derived column + badges.
struct CardVM: Identifiable, Hashable {
    let ticket: Ticket
    let column: KanbanColumn
    let badges: [CardBadge]
    let statusMarker: TaskStatusMarker?   // Claude's task-file status (shown as a dot, separate from column)
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
}

@MainActor
@Observable
final class AppModel {
    // Config
    private(set) var config: HermesConfig?
    private(set) var configError: String?
    private(set) var projects: [ProjectConfig] = []
    private(set) var selectedProject: ProjectConfig?

    // Sprints
    private(set) var sprints: [JiraSprint] = []
    private(set) var selectedSprint: JiraSprint?

    // Board
    private(set) var cards: [CardVM] = []
    private(set) var columns: [(column: KanbanColumn, cards: [CardVM])] = []
    private(set) var worktrees: [Worktree] = []
    private var lastMergeRequests: [MergeRequestRef] = []   // cached to re-derive a card locally

    // Detail
    private(set) var selectedTicketKey: String?
    private(set) var taskFile: TaskFile?
    private(set) var reviewMarkdowns: [String] = []   // full content of each <KEY>_review*.md → "Review" tab(s)
    private(set) var fallbackSections: [TaskSection] = []
    private(set) var detailLoading = false

    // Terminal
    private(set) var activeTerminalSession: String?           // left: Claude, main-tree cwd
    private(set) var activeWorktreeTerminalSession: String?   // right: plain shell, worktree cwd
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

    // Status
    private(set) var isLoadingSprints = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var lastRefresh: Date?

    // Settings sheet (gear button); writable — bound to the sheet presentation.
    var settingsPresented = false

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

    // Worklog booking: how much ⏱ time is already booked per ticket (local ledger), plus the state
    // of an in-flight booking. Writing to Jira is explicit (a button), never automatic.
    private(set) var bookedByTicket: [String: TimeInterval] = [:]
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
    private var gitlab: GitLabClient?
    private var pollTask: Task<Void, Never>?
    private var watcher: TaskFileWatcher?
    private var watchTask: Task<Void, Never>?
    private var reviewWatcher: TaskFileWatcher?
    private var reviewWatchTask: Task<Void, Never>?

    // Preferred tab order; everything else follows in file order.
    private static let preferredOrder = [
        "beschreibung", "kommentare", "analyse", "impact", "history",
        "umsetzungsplan", "lösungsplan", "loesungsplan", "stages",
        "fragen", "lösung", "loesung", "abschluss-checkliste",
    ]

    func bootstrap() {
        guard config == nil, configError == nil else { return }
        do {
            let cfg = try HermesConfigLoader.load()
            config = cfg
            projects = cfg.projects
            jira = JiraClient(email: cfg.jiraEmail, apiToken: cfg.jiraApiToken)
            if let apiUrl = cfg.gitlabApiUrl, let token = cfg.gitlabApiToken, !token.isEmpty {
                gitlab = GitLabClient(apiBaseUrl: apiUrl, token: token, backend: cfg.gitlabBackend)
            }
            let creds = Data("\(cfg.jiraEmail):\(cfg.jiraApiToken)".utf8).base64EncodedString()
            AvatarCache.shared.configure(
                authHeader: "Basic \(creds)",
                jiraBaseUrls: [cfg.jiraDefaultBaseUrl] + cfg.projects.map(\.jiraBaseUrl))
            // Optional deep-link: `Kanban --select BFEZVM-4259` opens that ticket on launch and wins
            // over the remembered selection.
            if let key = Self.launchArg("--select"),
               let project = projects.first(where: { key.uppercased().hasPrefix($0.prefix.uppercased()) }) {
                selectProject(project)
                selectTicket(key)
            } else if let project = projects.first(where: { $0.key == SelectionStore.projectKey })
                        ?? projects.first {
                selectProject(project)   // last session's project, else the first one
            }
            startPolling()
            startAttentionWatch()
            AttentionNotifier.shared.configure { [weak self] ticketKey in
                guard let self, self.cards.contains(where: { $0.ticket.key == ticketKey }) else { return }
                self.selectTicket(ticketKey)
            }
        } catch {
            configError = error.localizedDescription
        }
    }

    var hasGitlab: Bool { gitlab != nil }

    /// Re-reads the Hermes config after the settings sheet saved it: rebuilds clients + project
    /// list via `bootstrap()` and restores the previous selection where it still exists.
    func reloadConfig() {
        let previousProject = selectedProject?.key
        let previousTicket = selectedTicketKey
        pollTask?.cancel()
        pollTask = nil
        config = nil
        configError = nil
        jira = nil
        gitlab = nil
        projects = []
        selectedProject = nil
        bootstrap()
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

    /// The ticket-workflow commands offered in the header menu, in workflow order.
    /// `create-task` is deliberately absent — it starts from a description, not a ticket.
    private static let ticketCommandNames = ["get-task", "start-task", "solve-task", "review-task"]

    func selectProject(_ project: ProjectConfig) {
        guard project.id != selectedProject?.id else { return }
        selectedProject = project
        SelectionStore.projectKey = project.key   // restored on the next launch
        sprints = []
        selectedSprint = nil
        cards = []
        columns = []
        claudeCommands = ClaudeCommandScanner.scan(repoDir: project.repoDir,
                                                   only: Self.ticketCommandNames)
        clearDetail()
        Task { await loadSprints() }
    }

    func selectSprint(_ sprint: JiraSprint) {
        guard sprint.id != selectedSprint?.id else { return }
        selectedSprint = sprint
        if let project = selectedProject {
            SelectionStore.setSprintId(sprint.id, forProject: project.key)   // restored on the next launch
        }
        Task { await refresh() }
    }

    func selectTicket(_ key: String) {
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
            let all = try await jira.sprints(boardId: board.id, baseUrl: project.jiraBaseUrl,
                                             states: "active,future,closed")
            let sorted = SprintSelection.ordered(all)
            sprints = sorted
            // Restores the sprint the user last picked for this project (see SprintSelection.resolve).
            selectedSprint = SprintSelection.resolve(
                sprints: sorted, storedId: SelectionStore.sprintId(forProject: project.key))
            if selectedSprint != nil {
                await refresh()
            } else {
                errorMessage = "Keine Sprints für dieses Board."
            }
        } catch {
            errorMessage = "Sprints laden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard let project = selectedProject, let sprint = selectedSprint, let jira else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }
        do {
            async let issuesTask = jira.sprintIssues(sprintId: sprint.id, baseUrl: project.jiraBaseUrl)
            async let mrsTask = fetchMergeRequests(for: project)
            async let worktreesTask = WorktreeScanner.scan(repoDir: project.repoDir)

            // Sub-tasks are not shown as standalone cards — the story carries the work. Filter them
            // before building cards. (Epic inheritance stays for parity with the self-test; on the
            // board it is a no-op now, since the sub-tasks that would inherit are gone.)
            let issues = EpicResolution.inheritFromParents(try await issuesTask)
                .filter { !$0.isSubtask }
            let mrs = await mrsTask
            let worktrees = await worktreesTask
            self.worktrees = worktrees
            self.lastMergeRequests = mrs

            let dir = project.tasksPathAbsolute
            var sessionMap: [String: String] = [:]
            cards = issues.map { ticket in
                var info = TaskFileLoader.statusMarker(ticketKey: ticket.key, in: dir)
                let wt = WorktreeScanner.worktree(for: ticket.key, in: worktrees)
                // A ticket can carry two recorded ids that disagree; the one with a transcript is the
                // real conversation (see ClaudeSessionResolution). Read-only here — the file is only
                // corrected when the ticket is actually opened.
                if let sid = ClaudeSessionResolution.resolve(
                    taskFileId: TaskFileLoader.peekSessionId(ticketKey: ticket.key, in: dir),
                    storeId: SessionIdStore.peek(forTicket: ticket.key),
                    cwd: project.repoDir) {
                    sessionMap[ticket.key] = sid
                }

                let mr = WorkflowStatus.primaryMR(ticketKey: ticket.key, mergeRequests: mrs)

                // Rename the task file to match the MR's feature branch. First, so the writes below
                // re-find the renamed file. Safe: only when the new name still belongs to the ticket.
                if info.exists, let branch = mr?.sourceBranch,
                   let currentURL = TaskFileLoader.find(ticketKey: ticket.key, in: dir) {
                    TaskFileLoader.renameToMatchBranch(currentURL: currentURL, branch: branch, ticketKey: ticket.key)
                }

                // Auto-advance the persisted task-file status marker, idempotently, to match reality:
                //   • ✅ Done   when Jira says Erledigt/Geschlossen (statusCategory "done"), or
                //   • 🔵 Review when an MR is open for this ticket.
                // Done wins (higher precedence); neither overrides an existing ✅ Done. Keeps the
                // dot/marker in sync with the derived column so Claude and other tools see it too.
                if WorkflowStatus.shouldAutoSetDone(hasTaskFile: info.exists, currentMarker: info.marker,
                                                    jiraDone: ticket.isDoneInJira),
                   let url = TaskFileLoader.find(ticketKey: ticket.key, in: dir),
                   TaskFileLoader.writeStatus(.done, url: url) {
                    info.marker = .done
                } else if WorkflowStatus.shouldAutoSetReview(ticketKey: ticket.key, hasTaskFile: info.exists,
                                                             currentMarker: info.marker, mergeRequests: mrs),
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
                    jiraDone: ticket.isDoneInJira
                )
                return CardVM(ticket: ticket, column: res.column, badges: res.badges, statusMarker: info.marker)
            }
            sessionIdByTicket = sessionMap
            bookedByTicket = WorklogLedger.bookedSeconds()
            applyTimingsToCards()               // carry the cached ⏱ over, so badges don't blink per poll
            regroupColumns()                    // build columns from cards (always)
            recomputeAttention(notify: false)   // paint the ❓ where a console is waiting
            Task { await refreshPaneAttention() }
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
            // visible from the start instead of only after the user clicks a card.
            if selectedTicketKey == nil, let first = firstBoardTicket() {
                selectTicket(first)
            }
        } catch {
            errorMessage = "Aktualisieren fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func fetchMergeRequests(for project: ProjectConfig) async -> [MergeRequestRef] {
        guard let gitlab, let path = project.gitlabProjectPath else { return [] }
        return (try? await gitlab.openedAndMergedMRs(projectPath: path)) ?? []
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

    private func regroupColumns() {
        columns = KanbanColumn.ordered.map { col in
            (col, cards.filter { $0.column == col }.sorted { $0.ticket.key < $1.ticket.key })
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
                // Synthetic first tab holding the file preamble (status + worktree/branch/stack block),
                // with the title/worktree/branch/stack turned into clickable links.
                let linked = StatusLinks.linkify(
                    preamble: tf.preamble,
                    ticketKey: selectedTicketKey,
                    jiraBaseUrl: selectedProject?.jiraBaseUrl,
                    gitlabBaseUrl: config?.gitlabBaseUrl,
                    gitlabProjectPath: selectedProject?.gitlabProjectPath)
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

    /// The task-file path relative to the main repo root (Claude's cwd), e.g.
    /// `docs/tasks/EVEN-3530_foo.md`. Falls back to the bare filename if it's outside the repo.
    var relativeTaskFilePath: String? {
        guard let url = taskFile?.url else { return nil }
        if let repo = selectedProject?.repoDir {
            let full = url.standardizedFileURL.path
            let base = repo.hasSuffix("/") ? repo : repo + "/"
            if full.hasPrefix(base) { return String(full.dropFirst(base.count)) }
        }
        return url.lastPathComponent
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
        let wt = WorktreeScanner.worktree(for: key, in: worktrees)
        let res = WorkflowStatus.resolve(
            ticketKey: key, hasTaskFile: info.exists, statusMarker: info.marker,
            worktree: wt, mergeRequests: lastMergeRequests, jiraDone: cards[idx].ticket.isDoneInJira)
        cards[idx] = CardVM(ticket: cards[idx].ticket, column: res.column, badges: res.badges, statusMarker: info.marker)
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
        worktreeStatusText = ""
        worktreeCommandOutput = ""
        worktreeDbDump = nil
        selectedTicketKey = nil
        activeTerminalSession = nil
        activeWorktreeTerminalSession = nil
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
        let worktree = WorktreeScanner.worktree(for: key, in: worktrees)

        Task.detached { [weak self] in
            let tmux = TmuxController()
            guard tmux.isAvailable else {
                await MainActor.run {
                    guard let self, self.selectedTicketKey == key else { return }
                    self.activeTerminalSession = nil
                    self.activeWorktreeTerminalSession = nil
                }
                return
            }

            // One id per ticket, written to both stores: the task-file marker (where it belongs) and
            // `sessions.json` (which also covers tickets that have no task file yet). Without the
            // write-through the two drift apart as soon as Claude creates the task file mid-session,
            // and the board then watches a conversation that never existed.
            let taskFileURL = TaskFileLoader.find(ticketKey: key, in: tasksDir)
            let sessionId = ClaudeSessionResolution.resolve(
                taskFileId: taskFileURL.flatMap { TaskFileLoader.sessionId(in: $0) },
                storeId: SessionIdStore.peek(forTicket: key),
                cwd: repoDir) ?? UUID().uuidString.lowercased()
            if let taskFileURL { TaskFileLoader.writeSessionId(sessionId, url: taskFileURL) }
            SessionIdStore.set(sessionId, forTicket: key)

            let hasTranscript = ClaudeTranscripts.transcriptExists(sessionId: sessionId, cwd: repoDir)

            let plan = TerminalSessionResolver.resolve(
                ticketKey: key,
                repoDir: repoDir,
                worktree: worktree,
                sessionId: sessionId,
                hasTranscript: hasTranscript,
                existing: tmux.listSessions()
            )
            _ = tmux.run(plan: plan)
            tmux.setStatusBar(plan.name, visible: false)   // hide the green tmux status bar
            tmux.cancelCopyMode(plan.name)                 // clear any leftover copy-mode

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
                self.activeWorktreeTerminalSession = worktreeSession
                // The id may have been created just now — arm the ⏱ transcript watch on it.
                self.sessionIdByTicket[key] = sessionId
                self.startTimingWatch(for: key)
            }
        }
    }

    /// Types `/command <TICKET>` into the ticket's Claude console (without Enter, so the user can
    /// still edit/confirm) and switches the terminal pane to the Claude tab.
    func sendClaudeCommand(_ command: ClaudeCommand) {
        guard let key = selectedTicketKey, let session = activeTerminalSession else { return }
        claudeTerminalFocusRequest += 1
        Task.detached {
            let tmux = TmuxController()
            guard tmux.isAvailable else { return }
            tmux.cancelCopyMode(session)   // a scrolled-back pane would swallow the keystrokes
            tmux.sendText(session, "/\(command.name) \(key) ")
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
    var currentWorktree: Worktree? {
        guard let key = selectedTicketKey else { return nil }
        return WorktreeScanner.worktree(for: key, in: worktrees)
    }

    /// The ticket's numeric id used by `iwf worktree create` (e.g. BFEZVM-4569 → "4569").
    private var worktreeId: String? {
        selectedTicketKey?.split(separator: "-").last.map(String.init)
    }

    private enum WtOutput { case status, command }

    func refreshWorktreeStatus() {
        guard let cwd = currentWorktree?.path else { return }
        worktreeDbDump = WorktreeDbSeed.staged(worktreePath: cwd)
        runIwf(["stack", "ps"], cwd: cwd, into: .status)
        Task { await refreshStackStatus() }
    }

    /// GitLab-URL eines beliebigen Branches (nil ohne GitLab-Zuordnung).
    func branchURL(for branch: String) -> URL? {
        guard let base = config?.gitlabBaseUrl, !base.isEmpty,
              let path = selectedProject?.gitlabProjectPath, !path.isEmpty,
              let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/\(path)/-/tree/\(encoded)")
    }

    /// GitLab-URL des Worktree-Branches (nil ohne GitLab-Zuordnung).
    var worktreeBranchURL: URL? {
        guard let branch = currentWorktree?.branch,
              let base = config?.gitlabBaseUrl, !base.isEmpty,
              let path = selectedProject?.gitlabProjectPath, !path.isEmpty,
              let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/\(path)/-/tree/\(encoded)")
    }

    /// Die Stack-URL des Worktrees (`https://<name>.test`) — dieselbe, die der Domain-Status prüft.
    var worktreeStackURL: URL? {
        guard let path = currentWorktree?.path else { return nil }
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
        guard !worktreeBusy, let cwd = currentWorktree?.path else { return }
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
        guard !worktreeBusy, let worktree = currentWorktree?.path,
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
        guard let cwd = currentWorktree?.path, let repoDir = selectedProject?.repoDir else {
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

    /// Creates the worktree + stack for a ticket that has none yet (run from the main repo).
    func worktreeCreate() {
        guard let id = worktreeId, let repo = selectedProject?.repoDir else { return }
        runIwf(["worktree", "create", id, "--start"], cwd: repo, into: .command, thenRefresh: true)
    }

    private func runWorktreeLifecycle(_ args: [String]) {
        guard let cwd = currentWorktree?.path else { return }
        runIwf(args, cwd: cwd, into: .command, thenRefresh: true)
    }

    private func runIwf(_ args: [String], cwd: String, into target: WtOutput, thenRefresh: Bool = false) {
        guard !worktreeBusy else { return }
        worktreeBusy = true
        switch target {
        case .status:  worktreeStatusText = "Lade Status…\n"
        case .command: worktreeCommandOutput = "$ iwf \(args.joined(separator: " "))\n\n"
        }
        Task.detached { [weak self] in
            let code = WorktreeStackController().run(iwfArgs: args, cwd: cwd) { chunk in
                Task { @MainActor [weak self] in self?.appendWorktree(chunk, into: target) }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.worktreeBusy = false
                if target == .command { self.worktreeCommandOutput += "\n— fertig (exit \(code)) —\n" }
                if thenRefresh { self.refreshWorktreeStatus() }
            }
        }
    }

    @MainActor
    private func appendWorktree(_ chunk: String, into target: WtOutput) {
        switch target {
        case .status:
            if worktreeStatusText == "Lade Status…\n" { worktreeStatusText = "" }
            worktreeStatusText += chunk
        case .command:
            worktreeCommandOutput += chunk
            if worktreeCommandOutput.count > 60_000 {
                worktreeCommandOutput = String(worktreeCommandOutput.suffix(50_000))
            }
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
        worktreeStatusText = ""
        worktreeCommandOutput = ""
        worktreeDbDump = nil
        guard let project = selectedProject else { return }
        let dir = project.tasksPathAbsolute

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
        } else {
            loadJiraFallback(for: key, project: project)
        }
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
                if self.selectedSprint != nil { await self.refresh() }
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

    /// How long a transcript may be untouched before its unfinished last turn stops counting as
    /// live. Long tool calls (a build, a test run) append nothing meanwhile, so the tmux "working"
    /// signal carries those; this window covers the start of a turn before the first pane scan.
    private static let liveWindow: TimeInterval = 120

    /// The selected ticket's session timing (nil when Claude never ran for it).
    var selectedTiming: ClaudeSessionTiming? {
        selectedTicketKey.flatMap { timingByTicket[$0] }
    }

    /// Start of the turn that is running right now for a ticket, or nil when nothing runs. A turn
    /// counts as running when Claude wrote no turn-end record for it **and** the console still shows
    /// activity — otherwise an interrupted turn would tick up forever.
    func runningTurnStart(ticketKey: String) -> Date? {
        guard let timing = timingByTicket[ticketKey], let open = timing.openTurn else { return nil }
        let fresh = Date().timeIntervalSince(timing.lastModified ?? .distantPast) < Self.liveWindow
        guard fresh || workingTickets.contains(ticketKey) else { return nil }
        return open.start
    }

    /// Cumulated Claude time across every card of the current sprint.
    var sprintClaudeSeconds: TimeInterval {
        cards.reduce(0) { $0 + $1.claudeSeconds }
    }

    /// Re-derives the timings of every card from the transcripts. Cheap after the first pass: the
    /// store only reads what Claude appended since (see `ClaudeTimingStore`).
    private func refreshTimings() async {
        guard let repoDir = selectedProject?.repoDir, !sessionIdByTicket.isEmpty else { return }
        let map = sessionIdByTicket
        let timings = await ClaudeTimingStore.shared.timings(sessionIds: map, cwd: repoDir)
        timingByTicket = timings
        applyTimingsToCards()
    }

    /// Re-derives just one ticket's timing — used by the live transcript watcher, so the counter of
    /// the open ticket follows Claude's answer instead of waiting for the 45 s board poll.
    private func refreshTiming(for key: String) async {
        guard let repoDir = selectedProject?.repoDir, let sessionId = sessionIdByTicket[key] else { return }
        let timing = await ClaudeTimingStore.shared.timing(sessionId: sessionId, cwd: repoDir)
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
            // Off-main: the fallback store reads a file and locating the transcript may scan every
            // Claude project directory.
            let resolved: (id: String, url: URL)? = await Task.detached {
                guard let id = known ?? SessionIdStore.peek(forTicket: key),
                      let url = ClaudeTranscripts.transcriptURL(sessionId: id, cwd: repoDir)
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

    /// Where the commit runs: the ticket's worktree, else the main repo (`--no-worktree` tasks).
    var commitDirectory: String? { currentWorktree?.path ?? selectedProject?.repoDir }

    /// The message `solve-task` wrote under `## Lösung`, else a `TICKET | ` stub to complete.
    var suggestedCommitMessage: String {
        let fromFile = taskFile
            .flatMap { try? String(contentsOf: $0.url, encoding: .utf8) }
            .flatMap { CommitMessage.suggestion(in: $0) }
        return fromFile ?? CommitMessage.fallback(ticketKey: selectedTicketKey ?? "")
    }

    /// Reads branch / pending files / HEAD subject for the dialog. Off-main: it shells out to git.
    /// Preselects the first changed file so the diff pane is never empty on open.
    func loadCommitState() async {
        guard let dir = commitDirectory else { return }
        commitError = nil
        commitLog = ""
        let state = await Task.detached { GitCommitController().state(dir: dir) }.value
        commitState = state
        let stillThere = commitSelectedFile.flatMap { previous in
            state.changedFiles.first { $0.path == previous.path }
        }
        await selectCommitFile(stillThere ?? state.changedFiles.first)
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
        let loaded: (diff: String, text: String) = await Task.detached {
            let raw = GitCommitController().diff(dir: dir, file: file)
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            return (raw, text)
        }.value
        guard commitSelectedFile?.path == file.path else { return }   // a newer selection won
        commitDiff = DiffParser.parse(loaded.diff)
        commitFileHighlight = DiffHighlight.from(commitDiff)
        commitFileText = loaded.text
        commitFileLoadedText = loaded.text
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
        await loadCommitState()      // status + diff reflect the edit
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
        let result: Result<String, Error> = await Task.detached {
            let git = GitCommitController()
            do {
                var log = amend ? try git.amend(dir: dir) : try git.commit(dir: dir, message: message)
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

    /// ⏱ time already booked to Jira for a ticket.
    func bookedSeconds(ticketKey key: String) -> TimeInterval { bookedByTicket[key] ?? 0 }

    /// What a booking would log now: the rounded-up cumulative minus what is already booked. 0 means
    /// nothing new to book (and the button stays disabled — that is the no-double-booking guard).
    func openToBookSeconds(ticketKey key: String) -> TimeInterval {
        WorklogBooking.secondsToBook(measured: timingByTicket[key]?.total ?? 0,
                                     alreadyBooked: bookedSeconds(ticketKey: key))
    }

    /// When this ticket was last booked (nil if never).
    func lastBookedAt(ticketKey key: String) -> Date? { WorklogLedger.entry(forTicket: key)?.lastBookedAt }

    /// One line of the batch-booking confirmation: a ticket with open (unbooked) time.
    struct OpenBooking: Identifiable {
        let key: String
        let summary: String
        let seconds: TimeInterval
        var id: String { key }
    }

    /// Every card that has unbooked ⏱ time, most first — the list the "Alle offenen buchen" sheet
    /// shows and books.
    var openBookings: [OpenBooking] {
        cards.compactMap { card in
            card.openToBookSeconds > 0
                ? OpenBooking(key: card.ticket.key, summary: card.ticket.summary,
                              seconds: card.openToBookSeconds)
                : nil
        }.sorted { $0.seconds > $1.seconds }
    }

    var totalOpenToBookSeconds: TimeInterval { openBookings.reduce(0) { $0 + $1.seconds } }

    /// Books one ticket's open time to Jira.
    func bookTime(ticketKey key: String) async { await book(ticketKeys: [key]) }

    /// Books every ticket with open time (the batch action). Continues past a failing ticket and
    /// reports which ones failed.
    func bookAllOpenTime() async { await book(ticketKeys: openBookings.map(\.key)) }

    /// Posts a worklog per ticket and, only on success, records the booked delta in the ledger — so a
    /// rejected write never marks time as booked. Rounding and the "already booked" subtraction make
    /// each amount a 15-minute multiple and keep the same time from being logged twice.
    private func book(ticketKeys keys: [String]) async {
        guard !bookingBusy, let project = selectedProject, let jira else { return }
        bookingBusy = true
        bookingError = nil
        defer { bookingBusy = false }

        var failures: [String] = []
        for key in keys {
            let seconds = openToBookSeconds(ticketKey: key)
            guard seconds > 0 else { continue }
            do {
                try await jira.addWorklog(issueKey: key, timeSpentSeconds: Int(seconds),
                                          started: Date(), comment: nil,
                                          baseUrl: project.jiraBaseUrl)
                WorklogLedger.record(seconds, at: Date(), forTicket: key)
            } catch {
                failures.append("\(key): \(error.localizedDescription)")
            }
        }
        bookedByTicket = WorklogLedger.bookedSeconds()
        applyTimingsToCards()
        bookingError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}
