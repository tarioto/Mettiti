import Foundation
import Observation
import WidgetKit

/// The weather location chosen in Settings. Also mirrored into the App Group (see
/// `SharedStore.loadLocationSelection`) so the widgets can tell which location their saved plan is for.
@MainActor
@Observable
final class LocationPreferenceStore {
    var selection: LocationSelection {
        didSet {
            // Equality ignores the time zone, so compare it too: re-picking the same city can add one.
            guard selection != oldValue || selection.calendar(fallback: .current).timeZone != oldValue.calendar(fallback: .current).timeZone else { return }
            storedSelection.save(selection)
            shareSelection()
        }
    }

    private let storedSelection: StoredPreference<LocationSelection>
    @ObservationIgnored private let sharedDefaults: UserDefaults
    @ObservationIgnored private let reloadWidgets: @MainActor () -> Void

    /// Copies the saved selection to the App Group too, so selections saved before it was shared
    /// reach the widgets at launch.
    init(
        defaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults = SharedStore.appGroupDefaults,
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        storedSelection = .json("locationSelection", in: defaults)
        self.sharedDefaults = sharedDefaults
        self.reloadWidgets = reloadWidgets
        selection = storedSelection.load() ?? .currentLocation
        SharedStore.saveLocationSelection(selection, to: sharedDefaults)
    }

    private func shareSelection() {
        SharedStore.saveLocationSelection(selection, to: sharedDefaults)
        // The widgets judge their saved plan against the selection.
        reloadWidgets()
    }
}
