import Foundation

/// Die Ticketliste des **freien Modus**: nicht Jira sagt, was auf dem Board steht, sondern das, was
/// lokal existiert — jedes Task-File, dazu jeder Worktree und jeder MR, zu dem (noch) kein Task-File
/// gehört.
///
/// Der Titel kommt aus der H1 des Task-Files (`# EVEN-3687 - Trigger Nachtrag eingereicht`), nicht aus
/// Jira: der freie Modus soll ohne eine einzige Jira-Anfrage auskommen. Ein Ticket, das nur als
/// Worktree oder MR existiert, trägt den Branch- bzw. MR-Titel.
public enum LocalTickets {
    /// Alle lokal auffindbaren Tickets, nach Nummer aufsteigend.
    public static func discover(tasksDirectory: String,
                                prefix: String,
                                worktrees: [Worktree] = [],
                                mergeRequests: [MergeRequestRef] = []) -> [Ticket] {
        var titles: [String: String] = [:]     // key → Titel, erste Quelle gewinnt
        var order: [String] = []

        func note(_ key: String, title: String?) {
            let upper = key.uppercased()
            if titles[upper] == nil { order.append(upper) }
            if let title, !title.isEmpty, (titles[upper] ?? "").isEmpty { titles[upper] = title }
            else if titles[upper] == nil { titles[upper] = "" }
        }

        for file in taskFiles(in: tasksDirectory, prefix: prefix) {
            note(file.key, title: file.title)
        }
        // Worktrees und MRs ergänzen, was (noch) kein Task-File hat — z.B. ein Branch, den jemand
        // ohne Task-File angelegt hat.
        for worktree in worktrees {
            guard let branch = worktree.branch, let key = key(in: branch, prefix: prefix) else { continue }
            note(key, title: branch)
        }
        for mr in mergeRequests {
            guard let key = key(in: mr.sourceBranch, prefix: prefix) ?? key(in: mr.title, prefix: prefix)
            else { continue }
            note(key, title: mr.title)
        }

        let numbered = order
            .map { Ticket(key: $0, summary: titles[$0] ?? "") }
            .sorted { TicketNumber.isAscending($0.key, $1.key) }
        return numbered + mrTickets(tasksDirectory: tasksDirectory,
                                    mergeRequests: mergeRequests, prefix: prefix)
    }

    /// Die `!<iid>`-Karten: offene MRs ohne Ticketnummer **und** die Task-Files, die zu ihnen
    /// geschrieben wurden.
    ///
    /// `branchTickets` allein lässt die Karte mit dem Merge verschwinden — und mit ihr das Task-File
    /// samt Review, das jemand daran geschrieben hat. Ein `!49_slug.md` hält sie deshalb am Leben,
    /// unabhängig vom MR-Status. Der Branch kommt aus dem `🌿 BRANCH`-Block des Files, damit
    /// `TicketMatching` den (inzwischen gemergten) MR weiterhin an die Karte hängt; aus dem Dateinamen
    /// wäre er nicht zu holen, denn Branchnamen enthalten `/`.
    static func mrTickets(tasksDirectory: String,
                          mergeRequests: [MergeRequestRef], prefix: String) -> [Ticket] {
        var byKey: [String: Ticket] = [:]
        var order: [String] = []

        for ticket in branchTickets(mergeRequests: mergeRequests, prefix: prefix) {
            if byKey[ticket.key] == nil { order.append(ticket.key) }
            byKey[ticket.key] = ticket
        }
        for file in mrTaskFiles(in: tasksDirectory) {
            if var ticket = byKey[file.key] {
                // Der Titel des Task-Files gewinnt über den MR-Titel — wie bei nummerierten Tickets.
                if let title = file.title, !title.isEmpty { ticket.summary = title }
                byKey[file.key] = ticket
            } else {
                order.append(file.key)
                byKey[file.key] = Ticket(key: file.key,
                                         summary: file.title ?? file.key,
                                         sourceBranch: file.branch ?? "")
            }
        }
        return order.compactMap { byKey[$0] }.sorted { iid(of: $0.key) > iid(of: $1.key) }
    }

