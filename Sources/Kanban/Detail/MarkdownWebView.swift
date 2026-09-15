import AppKit
import SwiftUI
import WebKit
import KanbanCore

/// Renders a task-file section as Markdown **including raw HTML** (colored spans, `<u>`, `<sup>`,
/// tables, footnote `<div>`s) via cmark-gfm → HTML → WKWebView. Replaces MarkdownUI, which could
/// not render inline HTML. Local images are inlined as base64 `data:` URIs upstream (see
/// `TaskFileLoader.rewriteImagePaths`) because `loadHTMLString` grants no filesystem read access;
/// `baseURL` is still passed so any remaining relative links resolve.
/// Ein Suchauftrag an die gerenderte Ansicht: was markiert wird und welcher Treffer angesprungen
/// werden soll.
///
/// `token` steigt bei **jedem** Sprung. Ohne ihn bliebe ein erneutes „weiter" auf demselben Treffer
/// (gleiche Suche, gleiche Nummer) wirkungslos, weil sich der Wert nicht geändert hätte — und der
/// Ansicht fehlte der Anlass, wieder dorthin zu scrollen, nachdem der Mensch weggescrollt ist.
struct MarkdownSearch: Equatable {
    let query: String
    /// Der wievielte Treffer **in dieser Sektion** (0-basiert) — dieselbe Zählung wie
    /// `TaskSearchHit.indexInSection`.
    let occurrence: Int
    let token: Int
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?
    /// Klick auf einen Link, bevor er nach draussen geht — `true` heisst „übernommen". So bleibt die
    /// Knowledgebase beim Klick auf `../Common/HistoryEntry.md` in der Ansicht, statt den Finder zu
    /// rufen. Ohne Handler (Task-Files) gilt das bisherige Verhalten.
    var onLinkClick: ((URL) -> Bool)?
    /// Sprungmarke, zu der nach dem Laden gescrollt wird (`architektur.md#zwei-cqrs-generationen`).
    /// Innerhalb desselben Dokuments erledigt das WebKit selbst; über Dateigrenzen hinweg muss die
    /// Marke den Ladevorgang überleben, deshalb hier.
    var scrollToFragment: String?
    /// Was die Suche im Task-File gerade sucht und anspringt — nil heisst „keine Suche",
    /// leerer Text räumt die Markierungen wieder weg.
    var search: MarkdownSearch?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if onLinkClick != nil {
            configuration.userContentController.add(context.coordinator, name: Coordinator.linkHandlerName)
            configuration.userContentController.addUserScript(
                WKUserScript(source: HTMLTemplate.linkInterceptScript,
                             injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Transparent background so the SwiftUI pane shows through.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Der Handler muss **vor** dem Neuladen aktuell sein: er hängt an der gerade angezeigten
        // Datei, und die wechselt zusammen mit dem Inhalt.
        context.coordinator.onLinkClick = onLinkClick
        context.coordinator.pendingFragment = scrollToFragment
        context.coordinator.pendingSearch = search

        // Only reload when the content actually changed (avoids flicker on unrelated re-renders).
        guard context.coordinator.lastMarkdown != markdown else {
            // Gleicher Inhalt, neue Sprungmarke (zweiter Klick auf denselben Abschnitt) — dann
            // scrollen, statt gar nichts zu tun.
            context.coordinator.scrollToPendingFragment(in: webView)
            // Derselbe Tab, nächster Treffer: das Dokument steht schon, nur die Markierung wandert.
            context.coordinator.applyPendingSearch(in: webView)
            return
        }
        context.coordinator.lastMarkdown = markdown
        // Sprungmarken an den Überschriften: cmark vergibt keine, die Knowledgebase verlinkt sie
        // aber (`#zwei-cqrs-generationen`). Ohne IDs zeigt so ein Link ins Leere.
        let html = HTMLTemplate.wrap(HeadingAnchors.inject(into: MarkdownHTML.render(markdown)))
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let linkHandlerName = "kanbanLink"

        var lastMarkdown: String?
        var onLinkClick: ((URL) -> Bool)?
        var pendingFragment: String?
        var pendingSearch: MarkdownSearch?
        /// Zuletzt ausgeführte Suche — ohne die liefe das Skript bei jedem Rerender erneut über den
        /// ganzen DOM, obwohl sich nichts geändert hat.
        private var appliedSearch: MarkdownSearch?

        /// Der in JavaScript abgefangene Klick.
        ///
        /// Über die Navigation ginge es **nicht**: ein Dokument aus `loadHTMLString` darf nicht nach
        /// `file://` navigieren, WebKit bricht das ohne Rückfrage ab — der Delegate wird gar nicht
        /// erst gefragt (headless nachgemessen). Deshalb sind genau die Links tot, aus denen die
        /// Knowledgebase besteht, während `#anker` und `https://…` funktionieren; das ist das
        /// „mal geht's, mal nicht".
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let href = message.body as? String, let url = URL(string: href) else { return }
            if onLinkClick?(url) == true { return }
            StatusLinkOpener.open(url)
        }

        /// Erst den Aufrufer fragen (die Knowledgebase übernimmt Links auf ihre eigenen Dateien),
        /// sonst wie bisher: echte Klicks nach draussen, alles andere (initiales
        /// `loadHTMLString`, Sprung im selben Dokument) läuft in der Ansicht weiter.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if let onLinkClick, onLinkClick(url) {
                decisionHandler(.cancel)
                return
            }
            // Ein Sprung im selben Dokument ist kein „nach draussen": WebKit scrollt selbst,
            // sobald die Ziel-ID existiert.
            if url.fragment != nil, sameDocument(url, as: webView.url) {
                decisionHandler(.allow)
                return
            }
            StatusLinkOpener.open(url)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            scrollToPendingFragment(in: webView)
            // Frisch geladenes Dokument: die Markierungen des vorigen sind mit ihm weg, also neu
            // setzen. Genau das passiert beim Tabwechsel, den ein Sprung in eine andere Sektion
            // auslöst — die Suche muss den Ladevorgang überleben.
            appliedSearch = nil
            applyPendingSearch(in: webView)
        }

