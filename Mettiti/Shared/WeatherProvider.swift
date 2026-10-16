import Foundation

enum WeatherProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    case openMeteo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openMeteo: return "Open-Meteo"
        case .apple: return "Apple Weather"
        }
    }

    /// Text attribution for places that can't load Apple's remote logo image (e.g. widgets).
    /// U+F8FF renders as the Apple logo on Apple platforms.
    var attributionText: String {
        switch self {
        case .openMeteo: return "Weather data by Open-Meteo.com"
        case .apple: return "\u{F8FF}Weather"
        }
    }

    var attributionURL: URL {
        switch self {
        case .openMeteo: return URL(string: "https://open-meteo.com/")!
        case .apple: return URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!
        }
    }
}
