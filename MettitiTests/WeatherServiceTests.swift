import Foundation
import Testing
@testable import Mettiti

struct WeatherServiceTests {
    @Test func dailyDateIsMidnightOfTheForecastDayInAFarAheadTimeZone() throws {
        let data = try openMeteoResponse(timezone: "Pacific/Auckland", utcOffsetSeconds: 46_800, date: "2026-10-09")

        let weather = try WeatherService.dailyWeather(from: data)

        // 2026-10-09 00:00 NZDT (UTC+13)
        let expected = try isoDate("2026-10-08T11:00:00Z")
        #expect(weather.date == expected)
    }

    @Test(arguments: [
        ("Pacific/Auckland", 46_800),
        ("America/Los_Angeles", -25_200),
    ])
    func dailyDateIsTheGregorianForecastDayInTheForecastTimeZone(timezone: String, utcOffsetSeconds: Int) throws {
        let data = try openMeteoResponse(timezone: timezone, utcOffsetSeconds: utcOffsetSeconds, date: "2026-10-09")

        let weather = try WeatherService.dailyWeather(from: data)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timezone))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: weather.date)
        #expect(components.year == 2026)
        #expect(components.month == 10)
        #expect(components.day == 9)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
    }

    @Test func dailyDateIsTheGregorianForecastDayOnABuddhistCalendarDevice() throws {
        let data = try openMeteoResponse(timezone: "Asia/Bangkok", utcOffsetSeconds: 25_200, date: "2026-10-09")
        let thaiDevice = Locale(identifier: "th_TH@calendar=buddhist")

        let weather = try WeatherService.dailyWeather(from: data, deviceLocale: thaiDevice)

        // 2026-10-09 00:00 ICT (UTC+7), not Buddhist year 2026 (Gregorian 1483)
        let expected = try isoDate("2026-10-08T17:00:00Z")
        #expect(weather.date == expected)
    }

    @Test func unparseableDailyDateThrowsDecodingFailed() throws {
        let data = try openMeteoResponse(timezone: "Pacific/Auckland", utcOffsetSeconds: 46_800, date: "not-a-date")

        #expect(throws: WeatherServiceError.decodingFailed) {
            try WeatherService.dailyWeather(from: data)
        }
    }

    private func openMeteoResponse(timezone: String, utcOffsetSeconds: Int, date: String) throws -> Data {
        try #require("""
        {
          "timezone": "\(timezone)",
          "utc_offset_seconds": \(utcOffsetSeconds),
          "daily": {
            "time": ["\(date)"],
            "temperature_2m_max": [70.0],
            "temperature_2m_min": [55.0],
            "precipitation_probability_max": [10],
            "uv_index_max": [4.0],
            "windspeed_10m_max": [6.0],
            "weathercode": [1]
          }
        }
        """.data(using: .utf8))
    }

    private func isoDate(_ string: String) throws -> Date {
        try Date(string, strategy: .iso8601)
    }
}
