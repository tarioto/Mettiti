import SwiftUI
import UIKit

/// Purely the home screen's background color choice.
enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case none
    case sunset
    case ocean
    case aurora
    case midnight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Default"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .aurora: return "Aurora"
        case .midnight: return "Midnight"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .none:
            // A subtle system-gray fade that adapts to Light/Dark Mode.
            return [
                Color(.systemGroupedBackground),
                Color(.systemGray5)
            ]
        case .sunset:
            return [
                Color(red: 1.00, green: 0.60, blue: 0.35),
                Color(red: 0.90, green: 0.30, blue: 0.45),
                Color(red: 0.40, green: 0.15, blue: 0.55)
            ]
        case .ocean:
            return [
                Color(red: 0.10, green: 0.65, blue: 0.80),
                Color(red: 0.08, green: 0.40, blue: 0.70),
                Color(red: 0.06, green: 0.18, blue: 0.48)
            ]
        case .aurora:
            return [
                Color(red: 0.20, green: 0.80, blue: 0.60),
                Color(red: 0.25, green: 0.50, blue: 0.85),
                Color(red: 0.45, green: 0.30, blue: 0.80)
            ]
        case .midnight:
            return [
                Color(red: 0.10, green: 0.10, blue: 0.22),
                Color(red: 0.18, green: 0.12, blue: 0.32),
                Color(red: 0.05, green: 0.05, blue: 0.13)
            ]
        }
    }

    var accentColor: Color {
        switch self {
        case .none: return .accentColor
        case .sunset: return Color(red: 1.00, green: 0.60, blue: 0.35)
        case .ocean: return Color(red: 0.30, green: 0.75, blue: 0.90)
        case .aurora: return Color(red: 0.35, green: 0.85, blue: 0.65)
        case .midnight: return Color(red: 0.65, green: 0.55, blue: 0.95)
        }
    }

    /// The color scheme for content drawn directly on the gradient, such as the header.
    /// The colored gradients are too saturated for black text, so they always use dark styling.
    /// nil means follow the app's Light/Dark appearance.
    var overlayColorScheme: ColorScheme? {
        self == .none ? nil : .dark
    }

    var swatchGradient: LinearGradient {
        let colors = self == .none ? [Color(.systemGray4), Color(.systemGray2)] : gradientColors
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// The overall Light/Dark appearance, independent of which background color is chosen.
enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Applied to the window so already-presented sheets update immediately.
    /// .unspecified means "follow the device's current Light/Dark Mode setting".
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
