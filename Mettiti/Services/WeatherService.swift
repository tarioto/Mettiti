import Foundation
import CoreLocation

enum WeatherServiceError: Error, LocalizedError {
    case invalidResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Couldn't reach the weather service. Check your connection and try again."
        case .decodingFailed:
            return "Received an unexpected response from the weather service."
        }
    }
}

struct WeatherService {
    func fetchTodayForecast(for coordinate: CLLocationCoordinate2D) async throws -> DailyWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,windspeed_10m_max,weathercode"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "windspeed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]

        guard let url = components.url else { throw WeatherServiceError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }

        return try Self.dailyWeather(from: data)
    }

    /// `deviceLocale` stands in for the device's settings, which a fresh
    /// `DateFormatter` picks up; tests pass e.g. a Buddhist-calendar locale.
    static func dailyWeather(from data: Data, deviceLocale: Locale = .current) throws -> DailyWeather {
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

        return DailyWeather(
            date: date,
            highTemperatureF: high,
            lowTemperatureF: low,
            precipitationProbability: precipitation,
            uvIndex: uv,
            windSpeedMph: wind,
            conditionCode: code,
            conditionDescription: WMOWeatherCode.description(for: code)
        )
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
    let timezone: String?
    let utc_offset_seconds: Int?
    let daily: Daily

    /// The forecast location's time zone (requested with `timezone=auto`).
    var forecastTimeZone: TimeZone? {
        if let timezone, let zone = TimeZone(identifier: timezone) { return zone }
        if let utc_offset_seconds { return TimeZone(secondsFromGMT: utc_offset_seconds) }
        return nil
    }
}
