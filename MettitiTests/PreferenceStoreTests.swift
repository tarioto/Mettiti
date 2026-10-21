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

    @Test func widgetsReadThePlanWindowChosenInSettings() {
        let defaults = isolatedDefaults()
        #expect(SharedStore.loadPlanWindow(from: defaults) == .restOfDay)

        PlanWindowPreferenceStore(defaults: defaults, reloadWidgets: {}).window = .sixHours

        #expect(SharedStore.loadPlanWindow(from: defaults) == .sixHours)
    }

    @Test func changingThePlanWindowReloadsTheWidgets() {
        var reloads = 0
        let store = PlanWindowPreferenceStore(defaults: isolatedDefaults(), reloadWidgets: { reloads += 1 })

        store.window = .oneHour
        store.window = .oneHour

        #expect(reloads == 1)
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
            CardConfig(type: .location, isVisible: false),
            CardConfig(type: .plan, isVisible: true),
        ]

        #expect(CardPreferenceStore(defaults: defaults).visibleOrderedTypes == [.wearAndBring, .plan])
    }

    @Test func storedCardLayoutMissingCardsGetsThemAtTheirDefaultPositions() throws {
        let defaults = isolatedDefaults()
        let incomplete = [CardConfig(type: .weather, isVisible: true)]
        defaults.set(try JSONEncoder().encode(incomplete), forKey: "cardConfiguration")

        #expect(CardPreferenceStore(defaults: defaults).visibleOrderedTypes == [.plan, .weather, .location, .wearAndBring])
    }

    @Test func layoutSavedBeforeTheLocationCardKeepsItsOrderAndHiddenCards() throws {
        let defaults = isolatedDefaults()
        let saved = [
            CardConfig(type: .wearAndBring, isVisible: true),
            CardConfig(type: .weather, isVisible: false),
            CardConfig(type: .plan, isVisible: true),
        ]
        defaults.set(try JSONEncoder().encode(saved), forKey: "cardConfiguration")

        let cards = CardPreferenceStore(defaults: defaults).cards

        #expect(cards.map(\.type) == [.wearAndBring, .weather, .location, .plan])
        #expect(cards.map(\.isVisible) == [true, false, true, true])
    }

    @Test func storedCardLayoutListingACardTwiceFallsBackToTheDefaultLayout() throws {
        let defaults = isolatedDefaults()
        let duplicated = [CardConfig(type: .weather, isVisible: true), CardConfig(type: .weather, isVisible: false)]
        defaults.set(try JSONEncoder().encode(duplicated), forKey: "cardConfiguration")

        #expect(CardPreferenceStore(defaults: defaults).visibleOrderedTypes == [.plan, .weather, .location, .wearAndBring])
    }
}
