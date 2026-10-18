import Foundation
import Testing
@testable import Mettiti

struct PlanSnapshotTests {
    /// A snapshot as saved by earlier app versions, which always had a recommendation.
    private let savedBeforeWeatherOnlySnapshots = """
    {
      "weather": {
        "date": 781574400,
        "highTemperatureF": 68,
        "lowTemperatureF": 52,
        "precipitationProbability": 40,
        "uvIndex": 3,
        "windSpeedMph": 9,
        "conditionCode": 61,
        "conditionDescription": "Rain"
      },
      "recommendation": {
        "summary": "Showers on and off, so bring rain gear.",
        "items": [
          { "emoji": "☂️", "name": "Umbrella", "reason": "Showers likely" }
        ]
      },
      "generatedAt": 781578000,
      "provider": "openMeteo"
    }
    """

    @Test func snapshotSavedByEarlierVersionStillDecodesWithItsRecommendation() throws {
        let snapshot = try JSONDecoder().decode(PlanSnapshot.self, from: Data(savedBeforeWeatherOnlySnapshots.utf8))

        #expect(snapshot.weather.conditionDescription == "Rain")
        #expect(snapshot.weather.highTemperatureF == 68)
        #expect(snapshot.recommendation?.summary == "Showers on and off, so bring rain gear.")
        #expect(snapshot.recommendation?.items.map(\.name) == ["Umbrella"])
        #expect(snapshot.provider == .openMeteo)
    }

    @Test func weatherOnlySnapshotRoundTripsWithoutARecommendation() throws {
        let snapshot = PlanSnapshot(weather: .placeholder, recommendation: nil, generatedAt: Date(timeIntervalSinceReferenceDate: 0), provider: .apple)

        let decoded = try JSONDecoder().decode(PlanSnapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded.recommendation == nil)
        #expect(decoded.weather.conditionDescription == DailyWeather.placeholder.conditionDescription)
        #expect(decoded.weather.highTemperatureF == DailyWeather.placeholder.highTemperatureF)
        #expect(decoded.provider == .apple)
    }

    @Test func snapshotSavedByEarlierVersionHasNoLocationOrHourlyForecast() throws {
        let snapshot = try JSONDecoder().decode(PlanSnapshot.self, from: Data(savedBeforeWeatherOnlySnapshots.utf8))

        #expect(snapshot.location == nil)
        #expect(snapshot.hourly == nil)
    }

    @Test func locationAndHourlyForecastRoundTrip() throws {
        let hourly = HourlyForecast(timeZone: pacific, points: [
            HourlyTemperaturePoint(date: date("2026-10-08T09:00:00-07:00"), hourLabel: "9AM", meanF: 55, minF: 52, maxF: 58, precipitationProbability: 10),
            HourlyTemperaturePoint(date: date("2026-10-08T10:00:00-07:00"), hourLabel: "10AM", meanF: 60, minF: 57, maxF: 63, precipitationProbability: 30),
        ])
        var snapshot = PlanSnapshot.generated(at: date("2026-10-08T09:00:00-07:00"))
        snapshot.location = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        snapshot.hourly = hourly

        let decoded = try JSONDecoder().decode(PlanSnapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded.location == .custom(name: "Seattle", latitude: 47.6, longitude: -122.3))
        #expect(decoded.hourly?.timeZone == pacific)
        #expect(decoded.hourly?.points.map(\.hourLabel) == ["9AM", "10AM"])
        #expect(decoded.hourly?.points.map(\.meanF) == [55, 60])
        #expect(decoded.hourly?.points.map(\.minF) == [52, 57])
        #expect(decoded.hourly?.points.map(\.maxF) == [58, 63])
        #expect(decoded.hourly?.points.map(\.precipitationProbability) == [10, 30])
        #expect(decoded.hourly?.points.map(\.date) == [date("2026-10-08T09:00:00-07:00"), date("2026-10-08T10:00:00-07:00")])
    }
}
