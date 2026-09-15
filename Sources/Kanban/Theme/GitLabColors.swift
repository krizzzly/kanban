import AppKit
import SwiftUI

/// GitLab's own badge palette, so the review indicators on a card read exactly like the ones in the
/// MR list they mirror (green "Approved"/"Resolved", grey thread counter).
///
/// Values are GitLab's design tokens: green-100/green-700 and gray-100/gray-700 for light, the
/// corresponding dark-theme tokens (green-900/green-300, gray-800/gray-200) for dark — a light-green
/// pill on a dark card would glare, exactly as GitLab's own dark theme avoids.
enum GitLabColors {
    /// Text/icon of a success badge ("Approved", "Resolved").
    static let successText = dynamic(light: 0x24663B, dark: 0x91D4A8)
    static let successFill = dynamic(light: 0xC3E6CD, dark: 0x0A4A1F)
    /// Text/icon of the neutral thread counter ("0 of 4").
    static let neutralText = dynamic(light: 0x535158, dark: 0xBFBFC4)
    static let neutralFill = dynamic(light: 0xECECEF, dark: 0x3A383F)

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
