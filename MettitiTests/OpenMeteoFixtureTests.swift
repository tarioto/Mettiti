import Foundation
import Testing
@testable import Mettiti

/// Decodes whole responses shaped like the live Open-Meteo API's, extra fields and all.
struct OpenMeteoFixtureTests {
    @Test func forecastResponseGivesTheFirstDaysWeather() throws {
        let forecast = try WeatherService.forecast(from: fixture("open-meteo-forecast"), now: date("2026-10-09T20:10:00Z"))

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

    @Test func forecastResponseGivesTheNext24HoursWithEachHoursWeather() throws {
        let forecast = try WeatherService.forecast(from: fixture("open-meteo-forecast"), now: date("2026-10-09T20:10:00Z"))

        let hourly = try #require(forecast.hourly)
        #expect(hourly.timeZone == pacific)
        #expect(hourly.points.count == 24)
        // The hour in progress (13:00 PDT) comes first.
        let first = try #require(hourly.points.first)
        #expect(first.date == date("2026-10-09T20:00:00Z"))
        #expect(first.meanF == 59.8)
        #expect(first.precipitationProbability == 65)
        #expect(first.uvIndex == 2.35)
        #expect(first.windSpeedMph == 12.3)
        #expect(first.conditionCode == 61)
        #expect(first.isDaylight == true)
        #expect(hourly.points.last?.date == date("2026-10-10T19:00:00Z"))
    }

    @Test func aNullValueCostsOnlyThatValue() throws {
        // From 00:30 PDT on the second day, the last hour is in the window: its chance of rain
        // and UV are null.
        let forecast = try WeatherService.forecast(from: fixture("open-meteo-forecast"), now: date("2026-10-10T07:30:00Z"))

        let last = try #require(forecast.hourly?.points.last)
        #expect(last.date == date("2026-10-11T06:00:00Z"))
        #expect(last.meanF == 57.3)
        #expect(last.precipitationProbability == nil)
        #expect(last.uvIndex == nil)
        #expect(last.isDaylight == false)
    }

    @Test func forecastResponseGivesBothDaysSunriseAndSunset() throws {
        let forecast = try WeatherService.forecast(from: fixture("open-meteo-forecast"), now: date("2026-10-09T20:10:00Z"))

        #expect(forecast.hourly?.sunEvents == [
            SunEvent(kind: .sunrise, date: date("2026-10-09T14:17:00Z")),
            SunEvent(kind: .sunset, date: date("2026-10-10T01:32:00Z")),
            SunEvent(kind: .sunrise, date: date("2026-10-10T14:18:00Z")),
            SunEvent(kind: .sunset, date: date("2026-10-11T01:30:00Z")),
        ])
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
