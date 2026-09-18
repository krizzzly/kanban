import AppKit
import SwiftUI
import KanbanCore

/// Die Badge-Palette **der jeweiligen Forge**, damit die Review-Anzeigen auf einer Karte genauso
/// aussehen wie in der Liste, die sie spiegeln — grünes „Approved"/„Resolved", grauer Thread-Zähler.
///
/// Die Werte sind die Design-Tokens der Plattformen selbst. GitLab: green-100/green-700 und
/// gray-100/gray-700 für hell, die Dark-Theme-Entsprechungen (green-900/green-300,
/// gray-800/gray-200) für dunkel. GitHub (Primer): success-fg/success-muted und
/// neutral-fg/neutral-muted, ebenfalls je Modus. Eine hellgrüne Pille auf dunkler Karte blendete —
/// genau das vermeiden beide Dark-Themes auch selbst.
enum ForgeColors {
    struct Palette {
        /// Text/Symbol einer Erfolgs-Pille („Approved", „Resolved").
        let successText: Color
        let successFill: Color
        /// Text/Symbol des neutralen Thread-Zählers („0 of 4").
        let neutralText: Color
        let neutralFill: Color
    }

    static func palette(_ forge: ForgeKind) -> Palette {
        switch forge {
        case .gitlab: return gitlab
        case .github: return github
        }
    }

    static let gitlab = Palette(
        successText: dynamic(light: 0x24663B, dark: 0x91D4A8),
        successFill: dynamic(light: 0xC3E6CD, dark: 0x0A4A1F),
        neutralText: dynamic(light: 0x535158, dark: 0xBFBFC4),
        neutralFill: dynamic(light: 0xECECEF, dark: 0x3A383F))

    static let github = Palette(
        successText: dynamic(light: 0x1A7F37, dark: 0x3FB950),
        successFill: dynamic(light: 0xDAFBE1, dark: 0x102C19),
        neutralText: dynamic(light: 0x59636E, dark: 0x9198A1),
        neutralFill: dynamic(light: 0xEFF2F5, dark: 0x262C36))

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
