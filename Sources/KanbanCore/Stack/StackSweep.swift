import Foundation

/// Eine Karte, so wie der Sweep sie braucht: Ticket, abgeleitete Spalte, und ob gerade ein
/// Claude-Turn läuft.
public struct StackSweepCard: Sendable, Hashable {
    public let key: String
    public let column: KanbanColumn
    /// Ein laufender Turn — der einzige Grund, einen fertigen Stack **nicht** vorzuwählen: die
    /// Session arbeitet noch, und ihr den Stack unter den Füssen wegzuziehen bricht sie mitten drin ab.
    public let isWorking: Bool

    public init(key: String, column: KanbanColumn, isWorking: Bool) {
        self.key = key
        self.column = column
        self.isWorking = isWorking
    }
}

/// Ein laufender Worktree-Stack samt dem, was das Board über sein Ticket weiss.
public struct StackSweepCandidate: Sendable, Hashable, Identifiable {
    /// Stack-Name = Worktree-Ordnername (`even-3675`) — gleichzeitig Container-Präfix und Image-Tag.
    public let stackName: String
    /// Nackte Nummer für `iwf worktree stop <NR>`.
    public let number: String
    public let worktreePath: String
    /// Ticket der zugehörigen Karte — nil, wenn keine auf dem Board liegt (fremder Sprint,
    /// Sprint-Modus). Dann ist die Spalte unbekannt, und geraten wird nicht.
    public let ticketKey: String?
    public let column: KanbanColumn?
    public let runningContainers: Int
    public let isWorking: Bool
    /// Volumes dieses Stacks, wie Docker sie führt (`even-3675_dbdata`, `even-3675_appcache`).
    public let volumes: [String]
    /// Image-Tags dieses Stacks (`local/even-3675:latest`, `local/even-3675-base:latest`).
    public let imageTags: [String]
    /// Der im Worktree bereitgestellte DB-Dump — die Rückfahrkarte für ein gelöschtes Volume:
    /// beim nächsten Start importiert MySQL ihn in die leere DB.
    public let stagedDump: String?

    public var id: String { stackName }

    /// Fertig im Sinne des Boards: der Stack hat seine Aufgabe erfüllt.
    public var isFinished: Bool { column == .review || column == .done }
    /// Vorgewählt wird nur, was fertig **und** ruhig ist. Alles andere lässt sich von Hand
    /// dazuwählen — `iwf worktree start <NR>` holt es jederzeit zurück.
    public var isPreselected: Bool { isFinished && !isWorking }

    /// Tief abräumen heisst: Volumes und Images weg. Erlaubt nur mit bereitgestelltem Dump — ohne
    /// ihn ist die Datenbank des Worktrees endgültig weg, und das ist kein Aufräumen mehr, sondern
    /// Datenverlust. (Das `appcache`-Volume ist bloss Cache und käme von selbst wieder.)
    public var canDeepClean: Bool { stagedDump != nil && !(volumes.isEmpty && imageTags.isEmpty) }

    public init(stackName: String, number: String, worktreePath: String, ticketKey: String?,
                column: KanbanColumn?, runningContainers: Int, isWorking: Bool,
                volumes: [String] = [], imageTags: [String] = [], stagedDump: String? = nil) {
        self.stackName = stackName
        self.number = number
        self.worktreePath = worktreePath
        self.ticketKey = ticketKey
        self.column = column
        self.runningContainers = runningContainers
        self.isWorking = isWorking
        self.volumes = volumes
        self.imageTags = imageTags
        self.stagedDump = stagedDump
    }
}

public struct StackSweepPlan: Sendable {
    public let candidates: [StackSweepCandidate]
    /// Stacks, deren Container laufen, zu denen es aber keinen Worktree (mehr) gibt. `iwf worktree
    /// stop` greift dort nicht — sie werden nur benannt, nicht angefasst.
    public let orphanStacks: [String]

    public init(candidates: [StackSweepCandidate], orphanStacks: [String]) {
        self.candidates = candidates
        self.orphanStacks = orphanStacks
    }

    public static let empty = StackSweepPlan(candidates: [], orphanStacks: [])

    /// Die Stacks fertiger Tickets — der Zähler auf dem Toolbar-Knopf.
    public var finished: [StackSweepCandidate] { candidates.filter(\.isFinished) }
    public var preselected: Set<String> {
        Set(candidates.filter(\.isPreselected).map(\.stackName))
    }
}

