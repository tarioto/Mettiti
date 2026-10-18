import Foundation
import Testing
@testable import Mettiti

struct TemperatureUnitFormattingTests {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")

    @Test func fahrenheitInTheUSShowsJustTheDegreeSign() {
        #expect(TemperatureUnit.fahrenheit.formatted(fahrenheit: 72.4, locale: us) == "72°")
    }

    @Test func celsiusInGermanyUsesGermanFormatting() {
        // 72°F = 22.2°C
        #expect(TemperatureUnit.celsius.formatted(fahrenheit: 72, locale: germany) == "22 °C")
    }

    @Test func justBelowFreezingRoundsToZeroWithoutAMinusSign() {
        // 31.5°F = -0.28°C
        #expect(TemperatureUnit.celsius.formatted(fahrenheit: 31.5, locale: germany) == "0 °C")
    }

    @Test(arguments: [
        ("en_US", TemperatureUnit.fahrenheit),
        ("de_DE", .celsius),
        ("en_GB", .celsius),
        // Settings > General > Language & Region > Temperature Unit overrides the region's default.
        ("en_US@mu=celsius", .celsius),
        ("de_DE@mu=fahrenhe", .fahrenheit),
    ])
    func systemFollowsTheLocalesTemperatureUnit(localeID: String, expected: TemperatureUnit) {
        #expect(TemperatureUnit.system.resolved(for: Locale(identifier: localeID)) == expected)
    }

    @Test func anExplicitUnitIgnoresTheLocale() {
        #expect(TemperatureUnit.celsius.resolved(for: us) == .celsius)
        #expect(TemperatureUnit.fahrenheit.resolved(for: germany) == .fahrenheit)
    }

    @Test func systemFormatsInTheLocalesUnit() {
        #expect(TemperatureUnit.system.formatted(fahrenheit: 72, locale: germany) == "22 °C")
        #expect(TemperatureUnit.system.formatted(fahrenheit: 72, locale: us) == "72°")
    }

    @Test func highAndLowUseTheLocalesTemperatureFormat() {
        // 72°F = 22.2°C, 58°F = 14.4°C
        #expect(TemperatureUnit.fahrenheit.formattedHighLow(highFahrenheit: 72, lowFahrenheit: 58, locale: us) == "H:72° L:58°")
        #expect(TemperatureUnit.celsius.formattedHighLow(highFahrenheit: 72, lowFahrenheit: 58, locale: germany) == "H:22 °C L:14 °C")
    }

    @Test func halfDegreesRoundAwayFromZero() {
        // 33°F = 0.56°C -> 1, 0°F = -17.8°C -> -18, 72.5°F -> 73
        #expect(TemperatureUnit.celsius.formatted(fahrenheit: 33, locale: germany) == "1 °C")
        #expect(TemperatureUnit.celsius.formatted(fahrenheit: 0, locale: germany) == "-18 °C")
        #expect(TemperatureUnit.fahrenheit.formatted(fahrenheit: 72.5, locale: us) == "73°")
    }
}
