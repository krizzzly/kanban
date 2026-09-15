import Foundation

/// One file with uncommitted changes, as `git status --porcelain` reports it (`XY path`).
public struct GitChangedFile: Sendable, Hashable, Identifiable {
    public let path: String
    /// The two status columns: index (staged) and worktree. `??` = untracked.
    public let index: Character
    public let worktree: Character

    public var id: String { path }
    public var isUntracked: Bool { index == "?" }

    /// Short marker for the list: `A` added · `M` modified · `D` deleted · `R` renamed · `?` new file.
    public var marker: String {
        if isUntracked { return "?" }
        let code = index != " " ? index : worktree
        return String(code)
    }

    public init(path: String, index: Character, worktree: Character) {
        self.path = path
        self.index = index
        self.worktree = worktree
    }
}

/// The state of a working tree, as the commit dialog needs it.
public struct GitWorkingState: Sendable, Hashable {
    public let branch: String?
    /// Files with uncommitted changes (staged or not).
    public let changedFiles: [GitChangedFile]
    /// Subject of HEAD — shown when amending, so it is visible what gets rewritten.
    public let headSubject: String?
    /// True when HEAD exists on the remote — an amend then needs a force push.
    public let hasUpstream: Bool

    public var isClean: Bool { changedFiles.isEmpty }

    public init(branch: String?, changedFiles: [GitChangedFile], headSubject: String?, hasUpstream: Bool) {
        self.branch = branch
        self.changedFiles = changedFiles
        self.headSubject = headSubject
        self.hasUpstream = hasUpstream
    }
}

/// Was der Branch gegenüber seiner Abzweig-Basis geändert hat — der Blick, den auch der Reviewer im
/// Merge Request hat.
///
/// Gemessen wird ab dem **Merge-Base**, nicht ab der Spitze der Basis: sonst stünden die Commits, die
/// `develop` seit der Abzweigung bekommen hat, als *Rücknahmen* im eigenen Diff. Das ist derselbe
/// Dreipunkt-Vergleich (`base...HEAD`), aus dem `BranchParent` schon sein `ahead` zieht.
public struct GitBranchDiff: Sendable, Hashable {
    /// Die Basis, wie git sie nennt (`origin/develop`) — abgeleitet, siehe `BranchParent`.
    public let baseRef: String
    /// Der aufgelöste Merge-Base-Commit. Einmal aufgelöst und weitergereicht, damit jede Datei
    /// gegen **denselben** Stand verglichen wird, auch wenn sich die Basis nebenher bewegt.
    public let mergeBase: String
    /// Dateien, die der Branch geändert hat.
    public let files: [GitChangedFile]
    /// Eigene Commits über der Basis — die Zahl, die auch im MR steht.
    public let commits: Int

    public var isEmpty: Bool { files.isEmpty }

    public init(baseRef: String, mergeBase: String, files: [GitChangedFile], commits: Int) {
        self.baseRef = baseRef
        self.mergeBase = mergeBase
        self.files = files
        self.commits = commits
    }
}

/// Runs the git commands behind the Commit button. Every call is synchronous and meant to run off the
/// main actor (like `WorktreeScanner`); the caller reports stdout/stderr back to the user.
public struct GitCommitController: Sendable {
    public enum GitError: Error, LocalizedError {
        case failed(command: String, output: String)

        public var errorDescription: String? {
            switch self {
            case .failed(let command, let output):
                return output.isEmpty ? "git \(command) fehlgeschlagen" : output
            }
        }
    }

    private let git = "/usr/bin/git"

    public init() {}

    // MARK: - Reading

