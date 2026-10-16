import Foundation

enum LocationSelection: Codable, Equatable {
    case currentLocation
    case custom(name: String, latitude: Double, longitude: Double)
}

@MainActor
final class LocationPreferenceStore: ObservableObject {
    @Published var selection: LocationSelection {
        didSet { persist() }
    }

    private static let key = "locationSelection"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LocationSelection.self, from: data) {
            selection = decoded
        } else {
            selection = .currentLocation
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
