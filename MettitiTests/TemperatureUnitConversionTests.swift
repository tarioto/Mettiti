import Foundation
import Testing
@testable import Mettiti

struct TemperatureUnitConversionTests {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")

    @Test func celsiusConvertsFromFahrenheit() {
        #expect(TemperatureUnit.celsius.convert(fromFahrenheit: 212, locale: us) == 100)
        #expect(TemperatureUnit.celsius.convert(fromFahrenheit: 32, locale: us) == 0)
        #expect(TemperatureUnit.celsius.convert(fromFahrenheit: -40, locale: us) == -40)
    }

    @Test func fahrenheitIsLeftAsIs() {
        #expect(TemperatureUnit.fahrenheit.convert(fromFahrenheit: 72.4, locale: germany) == 72.4)
    }

    @Test func systemConvertsToTheLocalesUnit() {
        #expect(TemperatureUnit.system.convert(fromFahrenheit: 212, locale: germany) == 100)
        #expect(TemperatureUnit.system.convert(fromFahrenheit: 72.4, locale: us) == 72.4)
    }
}