        /// Markiert alle Fundstellen im Dokument und scrollt die gemeinte in die Mitte.
        func applyPendingSearch(in webView: WKWebView) {
            guard pendingSearch != appliedSearch else { return }
            appliedSearch = pendingSearch
            let suche = pendingSearch ?? MarkdownSearch(query: "", occurrence: 0, token: 0)
            webView.evaluateJavaScript(
                HTMLTemplate.findScript(query: suche.query, occurrence: suche.occurrence),
                completionHandler: nil)
        }

        /// Nach dem Laden zur gemerkten Marke springen. Über `scrollIntoView` statt
        /// `location.hash`: der Hash liesse WKWebView die Datei-URL neu auflösen, und das Dokument
        /// stammt aus `loadHTMLString` — es gibt dort keine, zu der zurückgesprungen werden könnte.
        func scrollToPendingFragment(in webView: WKWebView) {
            guard let fragment = pendingFragment, !fragment.isEmpty else { return }
            pendingFragment = nil
            let escaped = fragment
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript(
                "document.getElementById('\(escaped)')?.scrollIntoView({block:'start'});",
                completionHandler: nil)
        }

        private func sameDocument(_ url: URL, as documentURL: URL?) -> Bool {
            guard let documentURL else { return false }
            var stripped = URLComponents(url: url, resolvingAgainstBaseURL: false)
            stripped?.fragment = nil
            var base = URLComponents(url: documentURL, resolvingAgainstBaseURL: false)
            base?.fragment = nil
            return stripped?.url == base?.url
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
        document(body: body, extraCSS: "", script: "")
    }

    /// Dasselbe Dokument, aber **beschreibbar**: derselbe Stylesheet (der Editor soll aussehen wie
    /// die gerenderte Ansicht daneben), dazu Editor-Zutaten — Mindesthöhe, Platzhalter, und das
    /// Skript, das Tastatur und Toolbar bedient.
    static func wrapEditable(_ body: String, placeholder: String) -> String {
        document(body: body, extraCSS: editorCSS(placeholder: placeholder), script: "")
    }

