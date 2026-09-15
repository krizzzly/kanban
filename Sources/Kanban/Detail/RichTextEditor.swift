import AppKit
import SwiftUI
import WebKit
import KanbanCore

/// Ein Befehl der Editor-Toolbar. Die JS-Zeile steht direkt am Fall, damit Knopf und Wirkung nicht
/// auseinanderlaufen können.
enum RichTextCommand: Equatable {
    case bold, italic, strike, inlineCode
    case heading2, heading3, paragraph, quote, codeBlock
    case bulletList, orderedList, indent, outdent
    case link(String)
    case undo, redo

    var javaScript: String {
        switch self {
        case .bold:         return "kanbanEditor.cmd('bold')"
        case .italic:       return "kanbanEditor.cmd('italic')"
        case .strike:       return "kanbanEditor.cmd('strikeThrough')"
        case .inlineCode:   return "kanbanEditor.code()"
        case .heading2:     return "kanbanEditor.cmd('formatBlock', 'h2')"
        case .heading3:     return "kanbanEditor.cmd('formatBlock', 'h3')"
        case .paragraph:    return "kanbanEditor.cmd('formatBlock', 'p')"
        case .quote:        return "kanbanEditor.cmd('formatBlock', 'blockquote')"
        case .codeBlock:    return "kanbanEditor.cmd('formatBlock', 'pre')"
        case .bulletList:   return "kanbanEditor.cmd('insertUnorderedList')"
        case .orderedList:  return "kanbanEditor.cmd('insertOrderedList')"
        case .indent:       return "kanbanEditor.cmd('indent')"
        case .outdent:      return "kanbanEditor.cmd('outdent')"
        case .undo:         return "kanbanEditor.cmd('undo')"
        case .redo:         return "kanbanEditor.cmd('redo')"
        case .link(let url):
            let escaped = url.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "'", with: "\\'")
            return "kanbanEditor.cmd('createLink', '\(escaped)')"
        }
    }
}

/// Griff auf den laufenden Editor: die Toolbar schickt Befehle hinein, das Speichern holt den Stand
/// heraus. Die View selbst wird von SwiftUI neu gebaut, der Controller überlebt — deshalb hängt die
/// WebView-Referenz hier und nicht in der `NSViewRepresentable`-Struktur.
@MainActor
final class RichTextEditorController {
    fileprivate weak var webView: WKWebView?

    func apply(_ command: RichTextCommand) {
        webView?.evaluateJavaScript(command.javaScript)
    }

    /// Holt den aktuellen Stand **sofort** als Markdown, ohne auf den Debounce zu warten. Nötig
    /// beim Umschalten in die Markdown-Ansicht und vor dem Schreiben nach Jira: die letzten
    /// getippten Zeichen dürfen nicht in einem noch laufenden Timer hängen.
    func currentMarkdown() async -> String? {
        guard let webView else { return nil }
        let html = try? await webView.evaluateJavaScript("kanbanEditor.html()")
        guard let html = html as? String else { return nil }
        return HTMLToMarkdown.convert(html)
    }

    func focus() {
        guard let webView else { return }
        webView.window?.makeFirstResponder(webView)
        webView.evaluateJavaScript("kanbanEditor.focusEnd()")
    }
}

/// WYSIWYG-Editor für Markdown: **Markdown → HTML → tippen → Markdown**.
///
/// Beide Richtungen sind schon erprobter Code — `MarkdownHTML` (cmark-gfm) hin, `HTMLToMarkdown`
/// zurück, und der Rundreise-Test hält sie aneinander. Der Editor selbst ist eine
/// `contenteditable`-Fläche in einer WKWebView, weil das die einzige Variante ist, in der Auswahl,
/// Undo-Stapel, Listen-Verschachtelung und Einfügen aus dem Browser ohne eigene Editor-Engine
/// funktionieren. Ein `NSTextView` mit `NSAttributedString` wäre nativer, müsste aber Listen,
/// Verschachtelung und Undo selbst nachbauen.
///
/// **Geladen wird nur auf Ansage** (`reloadToken`): jede Änderung an `markdown` neu zu laden würde
/// bei jedem Tastendruck den Cursor an den Anfang werfen — der Text fliesst im Betrieb nur nach
/// aussen, nicht zurück.
struct RichTextEditor: NSViewRepresentable {
    let markdown: String
    /// Hochzählen erzwingt ein Neuladen aus `markdown` (Sheet geöffnet, Ansicht umgeschaltet).
    let reloadToken: Int
    let placeholder: String
    /// Gibt den Editor-Inhalt als **Markdown** zurück (entprellt, plus sofort nach jedem Befehl).
    let onChange: (String) -> Void
    let controller: RichTextEditorController

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "editor")
        // Als User-Script, nicht als <script> im Dokument: sonst stünde die Editor-Logik in
        // `document.body.innerHTML` und damit im gespeicherten Text.
        configuration.userContentController.addUserScript(
            WKUserScript(source: HTMLTemplate.editorScript,
                         injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        controller.webView = webView
        load(webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
        context.coordinator.onChange = onChange
        guard context.coordinator.loadedToken != reloadToken else { return }
        load(webView, context: context)
    }

    private func load(_ webView: WKWebView, context: Context) {
        context.coordinator.loadedToken = reloadToken
        // Der Editor-Inhalt kommt aus dem Markdown, nicht aus dem letzten HTML: so ist der
        // gespeicherte Text immer das, was auch angezeigt wird.
        let body = markdown.isEmpty ? "<p><br></p>" : MarkdownHTML.render(markdown)
        webView.loadHTMLString(HTMLTemplate.wrapEditable(body, placeholder: placeholder), baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onChange: (String) -> Void
        var loadedToken: Int = -1

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let html = message.body as? String else { return }
            onChange(HTMLToMarkdown.convert(html))
        }

        /// Ein Klick auf einen Link soll im Editor **nicht** navigieren — die Fläche würde durch die
        /// Zielseite ersetzt und der Text wäre weg. Externes Öffnen ist trotzdem nützlich.
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.window?.makeFirstResponder(webView)
            webView.evaluateJavaScript("kanbanEditor.focusEnd()")
        }
    }
}
