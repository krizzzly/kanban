import XCTest
@testable import KanbanCore

final class ConfigStoreTests: XCTestCase {
    private var dir: URL!
    private var configPath: String { dir.appendingPathComponent("config.json").path }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-configstore-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ json: String) throws {
        try json.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Round-trip

    func testRoundTripPreservesUnknownKeys() throws {
        try write("""
        {
          "basePath": "~/code",
          "exoticTopLevel": {"nested": [1, 2.5, true, null, "x"]},
          "modules": {
            "jira": {"baseUrl": "https://a.example", "customFlag": 42},
            "unknownModule": {"foo": "bar"}
          }
        }
        """)
        let store = ConfigStore(path: configPath)
        var doc = try store.load()
        doc.root.set(.string("neu@example.ch"), at: ["modules", "jira", "email"])
        try store.save(doc)

        let reloaded = try store.load()
        XCTAssertEqual(reloaded.root.value(at: ["modules", "jira", "email"])?.stringValue, "neu@example.ch")
        XCTAssertEqual(reloaded.root.value(at: ["modules", "jira", "customFlag"])?.intValue, 42)
        XCTAssertEqual(reloaded.root.value(at: ["modules", "unknownModule", "foo"])?.stringValue, "bar")
        let nested = reloaded.root.value(at: ["exoticTopLevel", "nested"])?.arrayValue
        XCTAssertEqual(nested, [.int(1), .double(2.5), .bool(true), .null, .string("x")])
    }

    func testNumbersKeepIntDoubleDistinction() throws {
        try write(#"{"i": 7, "d": 7.25}"#)
        let store = ConfigStore(path: configPath)
        try store.save(try store.load())
        let text = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertTrue(text.contains("\"i\" : 7") || text.contains("\"i\": 7"))
        XCTAssertFalse(text.contains("7.0"))
        XCTAssertTrue(text.contains("7.25"))
    }

    // MARK: - Key-path mutations

    func testSetCreatesIntermediateObjects() {
        var root = JSONValue.object([:])
        root.set(.bool(true), at: ["a", "b", "c"])
        XCTAssertEqual(root.value(at: ["a", "b", "c"])?.boolValue, true)
    }

    func testSetNilRemovesLeafOnly() {
        var root = JSONValue.object([:])
        root.set(.string("x"), at: ["m", "one"])
        root.set(.string("y"), at: ["m", "two"])
        root.set(nil, at: ["m", "one"])
        XCTAssertNil(root.value(at: ["m", "one"]))
        XCTAssertEqual(root.value(at: ["m", "two"])?.stringValue, "y")
    }

    /// The format the presence + people editors write: arrays of (nested) objects. Guards the
    /// on-disk shape survives a ConfigStore round-trip unchanged.
    func testArraysOfNestedObjectsRoundTrip() throws {
        try write("""
        {
          "modules": {
            "vertec": {"presence": [{"from": "09:00", "to": "12:00"}, {"from": "12:30", "to": "18:00", "text": "Nachmittag"}]},
            "whatsapp": {"people": [
              {"name": "Louis", "number": "+41790000000", "aliases": ["chef"],
               "autoReply": {"enabled": true, "prompt": "Sei knapp."}}
            ]}
          }
        }
        """)
        let store = ConfigStore(path: configPath)
        try store.save(try store.load())

        let root = try store.load().root
        let presence = root.value(at: ["modules", "vertec", "presence"])?.arrayValue
        XCTAssertEqual(presence?.count, 2)
        XCTAssertEqual(presence?[1].value(at: ["text"])?.stringValue, "Nachmittag")

        let people = root.value(at: ["modules", "whatsapp", "people"])?.arrayValue
        XCTAssertEqual(people?.first?.value(at: ["name"])?.stringValue, "Louis")
        XCTAssertEqual(people?.first?.value(at: ["aliases"])?.arrayValue, [.string("chef")])
        XCTAssertEqual(people?.first?.value(at: ["autoReply", "enabled"])?.boolValue, true)
    }

    // MARK: - Save behaviour

    func testSaveCreatesBackup() throws {
        try write(#"{"basePath": "~/code"}"#)
        let store = ConfigStore(path: configPath)
        var doc = try store.load()
        doc.root.set(.string("~/dev"), at: ["basePath"])
        try store.save(doc)

        let backup = try String(contentsOfFile: store.backupPath, encoding: .utf8)
        XCTAssertTrue(backup.contains("~/code"), "Backup muss den vorherigen Stand enthalten")
        let current = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertTrue(current.contains("~/dev"))
    }

    func testSaveDetectsExternalChange() throws {
        try write(#"{"basePath": "~/code"}"#)
        let store = ConfigStore(path: configPath)
        let doc = try store.load()

        // Simulate an external edit with a clearly different mtime.
        try write(#"{"basePath": "~/elsewhere"}"#)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: configPath)

        XCTAssertThrowsError(try store.save(doc)) { error in
            XCTAssertEqual(error as? ConfigStoreError, .conflict)
        }
        XCTAssertNoThrow(try store.save(doc, force: true))
    }

    func testMissingFileLoadsEmptyDocumentAndSaves() throws {
        let store = ConfigStore(path: configPath)
        var doc = try store.load()
        XCTAssertEqual(doc.root, .object([:]))
        doc.root.set(.string("~/code"), at: ["basePath"])
        try store.save(doc)
        XCTAssertEqual(try store.load().root.value(at: ["basePath"])?.stringValue, "~/code")
    }
}
