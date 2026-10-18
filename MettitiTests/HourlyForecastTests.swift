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

    @Test func eachHourTakesTheChanceOfRainForThatHour() {
        let forecast = HourlyForecast(timeZone: pacific, points: [
            point(at: date("2026-10-09T20:00:00Z")),
            point(at: date("2026-10-09T21:00:00Z")),
            point(at: date("2026-10-09T22:00:00Z")),
        ])

        let merged = forecast.applyingPrecipitation([
            date("2026-10-09T20:00:00Z"): 30,
            date("2026-10-09T22:00:00Z"): 70,
            date("2026-10-09T23:00:00Z"): 90,
        ])

        #expect(merged.points.map(\.precipitationProbability) == [30, 0, 70])
        #expect(merged.points.map(\.meanF) == [64, 64, 64])
    }

    private func point(at date: Date) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(date: date, hourLabel: "", meanF: 64, minF: 60, maxF: 68, precipitationProbability: 0)
    }

    private func ensembleResponse(timezone: String, utcOffsetSeconds: Int, time: [String], members: [[Double]]) throws -> Data {
        let memberJSON = members.enumerated().map { index, values in
            let key = index == 0 ? "temperature_2m" : "temperature_2m_member\(String(format: "%02d", index))"
            return "\"\(key)\": [\(values.map { String($0) }.joined(separator: ", "))]"
        }
        return try #require("""
        {
          "timezone": "\(timezone)",
          "utc_offset_seconds": \(utcOffsetSeconds),
          "hourly": {
            "time": [\(time.map { "\"\($0)\"" }.joined(separator: ", "))],
            \(memberJSON.joined(separator: ",\n    "))
          }
        }
        """.data(using: .utf8))
    }
}
