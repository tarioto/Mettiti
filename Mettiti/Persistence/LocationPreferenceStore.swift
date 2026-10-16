import Foundation

enum LocationSelection: Codable, Equatable {
    case currentLocation
    case custom(name: String, latitude: Double, longitude: Double)
}

@MainActor
final class LocationPreferenceStore: ObservableObject {
    @Published var selection: LocationSelection {
        didSet {
            guard selection != oldValue else { return }
            storedSelection.save(selection)
        }
    }

    private let storedSelection: StoredPreference<LocationSelection>

    init(defaults: UserDefaults = .standard) {
        storedSelection = .json("locationSelection", in: defaults)
        selection = storedSelection.load() ?? .currentLocation
    }
}
