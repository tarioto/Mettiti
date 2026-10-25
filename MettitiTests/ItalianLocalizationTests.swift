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
        "Checking today's weather…",
        "Putting together today's outfit…",
        "Updating…",
    ]

    @Test(arguments: errorAndStatusMessages)
    func errorOrStatusMessageIsInItalian(_ key: String) {
        let text = localized(key, table: nil, language: "it")
        #expect(text != "<missing>", "\(key) has no Italian translation")
        #expect(text != key)
    }

    @Test func serviceErrorsDescribeThemselvesWithTheirLocalizedText() {
        #expect(WeatherServiceError.decodingFailed.localizedDescription == String(localized: "Received an unexpected response from the weather service."))
        #expect(AppleWeatherServiceError.missingForecast.localizedDescription == String(localized: "Apple Weather didn't return a forecast for today."))
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

    @Test func homeTitleAndRefreshAreInItalian() {
        #expect(localized("Today", table: nil, language: "it") == "Oggi")
        #expect(localized("Refresh", table: nil, language: "it") == "Aggiorna")
        #expect(localized("Settings", table: nil, language: "it") == "Impostazioni")
    }
}
