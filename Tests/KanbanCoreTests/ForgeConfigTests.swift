import XCTest
@testable import KanbanCore

/// Wie ein Projekt zu seiner Forge kommt: aus der Config, aus dem `origin`-Remote — und was
/// passiert, wenn es zwei sein sollen.
final class ForgeConfigTests: XCTestCase {
    private func resolve(_ json: String) throws -> AppConfig {
        try KanbanConfig.resolve(Data(json.utf8), docsRoot: "/docs")
    }

    private let gitlabProject = """
    {"basePath": "/code",
     "modules": {
       "jira": {"baseUrl": "https://j", "projects": {"even": {"prefix": "EVEN", "tasksPath": "even/t"}}},
       "gitlab": {"baseUrl": "https://git.firma.io", "apiToken": "glpat-x",
                  "projects": {"even": {"path": "applications/even"}}}}}
    """

    private let githubProject = """
    {"basePath": "/code",
     "modules": {
       "jira": {"baseUrl": "https://j", "projects": {"kanban": {"prefix": "KANBAN", "tasksPath": "kanban/t"}}},
       "github": {"apiToken": "ghp_x", "projects": {"kanban": {"path": "krizzzly/kanban"}}}}}
    """

    // MARK: - Zuordnung

    func testGitlabProjectKeepsItsForge() throws {
        let project = try XCTUnwrap(resolve(gitlabProject).projects.first)
        XCTAssertEqual(project.forge, ForgeRef(kind: .gitlab, path: "applications/even"))
        // Der alte Schlüssel bleibt für die Übergangszeit ableitbar.
        XCTAssertEqual(project.gitlabProjectPath, "applications/even")
    }

    func testGithubProjectGetsTheOtherForge() throws {
        let config = try resolve(githubProject)
        let project = try XCTUnwrap(config.projects.first)
        XCTAssertEqual(project.forge, ForgeRef(kind: .github, path: "krizzzly/kanban"))
        // Und **keinen** GitLab-Pfad — der behauptete sonst etwas, das es nicht gibt.
        XCTAssertNil(project.gitlabProjectPath)
        XCTAssertTrue(config.hasGithub)
        XCTAssertFalse(config.hasGitlab)
    }

    /// Ohne Eintrag bleibt das Board bei den lokalen Artefakten — wie immer ohne GitLab.
    func testProjectWithoutForgeIsFine() throws {
        let config = try resolve("""
        {"modules": {"jira": {"projects": {"solo": {"prefix": "SOLO", "tasksPath": "solo/t"}}}}}
        """)
        XCTAssertNil(config.projects.first?.forge)
        XCTAssertFalse(config.hasGitlab)
        XCTAssertFalse(config.hasGithub)
    }

    /// Ein leerer Pfad ist keine Zuordnung — sonst würde später gegen das Projekt „" gefragt.
    func testEmptyPathIsNoForge() throws {
        let config = try resolve("""
        {"modules": {"jira": {"projects": {"even": {"prefix": "EVEN", "tasksPath": "even/t"}}},
                     "gitlab": {"projects": {"even": {"path": "  "}}}}}
        """)
        XCTAssertNil(config.projects.first?.forge)
    }

    /// **Melden, nicht raten:** dasselbe Projekt in beiden Abschnitten ist ein Konfigurationsfehler,
    /// und die Meldung nennt den Namen.
    func testAProjectInBothSectionsIsAnError() {
        let both = """
        {"modules": {
           "jira": {"projects": {"even": {"prefix": "EVEN", "tasksPath": "even/t"}}},
           "gitlab": {"projects": {"even": {"path": "applications/even"}}},
           "github": {"projects": {"even": {"path": "firma/even"}}}}}
        """
        XCTAssertThrowsError(try resolve(both)) {
            guard case KanbanConfigError.ambiguousForge(let project) = $0 else {
                return XCTFail("falscher Fehler: \($0)")
            }
            XCTAssertEqual(project, "even")
            XCTAssertTrue($0.localizedDescription.contains("even"), $0.localizedDescription)
        }
    }

    /// Auch dann, wenn der Key gar kein Jira-Projekt ist — sonst bliebe der Widerspruch stehen,
    /// bis ihn jemand dort einträgt.
    func testTheConflictIsFoundWithoutAJiraEntry() {
        XCTAssertThrowsError(try resolve("""
        {"modules": {"gitlab": {"projects": {"tech": {"path": "a/b"}}},
                     "github": {"projects": {"tech": {"path": "c/d"}}}}}
        """))
    }

    // MARK: - Base-URLs

    /// Die API-Basis hat eine Vorgabe — niemand soll `https://api.github.com` abtippen müssen.
    func testGithubBaseUrlDefaultsAndDerivesTheWebBase() throws {
        let config = try resolve(githubProject)
        XCTAssertEqual(config.githubApiUrl, "https://api.github.com")
        XCTAssertEqual(config.githubWebBaseUrl, "https://github.com")

        let enterprise = try resolve("""
        {"modules": {"github": {"baseUrl": "https://ghe.firma.io/api/v3", "apiToken": "ghp_x"}}}
        """)
        XCTAssertEqual(enterprise.githubApiUrl, "https://ghe.firma.io/api/v3")
        XCTAssertEqual(enterprise.githubWebBaseUrl, "https://ghe.firma.io")
    }

