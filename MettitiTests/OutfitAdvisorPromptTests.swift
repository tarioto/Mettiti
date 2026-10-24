import Foundation
import Testing
@testable import Mettiti

struct OutfitAdvisorPromptTests {
    /// The whole day peaked at UV 7 and a 90% chance of rain, but that was earlier.
    private let weather = DailyWeather(
        date: date("2026-10-09T07:00:00Z"),
        highTemperatureF: 80,
        lowTemperatureF: 50,
        precipitationProbability: 90,
        uvIndex: 7,
        windSpeedMph: 20,
        conditionCode: 1,
        conditionDescription: "Partly Cloudy"
    )

    /// 4 PM to 11 PM PDT: sunny and mild, then dark and cooler after a 6:30 PM sunset.
    private let hourly = HourlyForecast(
        timeZone: pacific,
        points: [
            hour("2026-10-09T23:00:00Z", temperature: 72, rain: 0, uv: 5, wind: 6, code: 0, daylight: true),   // 4 PM
            hour("2026-10-10T00:00:00Z", temperature: 70, rain: 0, uv: 3, wind: 7, code: 0, daylight: true),   // 5 PM
            hour("2026-10-10T01:00:00Z", temperature: 66, rain: 10, uv: 1, wind: 8, code: 2, daylight: true),  // 6 PM
            hour("2026-10-10T02:00:00Z", temperature: 62, rain: 20, uv: 0, wind: 11, code: 3, daylight: false), // 7 PM
            hour("2026-10-10T03:00:00Z", temperature: 60, rain: 10, uv: 0, wind: 9, code: 3, daylight: false), // 8 PM
            hour("2026-10-10T04:00:00Z", temperature: 59, rain: 0, uv: 0, wind: 8, code: 2, daylight: false),  // 9 PM
            hour("2026-10-10T05:00:00Z", temperature: 58, rain: 0, uv: 0, wind: 6, code: 1, daylight: false),  // 10 PM
            hour("2026-10-10T06:00:00Z", temperature: 58, rain: 0, uv: 0, wind: 5, code: 1, daylight: false),  // 11 PM
        ],
        sunEvents: [SunEvent(kind: .sunset, date: date("2026-10-10T01:30:00Z"))]
    )

    private let afternoon = date("2026-10-09T23:20:00Z") // 4:20 PM PDT
    private let evening = date("2026-10-10T03:05:00Z")   // 8:05 PM PDT

    private func restOfDay(from now: Date) -> PlanSpan {
        PlanSpan(window: .restOfDay, startingAt: now, timeZone: pacific)
    }

