import Foundation

/// Das Aussehen, das ein Projekt der Kopfzeile gibt: ein Bild links neben der Projektauswahl, die
/// Farben der Zeile selbst und ihr unterer Rand.
///
/// **Jedes Feld ist einzeln optional, und gar nichts gesetzt ist der Normalfall** — dann sieht die
/// Kopfzeile aus wie immer. Deshalb stehen hier auch keine Vorgabefarben: eine erfundene Vorgabe
/// wäre eine Behauptung darüber, wie ein Projekt auszusehen hat, und sie liesse sich nicht mehr von
/// einer echten Wahl unterscheiden.
///
/// Farben stehen als `#rrggbb`-Text — geprüft beim Einlesen, Unlesbares gilt als nicht gesetzt.
/// `KanbanCore` kennt bewusst keinen Farbtyp der Oberfläche (kein AppKit, kein SwiftUI); die
/// Umrechnung macht der Kanban-Layer über sein vorhandenes `Color(hex:)`.
public struct ProjectAppearance: Sendable, Hashable {
    /// Absoluter Pfad des Bildes **in Kanbans Datenordner** (siehe `ProjectImageStore`): das
    /// gewählte Bild wird dorthin kopiert, statt auf die Quelle zu zeigen. Sonst wäre das Logo weg,
    /// sobald jemand den Download-Ordner aufräumt.
    public let imagePath: String?
    public let headerBackground: String?
    public let headerForeground: String?
    public let headerBorderColor: String?
    /// Dicke des unteren Randes in Punkten. `nil` heisst „nicht definiert" und `0` „ausdrücklich
    /// keiner" — beides sieht gleich aus, aber nur das eine überschreibt eine spätere Vorgabe.
    public let headerBorderWidth: Double?

    /// Nichts definiert: die Kopfzeile bleibt, wie sie ohne dieses Feature wäre. Die Oberfläche
    /// fragt danach, statt fünf Einzelfelder zu prüfen.
    public var isEmpty: Bool {
        imagePath == nil && headerBackground == nil && headerForeground == nil
            && headerBorderColor == nil && headerBorderWidth == nil
    }

    public init(imagePath: String? = nil,
                headerBackground: String? = nil,
                headerForeground: String? = nil,
                headerBorderColor: String? = nil,
                headerBorderWidth: Double? = nil) {
        self.imagePath = imagePath
        self.headerBackground = headerBackground
        self.headerForeground = headerForeground
        self.headerBorderColor = headerBorderColor
        self.headerBorderWidth = headerBorderWidth
    }

    public static let none = ProjectAppearance()

    // MARK: - Einlesen

    /// Normalisiert eine Farbeingabe auf `#rrggbb` (klein). Alles, was `TerminalRGB` nicht als Hex
    /// erkennt, gilt als **nicht gesetzt**: eine halb getippte Farbe soll die Kopfzeile nicht
    /// einfärben, aber auch nicht die Config zu Fall bringen.
    public static func normalizeColor(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rgb = TerminalRGB(hex: trimmed) else { return nil }
        return String(format: "#%02x%02x%02x", rgb.r, rgb.g, rgb.b)
    }

    /// Was ein Hex-Eingabefeld von einer Eingabe übernimmt: ein vorangestelltes `#` (so kommt eine
    /// Farbe aus der Zwischenablage) fällt weg, alles, was keine Hexziffer ist, ebenso, und nach
    /// sechs Stellen ist Schluss. Zurück kommen **nur die Ziffern**, klein — das `#` steht im Feld
    /// fest davor und ist nichts, was jemand tippt.
    ///
    /// Unvollständig darf bleiben: man tippt von links, und ein Feld, das nach drei Zeichen etwas
    /// anderes tut als anzeigen, was dasteht, wäre unbedienbar.
    public static func sanitizeHexInput(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        return String(text.filter(\.isHexDigit).prefix(6)).lowercased()
    }

    /// Die Randdicke steht als Text in der Config, wie die Zahlen des Watchdogs — der
    /// Einstellungs-Editor kennt nur Text, Wahrheitswerte und Auswahllisten. Unlesbares gilt als
    /// nicht gesetzt, Werte darüber hinaus werden auf 0…20 beschnitten: ein vertippter Rand von
    /// 2000 Punkten wäre sonst das ganze Fenster.
    public static func normalizeWidth(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return nil }
        return Swift.min(Swift.max(value, 0), 20)
    }

    /// Baut die Darstellung aus den Rohwerten eines Projekteintrags. Bleibt alles leer, kommt
    /// `.none` heraus — und `isEmpty` sagt der Oberfläche, dass sie nichts zu tun hat.
    public static func make(imagePath: String?, background: String?, foreground: String?,
                            borderColor: String?, borderWidth: String?) -> ProjectAppearance {
        let bild = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProjectAppearance(
            imagePath: (bild?.isEmpty ?? true) ? nil : bild,
            headerBackground: normalizeColor(background),
            headerForeground: normalizeColor(foreground),
            headerBorderColor: normalizeColor(borderColor),
            headerBorderWidth: normalizeWidth(borderWidth))
    }
}
