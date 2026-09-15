import AppKit
import SwiftUI
import KanbanCore

/// The Jira issue type in front of the card title — **Jira's own icon**, fetched from
/// `issuetype.iconUrl` (a small SVG on the Jira host, which `NSImage` renders natively) through the
/// same authenticated cache as the avatars. Using Jira's image rather than a mapping means a Bug looks
/// like a Bug even for the instance's own types (`Test Plan`, `Test Execution`, …) and survives a
/// renamed or localised type.
///
/// The SF-Symbol fallback covers the moment before the image is loaded and an instance that serves no
/// icon; unknown type names get a neutral glyph rather than a guessed one. The type name is always in
/// the tooltip, so the card never depends on reading the symbol alone.
struct IssueTypeIcon: View {
    let type: String?
    let urlString: String?
    var size: CGFloat = 14

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: fallback.symbol)
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(fallback.color)
            }
        }
        .frame(width: size, height: size)
        .help(type ?? "Unbekannter Vorgangstyp")
        .accessibilityLabel(type ?? "Vorgangstyp")
        .task(id: urlString) {
            image = nil
            guard let urlString else { return }
            image = await AvatarCache.shared.image(for: urlString)
        }
    }

    /// Jira's own colours for the types every project has; anything else stays grey.
    private var fallback: (symbol: String, color: Color) {
        let name = (type ?? "").lowercased()
        // Sub-task first: "Unteraufgabe" also contains "aufgabe".
        if name.contains("unteraufgabe") || name.contains("subtask") || name.contains("sub-task") {
            return ("checklist", Color(hex: "#4688EC") ?? .blue)
        }
        if name.contains("bug") || name.contains("fehler") {
            return ("ladybug.fill", Color(hex: "#F15B50") ?? .red)
        }
        if name.contains("story") {
            return ("bookmark.fill", Color(hex: "#6A9A23") ?? .green)
        }
        if name.contains("epic") {
            return ("bolt.fill", Color(hex: "#904EE2") ?? .purple)
        }
        if name.contains("aufgabe") || name.contains("task") {
            return ("checkmark.square.fill", Color(hex: "#4688EC") ?? .blue)
        }
        return ("square.fill", .secondary)
    }
}
