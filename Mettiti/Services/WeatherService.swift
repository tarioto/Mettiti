import Foundation
import CoreLocation

enum WeatherServiceError: UserFacingError {
    case invalidResponse
    case decodingFailed

    /// The message as a resource, so a caller can pick the language it is written in.
    var message: LocalizedStringResource {
        switch self {
        case .invalidResponse:
            return "Couldn't reach the weather service. Check your connection and try again."
        case .decodingFailed:
            return "Received an unexpected response from the weather service."
        }
    }

    var errorDescription: String? { String(localized: message) }
}

/// Today's forecast plus the hourly forecast, from one request.
struct OpenMeteoForecast {
    let daily: DailyWeather
    /// The 24 hours from now, with sunrises and sunsets. Nil if the response had no usable hourly data.
    let hourly: HourlyForecast?
}

struct WeatherService {
    /// How long a weather request may sit without receiving data before it fails as timed out.
    /// Shorter than URLSession's 60 seconds, so a bad connection gets a message instead of a long wait (#29).
    static let requestTimeout: TimeInterval = 15

    func fetchForecast(for coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoForecast {
        guard let url = Self.forecastURL(for: coordinate) else { throw WeatherServiceError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: Self.requestTimeout))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.invalidResponse
        }

        return try Self.forecast(from: data, now: Date())
    }

    /// Two days of hourly data so the next 24 hours are covered late in the day. The daily
    /// values only use the first day; sunrise and sunset come from both.
    static func forecastURL(for coordinate: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = coordinate.weatherAPIQueryItems + [
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,windspeed_10m_max,weathercode,sunrise,sunset"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,uv_index,windspeed_10m,weathercode,is_day"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "windspeed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
        return components.url
    }

    static func forecast(from data: Data, now: Date) throws -> OpenMeteoForecast {
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

        // A fixed locale and calendar so the device's settings can't change the parse
        // (a Buddhist calendar would read 2026 as Gregorian 1483).
        let strategy = Date.ParseStrategy(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
        guard let date = try? Date(dateString, strategy: strategy) else {
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
            conditionDescription: WMOWeatherCode.description(for: code),
            condition: .wmo(code)
        )
        return OpenMeteoForecast(daily: daily, hourly: hourlyForecast(from: decoded, timeZone: timeZone, now: now))
    }

    /// The 24 hours from `now` (including the hour in progress). Open-Meteo gives a single
    /// value per hour, so min and max equal the mean; DayPlanFetcher layers the ensemble's
    /// spread on top.
    private static func hourlyForecast(from decoded: OpenMeteoResponse, timeZone: TimeZone, now: Date) -> HourlyForecast? {
        guard
            let hourly = decoded.hourly,
            let strategy = OpenMeteoHourlyTime.parseStrategy(utcOffsetSeconds: decoded.utc_offset_seconds)
        else { return nil }
        func value<T>(_ values: [T?]?, at index: Int) -> T? {
            guard let values, index < values.count else { return nil }
            return values[index]
        }
        let allPoints = hourly.time.enumerated().compactMap { index, time -> HourlyTemperaturePoint? in
            guard
                let date = try? Date(time, strategy: strategy),
                let temperature = value(hourly.temperature_2m, at: index)
            else { return nil }
            return HourlyTemperaturePoint(
                date: date,
                meanF: temperature,
                minF: temperature,
                maxF: temperature,
                precipitationProbability: value(hourly.precipitation_probability, at: index),
                uvIndex: value(hourly.uv_index, at: index),
                windSpeedMph: value(hourly.windspeed_10m, at: index),
                conditionCode: value(hourly.weathercode, at: index),
                isDaylight: value(hourly.is_day, at: index).map { $0 == 1 }
            )
        }
        let points = HourlyForecast.upcoming(allPoints, from: now)
        guard !points.isEmpty else { return nil }

        let sunrises = (decoded.daily.sunrise ?? []).compactMap { try? Date($0, strategy: strategy) }.map { SunEvent(kind: .sunrise, date: $0) }
        let sunsets = (decoded.daily.sunset ?? []).compactMap { try? Date($0, strategy: strategy) }.map { SunEvent(kind: .sunset, date: $0) }
        return HourlyForecast(timeZone: timeZone, points: points, sunEvents: (sunrises + sunsets).sorted { $0.date < $1.date })
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
        let sunrise: [String]?
        let sunset: [String]?
    }
    /// Each series is optional, and so is each value, so a gap costs only that value.
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double?]?
        let precipitation_probability: [Int?]?
        let uv_index: [Double?]?
        let windspeed_10m: [Double?]?
        let weathercode: [Int?]?
        let is_day: [Int?]?
    }
    let timezone: String?
    let utc_offset_seconds: Int?
    let daily: Daily
    /// Optional so a malformed hourly block costs only the hourly forecast, not the daily one.
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
