import Foundation
import Testing
@testable import Mettiti

@MainActor
struct PreferenceStoreTests {
    @Test func themeAndAppearanceAreRememberedAcrossLaunches() {
        let defaults = isolatedDefaults()
        let store = ThemePreferenceStore(defaults: defaults)

        store.theme = .ocean
        store.appearance = .dark

        let relaunched = ThemePreferenceStore(defaults: defaults)
        #expect(relaunched.theme == .ocean)
        #expect(relaunched.appearance == .dark)
    }

    @Test func weatherProviderSavedByEarlierVersionsStillLoads() {
        let defaults = isolatedDefaults()
        defaults.set("openMeteo", forKey: "weatherProvider")

        #expect(WeatherProviderPreferenceStore(defaults: defaults).provider == .openMeteo)
    }

    @Test func planWindowDefaultsToRestOfDay() {
        #expect(PlanWindowPreferenceStore(defaults: isolatedDefaults()).window == .restOfDay)
    }

    @Test func planWindowIsRememberedAcrossLaunches() {
        let defaults = isolatedDefaults()
        let store = PlanWindowPreferenceStore(defaults: defaults)

        store.window = .threeHours

        #expect(PlanWindowPreferenceStore(defaults: defaults).window == .threeHours)
    }

    @Test func customLocationIsRememberedAcrossLaunches() {
        let defaults = isolatedDefaults()
        let store = LocationPreferenceStore(defaults: defaults)

        store.selection = .custom(name: "Lisbon", latitude: 38.7, longitude: -9.1)

        #expect(LocationPreferenceStore(defaults: defaults).selection == .custom(name: "Lisbon", latitude: 38.7, longitude: -9.1))
    }

    @Test func cardLayoutIsRememberedAcrossLaunches() {
        let defaults = isolatedDefaults()
        let store = CardPreferenceStore(defaults: defaults)

        store.cards = [
            CardConfig(type: .weather, isVisible: false),
            CardConfig(type: .wearAndBring, isVisible: true),
            CardConfig(type: .plan, isVisible: true),
        ]

        #expect(CardPreferenceStore(defaults: defaults).visibleOrderedTypes == [.wearAndBring, .plan])
    }

    @Test func storedCardLayoutMissingACardFallsBackToTheDefaultLayout() throws {
        let defaults = isolatedDefaults()
        let incomplete = [CardConfig(type: .weather, isVisible: true)]
        defaults.set(try JSONEncoder().encode(incomplete), forKey: "cardConfiguration")

        #expect(CardPreferenceStore(defaults: defaults).visibleOrderedTypes == [.plan, .weather, .wearAndBring])
    }
}
