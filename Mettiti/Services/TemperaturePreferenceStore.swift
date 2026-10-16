import Foundation
import WidgetKit

@MainActor
final class TemperaturePreferenceStore: ObservableObject {
    @Published var unit: TemperatureUnit {
        didSet {
            guard unit != oldValue else { return }
            saveUnit(unit)
            reloadWidgets()
        }
    }

    private let saveUnit: (TemperatureUnit) -> Void
    private let reloadWidgets: () -> Void

    /// Assigning `unit` here doesn't run `didSet`, so loading the stored unit never reloads widgets.
    init(
        loadUnit: () -> TemperatureUnit = SharedStore.loadTemperatureUnit,
        saveUnit: @escaping (TemperatureUnit) -> Void = SharedStore.saveTemperatureUnit,
        reloadWidgets: @escaping () -> Void = TemperaturePreferenceStore.reloadAllWidgetTimelines
    ) {
        self.saveUnit = saveUnit
        self.reloadWidgets = reloadWidgets
        unit = loadUnit()
    }

    /// Default widget refresher: widgets read the unit from the app group, so they must redraw when it changes.
    nonisolated static func reloadAllWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
