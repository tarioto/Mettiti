import Foundation
import Observation

@MainActor
@Observable
final class WeatherProviderPreferenceStore {
    var provider: WeatherProvider {
        didSet { storedProvider.save(provider) }
    }

    private let storedProvider: StoredPreference<WeatherProvider>

    init(defaults: UserDefaults = .standard) {
        storedProvider = .rawValue("weatherProvider", in: defaults)
        provider = storedProvider.load() ?? .apple
    }
}