/// Leitet ab, welche Worktree-Stacks abgeräumt werden können: Docker sagt, was läuft, `git worktree`
/// sagt, wozu es gehört, und die Board-Spalte sagt, ob es noch gebraucht wird.
///
/// Alles davon ist **beobachtet**, nichts gemerkt — derselbe Grundsatz wie bei den Spalten. Ein
/// eigener „schon gestoppt"-Zustand würde falsch, sobald jemand den Stack von Hand wieder hochfährt;
/// so ist ein bereits gestoppter Stack einfach kein Kandidat mehr.
public enum StackSweep {
    /// - Parameters:
    ///   - cards: die Karten des Boards (Spalte + laufender Turn).
    ///   - worktrees: `git worktree list` des Projekts, inklusive Haupt-Repo.
    ///   - repoDir: das Haupt-Repo — sein Stack wird **nie** Kandidat, auch wenn es auf einem
    ///     Feature-Branch steht und damit auf ein Ticket zeigt.
    ///   - runningContainers: Namen der laufenden Container (`docker ps --format '{{.Names}}'`).
    ///   - projectName: Ordnername des Haupt-Repos (`even`) — Präfix der Stack-Namen.
    ///   - volumes: `docker volume ls` — für die tiefe Stufe.
    ///   - imageTags: `docker images` — dito.
    ///   - stagedDumps: Worktree-Pfad → Dateiname des bereitgestellten Dumps (`WorktreeDbSeed`).
    public static func plan(cards: [StackSweepCard],
                           worktrees: [Worktree],
                           repoDir: String,
                           runningContainers: [String],
                           projectName: String,
                           volumes: [String] = [],
                           imageTags: [String] = [],
                           stagedDumps: [String: String] = [:]) -> StackSweepPlan {
        let main = (repoDir as NSString).standardizingPath
        let running = runningContainers
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var candidates: [StackSweepCandidate] = []
        var seen: Set<String> = []

        for worktree in worktrees {
            guard (worktree.path as NSString).standardizingPath != main else { continue }
            let stackName = (worktree.path as NSString).lastPathComponent
            guard !seen.contains(stackName) else { continue }

            // Container zählen statt fragen, ob der Stack „läuft": ein einzelner übriger
            // fpm-Container ist genau der Fall, den man nicht sieht und der trotzdem Speicher hält.
            let count = running.filter { $0.hasPrefix(stackName + "-") }.count
            guard count > 0 else { continue }

            let card = cards.first { matches(worktree: worktree, stackName: stackName, key: $0.key) }
            guard let number = number(stackName: stackName, ticketKey: card?.key) else { continue }

            seen.insert(stackName)
            candidates.append(StackSweepCandidate(
                stackName: stackName,
                number: number,
                worktreePath: worktree.path,
                ticketKey: card?.key,
                column: card?.column,
                runningContainers: count,
                isWorking: card?.isWorking ?? false,
                volumes: volumes.filter { $0.hasPrefix(stackName + "_") }.sorted(),
                imageTags: imageTags.filter { belongs(tag: $0, stackName: stackName) }.sorted(),
                stagedDump: stagedDumps[worktree.path]))
        }

        return StackSweepPlan(candidates: candidates.sorted { $0.stackName < $1.stackName },
                              orphanStacks: orphans(running: running,
                                                    projectName: projectName,
                                                    known: seen))
    }

    /// Die Befehle der tiefen Stufe, als Shell-Zeilen — so steht im Log wortgleich, was ausgeführt
    /// wurde. Gelöscht wird nur, was der Scan gefunden hat: leere Listen ergeben keinen Befehl,
    /// statt ein `docker volume rm` ohne Argumente abzusetzen.
    public static func deepCleanCommands(_ candidate: StackSweepCandidate) -> [String] {
        var commands: [String] = []
        if !candidate.volumes.isEmpty {
            commands.append("docker volume rm "
                            + candidate.volumes.map(WorktreeStackController.quoted).joined(separator: " "))
        }
        if !candidate.imageTags.isEmpty {
            commands.append("docker image rm "
                            + candidate.imageTags.map(WorktreeStackController.quoted).joined(separator: " "))
        }
        return commands
    }

    /// Gehört ein Image-Tag zu diesem Stack? `local/<name>:tag` und alle Ableitungen
    /// `local/<name>-*:tag` (das `-base`-Image). Der Bindestrich ist Pflicht — ohne ihn würde
    /// `even-356` auch `local/even-3563` einsammeln, und ein falsch gelöschtes Image ist ein
    /// 10-Minuten-Rebuild in einem fremden Worktree.
    static func belongs(tag: String, stackName: String) -> Bool {
        guard let colon = tag.lastIndex(of: ":") else { return false }
        let repository = String(tag[tag.startIndex..<colon])
        return repository == "local/\(stackName)" || repository.hasPrefix("local/\(stackName)-")
    }

    /// Karte zu Worktree: über den Branch (wie beim Board) **und** über den Ordnernamen — ein
    /// Worktree im Detached-Head hat keinen Branch, sein Ordner nennt das Ticket aber trotzdem.
    static func matches(worktree: Worktree, stackName: String, key: String) -> Bool {
        if let branch = worktree.branch, TicketMatching.references(branch, ticketKey: key) { return true }
        return TicketMatching.references(stackName, ticketKey: key)
    }

    /// Die Nummer, mit der `iwf` den Worktree anspricht: die Ziffern am Ende des Ordnernamens
    /// (`even-3675` → `3675`), denn genau daraus baut `iwf` seinen Kontext. Ohne solche Ziffern
    /// bleibt das Ticket als Quelle — und ohne beides gibt es keinen Befehl, also keinen Kandidaten.
    static func number(stackName: String, ticketKey: String?) -> String? {
        if let digits = trailingDigits(stackName) { return digits }
        if let key = ticketKey, let digits = trailingDigits(key) { return digits }
        return nil
    }

    private static func trailingDigits(_ text: String) -> String? {
        let digits = String(text.reversed().prefix { $0.isNumber }.reversed())
        return digits.isEmpty ? nil : digits
    }

    /// Laufende Container in Stack-Form (`<projekt>-<zahl>-<service>`), zu denen kein Worktree
    /// gehört. Sie sind kein Kandidat: `iwf worktree stop` verlangt den Worktree und bricht sonst ab.
    static func orphans(running: [String], projectName: String, known: Set<String>) -> [String] {
        var stacks: Set<String> = []
        for name in running {
            guard name.hasPrefix(projectName + "-") else { continue }
            let rest = name.dropFirst(projectName.count + 1)
            guard let dash = rest.firstIndex(of: "-") else { continue }
            let number = rest[rest.startIndex..<dash]
            guard !number.isEmpty, number.allSatisfy(\.isNumber) else { continue }
            let stack = "\(projectName)-\(number)"
            if !known.contains(stack) { stacks.insert(stack) }
        }
        return stacks.sorted()
    }
}
