import Testing
@testable import Mettiti

@MainActor
struct TemperaturePreferenceStoreTests {
    @Test func changingUnitSavesItAndReloadsWidgetsOnce() {
        var saved: [TemperatureUnit] = []
        var reloads = 0
        let store = TemperaturePreferenceStore(
            loadUnit: { .fahrenheit },
            saveUnit: { saved.append($0) },
            reloadWidgets: { reloads += 1 }
        )

        store.unit = .celsius

        #expect(saved == [.celsius])
        #expect(reloads == 1)
    }

    @Test func loadingTheStoredUnitDoesNotReloadWidgets() {
        var saved: [TemperatureUnit] = []
        var reloads = 0
        let store = TemperaturePreferenceStore(
            loadUnit: { .celsius },
            saveUnit: { saved.append($0) },
            reloadWidgets: { reloads += 1 }
        )

        #expect(store.unit == .celsius)
        #expect(saved.isEmpty)
        #expect(reloads == 0)
    }

    @Test func settingTheSameUnitAgainDoesNotReloadWidgets() {
        var reloads = 0
        let store = TemperaturePreferenceStore(
            loadUnit: { .celsius },
            saveUnit: { _ in },
            reloadWidgets: { reloads += 1 }
        )

        store.unit = .celsius

        #expect(reloads == 0)
    }
}
