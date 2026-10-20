import Foundation
import Observation

/// The Plan Window chosen in Settings. Kept in the App Group so the widgets can read it.
@MainActor
@Observable
final class PlanWindowPreferenceStore {
    var window: PlanWindow {
        didSet { storedWindow.save(window) }
    }

    private let storedWindow: StoredPreference<PlanWindow>

    init(defaults: UserDefaults = SharedStore.appGroupDefaults) {
        storedWindow = .rawValue("planWindow", in: defaults)
        window = storedWindow.load() ?? .restOfDay
    }
}
