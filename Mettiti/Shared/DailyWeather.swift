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
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown conditions"
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
