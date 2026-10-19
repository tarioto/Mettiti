import Foundation
import Testing
@testable import Mettiti

struct HourlyForecastTests {
    @Test func ensembleHoursAverageTheMembersAndKeepTheirSpread() throws {
        let data = try ensembleResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: -25_200,
            time: ["2026-10-09T13:00", "2026-10-09T14:00"],
            members: [[60, 62], [64, 66], [68, 70]]
        )

        let forecast = try HourlyForecastService.hourlyForecast(from: data, now: date("2026-10-09T20:00:00Z"))

        #expect(forecast.points.map(\.date) == [date("2026-10-09T20:00:00Z"), date("2026-10-09T21:00:00Z")])
        #expect(forecast.points.map(\.meanF) == [64, 66])
        #expect(forecast.points.map(\.minF) == [60, 62])
        #expect(forecast.points.map(\.maxF) == [68, 70])
        #expect(forecast.points.map(\.precipitationProbability) == [nil, nil])
    }

    @Test func ensembleWithoutAUTCOffsetThrowsDecodingFailed() throws {
        let data = try ensembleResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: nil,
            time: ["2026-10-09T13:00"],
            members: [[60]]
        )

        #expect(throws: WeatherServiceError.decodingFailed) {
            try HourlyForecastService.hourlyForecast(from: data, now: date("2026-10-09T20:00:00Z"))
        }
    }

    @Test func ensembleHoursAfterAClockChangeUseTheResponsesFixedOffset() throws {
        // Berlin falls back at 03:00 CEST on 2026-10-25; Open-Meteo keeps writing times at +2.
        let data = try ensembleResponse(
            timezone: "Europe/Berlin",
            utcOffsetSeconds: 7_200,
            time: ["2026-10-25T02:00", "2026-10-25T03:00", "2026-10-25T04:00"],
            members: [[50, 51, 52]]
        )

        let forecast = try HourlyForecastService.hourlyForecast(from: data, now: date("2026-10-25T00:00:00Z"))

        #expect(forecast.points.map(\.date) == [
            date("2026-10-25T00:00:00Z"),
            date("2026-10-25T01:00:00Z"),
            date("2026-10-25T02:00:00Z"),
        ])
    }

    @Test func spreadFromTheEnsembleKeepsEachHoursOwnMeanAndWeather() {
        let hour = date("2026-10-09T20:00:00Z")
        let sunset = SunEvent(kind: .sunset, date: date("2026-10-10T01:30:00Z"))
        let apple = HourlyForecast(
            timeZone: pacific,
            points: [
                HourlyTemperaturePoint(date: hour, meanF: 70, minF: 70, maxF: 70, precipitationProbability: 40, uvIndex: 4, windSpeedMph: 9, conditionCode: 2, isDaylight: true),
            ],
            sunEvents: [sunset]
        )
        let ensemble = HourlyForecast(timeZone: pacific, points: [point(at: hour)])

        let merged = apple.applyingSpread(from: ensemble)

        #expect(merged.points.map(\.meanF) == [70])
        #expect(merged.points.map(\.minF) == [66])
        #expect(merged.points.map(\.maxF) == [74])
        #expect(merged.points.map(\.precipitationProbability) == [40])
        #expect(merged.points.map(\.uvIndex) == [4])
        #expect(merged.points.map(\.windSpeedMph) == [9])
        #expect(merged.points.map(\.conditionCode) == [2])
        #expect(merged.points.map(\.isDaylight) == [true])
        #expect(merged.sunEvents == [sunset])
    }

    @Test func aRefetchedHourKeepsItsIdentity() {
        let first = HourlyTemperaturePoint(date: date("2026-10-09T20:00:00Z"), meanF: 64, minF: 60, maxF: 68, precipitationProbability: 10)
        let refetched = HourlyTemperaturePoint(date: date("2026-10-09T20:00:00Z"), meanF: 65, minF: 61, maxF: 69, precipitationProbability: 20)

        #expect(first.id == refetched.id)
    }

    @Test func hoursAreLabelledInTheForecastLocationsTimeZone() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let forecast = HourlyForecast(timeZone: berlin, points: [point(at: date("2026-10-25T12:00:00Z"))])

        let label = date("2026-10-25T12:00:00Z").formatted(forecast.hourFormat.locale(Locale(identifier: "en_US")))

        // 12:00 UTC is 13:00 CET.
        #expect(label.replacingOccurrences(of: "\u{202F}", with: " ") == "1 PM")
    }

    @Test func bothHoursThatShareALabelAtTheFallBackStayApart() throws {
        // Berlin's clocks go from 03:00 CEST back to 02:00 CET, so two hours read "2 AM".
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let summerTwoAM = date("2026-10-25T00:00:00Z")
        let winterTwoAM = date("2026-10-25T01:00:00Z")
        let forecast = HourlyForecast(timeZone: berlin, points: [point(at: summerTwoAM), point(at: winterTwoAM)])
        let style = forecast.hourFormat.locale(Locale(identifier: "en_US"))

        #expect(summerTwoAM.formatted(style) == winterTwoAM.formatted(style))
        #expect(Set(forecast.points.map(\.id)).count == 2)
        #expect(forecast.axisDates == [summerTwoAM, winterTwoAM])
    }

    @Test func axisLabelsFourEvenlySpacedHours() {
        let start = date("2026-10-09T20:00:00Z")
        let forecast = HourlyForecast(timeZone: pacific, points: (0..<24).map { point(at: start.addingTimeInterval(Double($0) * 3600)) })

        #expect(forecast.axisDates == [0, 6, 12, 18].map { start.addingTimeInterval(Double($0) * 3600) })
    }

    @Test func forecastWithAnEnsembleSpreadHasSpread() {
        let forecast = HourlyForecast(timeZone: pacific, points: [point(at: date("2026-10-09T20:00:00Z"))])

        #expect(forecast.hasSpread)
    }

    @Test func forecastWithoutAnEnsembleSpreadHasNoSpread() {
        let flat = point(at: date("2026-10-09T20:00:00Z")).with(minF: 64, maxF: 64)
        let forecast = HourlyForecast(timeZone: pacific, points: [flat])

        #expect(!forecast.hasSpread)
    }

    private func point(at date: Date) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(date: date, meanF: 64, minF: 60, maxF: 68, precipitationProbability: nil)
    }

    private func ensembleResponse(timezone: String, utcOffsetSeconds: Int?, time: [String], members: [[Double]]) throws -> Data {
        let memberJSON = members.enumerated().map { index, values in
            let key = index == 0 ? "temperature_2m" : "temperature_2m_member\(String(format: "%02d", index))"
            return "\"\(key)\": [\(values.map { String($0) }.joined(separator: ", "))]"
        }
        let offsetJSON = utcOffsetSeconds.map { "\"utc_offset_seconds\": \($0)," } ?? ""
        return try #require("""
        {
          "timezone": "\(timezone)",
          \(offsetJSON)
          "hourly": {
            "time": [\(time.map { "\"\($0)\"" }.joined(separator: ", "))],
            \(memberJSON.joined(separator: ",\n    "))
          }
        }
        """.data(using: .utf8))
    }
}
