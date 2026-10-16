import Foundation
import Testing
@testable import Mettiti

struct OutfitAdvisorPromptTests {
    private let weather = DailyWeather(
        date: .now,
        highTemperatureF: 72,
        lowTemperatureF: 58,
        precipitationProbability: 20,
        uvIndex: 5,
        windSpeedMph: 8,
        conditionCode: 1,
        conditionDescription: "Partly Cloudy"
    )

    @Test func celsiusPromptStatesHighAndLowInCelsius() {
        let prompt = OutfitAdvisor.prompt(for: weather, unit: .celsius)

        // 72°F = 22.2°C, 58°F = 14.4°C
        #expect(prompt.contains("High: 22°C"))
        #expect(prompt.contains("Low: 14°C"))
        #expect(!prompt.contains("°F"))
    }

    @Test func fahrenheitPromptStatesHighAndLowInFahrenheit() {
        let prompt = OutfitAdvisor.prompt(for: weather, unit: .fahrenheit)

        #expect(prompt.contains("High: 72°F"))
        #expect(prompt.contains("Low: 58°F"))
        #expect(!prompt.contains("°C"))
    }

    @Test func celsiusPromptRoundsLikeTheOnScreenForecast() {
        let freezing = DailyWeather(
            date: .now,
            highTemperatureF: 33,
            lowTemperatureF: 0,
            precipitationProbability: 0,
            uvIndex: 1,
            windSpeedMph: 3,
            conditionCode: 0,
            conditionDescription: "Clear sky"
        )

        let prompt = OutfitAdvisor.prompt(for: freezing, unit: .celsius)

        // 33°F = 0.56°C -> 1, 0°F = -17.8°C -> -18 (matches TemperatureUnit.displayString)
        #expect(prompt.contains("High: 1°C"))
        #expect(prompt.contains("Low: -18°C"))
        #expect(TemperatureUnit.celsius.displayString(fromFahrenheit: 33) == "1°")
        #expect(TemperatureUnit.celsius.displayString(fromFahrenheit: 0) == "-18°")
    }

    @Test func instructionsTellTheModelNotToQuoteTemperatureNumbers() {
        let instructions = OutfitAdvisor.instructions.lowercased()

        #expect(instructions.contains("never quote numeric temperatures"))
        #expect(instructions.contains("summary"))
        #expect(instructions.contains("reason"))
    }
}
