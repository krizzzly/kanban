import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Converts Markdown to HTML via cmark-gfm, with **raw inline HTML passed through**
/// (`CMARK_OPT_UNSAFE`) so task-file styling like `<span style="color:…">`, `<u>`, `<sup>`,
/// `<b>`, `<br>` and `<div>` survives. GFM extensions (tables, strikethrough, autolink,
/// task lists) are enabled; `tagfilter` still neutralises dangerous tags (`<script>`, `<style>`…).
/// Placeholder tokens like `<WORKTREE>` / `<NNN>` live inside code spans in the task files and
/// are therefore escaped to literal text by cmark, exactly as desired.
public enum MarkdownHTML {
    public static func render(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        // Der YAML-Kopf wird zum Codeblock, **bevor** cmark ihn sieht — sonst macht es daraus eine
        // Trennlinie plus Setext-Überschrift (siehe `Frontmatter`). Hier und nicht bei den
        // Aufrufern, damit jede gerenderte Ansicht dasselbe zeigt und `TaskSearch.visibleText`
        // (das durch denselben Renderer geht) mit dem DOM gleich zählt.
        let markdown = Frontmatter.alsCodeblock(markdown)

        // CMARK_OPT_UNSAFE (1<<17) | CMARK_OPT_VALIDATE_UTF8 (1<<9)
        let options: Int32 = (1 << 17) | (1 << 9)

        guard let parser = cmark_parser_new(options) else { return fallback(markdown) }
        defer { cmark_parser_free(parser) }

        for name in ["table", "strikethrough", "autolink", "tagfilter", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        // Die **Byte-Länge** füttern, nicht `strlen`: ein eingebettetes NUL beendet sonst das
        // Dokument mitten im Text, und der Rest fehlt lautlos. Aufgefallen an einer Outlook-`.msg`,
        // deren Empfänger-Property ihre Null mitbringt (siehe `OutlookMessageReader.utf16String`);
        // ohne NUL ist `strlen` genau diese Länge, das Verhalten ändert sich also sonst nicht.
        let utf8 = Array(markdown.utf8)
        utf8.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { ptr in
                cmark_parser_feed(parser, ptr, buffer.count)
            }
        }

        guard let doc = cmark_parser_finish(parser) else { return fallback(markdown) }
        defer { cmark_node_free(doc) }

        let extensions = cmark_parser_get_syntax_extensions(parser)
        guard let cHTML = cmark_render_html(doc, options, extensions) else { return fallback(markdown) }
        defer { free(cHTML) }

        return String(cString: cHTML)
    }

    /// On any failure, fall back to the escaped source wrapped in a <pre> so nothing is lost.
    private static func fallback(_ markdown: String) -> String {
        let escaped = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<pre>\(escaped)</pre>"
    }
}
