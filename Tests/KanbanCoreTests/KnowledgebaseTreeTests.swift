import XCTest
@testable import KanbanCore

final class KnowledgebaseTreeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kb-tree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relativePath: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func mkdir(_ relativePath: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(relativePath),
                                                withIntermediateDirectories: true)
    }

    // MARK: - Aufbau

    func testFoldersComeBeforeFilesAndBothSortNaturally() throws {
        try write("README.md")
        try write("_konventionen.md")
        try write("ueberblick/architektur.md")
        try write("artefacts/index.html")

        let tree = KnowledgebaseTree.build(root: root.path)

        XCTAssertEqual(tree.map(\.name), ["artefacts", "ueberblick", "_konventionen.md", "README.md"])
        XCTAssertEqual(tree.filter(\.isDirectory).count, 2)
    }

    func testToolingFoldersAndHiddenFilesAreLeftOut() throws {
        try write("README.md")
        try write(".git/config")
        try write(".DS_Store")
        try write("_build/__pycache__/md2html.pyc")
        try write("_build/md2html.py")

        let tree = KnowledgebaseTree.build(root: root.path)

        XCTAssertEqual(tree.map(\.name), ["_build", "README.md"])
        // `_build` bleibt — es ist Inhalt der KB; nur `__pycache__` darin fällt weg.
        XCTAssertEqual(tree.first?.children.map(\.name), ["md2html.py"])
    }

    func testEmptyFoldersDisappear() throws {
        try write("ueberblick/architektur.md")
        try mkdir("leer")
        try mkdir("nur-hidden")
        try write("nur-hidden/.DS_Store")

        XCTAssertEqual(KnowledgebaseTree.build(root: root.path).map(\.name), ["ueberblick"])
    }

    func testSymlinksAreNotFollowed() throws {
        try write("ueberblick/architektur.md")
        // Ein Link zurück auf die Wurzel wäre eine Endlosschleife.
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("selbst"),
                                                  withDestinationURL: root)

        let tree = KnowledgebaseTree.build(root: root.path)
        XCTAssertEqual(tree.map(\.name), ["ueberblick"])
    }

    func testMissingRootIsAnEmptyTreeNotACrash() {
        XCTAssertTrue(KnowledgebaseTree.build(root: root.path + "/gibt-es-nicht").isEmpty)
    }

    func testFileCountCountsTheWholeSubtree() throws {
        try write("a/b/eins.md")
        try write("a/b/zwei.md")
        try write("a/drei.md")

        let a = KnowledgebaseTree.build(root: root.path)[0]
        XCTAssertEqual(a.fileCount, 3)
    }

    // MARK: - Dateiart

    func testKindIsDerivedFromTheExtension() {
        XCTAssertEqual(KBFileKind(path: "/kb/ueberblick/architektur.md"), .markdown)
        XCTAssertEqual(KBFileKind(path: "/kb/artefacts/index.html"), .html)
        XCTAssertEqual(KBFileKind(path: "/kb/_build/md2html.py"), .text)
        XCTAssertEqual(KBFileKind(path: "/kb/assets/logo.png"), .binary)
        XCTAssertEqual(KBFileKind(path: "/kb/README.MD"), .markdown)
    }

    func testUnknownExtensionsCountAsText() {
        // Über einen Link landet man in Repo-Dateien; deren Endungen sind nicht aufzählbar.
        for path in ["/repo/src/Entity/Dossier.php", "/repo/templates/mail.html.twig",
                     "/repo/scripts/rules.lua", "/repo/composer.lock", "/repo/Makefile",
                     "/repo/.env.dist"] {
            XCTAssertEqual(KBFileKind(path: path), .text, path)
        }
    }

    func testKnownBinaryExtensionsStayBinary() {
        for path in ["/repo/a.pdf", "/repo/b.zip", "/repo/c.woff2", "/repo/d.sqlite", "/repo/e.mp4"] {
            XCTAssertEqual(KBFileKind(path: path), .binary, path)
        }
    }

    // MARK: - Einstieg und Auswahl

    func testLandingFilePrefersReadmeAtTheTop() throws {
        try write("aaa.md")
        try write("README.md")

        XCTAssertEqual(KnowledgebaseTree.landingFile(KnowledgebaseTree.build(root: root.path))?.name,
                       "README.md")
    }

    /// Die Ansicht geht auf der gebauten Artefakt-Übersicht auf — sie ist der Einstieg, den man
    /// ohne den (jetzt zugeklappten) Baum braucht. Sie sticht auch ein README auf oberster Ebene.
    func testEntryFilePrefersTheArtefactsIndex() throws {
        try write("README.md")
        try write("artefacts/index.html")
        try write("artefacts/Geschäftsfall-Vorlage 75.html")

        let nodes = KnowledgebaseTree.build(root: root.path)
        XCTAssertEqual(KnowledgebaseTree.entryFile(nodes)?.path,
                       root.appendingPathComponent("artefacts/index.html").path)
    }

    /// Amerikanische Schreibweise ebenso — der Ordnername gehört der Knowledgebase.
    func testEntryFileAcceptsTheOtherSpelling() throws {
        try write("artifacts/index.html")
        XCTAssertEqual(KnowledgebaseTree.entryFile(KnowledgebaseTree.build(root: root.path))?.name,
                       "index.html")
    }

    /// Ohne Artefakt-Ordner (oder ohne Index darin) gilt weiter der bisherige Einstieg.
    func testEntryFileFallsBackToTheLandingFile() throws {
        try write("README.md")
        try write("artefacts/Geschäftsfall-Vorlage 75.html")

        XCTAssertEqual(KnowledgebaseTree.entryFile(KnowledgebaseTree.build(root: root.path))?.name,
                       "README.md")
    }

    /// Ein Link auf einen **Ordner** fragt etwas anderes: dort ist der Einstieg der des Ordners,
    /// nicht die Artefakt-Übersicht des ganzen Baums.
    func testLandingFileIsUnaffectedByTheArtefactsRule() throws {
        try write("artefacts/index.html")
        try write("ueberblick/README.md")
        try write("ueberblick/architektur.md")

        let nodes = KnowledgebaseTree.build(root: root.path)
        let folder = try XCTUnwrap(nodes.first { $0.name == "ueberblick" })
        XCTAssertEqual(KnowledgebaseTree.landingFile(folder.children)?.name, "README.md")
    }

    func testLandingFileFallsBackToTheFirstShowableFile() throws {
        try write("ueberblick/architektur.md")
        try write("assets/logo.png")

        // Kein README: die erste anzeigbare Datei in Baum-Reihenfolge, kein Binärkram.
        XCTAssertEqual(KnowledgebaseTree.landingFile(KnowledgebaseTree.build(root: root.path))?.name,
                       "architektur.md")
    }

    func testLandingFileIsNilWhenThereIsNothingToShow() throws {
        try write("assets/logo.png")
        XCTAssertNil(KnowledgebaseTree.landingFile(KnowledgebaseTree.build(root: root.path)))
    }

    func testAncestorFoldersOfTheSelectionAreListed() throws {
        try write("a/b/c/tief.md")
        try write("anderswo/flach.md")

        let tree = KnowledgebaseTree.build(root: root.path)
        let ids = KnowledgebaseTree.ancestorFolderIDs(
            of: root.appendingPathComponent("a/b/c/tief.md").path, in: tree)

        // Nur der Weg dorthin — nicht jeder Ordner der Knowledgebase.
        XCTAssertEqual(ids, Set(["a", "a/b", "a/b/c"].map { root.appendingPathComponent($0).path }))
    }

    func testAncestorFoldersAreEmptyForATopLevelFileOrAnUnknownPath() throws {
        try write("README.md")
        try write("a/b/tief.md")
        let tree = KnowledgebaseTree.build(root: root.path)

        XCTAssertTrue(KnowledgebaseTree.ancestorFolderIDs(
            of: root.appendingPathComponent("README.md").path, in: tree).isEmpty)
        XCTAssertTrue(KnowledgebaseTree.ancestorFolderIDs(of: "/gibt/es/nicht.md", in: tree).isEmpty)
    }

    func testNodeLookupFindsADeepFile() throws {
        try write("a/b/tief.md")
        let tree = KnowledgebaseTree.build(root: root.path)
        let path = root.appendingPathComponent("a/b/tief.md").path

        XCTAssertEqual(KnowledgebaseTree.node(at: path, in: tree)?.name, "tief.md")
        XCTAssertNil(KnowledgebaseTree.node(at: "/gibt/es/nicht.md", in: tree))
    }
}