    /// `!49` bzw. `#49` → 49, der Sortierschlüssel der MR-Karten (der jüngste zuerst).
    static func iid(of key: String) -> Int { Int(key.dropFirst()) ?? 0 }

    /// Arbeit **ohne Ticketnummer**: ein offener MR, dessen Branch und Titel kein
    /// `<PREFIX>-<zahl>` enthalten. Ohne diese Stufe fällt er ganz vom Brett — im freien Modus ist
    /// aber genau das die Arbeit, aus der man noch einen Task machen will.
    ///
    /// **Nur offene** MRs. Ein gemergter ohne Nummer ist erledigte Geschichte, aus der nichts mehr
    /// zu erstellen ist; sie mitzunehmen hiesse, Done mit Altlasten zu füllen — in `zba` sind das
    /// 10 von 14 (der älteste von 2023), gegen 4 offene, um die es wirklich geht.
    ///
    /// Der Key ist die **Schreibweise der Forge**: `!49` bei GitLab, `#49` bei GitHub — dieselbe,
    /// die `review-merge` als Argument nimmt. Gefunden wird die Karte trotzdem nicht über ihn,
    /// sondern über ihren Branch (siehe `Ticket.sourceBranch`); der Key benennt sie nur.
    static func branchTickets(mergeRequests: [MergeRequestRef], prefix: String) -> [Ticket] {
        mergeRequests
            .filter { $0.state == "opened" }
            .filter { key(in: $0.sourceBranch, prefix: prefix) == nil && key(in: $0.title, prefix: prefix) == nil }
            .sorted { $0.iid > $1.iid }   // der jüngste MR zuerst — er ist der, an dem gerade liegt
            .map { mr in
                Ticket(key: mr.numberLabel,
                       summary: mr.title.isEmpty ? mr.sourceBranch : mr.title,
                       sourceBranch: mr.sourceBranch)
            }
    }

    // MARK: - Task-Files

    struct TaskFileRef: Equatable {
        let key: String
        let title: String?
    }

    /// Alle Task-Files des Ordners mit Key und Titel. Review-Files (`<KEY>_review*.md`) sind eigene
    /// Tabs am Ticket, keine eigenen Tickets — genau wie in `TaskFileLoader.find`.
    static func taskFiles(in directory: String, prefix: String) -> [TaskFileRef] {
        let url = URL(fileURLWithPath: directory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }

        var seen: Set<String> = []
        var result: [TaskFileRef] = []
        for name in names.sorted() where name.hasSuffix(".md") {
            guard let key = key(inFileName: name, prefix: prefix),
                  !TaskFileLoader.isReviewFilename(name, keyPrefix: key),
                  seen.insert(key.uppercased()).inserted else { continue }
            result.append(TaskFileRef(key: key, title: title(inFileAt: url.appendingPathComponent(name))))
        }
        return result
    }

    /// Task-Files einer MR-Karte: `!49_cli_version_option.md` → `!49`. Review-Files sind auch hier
    /// Tabs am Ticket, keine eigenen Karten — dieselbe Regel wie in `taskFiles`.
    static func mrTaskFiles(in directory: String) -> [MRTaskFileRef] {
        let url = URL(fileURLWithPath: directory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }

        var seen: Set<String> = []
        var result: [MRTaskFileRef] = []
        for name in names.sorted() where name.hasSuffix(".md") {
            guard let key = mrKey(inFileName: name),
                  !TaskFileLoader.isReviewFilename(name, keyPrefix: key),
                  seen.insert(key).inserted else { continue }
            let preamble = head(ofFileAt: url.appendingPathComponent(name)) ?? ""
            result.append(MRTaskFileRef(key: key,
                                        title: title(inHead: preamble),
                                        branch: branch(inHead: preamble)))
        }
        return result
    }

    struct MRTaskFileRef: Equatable {
        let key: String
        let title: String?
        let branch: String?
    }

