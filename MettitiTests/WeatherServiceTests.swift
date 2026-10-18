import CoreLocation
import Foundation
import Testing
@testable import Mettiti

struct WeatherServiceTests {
    @Test func dailyDateIsMidnightOfTheForecastDayInAFarAheadTimeZone() throws {
        let data = try openMeteoResponse(timezone: "Pacific/Auckland", utcOffsetSeconds: 46_800, date: "2026-10-09")

        let weather = try WeatherService.forecast(from: data).daily

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

        let weather = try WeatherService.forecast(from: data).daily

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

        let weather = try WeatherService.forecast(from: data, deviceLocale: thaiDevice).daily

        // 2026-10-09 00:00 ICT (UTC+7), not Buddhist year 2026 (Gregorian 1483)
        let expected = try isoDate("2026-10-08T17:00:00Z")
        #expect(weather.date == expected)
    }

    @Test func unparseableDailyDateThrowsDecodingFailed() throws {
        let data = try openMeteoResponse(timezone: "Pacific/Auckland", utcOffsetSeconds: 46_800, date: "not-a-date")

        #expect(throws: WeatherServiceError.decodingFailed) {
            try WeatherService.forecast(from: data)
        }
    }

    @Test func requestAsksForTheDailyForecastAndTwoDaysOfHourlyPrecipitation() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

        let url = try #require(WeatherService.forecastURL(for: coordinate))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        #expect(components.host == "api.open-meteo.com")
        #expect(items.contains { $0.name == "daily" })
        #expect(items.contains(URLQueryItem(name: "hourly", value: "precipitation_probability")))
        #expect(items.contains(URLQueryItem(name: "forecast_days", value: "2")))
    }

    @Test func hourlyPrecipitationIsKeyedByTheHourItCovers() throws {
        let data = try openMeteoResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: -25_200,
            date: "2026-10-09",
            hourly: (time: ["2026-10-09T13:00", "2026-10-09T14:00"], precipitation: [20, 40])
        )

        let forecast = try WeatherService.forecast(from: data)

        #expect(forecast.hourlyPrecipitation == [
            try isoDate("2026-10-09T20:00:00Z"): 20,
            try isoDate("2026-10-09T21:00:00Z"): 40,
        ])
    }

    @Test func hourlyTimesAfterAClockChangeUseTheResponsesFixedOffset() throws {
        // Open-Meteo writes every timestamp at the response's UTC offset, even past a DST
        // change: in Berlin on 2026-10-25, "03:00" is 03:00 at +2, i.e. 02:00 CET.
        let data = try openMeteoResponse(
            timezone: "Europe/Berlin",
            utcOffsetSeconds: 7_200,
            date: "2026-10-25",
            hourly: (time: ["2026-10-25T02:00", "2026-10-25T03:00"], precipitation: [10, 30])
        )

        let forecast = try WeatherService.forecast(from: data)

        #expect(forecast.hourlyPrecipitation == [
            try isoDate("2026-10-25T00:00:00Z"): 10,
            try isoDate("2026-10-25T01:00:00Z"): 30,
        ])
    }

    @Test func missingHourlyDataStillGivesTheDailyForecast() throws {
        let data = try openMeteoResponse(timezone: "America/Los_Angeles", utcOffsetSeconds: -25_200, date: "2026-10-09")

        let forecast = try WeatherService.forecast(from: data)

        #expect(forecast.daily.highTemperatureF == 70)
        #expect(forecast.hourlyPrecipitation.isEmpty)
    }

    private func openMeteoResponse(
        timezone: String,
        utcOffsetSeconds: Int,
        date: String,
        hourly: (time: [String], precipitation: [Int])? = nil
    ) throws -> Data {
        let hourlyJSON = hourly.map { hourly in
            """
            ,
            "hourly": {
              "time": [\(hourly.time.map { "\"\($0)\"" }.joined(separator: ", "))],
              "precipitation_probability": [\(hourly.precipitation.map(String.init).joined(separator: ", "))]
            }
            """
        } ?? ""
        return try #require("""
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
          }\(hourlyJSON)
        }
        """.data(using: .utf8))
    }

    private func isoDate(_ string: String) throws -> Date {
        try Date(string, strategy: .iso8601)
    }
}
