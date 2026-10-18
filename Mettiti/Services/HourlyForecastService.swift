import Foundation
import CoreLocation

/// The ensemble's hourly temperature spread. It has no chance of rain: that comes from the
/// main forecast request instead (see `HourlyForecast.applyingPrecipitation`).
struct HourlyForecastService {
    func fetchHourlyForecast(for coordinate: CLLocationCoordinate2D) async throws -> HourlyForecast {
        var components = URLComponents(string: "https://ensemble-api.open-meteo.com/v1/ensemble")!
        components.queryItems = coordinate.weatherAPIQueryItems + [
            URLQueryItem(name: "hourly", value: "temperature_2m"),
            URLQueryItem(name: "models", value: "icon_seamless"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { throw WeatherServiceError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }

        return try Self.hourlyForecast(from: data, now: Date())
    }

    /// The 24 hours from `now` (including the hour in progress) in an ensemble response.
    static func hourlyForecast(from data: Data, now: Date) throws -> HourlyForecast {
        let decoded: EnsembleResponse
        do {
            decoded = try JSONDecoder().decode(EnsembleResponse.self, from: data)
        } catch {
            throw WeatherServiceError.decodingFailed
        }

        guard
            let timeZone = TimeZone(identifier: decoded.timezone),
            let strategy = OpenMeteoHourlyTime.parseStrategy(utcOffsetSeconds: decoded.utcOffsetSeconds),
            !decoded.memberSeries.isEmpty
        else {
            throw WeatherServiceError.decodingFailed
        }

        var points: [HourlyTemperaturePoint] = []
        for index in decoded.time.indices {
            guard let date = try? Date(decoded.time[index], strategy: strategy) else { continue }
            let valuesAtHour = decoded.memberSeries.compactMap { series -> Double? in
                guard index < series.count else { return nil }
                return series[index]
            }
            guard !valuesAtHour.isEmpty else { continue }
            let mean = valuesAtHour.reduce(0, +) / Double(valuesAtHour.count)
            points.append(
                HourlyTemperaturePoint(
                    date: date,
                    meanF: mean,
                    minF: valuesAtHour.min() ?? mean,
                    maxF: valuesAtHour.max() ?? mean,
                    precipitationProbability: nil
                )
            )
        }

        let cutoff = now.addingTimeInterval(-1800)
        let upcoming = Array(points.filter { $0.date >= cutoff }.prefix(24))

        guard !upcoming.isEmpty else {
            throw WeatherServiceError.decodingFailed
        }

        return HourlyForecast(timeZone: timeZone, points: upcoming)
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

private struct EnsembleResponse: Decodable {
    let timezone: String
    let utcOffsetSeconds: Int?
    let time: [String]
    let memberSeries: [[Double]]

    private enum TopLevelKeys: String, CodingKey {
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
        case hourly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TopLevelKeys.self)
        timezone = try container.decode(String.self, forKey: .timezone)
        utcOffsetSeconds = try container.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds)

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