    @Test func promptStatesTheCurrentTimeAndTheSpan() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .fahrenheit)

        #expect(prompt.contains("Current local time: 4:20 PM"))
        #expect(prompt.contains("from now until 12:00 AM"))
    }

    @Test func promptListsEachHourWithItsWeatherAndWhetherItsDayOrNight() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .fahrenheit)

        #expect(prompt.contains("- 4 PM: 72°F (warm), Clear sky, 0% chance of precipitation, UV index 5, wind 6 mph, daylight"))
        #expect(prompt.contains("- 7 PM: 62°F (mild), Overcast, 20% chance of precipitation, UV index 0, wind 11 mph, dark"))
    }

    @Test func promptSummarizesTheSpanInsteadOfTheWholeDay() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .fahrenheit)

        #expect(prompt.contains("High: 72°F (warm) at 4 PM, Low: 58°F (cool) at 10 PM"))
        #expect(prompt.contains("Highest chance of precipitation: 20% at 7 PM"))
        #expect(prompt.contains("Sunset at 6:30 PM"))
        #expect(prompt.contains("Daylight UV index peaks at 5 at 4 PM"))
        #expect(!prompt.contains("80°F"))
        #expect(!prompt.contains("90%"))
        #expect(!prompt.contains("UV index: 7"))
    }

    @Test func promptCoversOnlyTheChosenWindow() {
        let span = PlanSpan(window: .threeHours, startingAt: afternoon, timeZone: pacific)

        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: span, unit: .fahrenheit)

        // 4:20 to 7:20 PM, so the 7 PM hour is in progress at the end.
        #expect(prompt.contains("Forecast from now until 7:20 PM"))
        #expect(prompt.contains("- 7 PM: 62°F"))
        #expect(!prompt.contains("- 8 PM:"))
        #expect(prompt.contains("High: 72°F (warm) at 4 PM, Low: 62°F (mild) at 7 PM"))
        #expect(prompt.contains("Recommend what to wear and bring from now until 7:20 PM."))
    }

    @Test func promptAfterSunsetSaysTheSunIsDownForTheWholeSpan() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: evening), unit: .fahrenheit)

        #expect(prompt.contains("Current local time: 8:05 PM. The sun is down."))
        #expect(prompt.contains("No daylight hours in this forecast, so sun protection isn't needed."))
        #expect(!prompt.contains("UV index peaks"))
        #expect(!prompt.contains("Sunset"))
    }

    @Test func promptWithLowDaylightUVSaysSunProtectionIsntNeeded() {
        let hazy = HourlyForecast(timeZone: pacific, points: [
            hour("2026-10-09T23:00:00Z", temperature: 70, rain: 0, uv: 2, wind: 5, code: 3, daylight: true),
            hour("2026-10-10T00:00:00Z", temperature: 68, rain: 0, uv: 1, wind: 5, code: 3, daylight: true),
        ])

        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hazy, span: restOfDay(from: afternoon), unit: .fahrenheit)

        #expect(prompt.contains("Daylight UV index stays low, so sun protection isn't needed."))
    }

    @Test func promptWithoutAnHourlyForecastFallsBackToTheWholeDayWithoutItsPeakUV() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: nil, span: restOfDay(from: afternoon), unit: .fahrenheit)

        #expect(prompt.contains("Current local time: 4:20 PM"))
        #expect(prompt.contains("High: 80°F (warm), Low: 50°F (cool)"))
        #expect(!prompt.contains("UV"))
    }

    @Test func aWarmNightIsStillDescribedAsHot() {
        let tropical = HourlyForecast(timeZone: pacific, points: [
            hour("2026-10-10T03:00:00Z", temperature: 86, rain: 0, uv: 0, wind: 4, code: 0, daylight: false),
            hour("2026-10-10T04:00:00Z", temperature: 84, rain: 0, uv: 0, wind: 3, code: 0, daylight: false),
        ])

        let prompt = OutfitAdvisor.prompt(for: weather, hourly: tropical, span: restOfDay(from: evening), unit: .celsius)

        // 86°F = 30°C, 84°F = 29°C
        #expect(prompt.contains("High: 30°C (hot) at 8 PM, Low: 29°C (hot) at 9 PM"))
        #expect(prompt.contains("- 8 PM: 30°C (hot), Clear sky"))
    }

    /// Bangkok in the evening: thunderstorms, cooling off from hot to warm, never cooler.
    private let bangkokEvening = HourlyForecast(timeZone: pacific, points: [
        hour("2026-10-10T03:00:00Z", temperature: 86, rain: 60, uv: 0, wind: 6, code: 95, daylight: false),
        hour("2026-10-10T04:00:00Z", temperature: 81, rain: 40, uv: 0, wind: 5, code: 95, daylight: false),
        hour("2026-10-10T05:00:00Z", temperature: 78, rain: 20, uv: 0, wind: 4, code: 3, daylight: false),
    ])

    @Test func promptSaysNoWarmLayerIsNeededWhenItsWarmThroughout() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: bangkokEvening, span: restOfDay(from: evening), unit: .fahrenheit)

        #expect(prompt.contains("- Coldest it gets: warm, so no jacket, sweater or other warm layer is needed."))
    }

    @Test func promptDoesntRuleOutAWarmLayerWhenItGetsMildOrColder() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .fahrenheit)

        #expect(!prompt.contains("Coldest it gets"))
    }

    @Test func wholeDayPromptSaysNoWarmLayerIsNeededForAWarmDay() {
        let tropicalDay = DailyWeather(date: date("2026-10-09T07:00:00Z"), highTemperatureF: 90, lowTemperatureF: 79, precipitationProbability: 70, uvIndex: 8, windSpeedMph: 5, conditionCode: 95, conditionDescription: "Thunderstorm")

        let prompt = OutfitAdvisor.prompt(for: tropicalDay, hourly: nil, span: restOfDay(from: afternoon), unit: .celsius)

        // 79°F = 26°C
        #expect(prompt.contains("Low: 26°C (warm)\n- Coldest it gets: warm, so no jacket"))
    }

    @Test func recommendationForAWarmEveningDropsWarmLayersButKeepsRainGear() {
        let suggested = OutfitRecommendation(summary: "Stormy and warm.", items: [
            RecommendedItem(emoji: "👕", name: "Light jacket", reason: "Warmth is moderate in the morning."),
            RecommendedItem(emoji: "☂️", name: "Umbrella", reason: "Thunderstorms are expected."),
            RecommendedItem(emoji: "🧥", name: "Raincoat", reason: "Heavy showers."),
            RecommendedItem(emoji: "🧥", name: "Rain jacket", reason: "Heavy showers."),
            RecommendedItem(emoji: "🧥", name: "Waterproof jacket", reason: "Heavy showers."),
            RecommendedItem(emoji: "🧥", name: "Storm jacket", reason: "Heavy showers."),
            RecommendedItem(emoji: "🧥", name: "Rainproof jacket", reason: "Heavy showers."),
            RecommendedItem(emoji: "🧥", name: "Trench coat", reason: "Heavy showers."),
            RecommendedItem(emoji: "🧥", name: "Poncho", reason: "Heavy showers."),
            RecommendedItem(emoji: "🧥", name: "Heavy jacket", reason: "Temperature cools off after 7 PM."),
            RecommendedItem(emoji: "🧶", name: "Sweater", reason: "Cooler evening."),
            RecommendedItem(emoji: "🧥", name: "Fleeces", reason: "Cooler evening."),
            RecommendedItem(emoji: "🧶", name: "Cardigans", reason: "Cooler evening."),
            RecommendedItem(emoji: "🧥", name: "Parkas", reason: "Cooler evening."),
            RecommendedItem(emoji: "👕", name: "Light layer", reason: "Cooler evening."),
            RecommendedItem(emoji: "👕", name: "Layers", reason: "Cooler evening."),
            RecommendedItem(emoji: "👕", name: "Long sleeves", reason: "Cooler evening."),
            RecommendedItem(emoji: "👕", name: "Long-sleeved shirt", reason: "Cooler evening."),
            RecommendedItem(emoji: "🧥", name: "Training jacket", reason: "Cooler evening."),
            RecommendedItem(emoji: "🦺", name: "Vest", reason: "Cooler evening."),
            RecommendedItem(emoji: "👕", name: "Short-sleeve shirt", reason: "Warm all evening."),
        ])

        let checked = OutfitAdvisor.request(for: weather, hourly: bangkokEvening, span: restOfDay(from: evening), unit: .fahrenheit).droppingWarmLayersIfWarmThroughout(suggested)

        #expect(checked.items.map(\.name) == ["Umbrella", "Raincoat", "Rain jacket", "Waterproof jacket", "Storm jacket", "Rainproof jacket", "Trench coat", "Poncho", "Short-sleeve shirt"])
        #expect(checked.summary == "Stormy and warm.")
    }

    @Test func recommendationForACoolEveningKeepsItsJacket() {
        let suggested = OutfitRecommendation(summary: "", items: [
            RecommendedItem(emoji: "🧥", name: "Light jacket", reason: "Cooler after sunset."),
        ])

        let checked = OutfitAdvisor.request(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .fahrenheit).droppingWarmLayersIfWarmThroughout(suggested)

        #expect(checked.items.map(\.name) == ["Light jacket"])
    }

    @Test func instructionsOnlyAllowWarmLayersWhenSomeHourFeelsMildOrColder() {
        let instructions = OutfitAdvisor.instructions.lowercased()

        #expect(instructions.contains("only suggest a jacket, sweater or other warm layer when some hour feels mild or colder"))
    }

    @Test func temperaturesThatReadTheSameFeelTheSame() {
        let nearTheEdge = HourlyForecast(timeZone: pacific, points: [
            hour("2026-10-10T03:00:00Z", temperature: 46.4, rain: 0, uv: 0, wind: 4, code: 0, daylight: false),
            hour("2026-10-10T04:00:00Z", temperature: 45.9, rain: 0, uv: 0, wind: 4, code: 0, daylight: false),
        ])

        let prompt = OutfitAdvisor.prompt(for: weather, hourly: nearTheEdge, span: restOfDay(from: evening), unit: .celsius)

        // Both are 8°C once rounded.
        #expect(prompt.contains("- 8 PM: 8°C (cool),"))
        #expect(prompt.contains("- 9 PM: 8°C (cool),"))
    }

    @Test func wholeDayPromptInTheEveningSaysItsDark() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: nil, span: restOfDay(from: evening), unit: .fahrenheit)

        #expect(prompt.contains("Current local time: 8:05 PM. It's dark outside, so sun protection isn't needed."))
        #expect(prompt.contains("Today's forecast, including the hours that have passed:"))
        #expect(prompt.contains("Recommend what to wear and bring for the rest of tonight."))
    }

    @Test func wholeDayPromptInTheAfternoonDoesntSayItsDark() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: nil, span: restOfDay(from: afternoon), unit: .fahrenheit)

        #expect(!prompt.contains("dark"))
    }

    @Test func celsiusPromptStatesTemperaturesInCelsius() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .celsius)

        // 72°F = 22.2°C, 58°F = 14.4°C
        #expect(prompt.contains("High: 22°C (warm) at 4 PM, Low: 14°C (cool) at 10 PM"))
        #expect(prompt.contains("- 4 PM: 22°C (warm),"))
        #expect(!prompt.contains("°F"))
    }

    @Test func systemUnitPromptUsesTheLocalesUnitButStaysInPromptFormat() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .system, locale: Locale(identifier: "de_DE"))

        // Germany uses Celsius and a 24-hour clock, but the prompt is English text for the model,
        // so no German "22 °C" spacing or "16 Uhr".
        #expect(prompt.contains("High: 22°C (warm) at 4 PM, Low: 14°C (cool) at 10 PM"))
    }

    @Test func celsiusPromptRoundsLikeTheOnScreenForecast() {
        let freezing = HourlyForecast(timeZone: pacific, points: [
            hour("2026-10-09T23:00:00Z", temperature: 33, rain: 0, uv: 0, wind: 3, code: 0, daylight: true),
            hour("2026-10-10T00:00:00Z", temperature: 0, rain: 0, uv: 0, wind: 3, code: 0, daylight: true),
        ])

        let prompt = OutfitAdvisor.prompt(for: weather, hourly: freezing, span: restOfDay(from: afternoon), unit: .celsius)

        // 33°F = 0.56°C -> 1, 0°F = -17.8°C -> -18 (matches TemperatureUnit.formatted)
        let us = Locale(identifier: "en_US")
        #expect(prompt.contains("High: 1°C (cold) at 4 PM, Low: -18°C (freezing) at 5 PM"))
        #expect(TemperatureUnit.celsius.formatted(fahrenheit: 33, locale: us) == "1°C")
        #expect(TemperatureUnit.celsius.formatted(fahrenheit: 0, locale: us) == "-18°C")
    }

    @Test func instructionsTellTheModelNotToQuoteTemperatureNumbers() {
        let instructions = OutfitAdvisor.instructions.lowercased()

        #expect(instructions.contains("never quote numeric temperatures"))
        #expect(instructions.contains("summary"))
        #expect(instructions.contains("reason"))
    }

    @Test func instructionsOnlyAllowSunProtectionForMeaningfulDaylightUV() {
        let instructions = OutfitAdvisor.instructions.lowercased()

        #expect(!instructions.contains("always consider sun protection"))
        #expect(instructions.contains("only suggest sun protection"))
        #expect(instructions.contains("daylight"))
    }

    @Test func instructionsBaseClothingOnHowTheTemperatureFeels() {
        let instructions = OutfitAdvisor.instructions.lowercased()

        #expect(instructions.contains("how it feels"))
    }

    @Test func instructionsAskForChangesInWordsRatherThanAnAverage() {
        let instructions = OutfitAdvisor.instructions.lowercased()

        #expect(instructions.contains("describe the change in words"))
        #expect(instructions.contains("instead of averaging"))
    }

    // MARK: Response language and wind unit

    private let supportsItalian: (Locale) -> Bool = { $0.language.languageCode?.identifier == "it" }

    @Test func responseLanguageFollowsTheAppsLocalization() {
        #expect(OutfitAdvisor.responseLanguage(appLanguages: ["it"], supports: supportsItalian) == "Italian")
    }

    @Test func responseLanguageFallsBackToEnglishWhenTheModelDoesntSupportIt() {
        #expect(OutfitAdvisor.responseLanguage(appLanguages: ["it"], supports: { _ in false }) == "English")
        #expect(OutfitAdvisor.responseLanguage(appLanguages: [], supports: supportsItalian) == "English")
    }

    @Test func promptAsksForTheResponseLanguage() {
        let italian = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .fahrenheit, language: "Italian")
        let wholeDay = OutfitAdvisor.prompt(for: weather, hourly: nil, span: restOfDay(from: afternoon), unit: .fahrenheit, language: "Italian")
        let fallback = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .fahrenheit)

        #expect(italian.contains(OutfitAdvisor.responseLanguageLine("Italian")))
        #expect(wholeDay.contains(OutfitAdvisor.responseLanguageLine("Italian")))
        #expect(fallback.contains(OutfitAdvisor.responseLanguageLine("English")))
        #expect(!fallback.contains("Italian"))
        #expect(OutfitAdvisor.sessionInstructions(language: "Italian").contains("Respond in Italian"))
    }

    @Test func windSpeedIsInKilometersPerHourWhereTheLocaleDoesntUseMiles() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: hourly, span: restOfDay(from: afternoon), unit: .system, locale: Locale(identifier: "it_IT"))

        // 11 mph = 17.7 km/h; 20 mph = 32.2 km/h
        #expect(prompt.contains("wind 10 km/h"))
        #expect(prompt.contains("wind 18 km/h"))
        #expect(!prompt.contains("mph"))
    }

    @Test func windSpeedStaysInMilesPerHourInTheUS() {
        let prompt = OutfitAdvisor.prompt(for: weather, hourly: nil, span: restOfDay(from: afternoon), unit: .system, locale: Locale(identifier: "en_US"))

        #expect(prompt.contains("Wind: 20 mph"))
    }
}

private func hour(_ iso: String, temperature: Double, rain: Int, uv: Double, wind: Double, code: Int, daylight: Bool) -> HourlyTemperaturePoint {
    HourlyTemperaturePoint(
        date: date(iso),
        meanF: temperature,
        minF: temperature,
        maxF: temperature,
        precipitationProbability: rain,
        uvIndex: uv,
        windSpeedMph: wind,
        conditionCode: code,
        isDaylight: daylight
    )
}
