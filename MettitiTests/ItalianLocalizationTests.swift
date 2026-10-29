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

    /// The English text of every error and status message the user can see. Each one reaches the
    /// screen through `String(localized:)`, `LocalizedError` or a localized `Text`.
    private static let errorAndStatusMessages = [
        "Couldn't reach the weather service. Check your connection and try again.",
        "Received an unexpected response from the weather service.",
        "Couldn't reach Apple Weather. Check your connection, or switch to Open-Meteo in Settings.",
        "Apple Weather didn't return a forecast for today.",
        "Location access is off. Enable it in Settings to get weather for your area.",
        "Location unavailable",
        "Couldn't determine your location. Check your connection and try again.",
        "Couldn't find your location right now. Try again, or set a location in Settings.",
        "Something went wrong. Try again.",
        "You're offline. Check your connection and try again.",
        "The weather service is taking too long to respond. Try again in a moment.",
        "Apple Intelligence is busy right now. Try again in a moment.",
        "Apple Intelligence is still getting ready. Try again soon.",
        "Outfit suggestions aren't available in your language yet.",
        "Couldn't come up with outfit suggestions this time.",
        "Outfit suggestions need a device that supports Apple Intelligence.",
        "Turn on Apple Intelligence to get outfit suggestions.",
        "AI recommendations aren't available right now.",
        "This device doesn't support Apple Intelligence.",
        "Turn on Apple Intelligence in Settings to get AI recommendations.",
        "The on-device model is still downloading. Try again shortly.",
        "Couldn't find that location. Try a different search.",
        "Try Again",
        "Showing the plan saved earlier today.",
        "No outfit suggestions right now.",
        "Loading",
    ]

    @Test(arguments: errorAndStatusMessages)
    func errorOrStatusMessageIsInItalian(_ key: String) {
        let text = localized(key, table: nil, language: "it")
        #expect(text != "<missing>", "\(key) has no Italian translation")
        #expect(text != key)
    }

    @Test func serviceErrorsDescribeThemselvesWithTheirLocalizedText() {
        for (message, key) in [
            (WeatherServiceError.decodingFailed.message, "Received an unexpected response from the weather service."),
            (AppleWeatherServiceError.missingForecast.message, "Apple Weather didn't return a forecast for today."),
        ] {
            let text = italian(message)
            #expect(text == localized(key, table: nil, language: "it"))
            #expect(text != key, "\(key) has no Italian translation")
        }
        // The error's own description is that same message in the running language.
        #expect(WeatherServiceError.decodingFailed.localizedDescription == String(localized: WeatherServiceError.decodingFailed.message))
    }

    /// The widget extension's own bundle, which holds the gallery names and descriptions.
    private func widgetItalian() throws -> Bundle {
        let plugIns = try #require(appBundle.builtInPlugInsURL)
        let appex = try #require(FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil).first { $0.pathExtension == "appex" })
        let path = try #require(Bundle(url: appex)?.path(forResource: "it", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test(arguments: [
        ("Today's Summary", "Riepilogo di oggi"),
        ("Today's Emojis", "Emoji di oggi"),
        ("Today's Full Plan", "Piano completo di oggi"),
        ("A short text summary of what to wear and bring today.", "Un breve riepilogo di cosa indossare e portare oggi."),
        ("A quick emoji glance at what to wear and bring today.", "Un colpo d'occhio con emoji su cosa indossare e portare oggi."),
        ("Weather, summary, and everything to wear and bring today.", "Meteo, riepilogo e tutto ciò che serve indossare e portare oggi."),
        ("Open Mettiti", "Apri Mettiti"),
        ("Open Mettiti to update", "Apri Mettiti per aggiornare"),
    ])
    func widgetNamesDescriptionsAndPromptsAreInItalian(key: String, expected: String) throws {
        #expect(try widgetItalian().localizedString(forKey: key, value: "<missing>", table: nil) == expected)
    }

    @Test func aSavedConditionIsNamedInTheCurrentLanguageWithoutFetchingAgain() throws {
        var weather = DailyWeather.placeholder
        weather.condition = .wmo(61)
        // Saved while the app was in English...
        let saved = try JSONEncoder().encode(PlanSnapshot(weather: weather, recommendation: nil, generatedAt: .now, provider: .openMeteo))
        let decoded = try JSONDecoder().decode(PlanSnapshot.self, from: saved)
        // ...and shown in Italian, from the stored kind alone.
        #expect(decoded.weather.conditionDescription(in: Locale(identifier: "it")) == "Pioggia")
        #expect(decoded.weather.conditionDescription(in: Locale(identifier: "en")) == "Rain")
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

    @Test(arguments: [0, 1, 2, 3, 45, 51, 56, 61, 66, 71, 77, 80, 85, 95, 96, 999])
    func everyWeatherConditionNameIsInItalian(_ code: Int) {
        let english = WMOWeatherCode.description(for: code)
        let text = localized(english, table: "Shared", language: "it")
        #expect(text != "<missing>" && text != english, "\(english) has no Italian translation")
    }

    @Test func alternateIconIdentifiersStayEnglish() {
        #expect(ThemeIcon.ocean.alternateIconName == "AppIcon-Ocean")
        #expect(ThemeIcon.ocean.thumbnailName == "IconThumbnail-Ocean")
    }

    // A localized InfoPlist entry overrides Info.plist, and a language with no value falls back to
    // the key itself, so an English device once showed "CFBundleDisplayName" as the app's name.
    @Test func noLanguageRenamesTheApp() {
        for path in appBundle.paths(forResourcesOfType: "lproj", inDirectory: nil) {
            let name = Bundle(path: path)?.localizedString(forKey: "CFBundleDisplayName", value: "<missing>", table: "InfoPlist")
            #expect(name == "<missing>", "\(path) renames the app to \(name ?? "")")
        }
    }

    @Test func locationPermissionPromptIsInEnglish() {
        let text = localized("NSLocationWhenInUseUsageDescription", table: "InfoPlist", language: "en")
        #expect(text.hasPrefix("Mettiti uses your location"))
    }

    @Test func refreshAndSettingsAreInItalian() {
        #expect(localized("Refresh", table: nil, language: "it") == "Aggiorna")
        #expect(localized("Settings", table: nil, language: "it") == "Impostazioni")
    }
}
