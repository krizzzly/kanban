import SwiftUI

/// App-wide UI scale factor (ported from kanban-code). Reads UserDefaults so it works from
/// both SwiftUI and plain code; defaults to 1.0 when unset.
enum AppScale {
    static var factor: CGFloat {
        let uiTextSize = UserDefaults.standard.object(forKey: "uiTextSize") != nil
            ? UserDefaults.standard.integer(forKey: "uiTextSize") : 1
        switch uiTextSize {
        case 0: return 0.85
        case 2: return 1.15
        case 3: return 1.3
        case 4: return 1.5
        default: return 1.0
        }
    }
}

// MARK: - Scaled fonts (ported 1:1 from kanban-code's AppScale.swift)

extension Font {
    /// Scaled semantic font style.
    static func app(_ style: TextStyle, weight: Weight? = nil, design: Design? = nil) -> Font {
        let size = baseSize(for: style) * AppScale.factor
        return .system(size: size, weight: weight ?? defaultWeight(for: style), design: design ?? .default)
    }

    /// Scaled explicit size.
    static func app(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
        .system(size: size * AppScale.factor, weight: weight, design: design)
    }

    private static func baseSize(for style: TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 28
        case .title: 24
        case .title2: 19
        case .title3: 17
        case .headline: 15
        case .subheadline: 13
        case .body: 15
        case .callout: 14
        case .footnote: 12
        case .caption: 12
        case .caption2: 11
        @unknown default: 15
        }
    }

    private static func defaultWeight(for style: TextStyle) -> Weight {
        style == .headline ? .semibold : .regular
    }
}

extension CGFloat {
    /// Scale a point size by the app UI factor.
    var scaled: CGFloat { self * AppScale.factor }
}
