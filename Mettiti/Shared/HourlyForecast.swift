import Foundation

struct HourlyTemperaturePoint: Identifiable, Codable, Sendable {
    /// Only identifies points within one chart, so it's regenerated rather than saved.
    let id = UUID()
    let date: Date
    let hourLabel: String
    let meanF: Double
    let minF: Double
    let maxF: Double
    let precipitationProbability: Int

    private enum CodingKeys: String, CodingKey {
        case date, hourLabel, meanF, minF, maxF, precipitationProbability
    }
}

struct HourlyForecast: Codable, Sendable {
    let timeZone: TimeZone
    let points: [HourlyTemperaturePoint]

    /// Wraps an ensemble's spread around these points: each hour keeps its own mean but
    /// takes the ensemble's distance below and above its mean. Each hour uses the nearest
    /// ensemble hour within 30 minutes, so sources aligned to different hour boundaries
    /// (e.g. half-hour time zones) still line up. Hours with no match keep their original
    /// min and max.
    func applyingSpread(from ensemble: HourlyForecast) -> HourlyForecast {
        let merged = points.map { point -> HourlyTemperaturePoint in
            guard
                let match = ensemble.points.min(by: {
                    abs($0.date.timeIntervalSince(point.date)) < abs($1.date.timeIntervalSince(point.date))
                }),
                abs(match.date.timeIntervalSince(point.date)) <= 1800
            else { return point }
            return HourlyTemperaturePoint(
                date: point.date,
                hourLabel: point.hourLabel,
                meanF: point.meanF,
                minF: point.meanF - (match.meanF - match.minF),
                maxF: point.meanF + (match.maxF - match.meanF),
                precipitationProbability: point.precipitationProbability
            )
        }
        return HourlyForecast(timeZone: timeZone, points: merged)
    }
}
