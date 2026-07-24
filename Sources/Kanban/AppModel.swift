import Foundation
import Observation
import KanbanCore

/// A board card = a ticket plus its derived column + badges.
struct CardVM: Identifiable, Hashable {
    let ticket: Ticket
    let column: KanbanColumn
    let badges: [CardBadge]
    let statusMarker: TaskStatusMarker?   // Claude's task-file status (shown as a dot, separate from column)
    var id: String { ticket.key }
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
    // Extra, user-spawned terminals, kept per ticket so they survive ticket switches.
    private var extraTerminalsByTicket: [String: [String]] = [:]

    // Worktree stack control panel (the "Worktree" tab)
    private(set) var worktreeStatusText: String = ""     // output of `iwf stack ps`
    private(set) var worktreeCommandOutput: String = ""  // stdout of the last lifecycle command
    private(set) var worktreeBusy = false
    private(set) var worktreeDbDump: StagedDbDump?       // staged DB seed file (path/size/age)

    // Status
    private(set) var isLoadingSprints = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var lastRefresh: Date?

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
                gitlab = GitLabClient(apiBaseUrl: apiUrl, token: token)
            }
            let creds = Data("\(cfg.jiraEmail):\(cfg.jiraApiToken)".utf8).base64EncodedString()
            AvatarCache.shared.configure(
                authHeader: "Basic \(creds)",
                jiraBaseUrls: [cfg.jiraDefaultBaseUrl] + cfg.projects.map(\.jiraBaseUrl))
            // Optional deep-link: `Kanban --select BFEZVM-4259` opens that ticket on launch.
            if let key = Self.launchArg("--select"),
               let project = projects.first(where: { key.uppercased().hasPrefix($0.prefix.uppercased()) }) {
                selectProject(project)
                selectTicket(key)
            } else if let first = projects.first {
                selectProject(first)
            }
            startPolling()
        } catch {
            configError = error.localizedDescription
        }
    }

    var hasGitlab: Bool { gitlab != nil }

    // MARK: - Selection

    func selectProject(_ project: ProjectConfig) {
        guard project.id != selectedProject?.id else { return }
        selectedProject = project
        sprints = []
        selectedSprint = nil
        cards = []
        columns = []
        clearDetail()
        Task { await loadSprints() }
    }

    func selectSprint(_ sprint: JiraSprint) {
        guard sprint.id != selectedSprint?.id else { return }
        selectedSprint = sprint
        Task { await refresh() }
    }

    func selectTicket(_ key: String) {
        selectedTicketKey = key
        loadDetail(for: key)
        setupTerminal(for: key)
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
            let sorted = all.sorted { a, b in
                if (a.state == "active") != (b.state == "active") { return a.state == "active" }
                return a.id > b.id
            }
            sprints = sorted
            selectedSprint = sorted.first { $0.state == "active" } ?? sorted.first
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

            let issues = try await issuesTask
            let mrs = await mrsTask
            let worktrees = await worktreesTask
            self.worktrees = worktrees
            self.lastMergeRequests = mrs

            let dir = project.tasksPathAbsolute
            cards = issues.map { ticket in
                let info = TaskFileLoader.statusMarker(ticketKey: ticket.key, in: dir)
                let wt = WorktreeScanner.worktree(for: ticket.key, in: worktrees)
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
            regroupColumns()
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

    var displaySections: [TaskSection] {
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

            let sessionId: String?
            if let url = TaskFileLoader.find(ticketKey: key, in: tasksDir) {
                sessionId = TaskFileLoader.ensureSessionId(url: url)
            } else {
                sessionId = SessionIdStore.ensure(forTicket: key)
            }

            let plan = TerminalSessionResolver.resolve(
                ticketKey: key,
                repoDir: repoDir,
                worktree: worktree,
                sessionId: sessionId,
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
            }
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
                }
            }
            loadReviews(for: key, in: dir)
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
}
