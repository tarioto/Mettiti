import Foundation

@MainActor
final class ThemePreferenceStore: ObservableObject {
    @Published var theme: AppTheme {
        didSet { persistTheme() }
    }
    @Published var appearance: AppAppearance {
        didSet { persistAppearance() }
    }

    private static let themeKey = "appTheme"
    private static let appearanceKey = "appAppearance"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.themeKey), let theme = AppTheme(rawValue: raw) {
            self.theme = theme
        } else {
            self.theme = .none
        }

        if let raw = UserDefaults.standard.string(forKey: Self.appearanceKey), let appearance = AppAppearance(rawValue: raw) {
            self.appearance = appearance
        } else {
            self.appearance = .system
        }
    }

    private func persistTheme() {
        UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
    }

    private func persistAppearance() {
        UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
    }
}
