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

    @Test func homeTitleAndRefreshAreInItalian() {
        #expect(localized("Today", table: nil, language: "it") == "Oggi")
        #expect(localized("Refresh", table: nil, language: "it") == "Aggiorna")
        #expect(localized("Settings", table: nil, language: "it") == "Impostazioni")
    }
}
