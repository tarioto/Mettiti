import Foundation
import CoreLocation

enum WeatherServiceError: Error, LocalizedError {
    case invalidResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Couldn't reach the weather service. Check your connection and try again.")
        case .decodingFailed:
            return String(localized: "Received an unexpected response from the weather service.")
        }
    }
}

/// Today's forecast plus the hourly chance of rain for the hourly chart, from one request.
struct OpenMeteoForecast {
    let daily: DailyWeather
    /// Keyed by the start of each hour. Empty if the response had no usable hourly data.
    let hourlyPrecipitation: [Date: Int]
}

struct WeatherService {
    func fetchForecast(for coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoForecast {
        guard let url = Self.forecastURL(for: coordinate) else { throw WeatherServiceError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }

        return try Self.forecast(from: data)
    }

    /// Two days of hourly data so the chart's next 24 hours are covered late in the day.
    /// The daily values only use the first day.
    static func forecastURL(for coordinate: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = coordinate.weatherAPIQueryItems + [
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,windspeed_10m_max,weathercode"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "windspeed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
        return components.url
    }

    /// `deviceLocale` stands in for the device's settings, which a fresh
    /// `DateFormatter` picks up; tests pass e.g. a Buddhist-calendar locale.
    static func forecast(from data: Data, deviceLocale: Locale = .current) throws -> OpenMeteoForecast {
        let decoded: OpenMeteoResponse
        do {
            decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw WeatherServiceError.decodingFailed
        }

        guard
            let dateString = decoded.daily.time.first,
            let high = decoded.daily.temperature_2m_max.first,
            let low = decoded.daily.temperature_2m_min.first,
            let precipitation = decoded.daily.precipitation_probability_max.first,
            let uv = decoded.daily.uv_index_max.first,
            let wind = decoded.daily.windspeed_10m_max.first,
            let code = decoded.daily.weathercode.first
        else {
            throw WeatherServiceError.decodingFailed
        }

        guard let timeZone = decoded.forecastTimeZone else {
            throw WeatherServiceError.decodingFailed
        }

        let formatter = DateFormatter()
        formatter.locale = deviceLocale
        // Override the device's locale and calendar so they can't change the parse
        // (a Buddhist calendar would read 2026 as Gregorian 1483).
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else {
            throw WeatherServiceError.decodingFailed
        }

        let daily = DailyWeather(
            date: date,
            highTemperatureF: high,
            lowTemperatureF: low,
            precipitationProbability: precipitation,
            uvIndex: uv,
            windSpeedMph: wind,
            conditionCode: code,
            conditionDescription: WMOWeatherCode.description(for: code)
        )
        return OpenMeteoForecast(daily: daily, hourlyPrecipitation: hourlyPrecipitation(from: decoded))
    }

    private static func hourlyPrecipitation(from decoded: OpenMeteoResponse) -> [Date: Int] {
        guard let hourly = decoded.hourly, let utcOffsetSeconds = decoded.utc_offset_seconds else { return [:] }
        let strategy = OpenMeteoHourlyTime.parseStrategy(utcOffsetSeconds: utcOffsetSeconds)
        var result: [Date: Int] = [:]
        for (time, probability) in zip(hourly.time, hourly.precipitation_probability) {
            guard let date = try? Date(time, strategy: strategy), let probability else { continue }
            result[date] = probability
        }
        return result
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int]
        let uv_index_max: [Double]
        let windspeed_10m_max: [Double]
        let weathercode: [Int]
    }
    struct Hourly: Decodable {
        let time: [String]
        let precipitation_probability: [Int?]
    }
    let timezone: String?
    let utc_offset_seconds: Int?
    let daily: Daily
    /// Optional so a malformed hourly block costs only the chart's rain bars, not the forecast.
    let hourly: Hourly?

    private enum CodingKeys: String, CodingKey {
        case timezone, utc_offset_seconds, daily, hourly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        utc_offset_seconds = try container.decodeIfPresent(Int.self, forKey: .utc_offset_seconds)
        daily = try container.decode(Daily.self, forKey: .daily)
        hourly = try? container.decodeIfPresent(Hourly.self, forKey: .hourly)
    }

    /// The forecast location's time zone (requested with `timezone=auto`).
    var forecastTimeZone: TimeZone? {
        if let timezone, let zone = TimeZone(identifier: timezone) { return zone }
        if let utc_offset_seconds { return TimeZone(secondsFromGMT: utc_offset_seconds) }
        return nil
    }
}