    private static func document(body: String, extraCSS: String, script: String) -> String {
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
        /* Fundstellen der Task-File-Suche: alle gelb, die gemeinte orange und umrandet, damit man
           beim Springen sieht, welche von mehreren gleichen gerade dran ist. */
        mark[data-kanban-find] {
          background: #fff3a3; color: inherit; border-radius: 3px; padding: 0 1px;
        }
        mark[data-kanban-current] {
          background: #ffb340; box-shadow: 0 0 0 2px rgba(255, 149, 0, 0.55);
        }
        @media (prefers-color-scheme: dark) {
          mark[data-kanban-find] { background: #6b5d16; color: inherit; }
          mark[data-kanban-current] { background: #b4740a; box-shadow: 0 0 0 2px rgba(255, 179, 64, 0.5); }
        }
        .footnote, .page-footnotes { font-size: 13px; color: var(--secondary-text); }
        /* Kommentar-Diskussion (comments.json): eine Karte je Beitrag, chronologisch. Bewusst ohne
           Einrückung — Jira kennt keine Antwort-Bäume, jede „Antwort" ist der nächste Kommentar. */
        .comment {
          border: 1px solid var(--border); border-radius: 8px;
          padding: 8px 12px; margin: 8px 0; background: var(--bg2);
        }
        /* Antworten stehen eingerückt unter ihrem Bezug — wie in Jira. */
        .comment.reply { margin-left: 28px; }
        .comment.depth-2 { margin-left: 56px; }
        .comment.depth-3 { margin-left: 84px; }
        .comment-head {
          display: flex; align-items: center; gap: 8px; margin-bottom: 6px;
        }
        /* Kürzel statt Bild: ein Profilfoto führt die Datei nicht mit. */
        /* Gilt für beides: das geladene Profilbild (img) und die Initialen (span). */
        .comment-avatar {
          flex: none; width: 22px; height: 22px; border-radius: 50%; object-fit: cover;
          background: var(--divider); color: var(--text);
          font-size: 10px; font-weight: 700; letter-spacing: 0.02em;
          display: inline-flex; align-items: center; justify-content: center;
        }
        .comment-author { font-weight: 600; }
        .comment-date { font-size: 12px; color: var(--secondary-text); white-space: nowrap;
                        margin-left: auto; }
        .comment > :last-child { margin-bottom: 0; }
        .comment p:first-of-type { margin-top: 0; }
        /* Erwähnung: nur für Namen, die in dieser Diskussion als Autor vorkommen. */
        .mention {
          background: var(--border); border-radius: 4px; padding: 0 4px;
          font-weight: 500; white-space: nowrap;
        }
        \(extraCSS)
        </style>
        </head>
        <body>
        \(body)
        \(script)
        </body>
        </html>
        """
    }

    /// Editor-Zusätze: die Fläche muss die ganze Höhe klickbar machen (sonst trifft ein Klick unter
    /// dem letzten Absatz nichts und der Cursor springt nach oben), und ein leeres Dokument braucht
    /// einen Platzhalter, weil ein leerer `contenteditable`-Body sonst wie ein Fehler aussieht.
    private static func editorCSS(placeholder: String) -> String {
        """
        html, body { height: 100%; }
        body { padding: 12px 16px; outline: none; }
        body:empty::before, body > p:only-child:empty::before {
          content: "\(placeholder)"; color: var(--secondary-text); pointer-events: none;
        }
        /* Auswahl auch in Codeblöcken sichtbar halten. */
        ::selection { background: rgba(76, 142, 248, 0.35); }
        """
    }

    /// Markiert jede Fundstelle von `query` im Dokument und scrollt die `occurrence`-te in die Mitte.
    ///
    /// Gezählt wird über die **Textknoten in Dokumentreihenfolge**, hinter jedem Treffer neu
    /// ansetzend — dieselbe Zählung wie `TaskSearch.bereiche`, damit „der dritte Treffer" auf beiden
    /// Seiten dieselbe Stelle meint. Verglichen wird in Kleinschreibung, sonst nichts: jede weitere
    /// Normalisierung müsste Swift genauso machen.
    ///
    /// Die Knoten werden **erst gesammelt, dann ersetzt** — ein TreeWalker, dem man unter den Füssen
    /// den Baum umbaut, überspringt Knoten.
    ///
    /// `script`/`style` bleiben aussen vor: deren Inhalt ist kein sichtbarer Text (und `TaskSearch`
    /// wirft ihn ebenfalls weg).
    static func findScript(query: String, occurrence: Int) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return """
        (function(needleRaw, wanted) {
          document.querySelectorAll('mark[data-kanban-find]').forEach(function (m) {
            m.replaceWith(document.createTextNode(m.textContent));
          });
          if (document.body) { document.body.normalize(); }
          if (!needleRaw) { return 0; }
          var needle = needleRaw.toLowerCase();
          var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
              var parent = node.parentElement;
              if (!parent) { return NodeFilter.FILTER_REJECT; }
              var tag = parent.tagName;
              if (tag === 'SCRIPT' || tag === 'STYLE') { return NodeFilter.FILTER_REJECT; }
              return NodeFilter.FILTER_ACCEPT;
            }
          });
          var nodes = [], node;
          while ((node = walker.nextNode())) { nodes.push(node); }

          var count = 0, target = null;
          nodes.forEach(function (textNode) {
            var text = textNode.nodeValue, lower = text.toLowerCase();
            var at = lower.indexOf(needle);
            if (at < 0) { return; }
            var fragment = document.createDocumentFragment(), from = 0;
            while (at >= 0) {
              if (at > from) {
                fragment.appendChild(document.createTextNode(text.slice(from, at)));
              }
              var mark = document.createElement('mark');
              mark.setAttribute('data-kanban-find', String(count));
              mark.textContent = text.substr(at, needleRaw.length);
              if (count === wanted) {
                mark.setAttribute('data-kanban-current', '1');
                target = mark;
              }
              fragment.appendChild(mark);
              from = at + needleRaw.length;
              count += 1;
              at = lower.indexOf(needle, from);
            }
            if (from < text.length) {
              fragment.appendChild(document.createTextNode(text.slice(from)));
            }
            textNode.parentNode.replaceChild(fragment, textNode);
          });
          if (target) { target.scrollIntoView({ block: 'center', inline: 'nearest' }); }
          return count;
        })("\(escaped)", \(occurrence));
        """
    }

    /// Fängt Link-Klicks ab, bevor WebKit sie zu einer Navigation macht.
    ///
    /// Nötig, weil ein Dokument aus `loadHTMLString` nicht nach `file://` navigieren darf: der
    /// Klick auf `../Common/HistoryEntry.md` wird verworfen, **ohne** dass der Navigation-Delegate
    /// gefragt wird. `anchor.href` liefert die gegen die Basis-URL aufgelöste absolute Adresse —
    /// das ist reine DOM-Auflösung und von der Sperre nicht betroffen.
    ///
    /// Reine `#anker` bleiben unangetastet: die sind eine Navigation im selben Dokument, die
    /// WebKit selbst erledigt (und besser, als ein nachgebautes Scrollen es könnte).
    static var linkInterceptScript: String {
        """
        (function () {
          document.addEventListener('click', function (event) {
            const anchor = event.target.closest ? event.target.closest('a[href]') : null;
            if (!anchor) return;
            const raw = anchor.getAttribute('href') || '';
            if (raw.startsWith('#')) return;
            if (!window.webkit || !window.webkit.messageHandlers.\(MarkdownWebView.Coordinator.linkHandlerName)) return;
            event.preventDefault();
            window.webkit.messageHandlers.\(MarkdownWebView.Coordinator.linkHandlerName).postMessage(anchor.href);
          }, true);
        })();
        """
    }

    /// Die Editor-Logik — als **`WKUserScript`**, nicht als `<script>` im Dokument.
    ///
    /// Der Unterschied ist kein Stil: ein eingebettetes `<script>` steht in
    /// `document.body.innerHTML`, und genau das liest der Editor beim Speichern aus. Gemessen im
    /// kopflosen Probelauf — der ganze JavaScript-Quelltext wäre als Text im Jira-Feld gelandet.
    ///
    /// `document.execCommand` ist formal veraltet, in WebKit aber vollständig da und der einzige Weg,
    /// der Auswahl, Undo-Stapel und Listen-Verschachtelung ohne eigene Editor-Engine richtig
    /// behandelt — ein selbstgebauter DOM-Umbau bricht genau daran.
    static var editorScript: String {
        """
        (function () {
          document.body.contentEditable = 'true';
          document.execCommand('defaultParagraphSeparator', false, 'p');

          function post() {
            // Ohne den Wächter reisst eine fehlende Brücke (kopfloser Probelauf, künftige
            // Einbettung) den ganzen Befehl mit — getippt wäre dann schon geändert, gemeldet nicht.
            if (!window.webkit || !window.webkit.messageHandlers.editor) return;
            window.webkit.messageHandlers.editor.postMessage(document.body.innerHTML);
          }
          let timer = null;
          function postSoon() {
            clearTimeout(timer);
            // Getippt wird schneller als konvertiert — erst nach einer Pause zurückmelden.
            timer = setTimeout(post, 400);
          }
          document.addEventListener('input', postSoon);

          function closestTag(node, tag) {
            while (node && node !== document.body) {
              if (node.nodeType === 1 && node.tagName.toLowerCase() === tag) return node;
              node = node.parentNode;
            }
            return null;
          }

          function inListItem() {
            const selection = window.getSelection();
            if (!selection.rangeCount) return false;
            return closestTag(selection.getRangeAt(0).commonAncestorContainer, 'li') !== null;
          }

          window.kanbanEditor = {
            html: function () { return document.body.innerHTML; },
            cmd: function (name, arg) {
              // `indent`/`outdent` verschachteln **nur in einer Liste**. Auf einem normalen Absatz
              // baut WebKit daraus ein `<blockquote style="…border: none">` — aus „einrücken" würde
              // in Jira ein Zitat. Im Probelauf genau so passiert.
              if ((name === 'indent' || name === 'outdent') && !inListItem()) return;
              document.execCommand(name, false, arg === undefined ? null : arg);
              post();
            },
            // Inline-Code hat kein execCommand — Auswahl in <code> packen, oder auspacken, wenn sie
            // schon drin liegt (derselbe Knopf schaltet beides).
            code: function () {
              const selection = window.getSelection();
              if (!selection.rangeCount) return;
              const range = selection.getRangeAt(0);
              const existing = closestTag(range.commonAncestorContainer, 'code');
              if (existing) {
                const parent = existing.parentNode;
                while (existing.firstChild) parent.insertBefore(existing.firstChild, existing);
                parent.removeChild(existing);
                post();
                return;
              }
              if (selection.isCollapsed) return;
              const element = document.createElement('code');
              element.appendChild(range.extractContents());
              range.insertNode(element);
              selection.removeAllRanges();
              const after = document.createRange();
              after.selectNodeContents(element);
              selection.addRange(after);
              post();
            },
            focusEnd: function () {
              document.body.focus();
              const range = document.createRange();
              range.selectNodeContents(document.body);
              range.collapse(false);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
            }
          };

          // Tab rückt in Listen ein/aus — sonst verlässt Tab das Feld und die Verschachtelung wäre
          // nur über die Toolbar erreichbar.
          document.addEventListener('keydown', function (event) {
            if (event.key !== 'Tab' || !inListItem()) return;   // ausserhalb: Tab bleibt Tab
            event.preventDefault();
            document.execCommand(event.shiftKey ? 'outdent' : 'indent', false, null);
            post();
          });
        })();
        """
    }
}
