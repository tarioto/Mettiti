import Foundation

@MainActor
final class WeatherProviderPreferenceStore: ObservableObject {
    @Published var provider: WeatherProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey) }
    }

    private static let providerKey = "weatherProvider"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.providerKey), let provider = WeatherProvider(rawValue: raw) {
            self.provider = provider
        } else {
            self.provider = .apple
        }
    }
}
