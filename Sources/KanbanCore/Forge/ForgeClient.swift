import Foundation

/// Auf welcher Plattform der Code eines Projekts liegt.
///
/// Fachlich ist ein Pull Request dasselbe wie ein Merge Request — ein Zweig, der in einen anderen
/// soll, mit Kommentaren, Zustimmung und einem Zustand. Unterschiedlich sind die API dahinter (siehe
/// `GitHubClient`) und die **Sprache**: dieselbe Sache heisst hier „MR !42" und dort „PR #42".
/// Genau diese beiden Dinge stehen in diesem Enum, und sonst nichts — das Domänenmodell
/// (`MergeRequestRef`, `MRReviewState`, `WorkflowStatus`) bleibt provider-neutral.
public enum ForgeKind: String, Sendable, Hashable, CaseIterable, Codable {
    case gitlab
    case github

    /// Wie die Plattform heisst — für Badges, Tooltips und Fehlermeldungen.
    public var label: String {
        switch self {
        case .gitlab: return "GitLab"
        case .github: return "GitHub"
        }
    }

    /// Die Kurzform auf der Karte und im Command: „MR" bzw. „PR".
    public var requestAbbreviation: String {
        switch self {
        case .gitlab: return "MR"
        case .github: return "PR"
        }
    }

    /// Ausgeschrieben, für Tooltips und Fliesstext.
    public var requestNoun: String {
        switch self {
        case .gitlab: return "Merge Request"
        case .github: return "Pull Request"
        }
    }

    /// Wie die Plattform selbst die Nummer schreibt: GitLab `!42`, GitHub `#42`. Trägt die Keys der
    /// Karten ohne Ticketnummer (`LocalTickets`) und das Argument von `review-merge`.
    public var numberPrefix: String {
        switch self {
        case .gitlab: return "!"
        case .github: return "#"
        }
    }

    /// Der Pfadabschnitt vor dem Branch in der Web-URL. GitLab schiebt sein `/-/` zwischen Projekt
    /// und Ressource, GitHub nicht — ohne diese Unterscheidung ginge der Branch-Link im Task-File
    /// still ins Leere.
    public var branchPathSegment: String {
        switch self {
        case .gitlab: return "/-/tree/"
        case .github: return "/tree/"
        }
    }
}

/// Die Forge-Zuordnung eines Projekts: Plattform **und** Pfad (`applications/even` bzw.
/// `owner/repo`). Nil, wenn ein Projekt auf keiner Forge liegt — dann bleibt das Board bei den
/// lokalen Artefakten, wie bisher ohne GitLab.
public struct ForgeRef: Sendable, Hashable, Codable {
    public let kind: ForgeKind
    public let path: String

    public init(kind: ForgeKind, path: String) {
        self.kind = kind
        self.path = path
    }
}

/// Was zum Bauen einer Web-URL nötig ist: Plattform, **Web**-Basis (nicht die API-Basis) und
/// Projekt-Pfad. Als eigener Wert, weil Branch-Links an drei Stellen gebraucht werden
/// (`StatusLinks`, Branch-Chip, Branch-Stack) und keine davon die Config kennen soll.
public struct ForgeLocation: Sendable, Hashable {
    public let kind: ForgeKind
    public let webBaseUrl: String
    public let projectPath: String

    public init?(kind: ForgeKind, webBaseUrl: String?, projectPath: String?) {
        guard let webBaseUrl, !webBaseUrl.isEmpty,
              let projectPath, !projectPath.isEmpty else { return nil }
        self.kind = kind
        self.webBaseUrl = webBaseUrl.hasSuffix("/") ? String(webBaseUrl.dropLast()) : webBaseUrl
        self.projectPath = projectPath
    }

    /// `<base>/<pfad>/-/tree/<branch>` bei GitLab, `<base>/<owner>/<repo>/tree/<branch>` bei GitHub.
    public func branchURL(_ branch: String) -> String? {
        guard !branch.isEmpty,
              let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return "\(webBaseUrl)/\(projectPath)\(kind.branchPathSegment)\(encoded)"
    }
}

/// Was das Board von einer Forge braucht — und nicht mehr.
///
/// Bewusst schmal: die Detail-Ebene (Diffs, Notes, Schreibwege) hängt heute an keiner Oberfläche,
/// weder bei GitLab noch bei GitHub. Sie ins Protokoll zu heben hiesse, es auf Vorrat aufzublähen;
/// sie steht deshalb je Forge in `Modules/<Forge>` und wird direkt am konkreten Client gerufen.
public protocol ForgeClient: Sendable {
    var kind: ForgeKind { get }

    /// Offene und gemergte Requests eines Projekts, **normalisiert** auf GitLabs Zustandsnamen
    /// (`opened` / `merged` / `closed`). Offene tragen zusätzlich ihren Review-Stand.
    func openedAndMergedRequests(projectPath: String) async throws -> [MergeRequestRef]

    /// Erledigte und offene Review-Threads eines Requests. Ein Fehlschlag zählt als (0, 0) — das
    /// Badge ist ein Hinweis, es darf den Board-Durchlauf nie kippen.
    func discussionCounts(projectPath: String, iid: Int) async -> (resolved: Int, unresolved: Int)

    /// Ob mindestens eine Person zugestimmt hat, samt Namen für den Tooltip. Fehlschlag = keine
    /// Zustimmung, aus demselben Grund.
    func approval(projectPath: String, iid: Int) async -> (approved: Bool, by: [String])
}
