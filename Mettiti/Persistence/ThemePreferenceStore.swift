import Foundation
import Observation

@MainActor
@Observable
final class ThemePreferenceStore {
    var theme: AppTheme {
        didSet { storedTheme.save(theme) }
    }
    var appearance: AppAppearance {
        didSet { storedAppearance.save(appearance) }
    }

    private let storedTheme: StoredPreference<AppTheme>
    private let storedAppearance: StoredPreference<AppAppearance>

    init(defaults: UserDefaults = .standard) {
        storedTheme = .rawValue("appTheme", in: defaults)
        storedAppearance = .rawValue("appAppearance", in: defaults)
        theme = storedTheme.load() ?? .none
        appearance = storedAppearance.load() ?? .system
    }
}
