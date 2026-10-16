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
}
