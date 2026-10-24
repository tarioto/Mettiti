import Foundation
import Testing
@testable import Mettiti

struct ItalianLocalizationTests {
    private var appBundle: Bundle { Bundle(for: DayPlanViewModel.self) }

    private func localized(_ key: String, table: String?, language: String) -> String {
        guard let path = appBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return "<no \(language).lproj>" }
        return bundle.localizedString(forKey: key, value: "<missing>", table: table)
    }

    @Test func italianIsABundledLocalization() {
        #expect(appBundle.localizations.contains("it"))
    }

    @Test func locationPermissionPromptIsInItalian() {
        let text = localized("NSLocationWhenInUseUsageDescription", table: "InfoPlist", language: "it")
        #expect(text.hasPrefix("Mettiti usa la tua posizione"))
    }

    private func italian(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = Locale(identifier: "it")
        return String(localized: resource)
    }

    @Test func settingsStaticTextIsInItalian() {
        let keys = [
            "Location", "Weather Location", "Weather Source", "Plan Window", "Temperature Unit",
            "Forecast", "Theme", "Light/Dark", "App Icon", "Cards", "Appearance",
            "Current Location", "City name",
            "Plan Window is how far ahead from now the outfit advice covers. Rest of day runs until midnight, but at least 3 hours.",
            "Apple Weather uses the same data as the Weather app. With either source, the hourly chart's shaded band shows the forecast spread from Open-Meteo's ensemble.",
            "The theme color is used for the main screen's background. Cards sets which cards the main screen shows, and in what order.",
            "Search for a city to see its weather instead of your current location.",
            "Couldn't find that location. Try a different search.",
            "Drag to reorder. Turn off a card to hide it from the main screen.",
        ]
        for key in keys {
            let text = localized(key, table: nil, language: "it")
            #expect(text != key && text != "<missing>", "\(key)")
        }
    }

    @Test func modelLabelsAreInItalian() {
        #expect(italian(AppTheme.sunset.label) == "Tramonto")
        #expect(italian(AppTheme.none.label) == "Predefinito")
        #expect(italian(AppAppearance.dark.label) == "Scuro")
        #expect(italian(CardType.wearAndBring.title) == "Cosa indossare e portare")
        #expect(italian(TemperatureUnit.system.label) == "Sistema")
        #expect(italian(WeatherProvider.apple.label) == "Apple Meteo")
        #expect(italian(ThemeIcon.ocean.label) == "Oceano")
        #expect(localized("Rest of day", table: "Shared", language: "it") == "Resto della giornata")
        #expect(localized("Next 3 hours", table: "Shared", language: "it") == "Prossime 3 ore")
    }

    @Test func alternateIconIdentifiersStayEnglish() {
        #expect(ThemeIcon.ocean.alternateIconName == "AppIcon-Ocean")
        #expect(ThemeIcon.ocean.thumbnailName == "IconThumbnail-Ocean")
    }

    @Test func homeTitleAndRefreshAreInItalian() {
        #expect(localized("Today", table: nil, language: "it") == "Oggi")
        #expect(localized("Refresh", table: nil, language: "it") == "Aggiorna")
        #expect(localized("Settings", table: nil, language: "it") == "Impostazioni")
    }
}
