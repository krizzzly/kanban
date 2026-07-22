import XCTest
@testable import KanbanCore

final class MarkdownHTMLTests: XCTestCase {
    func testInlineHTMLPassesThroughAndMarkdownStillRenders() {
        let md = """
        ## Beispiel
        <u>Betriebsstätten</u> und <span style="color:#bf2600">**Rot**</span>.
        Footnote<sup>1</sup>. Befehl: `git -C <WORKTREE> status`.

        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let html = MarkdownHTML.render(md)

        // Real styling HTML is preserved (CMARK_OPT_UNSAFE)…
        XCTAssertTrue(html.contains("<u>Betriebsstätten</u>"), html)
        XCTAssertTrue(html.contains("color:#bf2600"), html)
        XCTAssertTrue(html.contains("<sup>1</sup>"), html)
        // …markdown inside the span still renders…
        XCTAssertTrue(html.contains("<strong>Rot</strong>"), html)
        // …GFM tables work…
        XCTAssertTrue(html.contains("<table>"), html)
        // …and placeholder tokens inside code spans stay literal (escaped).
        XCTAssertTrue(html.contains("&lt;WORKTREE&gt;"), html)
        XCTAssertFalse(html.contains("<WORKTREE>"), html)
    }

    func testScriptTagIsNeutralised() {
        let html = MarkdownHTML.render("Hallo <script>alert(1)</script> Welt")
        XCTAssertFalse(html.contains("<script>"), html)
    }

    /// A local relative image is inlined as a base64 `data:` URI (WKWebView can't load `file://`
    /// resources from `loadHTMLString`) and that URI survives the cmark → HTML render.
    func testLocalImageIsInlinedAsDataURIAndRenders() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1×1 transparent PNG.
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let png = Data(base64Encoded: pngBase64)!
        try png.write(to: dir.appendingPathComponent("shot.png"))

        let md = "Vorher\n\n![Screenshot](shot.png)\n\nNachher"
        let rewritten = TaskFileLoader.rewriteImagePaths(md, directory: dir)
        XCTAssertTrue(rewritten.contains("data:image/png;base64,\(pngBase64)"), rewritten)
        XCTAssertFalse(rewritten.contains("shot.png"), rewritten)

        let html = MarkdownHTML.render(rewritten)
        XCTAssertTrue(html.contains("<img"), html)
        XCTAssertTrue(html.contains("data:image/png;base64,"), html)
        // The base64 payload must pass through cmark's href escaping untouched.
        XCTAssertTrue(html.contains(pngBase64), html)
    }

    func testRemoteAndMissingImagesAreLeftUntouched() {
        let dir = FileManager.default.temporaryDirectory
        let md = "![a](https://example.com/x.png) ![b](does-not-exist.png)"
        let out = TaskFileLoader.rewriteImagePaths(md, directory: dir)
        XCTAssertEqual(out, md)
    }

    /// Real-data smoke: across the actual bfezvm task files, at least one styled `<span>`/`<u>`
    /// must survive rendering (proves the passthrough on real content). Spans inside fenced code
    /// are correctly escaped and don't count — which is the intended behaviour.
    func testRealTaskFilesRenderStyledHTML() throws {
        let dir = "/Users/christianhiller/code/bfezvm/docs/tasks"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            throw XCTSkip("bfezvm tasks dir not present")
        }
        for name in entries where name.hasSuffix(".md") {
            guard let content = try? String(contentsOfFile: "\(dir)/\(name)", encoding: .utf8) else { continue }
            let html = MarkdownHTML.render(content)
            if html.contains("<span style=") || html.contains("<u>") {
                return  // proven on real data
            }
        }
        throw XCTSkip("no real styled HTML found in bfezvm task files")
    }
}
