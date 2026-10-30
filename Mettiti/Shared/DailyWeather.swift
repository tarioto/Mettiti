import Foundation
import WeatherKit

struct DailyWeather: Sendable, Codable, Hashable {
    let date: Date
    let highTemperatureF: Double
    let lowTemperatureF: Double
    let precipitationProbability: Int
    let uvIndex: Double
    let windSpeedMph: Double
    let conditionCode: Int
    /// The condition's English name as it was when the plan was fetched. Only for snapshots saved
    /// before `condition` existed: new ones still fill it in, so an older widget keeps working.
    /// Follow-up: remove it one release after `condition` ships.
    let conditionDescription: String
    /// What kind of weather it is, named in the current language at render time. Nil in snapshots
    /// saved before it was stored, which show `conditionDescription` until the next refresh.
    var condition: WeatherConditionKind? = nil

    /// The condition's name in the current language, or the stored text when there's no condition.
    var localizedConditionDescription: String {
        conditionDescription(in: .autoupdatingCurrent)
    }

    func conditionDescription(in locale: Locale) -> String {
        condition?.localizedDescription(locale: locale) ?? conditionDescription
    }
}

/// The kind of weather a provider reported, kept apart from its wording so the name is written
/// in the current language when shown, not the one the plan was fetched in.
enum WeatherConditionKind: Codable, Sendable, Hashable {
    /// An Open-Meteo WMO weather code.
    case wmo(Int)
    /// A WeatherKit condition, by its raw value so a case this version doesn't know still decodes.
    case weatherKit(String)

    init(_ condition: WeatherCondition) {
        self = .weatherKit(condition.rawValue)
    }

    /// The condition's name in the current language: our catalog for WMO codes, Apple's own
    /// description for WeatherKit conditions. Nil for a WeatherKit condition this version doesn't know.
    func localizedDescription(locale: Locale = .autoupdatingCurrent) -> String? {
        switch self {
        case .wmo(let code):
            return WMOWeatherCode.description(for: code, locale: locale)
        case .weatherKit(let rawValue):
            return WeatherCondition(rawValue: rawValue)?.description
        }
    }
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
    static func description(for code: Int, locale: Locale = .autoupdatingCurrent) -> String {
        // A resource carries the locale so it picks the language, not just the number formats.
        func name(_ resource: LocalizedStringResource) -> String {
            var resource = resource
            resource.locale = locale
            return String(localized: resource)
        }
        switch code {
        case 0: return name(LocalizedStringResource("Clear sky", table: "Shared"))
        case 1: return name(LocalizedStringResource("Mainly clear", table: "Shared"))
        case 2: return name(LocalizedStringResource("Partly cloudy", table: "Shared"))
        case 3: return name(LocalizedStringResource("Overcast", table: "Shared"))
        case 45, 48: return name(LocalizedStringResource("Foggy", table: "Shared"))
        case 51, 53, 55: return name(LocalizedStringResource("Drizzle", table: "Shared"))
        case 56, 57: return name(LocalizedStringResource("Freezing drizzle", table: "Shared"))
        case 61, 63, 65: return name(LocalizedStringResource("Rain", table: "Shared"))
        case 66, 67: return name(LocalizedStringResource("Freezing rain", table: "Shared"))
        case 71, 73, 75: return name(LocalizedStringResource("Snow", table: "Shared"))
        case 77: return name(LocalizedStringResource("Snow grains", table: "Shared"))
        case 80, 81, 82: return name(LocalizedStringResource("Rain showers", table: "Shared"))
        case 85, 86: return name(LocalizedStringResource("Snow showers", table: "Shared"))
        case 95: return name(LocalizedStringResource("Thunderstorm", table: "Shared"))
        case 96, 99: return name(LocalizedStringResource("Thunderstorm with hail", table: "Shared"))
        default: return name(LocalizedStringResource("Unknown conditions", table: "Shared"))
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
