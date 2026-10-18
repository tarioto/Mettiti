import Foundation

struct HourlyTemperaturePoint: Identifiable, Codable, Sendable {
    let date: Date
    let meanF: Double
    let minF: Double
    let maxF: Double
    /// Nil when the source had no chance of rain for this hour (e.g. the ensemble on its own).
    /// Optional decoding still reads the plain numbers older saved plans stored.
    let precipitationProbability: Int?

    /// Identified by its hour, so a refetch keeps each point's identity for diffing and animation.
    /// Computed, so it isn't saved; the "hourLabel" older saved plans stored is ignored on decode.
    var id: Date { date }

    /// A copy with a different spread around the same mean.
    func with(minF: Double, maxF: Double) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(date: date, meanF: meanF, minF: minF, maxF: maxF, precipitationProbability: precipitationProbability)
    }

    /// A copy with a different chance of rain.
    func with(precipitationProbability: Int?) -> HourlyTemperaturePoint {
        HourlyTemperaturePoint(date: date, meanF: meanF, minF: minF, maxF: maxF, precipitationProbability: precipitationProbability)
    }
}

struct HourlyForecast: Codable, Sendable {
    let timeZone: TimeZone
    let points: [HourlyTemperaturePoint]

    /// The hour in the forecast location's time zone, in the locale's preferred style:
    /// "3 PM" in the US, "15 Uhr" in Germany.
    var hourFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = timeZone
        return style
    }

    /// Up to 4 evenly spaced hours for the chart's x-axis labels.
    var axisDates: [Date] {
        guard !points.isEmpty else { return [] }
        let count = points.count
        var dates: [Date] = []
        for index in [0, count / 4, count / 2, (count * 3) / 4] where dates.last != points[index].date {
            dates.append(points[index].date)
        }
        return dates
    }

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
