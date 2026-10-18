import Foundation

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
