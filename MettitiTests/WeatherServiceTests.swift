import CoreLocation
import Foundation
import Testing
@testable import Mettiti

struct WeatherServiceTests {
    @Test func dailyDateIsMidnightOfTheForecastDayInAFarAheadTimeZone() throws {
        let data = try openMeteoResponse(timezone: "Pacific/Auckland", utcOffsetSeconds: 46_800, date: "2026-10-09")

        let weather = try WeatherService.forecast(from: data, now: .now).daily

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

        let weather = try WeatherService.forecast(from: data, now: .now).daily

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timezone))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: weather.date)
        #expect(components.year == 2026)
        #expect(components.month == 10)
        #expect(components.day == 9)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
    }

    @Test func unparseableDailyDateThrowsDecodingFailed() throws {
        let data = try openMeteoResponse(timezone: "Pacific/Auckland", utcOffsetSeconds: 46_800, date: "not-a-date")

        #expect(throws: WeatherServiceError.decodingFailed) {
            try WeatherService.forecast(from: data, now: .now)
        }
    }

    @Test func requestAsksForTwoDaysOfHourlyWeatherAndSunTimes() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

        let url = try #require(WeatherService.forecastURL(for: coordinate))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let daily = try #require(items.first { $0.name == "daily" }?.value).split(separator: ",")
        let hourly = try #require(items.first { $0.name == "hourly" }?.value).split(separator: ",")
        #expect(components.host == "api.open-meteo.com")
        #expect(daily.contains("sunrise") && daily.contains("sunset"))
        #expect(Set(hourly).isSuperset(of: ["temperature_2m", "precipitation_probability", "uv_index", "windspeed_10m", "weathercode", "is_day"]))
        #expect(items.contains(URLQueryItem(name: "forecast_days", value: "2")))
    }

    @Test func hourlyForecastCarriesEachHoursWeather() throws {
        let data = try openMeteoResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: -25_200,
            date: "2026-10-09",
            hourly: [
                .init(time: "2026-10-09T18:00", temperature: 66, precipitation: 20, uv: 1.5, wind: 9, code: 2, isDay: 1),
                .init(time: "2026-10-09T19:00", temperature: 62, precipitation: 40, uv: 0, wind: 12, code: 61, isDay: 0),
            ]
        )

        let hourly = try #require(try WeatherService.forecast(from: data, now: date("2026-10-10T01:00:00Z")).hourly)

        #expect(hourly.timeZone == pacific)
        #expect(hourly.points.map(\.date) == [date("2026-10-10T01:00:00Z"), date("2026-10-10T02:00:00Z")])
        #expect(hourly.points.map(\.meanF) == [66, 62])
        #expect(hourly.points.map(\.minF) == [66, 62])
        #expect(hourly.points.map(\.maxF) == [66, 62])
        #expect(hourly.points.map(\.precipitationProbability) == [20, 40])
        #expect(hourly.points.map(\.uvIndex) == [1.5, 0])
        #expect(hourly.points.map(\.windSpeedMph) == [9, 12])
        #expect(hourly.points.map(\.conditionCode) == [2, 61])
        #expect(hourly.points.map(\.isDaylight) == [true, false])
    }

    @Test func hourlyForecastStartsWithTheHourInProgressAndCoversADay() throws {
        let times = (0..<48).map { String(format: "2026-10-%02dT%02d:00", 9 + $0 / 24, $0 % 24) }
        let data = try openMeteoResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: -25_200,
            date: "2026-10-09",
            hourly: times.map { .init(time: $0) }
        )

        // 9:20 AM PDT
        let hourly = try #require(try WeatherService.forecast(from: data, now: date("2026-10-09T16:20:00Z")).hourly)

        #expect(hourly.points.count == 24)
        #expect(hourly.points.first?.date == date("2026-10-09T16:00:00Z"))
    }

    @Test func hourlyForecastKeepsTheHourInProgressLateInTheHour() throws {
        let data = try openMeteoResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: -25_200,
            date: "2026-10-09",
            hourly: [.init(time: "2026-10-09T18:00", isDay: 1), .init(time: "2026-10-09T19:00", isDay: 0)]
        )

        // 6:45 PM PDT, still in the 6 PM hour
        let hourly = try #require(try WeatherService.forecast(from: data, now: date("2026-10-10T01:45:00Z")).hourly)

        #expect(hourly.points.first?.date == date("2026-10-10T01:00:00Z"))
    }

    @Test func sunEventsComeFromEachDaysSunriseAndSunset() throws {
        let data = try openMeteoResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: -25_200,
            date: "2026-10-09",
            hourly: [.init(time: "2026-10-09T18:00")],
            sun: (sunrise: ["2026-10-09T07:12", "2026-10-10T07:13"], sunset: ["2026-10-09T18:31", "2026-10-10T18:29"])
        )

        let hourly = try #require(try WeatherService.forecast(from: data, now: date("2026-10-10T01:00:00Z")).hourly)

        #expect(hourly.sunEvents == [
            SunEvent(kind: .sunrise, date: date("2026-10-09T14:12:00Z")),
            SunEvent(kind: .sunset, date: date("2026-10-10T01:31:00Z")),
            SunEvent(kind: .sunrise, date: date("2026-10-10T14:13:00Z")),
            SunEvent(kind: .sunset, date: date("2026-10-11T01:29:00Z")),
        ])
    }

    @Test func hourlyTimesAfterAClockChangeUseTheResponsesFixedOffset() throws {
        // Open-Meteo writes every timestamp at the response's UTC offset, even past a DST
        // change: in Berlin on 2026-10-25, "03:00" is 03:00 at +2, i.e. 02:00 CET.
        let data = try openMeteoResponse(
            timezone: "Europe/Berlin",
            utcOffsetSeconds: 7_200,
            date: "2026-10-25",
            hourly: [.init(time: "2026-10-25T02:00"), .init(time: "2026-10-25T03:00")]
        )

        let hourly = try #require(try WeatherService.forecast(from: data, now: date("2026-10-25T00:00:00Z")).hourly)

        #expect(hourly.points.map(\.date) == [
            date("2026-10-25T00:00:00Z"),
            date("2026-10-25T01:00:00Z"),
        ])
    }

    @Test func missingHourlyDataStillGivesTheDailyForecast() throws {
        let data = try openMeteoResponse(timezone: "America/Los_Angeles", utcOffsetSeconds: -25_200, date: "2026-10-09")

        let forecast = try WeatherService.forecast(from: data, now: date("2026-10-09T16:00:00Z"))

        #expect(forecast.daily.highTemperatureF == 70)
        #expect(forecast.hourly == nil)
    }

    @Test func hourlyDataWithoutAUTCOffsetIsLeftOut() throws {
        let data = try openMeteoResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: nil,
            date: "2026-10-09",
            hourly: [.init(time: "2026-10-09T13:00")]
        )

        let forecast = try WeatherService.forecast(from: data, now: date("2026-10-09T16:00:00Z"))

        #expect(forecast.daily.highTemperatureF == 70)
        #expect(forecast.hourly == nil)
    }

    private struct HourJSON {
        var time: String
        var temperature: Double = 60
        var precipitation: Int = 0
        var uv: Double = 0
        var wind: Double = 5
        var code: Int = 1
        var isDay: Int = 1
    }

    private func openMeteoResponse(
        timezone: String,
        utcOffsetSeconds: Int?,
        date: String,
        hourly: [HourJSON]? = nil,
        sun: (sunrise: [String], sunset: [String])? = nil
    ) throws -> Data {
        func list<T>(_ values: [T]) -> String { values.map { "\($0)" }.joined(separator: ", ") }
        let hourlyJSON = hourly.map { hours in
            """
            ,
            "hourly": {
              "time": [\(hours.map { "\"\($0.time)\"" }.joined(separator: ", "))],
              "temperature_2m": [\(list(hours.map(\.temperature)))],
              "precipitation_probability": [\(list(hours.map(\.precipitation)))],
              "uv_index": [\(list(hours.map(\.uv)))],
              "windspeed_10m": [\(list(hours.map(\.wind)))],
              "weathercode": [\(list(hours.map(\.code)))],
              "is_day": [\(list(hours.map(\.isDay)))]
            }
            """
        } ?? ""
        let sunJSON = sun.map { sun in
            """
            ,
            "sunrise": [\(sun.sunrise.map { "\"\($0)\"" }.joined(separator: ", "))],
            "sunset": [\(sun.sunset.map { "\"\($0)\"" }.joined(separator: ", "))]
            """
        } ?? ""
        let offsetJSON = utcOffsetSeconds.map { "\"utc_offset_seconds\": \($0)," } ?? ""
        return try #require("""
        {
          "timezone": "\(timezone)",
          \(offsetJSON)
          "daily": {
            "time": ["\(date)"],
            "temperature_2m_max": [70.0],
            "temperature_2m_min": [55.0],
            "precipitation_probability_max": [10],
            "uv_index_max": [4.0],
            "windspeed_10m_max": [6.0],
            "weathercode": [1]\(sunJSON)
          }\(hourlyJSON)
        }
        """.data(using: .utf8))
    }

    private func isoDate(_ string: String) throws -> Date {
        try Date(string, strategy: .iso8601)
    }
}
