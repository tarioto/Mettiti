import Foundation
import Testing
@testable import Mettiti

/// Decodes whole responses shaped like the live Open-Meteo API's, extra fields and all.
struct OpenMeteoFixtureTests {
    @Test func forecastResponseGivesTheFirstDaysWeather() throws {
        let forecast = try WeatherService.forecast(from: fixture("open-meteo-forecast"))

        let weather = forecast.daily
        #expect(weather.date == date("2026-10-09T07:00:00Z"))
        #expect(weather.highTemperatureF == 61.3)
        #expect(weather.lowTemperatureF == 48.9)
        #expect(weather.precipitationProbability == 85)
        #expect(weather.uvIndex == 2.35)
        #expect(weather.windSpeedMph == 12.4)
        #expect(weather.conditionCode == 61)
        #expect(weather.conditionDescription == WMOWeatherCode.description(for: 61))
    }

    @Test func forecastResponseKeysEachHoursChanceOfRainAndSkipsNullHours() throws {
        let forecast = try WeatherService.forecast(from: fixture("open-meteo-forecast"))

        // 48 hours; the last one's chance of rain is null.
        #expect(forecast.hourlyPrecipitation.count == 47)
        #expect(forecast.hourlyPrecipitation[date("2026-10-09T20:00:00Z")] == 65)
        #expect(forecast.hourlyPrecipitation[date("2026-10-11T06:00:00Z")] == nil)
    }

    @Test func ensembleResponseGivesTheNext24HoursAcrossAllMembers() throws {
        let forecast = try HourlyForecastService.hourlyForecast(
            from: fixture("open-meteo-ensemble"),
            now: date("2026-10-09T20:10:00Z")
        )

        #expect(forecast.timeZone == pacific)
        #expect(forecast.points.count == 24)
        // The hour in progress (13:00 PDT) comes first; its members read 68, 70, 72 and 74 °F.
        let first = try #require(forecast.points.first)
        #expect(first.date == date("2026-10-09T20:00:00Z"))
        #expect(first.meanF == 71)
        #expect(first.minF == 68)
        #expect(first.maxF == 74)
        #expect(forecast.points.last?.date == date("2026-10-10T19:00:00Z"))
    }
}
