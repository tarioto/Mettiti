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
