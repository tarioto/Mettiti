import Testing
@testable import Mettiti

struct WMOWeatherCodeTests {
    @Test(arguments: [
        (0, "Clear sky", "sun.max.fill"),
        (2, "Partly cloudy", "cloud.sun.fill"),
        (48, "Foggy", "cloud.fog.fill"),
        (63, "Rain", "cloud.rain.fill"),
        (82, "Rain showers", "cloud.heavyrain.fill"),
        (75, "Snow", "cloud.snow.fill"),
        (99, "Thunderstorm with hail", "cloud.bolt.rain.fill"),
    ])
    func eachCodeHasADescriptionAndSymbol(code: Int, description: String, symbol: String) {
        #expect(WMOWeatherCode.description(for: code) == description)
        #expect(WMOWeatherCode.symbolName(for: code) == symbol)
    }

    @Test func intensitiesOfTheSameConditionShareADescription() {
        // Light, moderate and heavy rain are 61, 63 and 65.
        #expect(WMOWeatherCode.description(for: 61) == "Rain")
        #expect(WMOWeatherCode.description(for: 65) == "Rain")
    }

    @Test func freezingDrizzleIsDescribedApartFromDrizzleButSharesItsSymbol() {
        #expect(WMOWeatherCode.description(for: 56) == "Freezing drizzle")
        #expect(WMOWeatherCode.description(for: 51) == "Drizzle")
        #expect(WMOWeatherCode.symbolName(for: 56) == "cloud.drizzle.fill")
        #expect(WMOWeatherCode.symbolName(for: 51) == "cloud.drizzle.fill")
    }

    @Test(arguments: [4, 50, 100, -1])
    func codesOutsideTheWMOTableAreUnknown(code: Int) {
        #expect(WMOWeatherCode.description(for: code) == "Unknown conditions")
        #expect(WMOWeatherCode.symbolName(for: code) == "questionmark.circle")
    }
}