    /// `!49_cli_version_option.md` → `!49`, `#49_cli_version_option.md` → `#49`. Verlangt den Key
    /// am Anfang, damit `notiz_zu_!49.md` nicht als Karte zählt — dieselbe Regel wie bei
    /// `key(inFileName:prefix:)`.
    ///
    /// **Beide** Schreibweisen, unabhängig von der Forge des Projekts: bestehende Task-Files heissen
    /// `!49_…` und werden nicht rückwirkend umbenannt, nur weil ein Projekt auf GitHub liegt.
    static func mrKey(inFileName name: String) -> String? {
        let stem = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        guard let regex = try? NSRegularExpression(pattern: #"^[!#]\d+"#),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              let range = Range(match.range, in: stem) else { return nil }
        return String(stem[range])
    }

    /// Der Branch aus dem Präambel-Block — ``> 🌿 **BRANCH**: `feature/x` `` → `feature/x`.
    static func branch(inHead head: String) -> String? {
        for line in head.components(separatedBy: .newlines) where line.contains("**BRANCH**") {
            guard let open = line.firstIndex(of: "`") else { continue }
            let rest = line[line.index(after: open)...]
            guard let close = rest.firstIndex(of: "`") else { continue }
            let value = String(rest[..<close]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// `EVEN-3687_resolve_pendenz.md` → `EVEN-3687`. Nur Dateien des eigenen Projekt-Präfixes.
    static func key(inFileName name: String, prefix: String) -> String? {
        let stem = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        return key(in: stem, prefix: prefix, anchoredAtStart: true)
    }

    /// Sucht `<PREFIX>-<zahl>` in einem beliebigen Text (Branch, MR-Titel). `anchoredAtStart` verlangt
    /// den Key am Anfang — für Dateinamen, damit `notizen_zu_EVEN-1.md` nicht als Ticket zählt.
    static func key(in text: String, prefix: String, anchoredAtStart: Bool = false) -> String? {
        guard !prefix.isEmpty else { return nil }
        let pattern = (anchoredAtStart ? "^" : "") + "\(NSRegularExpression.escapedPattern(for: prefix))-(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range]).uppercased()
    }

    /// Der Titel aus der ersten H1 — `# EVEN-3687 - Trigger Nachtrag eingereicht` → „Trigger Nachtrag
    /// eingereicht". Gelesen werden nur die ersten 1 KB: bei 160 Task-Files pro Poll-Durchlauf zählt
    /// das, und die H1 steht immer oben (davor höchstens der Session-Id-Kommentar).
    static func title(inFileAt url: URL) -> String? {
        guard let head = head(ofFileAt: url) else { return nil }
        return title(inHead: head)
    }

    /// Die ersten 1 KB einer Datei — genug für H1 **und** Präambel-Block, und nur ein Read für beide.
    static func head(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func title(inHead head: String) -> String? {
        for line in head.components(separatedBy: .newlines) {
            guard line.hasPrefix("# ") else { continue }
            let heading = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            // „EVEN-3687 - Titel" / „EVEN-3687 | Titel" / „EVEN-3687: Titel" → Titel. Ohne Trenner
            // bleibt die ganze Überschrift stehen. Der Doppelpunkt darf am Key kleben, Strich und
            // Pipe brauchen Leerzeichen — sonst zerschnitte „EVEN-3687" sich am eigenen Bindestrich.
            if let separator = heading.range(of: #"(\s*:|\s+[-–—|])\s+"#, options: .regularExpression) {
                return String(heading[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return heading
        }
        return nil
    }
}

/// Ticket-Keys numerisch vergleichen. Rein lexikografisch stünde `EVEN-999` hinter `EVEN-1000` —
/// im Sprint mit 30 Karten fällt das kaum auf, im freien Modus mit der ganzen Historie sofort.
public enum TicketNumber {
    public static func isAscending(_ lhs: String, _ rhs: String) -> Bool {
        let (leftPrefix, leftNumber) = split(lhs)
        let (rightPrefix, rightNumber) = split(rhs)
        if leftPrefix != rightPrefix { return leftPrefix < rightPrefix }
        if leftNumber != rightNumber { return leftNumber < rightNumber }
        return lhs < rhs
    }

    static func split(_ key: String) -> (prefix: String, number: Int) {
        guard let dash = key.lastIndex(of: "-"),
              let number = Int(key[key.index(after: dash)...]) else { return (key.uppercased(), 0) }
        return (String(key[..<dash]).uppercased(), number)
    }
}
