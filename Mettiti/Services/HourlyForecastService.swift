import Foundation
import CoreLocation

struct HourlyTemperaturePoint: Identifiable {
    let id = UUID()
    let date: Date
    let hourLabel: String
    let meanF: Double
    let minF: Double
    let maxF: Double
    let precipitationProbability: Int
}

struct HourlyForecast {
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

struct HourlyForecastService {
    /// Pass `includePrecipitation: false` when only the temperature spread is needed,
    /// to skip the extra precipitation request.
    func fetchHourlyForecast(for coordinate: CLLocationCoordinate2D, includePrecipitation: Bool = true) async throws -> HourlyForecast {
        var components = URLComponents(string: "https://ensemble-api.open-meteo.com/v1/ensemble")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m"),
            URLQueryItem(name: "models", value: "icon_seamless"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { throw WeatherServiceError.invalidResponse }

        async let precipitationTask: [String: Int] = includePrecipitation
            ? (try? fetchPrecipitationProbabilities(for: coordinate)) ?? [:]
            : [:]

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }

        let decoded: EnsembleResponse
        do {
            decoded = try JSONDecoder().decode(EnsembleResponse.self, from: data)
        } catch {
            throw WeatherServiceError.decodingFailed
        }

        let precipitationByTime = await precipitationTask

        guard let timeZone = TimeZone(identifier: decoded.timezone), !decoded.memberSeries.isEmpty else {
            throw WeatherServiceError.decodingFailed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "h a"
        labelFormatter.timeZone = timeZone
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")

        var points: [HourlyTemperaturePoint] = []
        for index in decoded.time.indices {
            guard let date = formatter.date(from: decoded.time[index]) else { continue }
            let valuesAtHour = decoded.memberSeries.compactMap { series -> Double? in
                guard index < series.count else { return nil }
                return series[index]
            }
            guard !valuesAtHour.isEmpty else { continue }
            let mean = valuesAtHour.reduce(0, +) / Double(valuesAtHour.count)
            points.append(
                HourlyTemperaturePoint(
                    date: date,
                    hourLabel: labelFormatter.string(from: date),
                    meanF: mean,
                    minF: valuesAtHour.min() ?? mean,
                    maxF: valuesAtHour.max() ?? mean,
                    precipitationProbability: precipitationByTime[decoded.time[index]] ?? 0
                )
            )
        }

        let cutoff = Date().addingTimeInterval(-1800)
        let upcoming = Array(points.filter { $0.date >= cutoff }.prefix(24))

        guard !upcoming.isEmpty else {
            throw WeatherServiceError.decodingFailed
        }

        return HourlyForecast(timeZone: timeZone, points: upcoming)
    }

    private func fetchPrecipitationProbabilities(for coordinate: CLLocationCoordinate2D) async throws -> [String: Int] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
        guard let url = components.url else { throw WeatherServiceError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(HourlyPrecipitationResponse.self, from: data)
        var result: [String: Int] = [:]
        for index in decoded.hourly.time.indices where index < decoded.hourly.precipitation_probability.count {
            result[decoded.hourly.time[index]] = decoded.hourly.precipitation_probability[index]
        }
        return result
    }
}

private struct HourlyPrecipitationResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let precipitation_probability: [Int]
    }
    let hourly: Hourly
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

private struct EnsembleResponse: Decodable {
    let timezone: String
    let time: [String]
    let memberSeries: [[Double]]

    private enum TopLevelKeys: String, CodingKey {
        case timezone
        case hourly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TopLevelKeys.self)
        timezone = try container.decode(String.self, forKey: .timezone)

        let hourlyContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .hourly)

        guard let timeKey = DynamicCodingKey(stringValue: "time") else {
            throw WeatherServiceError.decodingFailed
        }
        time = try hourlyContainer.decode([String].self, forKey: timeKey)

        var members: [(Int, [Double])] = []
        for key in hourlyContainer.allKeys {
            let name = key.stringValue
            guard name == "temperature_2m" || name.hasPrefix("temperature_2m_member") else { continue }
            guard let values = try? hourlyContainer.decode([Double].self, forKey: key) else { continue }
            let index = name == "temperature_2m" ? 0 : Int(name.replacingOccurrences(of: "temperature_2m_member", with: "")) ?? Int.max
            members.append((index, values))
        }
        memberSeries = members.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}
