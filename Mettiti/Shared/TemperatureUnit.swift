import Foundation

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case system
    case fahrenheit
    case celsius

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .fahrenheit: return "Fahrenheit"
        case .celsius: return "Celsius"
        }
    }

    var symbol: String {
        resolved == .fahrenheit ? "°F" : "°C"
    }

    /// Follows the device's Settings > General > Language & Region > Temperature Unit when set to `.system`.
    var resolved: TemperatureUnit {
        guard self == .system else { return self }
        return UnitTemperature(forLocale: .autoupdatingCurrent) == .fahrenheit ? .fahrenheit : .celsius
    }

    func displayString(fromFahrenheit value: Double) -> String {
        "\(Int(convert(fromFahrenheit: value).rounded()))°"
    }

    func convert(fromFahrenheit value: Double) -> Double {
        resolved == .fahrenheit ? value : (value - 32) * 5 / 9
    }
}
