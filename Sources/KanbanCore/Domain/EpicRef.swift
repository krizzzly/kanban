import Foundation

/// The epic a ticket belongs to, as the Jira Agile API reports it on a board issue.
public struct EpicRef: Sendable, Hashable {
    public let key: String            // e.g. EVEN-3345
    /// Written-out epic name. Jira leaves `name` empty on issue-type epics, where the summary is the
    /// name — so the caller passes whichever is filled.
    public let title: String
    /// Jira's `issueColor.key`, e.g. `purple`. Only a fallback: on this Jira it comes back `purple`
    /// for every epic, so it cannot tell them apart (see `EpicColors.paletteNames`).
    public let colorName: String?
    /// Jira's epic-colour key (`color.key`, e.g. `color_14`) — the same value as the epic's
    /// `ghx-label-14`, and the field that actually distinguishes epics.
    public let paletteKey: String?

    public init(key: String, title: String, colorName: String? = nil, paletteKey: String? = nil) {
        self.key = key
        self.title = title
        self.colorName = colorName
        self.paletteKey = paletteKey
    }

    /// `EVEN-3345 · Pendenzensystem`, or just the key when Jira sent no name.
    public var label: String {
        title.isEmpty ? key : "\(key) · \(title)"
    }

    /// The swatch to paint, as `#rrggbb`.
    public var hex: String {
        EpicColors.hex(paletteKey: paletteKey, colorName: colorName, fallbackSeed: paletteKey ?? key)
    }
}

/// Jira's issue/epic colour palette, mapped to hex so the UI layer stays free of Jira specifics.
public enum EpicColors {
    /// Jira's epic-colour key → colour name. Jira's own board API reports both for every epic
    /// (`{"epicColor": "ghx-label-13", "color": "dark_green"}` from
    /// `greenhopper/1.0/xboard/plan/backlog/epics.json`), and this table is that mapping, read off all
    /// 14 keys. It is needed because the Agile API's `issueColor` answers `purple` for every epic
    /// regardless of its real colour, so only `color_N` tells epics apart.
    static let paletteNames: [String: String] = [
        "color_1": "dark_grey", "color_2": "dark_yellow", "color_3": "yellow",
        "color_4": "dark_blue", "color_5": "dark_teal", "color_6": "green",
        "color_7": "purple", "color_8": "dark_purple", "color_9": "orange",
        "color_10": "blue", "color_11": "teal", "color_12": "grey",
        "color_13": "dark_green", "color_14": "dark_orange",
    ]

    /// Atlassian's epic colour names → swatch.
    static let palette: [String: String] = [
        "purple": "#8777D9", "blue": "#2684FF", "green": "#57D9A3", "teal": "#00C7E6",
        "yellow": "#FFC400", "orange": "#FF7452", "grey": "#8993A4", "gray": "#8993A4",
        "dark_purple": "#5243AA", "dark_blue": "#0052CC", "dark_green": "#00875A",
        "dark_teal": "#00A3BF", "dark_yellow": "#FF991F", "dark_orange": "#FF5630",
        "dark_grey": "#505F79", "dark_gray": "#505F79",
    ]

    /// Ordered swatches used when Jira names no colour: distinct hues, picked deterministically from
    /// the seed so an epic keeps its colour across launches. It will not match Jira's own colour —
    /// it only keeps epics visually apart.
    static let fallbacks = ["#8777D9", "#2684FF", "#57D9A3", "#00C7E6",
                            "#FFC400", "#FF7452", "#5243AA", "#00875A"]

    /// Resolution order: the epic-colour key through Jira's own mapping, then the `issueColor` name,
    /// then a stable stand-in.
    public static func hex(paletteKey: String?, colorName: String?, fallbackSeed: String) -> String {
        if let key = paletteKey?.lowercased(), let name = paletteNames[key], let hex = palette[name] {
            return hex
        }
        if let name = colorName?.lowercased().replacingOccurrences(of: "-", with: "_"),
           let hex = palette[name] {
            return hex
        }
        // FNV-1a plus an avalanche step, all stable across processes (unlike Swift's randomly seeded
        // hashValue). The avalanche is what makes this usable here: the seeds we get differ only in a
        // trailing digit ("color_1" vs "color_9"), and neither a byte sum nor a bare multiply-hash can
        // carry such a high-bit difference down into the low bits the modulo looks at.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in fallbackSeed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        hash ^= hash >> 33
        hash = hash &* 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
        return fallbacks[Int(hash % UInt64(fallbacks.count))]
    }
}

/// Jira only fills the `epic` field on issues that sit directly under an epic. A sub-task points at
/// its story instead, so its epic has to come from that story.
public enum EpicResolution {
    /// Returns `tickets` with every sub-task adopting its parent's epic. The parent is looked up
    /// among the same tickets — for a board that means no extra Jira request, since a sub-task's
    /// story is normally in the same sprint. A sub-task whose story is not on the board keeps no
    /// epic rather than a guessed one.
    public static func inheritFromParents(_ tickets: [Ticket]) -> [Ticket] {
        let epicByKey: [String: EpicRef] = tickets.reduce(into: [:]) { result, ticket in
            if let epic = ticket.epic { result[ticket.key] = epic }
        }
        guard !epicByKey.isEmpty else { return tickets }
        return tickets.map { ticket in
            guard ticket.epic == nil, let parent = ticket.parentKey,
                  let inherited = epicByKey[parent] else { return ticket }
            var copy = ticket
            copy.epic = inherited
            return copy
        }
    }
}
