import AppKit
import SwiftUI
import KanbanCore

extension NSImage {
    /// Lädt das Bild eines Projekts von der Platte — der eine Weg dorthin, für Kopfzeile und
    /// Einstellungen.
    ///
    /// `nil` heisst „nichts anzuzeigen", und zwar für alle drei Fälle, die gleich aussehen: kein
    /// Pfad gesetzt, Datei verschwunden, oder eine Datei ohne Fläche. Letzteres trifft ein SVG ohne
    /// `width`/`height`/`viewBox`: `NSImage` lädt es klaglos mit Grösse 0×0, und ein Bild ohne
    /// Fläche wäre in der Leiste eine unsichtbare Lücke statt einer erkennbaren Fehlstelle.
    static func projectImage(atPath path: String?) -> NSImage? {
        guard let path, !path.isEmpty,
              let bild = NSImage(contentsOfFile: path),
              bild.size.width > 0, bild.size.height > 0 else { return nil }
        return bild
    }
}

/// Legt Hintergrund und unteren Rand der Kopfzeile auf das Fenster — die zwei Teile der
/// Projekt-Darstellung, die nicht an einem einzelnen Leisten-Element hängen.
///
/// Beide Teile werden **nur angebracht, wenn sie konfiguriert sind**. Das ist kein Feinschliff,
/// sondern der Kern der Anforderung: `.toolbarBackground(.clear, …)` wäre keine Nicht-Entscheidung,
/// sondern nähme der Leiste ihr normales Material. Ohne Eintrag darf hier gar kein Modifier landen.
///
/// Der Rand ist bewusst **kein** Leisten-Modifier — dafür gibt es keinen. Er ist die oberste Zeile
/// des Fensterinhalts (`safeAreaInset`), sitzt damit bündig unter der Leiste und liest sich als
/// deren Abschluss. Der Inhalt darunter rückt um genau diese Dicke nach.
struct HeaderChrome: ViewModifier {
    let appearance: ProjectAppearance

    private var background: Color? { appearance.headerBackground.flatMap(Color.init(hex:)) }
    private var borderColor: Color? { appearance.headerBorderColor.flatMap(Color.init(hex:)) }

    /// Farbe **und** Dicke müssen stehen: eine Farbe ohne Dicke hätte keine Fläche, eine Dicke ohne
    /// Farbe keine Erscheinung. Beides einzeln zu zeichnen hiesse, sich eine Vorgabe auszudenken.
    private var border: (color: Color, width: Double)? {
        guard let borderColor, let width = appearance.headerBorderWidth, width > 0 else { return nil }
        return (borderColor, width)
    }

    func body(content: Content) -> some View {
        content
            .modifier(HeaderBackground(color: background))
            .modifier(HeaderBottomBorder(border: border))
    }
}

/// Getrennte Modifier statt eines `if`-Baums: ein `@ViewBuilder` mit vier Zweigen (Hintergrund ja/
/// nein × Rand ja/nein) baut vier verschiedene Ansichtstypen, und SwiftUI wirft beim Umschalten den
/// Zustand darunter weg — das Board würde beim Setzen einer Farbe neu aufgebaut.
private struct HeaderBackground: ViewModifier {
    let color: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let color {
            content
                .toolbarBackground(color, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}

private struct HeaderBottomBorder: ViewModifier {
    let border: (color: Color, width: Double)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let border {
            content.safeAreaInset(edge: .top, spacing: 0) {
                Rectangle()
                    .fill(border.color)
                    .frame(height: border.width)
                    .frame(maxWidth: .infinity)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Kopfzeilen-Darstellung des Projekts. Bei `.none` bleibt die Ansicht unverändert.
    func headerChrome(_ appearance: ProjectAppearance) -> some View {
        modifier(HeaderChrome(appearance: appearance))
    }
}
