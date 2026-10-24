import Foundation

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case system
    case fahrenheit
    case celsius

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .system: return LocalizedStringResource("System", table: "Shared")
        case .fahrenheit: return LocalizedStringResource("Fahrenheit", table: "Shared")
        case .celsius: return LocalizedStringResource("Celsius", table: "Shared")
        }
    }

    /// `.system` follows `locale`'s temperature unit, which on device is
    /// Settings > General > Language & Region > Temperature Unit (falling back to the region's default).
    func resolved(for locale: Locale = .autoupdatingCurrent) -> TemperatureUnit {
        guard self == .system else { return self }
        return UnitTemperature(forLocale: locale) == .fahrenheit ? .fahrenheit : .celsius
    }

    /// A whole-degree temperature in this unit, written the way `locale` writes temperatures.
    /// The default `.narrow` width is what the UI shows (in the US that's "72°", with no unit letter).
    func formatted(
        fahrenheit value: Double,
        width: Measurement<UnitTemperature>.FormatStyle.UnitWidth = .narrow,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let unit: UnitTemperature = resolved(for: locale) == .fahrenheit ? .fahrenheit : .celsius
        // Round here rather than in the number style so halves round away from zero, and add 0
        // so a value that rounds to -0 prints as "0" instead of "-0".
        let measurement = Measurement(value: convert(fromFahrenheit: value, locale: locale).rounded() + 0, unit: unit)
        return measurement.formatted(
            .measurement(width: width, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }

    /// The day's high and low, e.g. "H:72° L:58°". Shared by the app and the widgets, so it lives in the
    /// `Shared` string table that both targets bundle.
    func formattedHighLow(highFahrenheit: Double, lowFahrenheit: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let high = formatted(fahrenheit: highFahrenheit, locale: locale)
        let low = formatted(fahrenheit: lowFahrenheit, locale: locale)
        return String(
            localized: "H:\(high) L:\(low)",
            table: "Shared",
            locale: locale,
            comment: "Today's high and low temperatures, each already formatted with its unit"
        )
    }

    func convert(fromFahrenheit value: Double, locale: Locale = .autoupdatingCurrent) -> Double {
        resolved(for: locale) == .fahrenheit ? value : (value - 32) * 5 / 9
    }
}
