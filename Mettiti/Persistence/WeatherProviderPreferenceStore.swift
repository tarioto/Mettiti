import Foundation

@MainActor
final class WeatherProviderPreferenceStore: ObservableObject {
    @Published var provider: WeatherProvider {
        didSet { storedProvider.save(provider) }
    }

    private let storedProvider: StoredPreference<WeatherProvider>

    init(defaults: UserDefaults = .standard) {
        storedProvider = .rawValue("weatherProvider", in: defaults)
        provider = storedProvider.load() ?? .apple
    }
}
