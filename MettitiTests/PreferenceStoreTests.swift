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

    @Test func customLocationKeepsItsTimeZoneAcrossLaunches() {
        let defaults = isolatedDefaults()
        LocationPreferenceStore(defaults: defaults, sharedDefaults: isolatedDefaults(), reloadWidgets: {}).selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)

        let relaunched = LocationPreferenceStore(defaults: defaults, sharedDefaults: isolatedDefaults(), reloadWidgets: {})

        #expect(relaunched.selection.calendar(fallback: gregorianCalendar(in: pacific)).timeZone == tokyo)
    }

    @Test func locationSavedBeforeTimeZonesStillLoadsAndEqualsTheSameCityWithOne() throws {
        let old = Data(#"{"custom":{"name":"Tokyo","latitude":35.7,"longitude":139.7}}"#.utf8)

        let decoded = try JSONDecoder().decode(LocationSelection.self, from: old)

        #expect(decoded == .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo))
        #expect(decoded.calendar(fallback: gregorianCalendar(in: pacific)).timeZone == pacific)
        let current = try JSONDecoder().decode(LocationSelection.self, from: Data(#"{"currentLocation":{}}"#.utf8))
        #expect(current == .currentLocation)
    }

    @Test func locationWithAnUnknownTimeZoneStillLoads() throws {
        let data = Data(#"{"custom":{"name":"Tokyo","latitude":35.7,"longitude":139.7,"timeZone":"Not/AZone"}}"#.utf8)

        let decoded = try JSONDecoder().decode(LocationSelection.self, from: data)

        #expect(decoded == .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7))
    }

    @Test func selectionIsSharedWithTheWidgetsWhenItChangesAndAtLaunch() {
        let defaults = isolatedDefaults()
        let shared = isolatedDefaults()
        var reloads = 0
        let tokyoSelection = LocationSelection.custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        // Saved by an earlier version, which didn't share it.
        StoredPreference<LocationSelection>.json("locationSelection", in: defaults).save(tokyoSelection)
        #expect(SharedStore.loadLocationSelection(from: shared) == nil)

        let store = LocationPreferenceStore(defaults: defaults, sharedDefaults: shared, reloadWidgets: { reloads += 1 })
        #expect(SharedStore.loadLocationSelection(from: shared) == tokyoSelection)

        store.selection = .currentLocation

        #expect(SharedStore.loadLocationSelection(from: shared) == .currentLocation)
        #expect(reloads == 1)
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
