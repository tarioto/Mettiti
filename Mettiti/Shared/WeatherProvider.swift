import Foundation

enum WeatherProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    case openMeteo

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .openMeteo: return LocalizedStringResource(stringLiteral: "Open-Meteo")
        case .apple: return LocalizedStringResource("Apple Weather", table: "Shared")
        }
    }

    /// Text attribution for places that can't load Apple's remote logo image (e.g. widgets).
    /// U+F8FF renders as the Apple logo on Apple platforms.
    var attributionText: String {
        switch self {
        case .openMeteo: return String(localized: "Weather data by Open-Meteo.com", table: "Shared")
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
