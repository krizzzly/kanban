import SwiftUI
import AppKit

/// Stellt den Teiler des umgebenden `VSplitView` **einmal** auf einen Anteil der Höhe.
///
/// `VSplitView` kennt keinen einstellbaren Anteil, und der naheliegende Hebel trägt nicht: gemessen
/// gegen echtes AppKit (macOS 15) wird **`idealHeight` vollständig ignoriert** — 220, 380, 600 und
/// gar keins ergaben dieselbe Position. Verteilt wird **proportional zu den Mindesthöhen**: 240 oben
/// zu 120 unten sind 2 : 1, also genau das Drittel, das dem Terminal zu wenig ist (240/240 ergäbe
/// 50 %, 240/480 zwei Drittel).
///
/// Die Mindesthöhen anzugleichen wäre deshalb der kürzere Weg und der falsche. Zum einen wäre die
/// Hälfte dann ein Nebenprodukt zweier zufällig gleicher Zahlen — wer später die Mindesthöhe des
/// Task-Files anhebt, verschiebt den Teiler, ohne es zu merken. Zum anderen ist eine Mindesthöhe
/// eine Zusage über die *kleinste* erlaubte Grösse, nicht über die Startposition: das Terminal
/// liesse sich nie wieder unter 240 pt ziehen.
///
/// Also die Position direkt setzen, am echten `NSSplitView`, den SwiftUI darunter führt. Danach hat
/// die Hand das letzte Wort: ein von Hand gezogener Teiler bleibt stehen, und ein Fenster-Resize
/// behält seinen **Anteil** (gemessen: auf 150 pt gezogen, über 760 → 1100 → 760 unverändert).
///
/// **Genau einmal**, nicht bei jeder Aktualisierung: jede Teiler-Verschiebung ändert die Grösse der
/// Terminal-Pane, und das ist ein SIGWINCH — tmux baut Claudes ganze TUI neu auf (derselbe Grund,
/// aus dem die Prompt-Timeline über dem Terminal liegt statt daneben). Dafür steht das Merkzeichen
/// im Coordinator: es überlebt jede Aktualisierung, solange der Split lebt.
struct SplitFractionSetter: NSViewRepresentable {
    /// Anteil, den die **untere** Hälfte bekommen soll (0…1).
    let unten: CGFloat

    final class Coordinator {
        var gesetzt = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Unsichtbar **und** unfühlbar: als Hintergrund der unteren Hälfte liegt die Hilfsansicht über
    /// deren ganzer Fläche, und `TerminalCache` entscheidet per `hitTest`, ob ein Rad-Event ins
    /// tmux-copy-mode gehört. Sie steht zwar hinter dem Terminal und käme dort nicht zum Zug — aber
    /// eine Ansicht, die nichts zeigt und nichts tut, soll auch in keiner Trefferprüfung auftauchen.
    final class Durchreiche: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Durchreiche {
        let view = Durchreiche(frame: .zero)
        DispatchQueue.main.async { setzen(from: view, context: context) }
        return view
    }

    /// Auch beim Aktualisieren, wie beim `WindowAccessor`: beim ersten Aufbau hängt die Ansicht noch
    /// in keinem Fenster, und ein Split ohne Höhe lässt sich nicht teilen. Das Merkzeichen macht
    /// jeden weiteren Aufruf zum No-op, sobald es einmal geklappt hat.
    func updateNSView(_ nsView: Durchreiche, context: Context) {
        DispatchQueue.main.async { setzen(from: nsView, context: context) }
    }

    private func setzen(from view: NSView, context: Context) {
        guard !context.coordinator.gesetzt else { return }
        var kandidat: NSView? = view
        while let aktuell = kandidat, !(aktuell is NSSplitView) { kandidat = aktuell.superview }
        guard let split = kandidat as? NSSplitView,
              split.arrangedSubviews.count >= 2,
              split.frame.height > 0 else { return }
        context.coordinator.gesetzt = true
        // `setPosition` misst die Kante der **oberen** Hälfte, der Anteil gilt der unteren.
        // Liegt die Hälfte unter einer der Mindesthöhen (sehr niedriges Fenster), klemmt
        // `NSSplitView` selbst — deshalb hier keine eigene Rechnerei.
        let nutzbar = split.frame.height - split.dividerThickness
        split.setPosition(nutzbar * (1 - unten), ofDividerAt: 0)
    }
}

extension View {
    /// Legt den Teiler des umgebenden `VSplitView` einmalig auf `unten` (Anteil der unteren Hälfte).
    ///
    /// Angewandt wird es auf die **untere** Hälfte des Splits — von dort findet die Hilfsansicht den
    /// `NSSplitView` über die Superview-Kette. Bewusst **kein** `autosaveName` am Split: die
    /// Position soll das Öffnen gerade *nicht* überleben.
    func splitDividerOnce(unten anteil: CGFloat) -> some View {
        background(SplitFractionSetter(unten: anteil))
    }
}
