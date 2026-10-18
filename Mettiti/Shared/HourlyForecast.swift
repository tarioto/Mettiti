import Foundation

struct HourlyTemperaturePoint: Identifiable, Codable, Sendable {
    /// Only identifies points within one chart, so it's regenerated rather than saved.
    let id = UUID()
    let date: Date
    let hourLabel: String
    let meanF: Double
    let minF: Double
    let maxF: Double
    /// Nil when the source had no chance of rain for this hour (e.g. the ensemble on its own).
    /// Optional decoding still reads the plain numbers older saved plans stored.
    let precipitationProbability: Int?

    private enum CodingKeys: String, CodingKey {
        case date, hourLabel, meanF, minF, maxF, precipitationProbability
    }

    /// A copy with a different spread around the same mean.
    func with(minF: Double, maxF: Double) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(date: date, hourLabel: hourLabel, meanF: meanF, minF: minF, maxF: maxF, precipitationProbability: precipitationProbability)
    }

    /// A copy with a different chance of rain.
    func with(precipitationProbability: Int?) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(date: date, hourLabel: hourLabel, meanF: meanF, minF: minF, maxF: maxF, precipitationProbability: precipitationProbability)
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
            return point.with(
                minF: point.meanF - (match.meanF - match.minF),
                maxF: point.meanF + (match.maxF - match.meanF)
            )
        }
        return HourlyForecast(timeZone: timeZone, points: merged)
    }

    /// Sets each hour's chance of rain from `probabilities`, keyed by the start of the hour.
    /// Hours with no entry keep their current value.
    func applyingPrecipitation(_ probabilities: [Date: Int]) -> HourlyForecast {
        let merged = points.map { point -> HourlyTemperaturePoint in
            guard let probability = probabilities[point.date] else { return point }
            return point.with(precipitationProbability: probability)
        }
        return HourlyForecast(timeZone: timeZone, points: merged)
    }
}
