import Foundation

struct DailyWeather: Sendable, Codable {
    let date: Date
    let highTemperatureF: Double
    let lowTemperatureF: Double
    let precipitationProbability: Int
    let uvIndex: Double
    let windSpeedMph: Double
    let conditionCode: Int
    let conditionDescription: String
}

extension DailyWeather {
    static let placeholder = DailyWeather(
        date: .now,
        highTemperatureF: 72,
        lowTemperatureF: 58,
        precipitationProbability: 20,
        uvIndex: 5,
        windSpeedMph: 8,
        conditionCode: 1,
        conditionDescription: "Partly Cloudy"
    )
}

enum WMOWeatherCode {
    static func description(for code: Int) -> String {
        switch code {
        case 0: return String(localized: "Clear sky", table: "Shared")
        case 1: return String(localized: "Mainly clear", table: "Shared")
        case 2: return String(localized: "Partly cloudy", table: "Shared")
        case 3: return String(localized: "Overcast", table: "Shared")
        case 45, 48: return String(localized: "Foggy", table: "Shared")
        case 51, 53, 55: return String(localized: "Drizzle", table: "Shared")
        case 56, 57: return String(localized: "Freezing drizzle", table: "Shared")
        case 61, 63, 65: return String(localized: "Rain", table: "Shared")
        case 66, 67: return String(localized: "Freezing rain", table: "Shared")
        case 71, 73, 75: return String(localized: "Snow", table: "Shared")
        case 77: return String(localized: "Snow grains", table: "Shared")
        case 80, 81, 82: return String(localized: "Rain showers", table: "Shared")
        case 85, 86: return String(localized: "Snow showers", table: "Shared")
        case 95: return String(localized: "Thunderstorm", table: "Shared")
        case 96, 99: return String(localized: "Thunderstorm with hail", table: "Shared")
        default: return String(localized: "Unknown conditions", table: "Shared")
        }
    }

    static func symbolName(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }
}