    /// Branch, pending changes and HEAD subject of `dir`. Fail-open: a non-repo yields an empty state.
    public func state(dir: String) -> GitWorkingState {
        let branch = run(["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"], dir: dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `--untracked-files=all` lists the files inside a brand-new directory; without it git collapses
        // them into a single `dir/` entry, which under-reports what `add -A` will commit and has no diff.
        // `-z` (NUL-separated) keeps paths raw — the default output quotes and octal-escapes anything
        // non-ASCII (`"L\303\266sung.md"`), and such a path finds no file when the diff runs.
        let status = run(["-C", dir, "status", "--porcelain", "-z", "--untracked-files=all"], dir: dir).output
        let files = Self.parseStatus(status)
        let subject = run(["-C", dir, "log", "-1", "--pretty=%s"], dir: dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `@{upstream}` resolves only when the branch is tracked — that decides push vs force-push.
        let upstream = run(["-C", dir, "rev-parse", "--abbrev-ref", "@{upstream}"], dir: dir)
        return GitWorkingState(branch: branch.isEmpty ? nil : branch,
                               changedFiles: files,
                               headSubject: subject.isEmpty ? nil : subject,
                               hasUpstream: upstream.status == 0)
    }

    /// Splits the NUL-separated `--porcelain -z` output into files.
    static func parseStatus(_ output: String) -> [GitChangedFile] {
        var files: [GitChangedFile] = []
        var records = output.components(separatedBy: "\0").makeIterator()
        while let record = records.next() {
            guard let file = parseStatusRecord(record) else { continue }
            // A rename/copy carries the *source* path in the following record — skip it, we show the new one.
            if isRenameOrCopy(file) { _ = records.next() }
            files.append(file)
        }
        return files
    }

    /// `XY path` → a changed file. In `-z` output the path is raw: never quoted, never escaped, and it
    /// may legally end in a space — so nothing here trims it.
    static func parseStatusRecord(_ record: String) -> GitChangedFile? {
        guard record.count > 3 else { return nil }
        let chars = Array(record)
        guard chars[2] == " " else { return nil }
        return GitChangedFile(path: String(chars[3...]), index: chars[0], worktree: chars[1])
    }

    private static func isRenameOrCopy(_ file: GitChangedFile) -> Bool {
        "RC".contains(file.index) || "RC".contains(file.worktree)
    }

    /// The unified diff of one file against HEAD — what the dialog renders. An untracked file has no
    /// HEAD side, so it is diffed against /dev/null and shows up as all-additions.
    /// git exits non-zero when differences exist, so the status is deliberately ignored here.
    public func diff(dir: String, file: GitChangedFile) -> String {
        if file.isUntracked {
            return run(["-C", dir, "diff", "--no-index", "--", "/dev/null", file.path], dir: dir).output
        }
        return run(["-C", dir, "diff", "HEAD", "--", file.path], dir: dir).output
    }

    /// Was der Branch seit der Abzweigung von `baseRef` geändert hat. Nil, wenn es keinen
    /// gemeinsamen Vorfahren gibt (fremde Historie) — dann ist die Frage nicht zu beantworten, und
    /// ein leeres Ergebnis wäre die falsche Antwort darauf.
    public func branchDiff(dir: String, baseRef: String) -> GitBranchDiff? {
        let mergeBase = run(["-C", dir, "merge-base", baseRef, "HEAD"], dir: dir)
        guard mergeBase.status == 0 else { return nil }
        let sha = mergeBase.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sha.isEmpty else { return nil }

        // `-M` findet Umbenennungen: ohne das steht eine verschobene Datei als Löschung **und**
        // Neuanlage in der Liste, und ihr Diff behauptet, der ganze Inhalt sei neu geschrieben.
        let names = run(["-C", dir, "diff", "--name-status", "-z", "-M", sha, "HEAD"], dir: dir).output
        let count = run(["-C", dir, "rev-list", "--count", "\(sha)..HEAD"], dir: dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return GitBranchDiff(baseRef: baseRef, mergeBase: sha,
                             files: Self.parseNameStatus(names),
                             commits: Int(count) ?? 0)
    }

    /// `--name-status -z`: die Felder sind NUL-getrennt, **nicht** durch einen Tab wie ohne `-z`.
    /// Ein Umbenennen/Kopieren (`R095`, `C070`) trägt seine Ähnlichkeit im Statusfeld und **zwei**
    /// Pfade dahinter — gezeigt wird der neue, wie in der Status-Liste des Commit-Dialogs.
    static func parseNameStatus(_ output: String) -> [GitChangedFile] {
        var files: [GitChangedFile] = []
        var fields = output.components(separatedBy: "\0").makeIterator()
        while let status = fields.next() {
            guard let code = status.first else { continue }
            guard let first = fields.next(), !first.isEmpty else { continue }
            let path = "RC".contains(code) ? (fields.next() ?? first) : first
            files.append(GitChangedFile(path: path, index: code, worktree: " "))
        }
        return files
    }

    /// Das Diff **einer** Datei gegen den Merge-Base. Anders als beim Arbeitsverzeichnis gibt es hier
    /// keinen Sonderfall „unversioniert": gegen einen Commit hat jede Datei zwei Seiten.
    /// git endet bei Unterschieden mit ungleich 0, der Status wird deshalb bewusst ignoriert.
    public func diff(dir: String, file: GitChangedFile, against base: String) -> String {
        run(["-C", dir, "diff", "-M", base, "HEAD", "--", file.path], dir: dir).output
    }

    /// Dasselbe, aber gegen den **Arbeitsstand** statt gegen HEAD: `git diff <base> -- <datei>`
    /// (ohne `HEAD`) vergleicht den Commit mit der Datei, wie sie gerade auf der Platte liegt.
    ///
    /// Das ist die Grundlage der Editor-Einfärbung im Reiter „Diff": der Editor zeigt die Datei von
    /// heute, also muss auch das Grün/Rot daneben von heute sein. Gegen `base HEAD` gerechnet
    /// verrutschte es, sobald man im Editor eine Zeile einfügt — genau der Grund, aus dem der Editor
    /// dort zunächst gar nicht angeboten wurde.
    public func diffWorktree(dir: String, file: GitChangedFile, against base: String) -> String {
        run(["-C", dir, "diff", "-M", base, "--", file.path], dir: dir).output
    }

    // MARK: - Writing

    /// Stages everything and commits with `message`. Returns git's output for the log pane.
    /// `excluding` lists paths that stay out of the commit (see `stageAll`).
    @discardableResult
    public func commit(dir: String, message: String, excluding: [String] = []) throws -> String {
        var log = try stageAll(dir: dir, excluding: excluding)
        log += try expect(["-C", dir, "commit", "-m", message], dir: dir, name: "commit")
        return log
    }

    /// Stages everything and folds it into HEAD, keeping the existing message (`--no-edit`) — which is
    /// why amending needs no message from the user.
    @discardableResult
    public func amend(dir: String, excluding: [String] = []) throws -> String {
        var log = try stageAll(dir: dir, excluding: excluding)
        log += try expect(["-C", dir, "commit", "--amend", "--no-edit"], dir: dir, name: "commit --amend")
        return log
    }

    /// Pushes the current branch. `force` uses **--force-with-lease**, never a bare --force: it refuses
    /// when the remote moved since we last fetched, so a colleague's push cannot be overwritten blindly.
    @discardableResult
    public func push(dir: String, force: Bool, setUpstream: Bool) throws -> String {
        var args = ["-C", dir, "push"]
        if force { args.append("--force-with-lease") }
        if setUpstream, let branch = state(dir: dir).branch {
            args += ["--set-upstream", "origin", branch]
        }
        return try expect(args, dir: dir, name: force ? "push --force-with-lease" : "push")
    }

    /// `git add -A`, danach die abgewählten Pfade wieder **aus dem Index nehmen**.
    ///
    /// Bewusst dieser Weg statt `git add -A -- <nur die gewählten>`: so bleibt das bisherige
    /// Verhalten für alles Nicht-Abgewählte wortgleich erhalten — auch für eine Datei, die zwischen
    /// dem Laden der Liste und dem Klick auf „Commit" dazukommt. Abgewählt wird, was der Mensch
    /// abgewählt hat, nicht „alles ausser dem, was ich vorhin gesehen habe".
    ///
    /// `restore --staged` ist der richtige Griff, nicht `rm --cached`: es stellt den **Index-Stand
    /// aus HEAD** wieder her. Eine abgewählte Löschung bleibt damit in HEAD stehen, eine abgewählte
    /// neue Datei fällt auf „unversioniert" zurück, und in beiden Fällen bleibt das
    /// Arbeitsverzeichnis unangetastet — gegen echtes git geprüft, nicht aus der Doku geschlossen.
    private func stageAll(dir: String, excluding: [String]) throws -> String {
        var log = try expect(["-C", dir, "add", "-A"], dir: dir, name: "add -A")
        guard !excluding.isEmpty else { return log }
        // Einzeln, nicht in einem Aufruf: git bricht die **ganze** Liste ab, sobald ein Pfad ihm
        // unbekannt ist („pathspec did not match"), und ein zwischenzeitlich verschwundener Pfad
        // darf den Commit nicht verhindern. Ein Fehlschlag heisst hier ohnehin „liegt nicht im
        // Index", also genau der gewünschte Zustand.
        for path in excluding {
            let result = run(["-C", dir, "restore", "--staged", "--", path], dir: dir)
            if result.status != 0 { log += result.output }
        }
        return log
    }

    // MARK: - Process plumbing

    private func expect(_ args: [String], dir: String, name: String) throws -> String {
        let result = run(args, dir: dir)
        guard result.status == 0 else {
            throw GitError.failed(command: name, output: result.output)
        }
        return result.output.isEmpty ? "" : result.output + "\n"
    }

    private func run(_ args: [String], dir: String) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "git nicht ausführbar: \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
