import SwiftUI
import KanbanCore

extension Color {
    /// `#rrggbb` (or `#rrggbbaa`) → Color. Nil for anything malformed, so a bad value shows nothing
    /// instead of a wrong colour.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let shift = hasAlpha ? 8 : 0
        self.init(.sRGB,
                  red: Double((value >> (16 + shift)) & 0xFF) / 255,
                  green: Double((value >> (8 + shift)) & 0xFF) / 255,
                  blue: Double((value >> shift) & 0xFF) / 255,
                  opacity: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }
}

extension EpicRef {
    /// The epic's Jira colour.
    var color: Color { Color(hex: hex) ?? .secondary }
}

/// The epic's colour code on a board card: a vertical bar down the card's leading edge, the way Jira
/// itself marks epic membership. Colour only — the name is written out in the detail header.
struct EpicColorStripe: View {
    let epic: EpicRef

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(epic.color)
            .frame(width: 4)
            .help("Epic: \(epic.label)")
            .accessibilityLabel("Epic \(epic.label)")
    }
}

/// The epic written out, as a colour-coded pill: shown in the detail header next to the task file, so
/// the epic of the open ticket is readable rather than just colour-coded.
struct EpicPill: View {
    let epic: EpicRef

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(epic.color).frame(width: 8, height: 8)
            Text(epic.title.isEmpty ? epic.key : epic.title)
                .font(.app(.subheadline))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(epic.color.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(epic.color.opacity(0.45), lineWidth: 1))
        .help("Epic \(epic.key): \(epic.title)")
    }
}
