import Foundation
import Observation
import WidgetKit

/// The Plan Window chosen in Settings. Kept in the App Group so the widgets can read it.
@MainActor
@Observable
final class PlanWindowPreferenceStore {
    var window: PlanWindow {
        didSet {
            guard window != oldValue else { return }
            storedWindow.save(window)
            // The widgets follow this window, so their saved plan may no longer match it.
            reloadWidgets()
        }
    }

    private let storedWindow: StoredPreference<PlanWindow>
    @ObservationIgnored private let reloadWidgets: @MainActor () -> Void

    init(
        defaults: UserDefaults = SharedStore.appGroupDefaults,
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        storedWindow = SharedStore.storedPlanWindow(in: defaults)
        self.reloadWidgets = reloadWidgets
        window = SharedStore.loadPlanWindow(from: defaults)
    }
}