    /// Die Branch-URL der Forge — GitLabs `/-/tree/` gegen GitHubs `/tree/`.
    func testForgeLocationBuildsTheBranchURLPerForge() throws {
        let gitlab = try resolve(gitlabProject)
        let onGitlab = try XCTUnwrap(gitlab.forgeLocation(for: gitlab.projects.first))
        XCTAssertEqual(onGitlab.branchURL("feature/EVEN-1_x"),
                       "https://git.firma.io/applications/even/-/tree/feature/EVEN-1_x")

        let github = try resolve(githubProject)
        let onGithub = try XCTUnwrap(github.forgeLocation(for: github.projects.first))
        XCTAssertEqual(onGithub.branchURL("feature/KANBAN-7_x"),
                       "https://github.com/krizzzly/kanban/tree/feature/KANBAN-7_x")
    }

    // MARK: - Beschriftung

    /// Die einzige Stelle, an der die Forge überhaupt durchschlägt: wie die Sache heisst.
    func testWordingPerForge() {
        XCTAssertEqual(ForgeKind.gitlab.requestAbbreviation, "MR")
        XCTAssertEqual(ForgeKind.github.requestAbbreviation, "PR")
        XCTAssertEqual(ForgeKind.gitlab.numberPrefix, "!")
        XCTAssertEqual(ForgeKind.github.numberPrefix, "#")
        XCTAssertEqual(ForgeKind.gitlab.requestNoun, "Merge Request")
        XCTAssertEqual(ForgeKind.github.requestNoun, "Pull Request")
    }

    // MARK: - Vorschlag aus dem origin-Remote

    func testForgeFromSshRemote() {
        XCTAssertEqual(ProjectSuggestion.forge(fromOriginURL: "git@github.com:krizzzly/kanban.git"),
                       ForgeRef(kind: .github, path: "krizzzly/kanban"))
        XCTAssertEqual(ProjectSuggestion.forge(fromOriginURL: "git@git.iwf.io:applications/even.git"),
                       ForgeRef(kind: .gitlab, path: "applications/even"))
    }

    func testForgeFromHttpsRemote() {
        XCTAssertEqual(ProjectSuggestion.forge(fromOriginURL: "https://github.com/krizzzly/kanban.git"),
                       ForgeRef(kind: .github, path: "krizzzly/kanban"))
        XCTAssertEqual(ProjectSuggestion.forge(fromOriginURL: "https://git.iwf.io/gruppe/unter/projekt"),
                       ForgeRef(kind: .gitlab, path: "gruppe/unter/projekt"))
        XCTAssertEqual(ProjectSuggestion.forge(fromOriginURL: "ssh://git@github.com/o/r.git"),
                       ForgeRef(kind: .github, path: "o/r"))
    }

    func testUnusableRemotesYieldNothing() {
        XCTAssertNil(ProjectSuggestion.forge(fromOriginURL: ""))
        XCTAssertNil(ProjectSuggestion.forge(fromOriginURL: "/lokaler/pfad"))
        XCTAssertNil(ProjectSuggestion.forge(fromOriginURL: "git@github.com:"))
    }

    /// Der Remote schlägt das Muster: die Nachbarprojekte liegen auf GitLab, dieses Repo nicht.
    func testTheRemoteWinsOverTheNeighboursPattern() throws {
        let config = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"modules": {"gitlab": {"projects": {"even": {"path": "applications/even"},
                                             "zba": {"path": "applications/zba"}}}}}
        """.utf8))

        let geraten = ProjectSuggestion.record(for: "neu", from: config)
        XCTAssertEqual(geraten.gitlab?.path, "applications/neu")
        XCTAssertNil(geraten.github)

        let gewusst = ProjectSuggestion.record(for: "neu", from: config,
                                               originURL: "git@github.com:krizzzly/neu.git")
        XCTAssertEqual(gewusst.github?.path, "krizzzly/neu")
        XCTAssertNil(gewusst.gitlab, "genau eine Forge, sonst wäre der Vorschlag nicht ladbar")
    }

    /// Ein leerer GitHub-Block fliegt beim Anlegen raus, genau wie ein leerer GitLab-Block.
    func testEmptyGithubBlockIsStripped() {
        var record = ProjectRecord(prefix: "K")
        record.github = .init(path: "   ")
        XCTAssertNil(record.strippingEmptyModules().github)

        record.github = .init(path: "krizzzly/kanban")
        XCTAssertEqual(record.strippingEmptyModules().github?.path, "krizzzly/kanban")
    }

    /// Die Projektion kennt den Abschnitt in beide Richtungen — sonst verschwände er beim nächsten
    /// Speichern wieder.
    func testProjectionRoundTripsTheGithubSection() throws {
        var config = JSONValue.object([:])
        config = ProjectProjection.apply(
            ProjectRecord(prefix: "KANBAN", tasksPath: "kanban/t",
                          github: .init(path: "krizzzly/kanban")),
            key: "kanban", to: config)

        XCTAssertEqual(config.value(at: ["modules", "github", "projects", "kanban", "path"]),
                       .string("krizzzly/kanban"))
        XCTAssertEqual(ProjectProjection.importing(from: config)["kanban"]?.github?.path,
                       "krizzzly/kanban")
        // Und ein entfernter Block räumt den Eintrag mit weg.
        let ohne = ProjectProjection.remove("kanban", from: config)
        XCTAssertNil(ohne.value(at: ["modules", "github", "projects", "kanban"]))
    }

    /// Ein Key, den es nur unter GitHub gibt, ist trotzdem vergeben.
    func testGithubOnlyKeyCountsAsTaken() throws {
        let config = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"modules": {"github": {"projects": {"kanban": {"path": "krizzzly/kanban"}}}}}"#.utf8))
        XCTAssertTrue(ProjectSuggestion.isTaken("kanban", in: config))
        XCTAssertFalse(ProjectSuggestion.isTaken("anderes", in: config))
    }
}
