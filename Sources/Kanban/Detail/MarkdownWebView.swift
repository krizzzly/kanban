import AppKit
import SwiftUI
import WebKit
import KanbanCore

/// Renders a task-file section as Markdown **including raw HTML** (colored spans, `<u>`, `<sup>`,
/// tables, footnote `<div>`s) via cmark-gfm → HTML → WKWebView. Replaces MarkdownUI, which could
/// not render inline HTML. Local images are inlined as base64 `data:` URIs upstream (see
/// `TaskFileLoader.rewriteImagePaths`) because `loadHTMLString` grants no filesystem read access;
/// `baseURL` is still passed so any remaining relative links resolve.
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        // Transparent background so the SwiftUI pane shows through.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload when the content actually changed (avoids flicker on unrelated re-renders).
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.lastMarkdown = markdown
        let html = HTMLTemplate.wrap(MarkdownHTML.render(markdown))
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String?

        /// Open real link clicks externally; let the initial `loadHTMLString` (and other non-link
        /// navigation) proceed in the web view.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            StatusLinkOpener.open(url)
            decisionHandler(.cancel)
        }
    }
}

/// Routes link clicks from the rendered task markdown: the `kanban-ide://` scheme opens the worktree
/// directory in PhpStorm; everything else (http(s), mailto, …) opens in the default app / browser.
enum StatusLinkOpener {
    static func open(_ url: URL) {
        guard url.scheme == StatusLinks.ideScheme else {
            NSWorkspace.shared.open(url)
            return
        }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "path" }?.value
        if let path { openInPhpStorm(path) }
    }

    private static func openInPhpStorm(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "PhpStorm", path]
        try? process.run()
    }
}

/// Wraps cmark's HTML body in a full document with a compact, dark-mode-aware stylesheet that
/// mirrors the kanban-code font sizing.
enum HTMLTemplate {
    static func wrap(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        /* Palette ported 1:1 from MarkdownUI's `.gitHub` theme (kanban-code uses it). */
        :root {
          color-scheme: light dark;
          --text: #060606;
          --secondary-text: #6b6e7b;
          --bg2: #f7f7f9;        /* inline code, code blocks, table header/alt rows */
          --link: #2c65cf;
          --border: #e4e4e8;
          --divider: #d0d0d3;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --text: #fbfbfc;
            --secondary-text: #9294a0;
            --bg2: #25262a;
            --link: #4c8ef8;
            --border: #42444e;
            --divider: #333438;
          }
        }
        html, body { background: transparent; margin: 0; }
        body {
          font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif;
          font-size: 15px; line-height: 1.5; color: var(--text); padding: 16px;
          -webkit-text-size-adjust: 100%; word-wrap: break-word;
        }
        /* kanban-code keeps headings at body size, differentiated by weight only. */
        h1, h2, h3, h4, h5, h6 { font-size: 15px; line-height: 1.3; margin: 12px 0 6px; }
        h1 { font-weight: 700; }
        h2 { font-weight: 600; }
        h3 { font-weight: 500; }
        h4, h5, h6 { font-weight: 600; }
        p { margin: 6px 0; }
        ul, ol { margin: 6px 0; padding-left: 22px; }
        li { margin: 2px 0; }
        a { color: var(--link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        code {
          font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.85em;
          background: var(--bg2); padding: 0.2em 0.4em; border-radius: 6px;
        }
        pre {
          background: var(--bg2); padding: 12px; border-radius: 8px; overflow-x: auto;
        }
        pre code { background: none; padding: 0; }
        blockquote {
          margin: 6px 0; padding: 0 12px; border-left: 3px solid var(--divider);
          color: var(--secondary-text);
        }
        table { border-collapse: collapse; margin: 8px 0; }
        th, td { border: 1px solid var(--border); padding: 6px 13px; text-align: left; }
        th { background: var(--bg2); font-weight: 600; }
        tr:nth-child(2n) { background: var(--bg2); }
        img { max-width: 100%; height: auto; border-radius: 6px; }
        hr { border: none; border-top: 1px solid var(--divider); margin: 12px 0; }
        sup, sub { font-size: 0.75em; }
        .footnote, .page-footnotes { font-size: 13px; color: var(--secondary-text); }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
