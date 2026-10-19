import Foundation
import FoundationModels
import Synchronization

enum OutfitAdvisorError: UserFacingError {
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return reason
        }
    }
}

struct OutfitAdvisor: Sendable {
    var unitProvider: @Sendable () -> TemperatureUnit = { SharedStore.loadTemperatureUnit() }
    /// The advice covers the forecast from this moment on.
    var now: @Sendable () -> Date = { .now }
    private let preparedSession = PreparedSession()

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?) async throws -> OutfitRecommendation {
        try Self.checkAvailability()
        let response = try await Self.makeSession().respond(to: Self.prompt(for: weather, hourly: hourly, now: now(), unit: unitProvider()), generating: OutfitRecommendation.self)
        return response.content
    }

    /// Creates the next recommendation's session and loads the model into memory, so it can run
    /// while the weather is still loading (#23). Does nothing when the model is unavailable.
    func prewarm() {
        guard Self.isAvailable else { return }
        let session = Self.makeSession()
        session.prewarm()
        preparedSession.store(session)
    }

    /// Streams the recommendation, reporting the suggestion so far after each update. Uses the
    /// session from `prewarm()` if there is one.
    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        try Self.checkAvailability()
        let session = preparedSession.take() ?? Self.makeSession()
        let stream = session.streamResponse(to: Self.prompt(for: weather, hourly: hourly, now: now(), unit: unitProvider()), generating: OutfitRecommendation.self)
        for try await partial in stream {
            await onPartial(Self.draft(from: partial.content))
        }
        return try await stream.collect().content
    }

    /// The suggestion so far: fields the model hasn't reached are empty, and items appear once
    /// they have an emoji and a name.
    static func draft(from partial: OutfitRecommendation.PartiallyGenerated) -> OutfitRecommendation {
        OutfitRecommendation(
            summary: partial.summary ?? "",
            items: (partial.items ?? []).compactMap { item in
                guard let emoji = item.emoji, let name = item.name else { return nil }
                return RecommendedItem(emoji: emoji, name: name, reason: item.reason ?? "")
            }
        )
    }

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Instructions { instructions })
    }

    private static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static func checkAvailability() throws {
        guard isAvailable else {
            throw OutfitAdvisorError.modelUnavailable(message(for: SystemLanguageModel.default.availability))
        }
    }

    private static let promptLocale = Locale(identifier: "en_US_POSIX")

    static let instructions = """
    You are a friendly outfit and packing assistant. Given the weather from now until \
    the end of the forecast, recommend what someone should wear and bring for that time. \
    Consider rain protection (umbrella, raincoat) and temperature layering (light or heavy \
    jacket) when relevant to the forecast. Each temperature comes with how it feels (freezing, \
    cold, cool, mild, warm or hot); base clothing on how it feels, whatever the time of day. \
    Only suggest sun protection (sunglasses, sunscreen, \
    hat) when the forecast shows meaningful UV during daylight hours; never for hours after \
    dark. When the weather changes during the forecast, describe the change in words, such as \
    "bright until sunset" or "cooling off after 7", instead of averaging it away. \
    Keep recommendations practical, specific, and concise. \
    In the summary and in each item's reason, never quote numeric temperatures \
    or temperature units; describe temperature qualitatively instead, such as \
    "chilly morning", "mild afternoon", or "hot and sunny".
    """

    /// Covers `ForecastWindow.span` from `now`, hour by hour, or the whole day when there's no
    /// hourly forecast for it.
    ///
    /// `locale` only decides what `.system` means. Temperatures are always written in a fixed form with an
    /// explicit unit and how they feel ("72°F (warm)"), and times in English ("4 PM"), because the model
    /// reads them, not the user. Conditions are in the user's language, like the weather provider's own
    /// descriptions. Without an hourly forecast there's no location time zone, so times are in
    /// `deviceTimeZone`.
    static func prompt(for weather: DailyWeather, hourly: HourlyForecast?, now: Date, unit: TemperatureUnit, locale: Locale = .autoupdatingCurrent, deviceTimeZone: TimeZone = .autoupdatingCurrent) -> String {
        let unit = unit.resolved(for: locale)
        func temperature(_ fahrenheit: Double) -> String {
            // The feel goes by the rounded value shown, so two hours that both read 8°C feel the same.
            let shown = unit.convert(fromFahrenheit: fahrenheit, locale: promptLocale).rounded()
            return "\(unit.formatted(fahrenheit: fahrenheit, width: .abbreviated, locale: promptLocale)) (\(feel(shown, in: unit)))"
        }
        let timeZone = hourly?.timeZone ?? deviceTimeZone
        func formatted(_ date: Date, _ style: Date.FormatStyle) -> String {
            var style = style
            style.timeZone = timeZone
            // A plain space before "PM" instead of the narrow no-break one the format uses.
            return date.formatted(style.locale(promptLocale)).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        func hour(_ date: Date) -> String { formatted(date, .dateTime.hour()) }
        func clockTime(_ date: Date) -> String { formatted(date, .dateTime.hour().minute()) }

        var currentTime = "Current local time: \(clockTime(now))."
        let window = hourly.map { ForecastWindow(forecast: $0, span: ForecastWindow.span(startingAt: now, in: timeZone)) }
        guard let window, let high = window.high, let low = window.low else {
            // No sunset to go by, so assume it's dark late in the evening and at night.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let localHour = calendar.component(.hour, from: now)
            let isDark = localHour >= 20 || localHour < 6
            if isDark {
                currentTime += " It's dark outside, so sun protection isn't needed."
            }
            return wholeDayPrompt(for: weather, currentTime: currentTime, isDark: isDark, temperature: temperature)
        }

        switch window.isDaylightAtStart {
        case true: currentTime += " The sun is up."
        case false: currentTime += " The sun is down."
        case nil: break
        }

        var summary = ["- High: \(temperature(high.meanF)) at \(hour(high.date)), Low: \(temperature(low.meanF)) at \(hour(low.date))"]
        if let wettest = window.wettest, let probability = wettest.precipitationProbability {
            summary.append("- Highest chance of precipitation: \(probability)% at \(hour(wettest.date))")
        }
        if let windiest = window.windiest, let speed = windiest.windSpeedMph {
            summary.append("- Strongest wind: \(Int(speed.rounded())) mph at \(hour(windiest.date))")
        }
        for event in window.sunEvents {
            summary.append("- \(event.kind == .sunrise ? "Sunrise" : "Sunset") at \(clockTime(event.date))")
        }
        if let peak = window.peakDaylightUV, let uvIndex = peak.uvIndex, window.hasMeaningfulDaylightUV {
            summary.append("- Daylight UV index peaks at \(Int(uvIndex.rounded())) at \(hour(peak.date))")
        } else if window.hasDaylight {
            summary.append("- Daylight UV index stays low, so sun protection isn't needed.")
        } else {
            summary.append("- No daylight hours in this forecast, so sun protection isn't needed.")
        }

        let hours = window.hours.map { point in
            var parts = [temperature(point.meanF)]
            if let code = point.conditionCode { parts.append(WMOWeatherCode.description(for: code)) }
            if let probability = point.precipitationProbability { parts.append("\(probability)% chance of precipitation") }
            if let uvIndex = point.uvIndex { parts.append("UV index \(Int(uvIndex.rounded()))") }
            if let speed = point.windSpeedMph { parts.append("wind \(Int(speed.rounded())) mph") }
            if let isDaylight = point.isDaylight { parts.append(isDaylight ? "daylight" : "dark") }
            return "- \(hour(point.date)): \(parts.joined(separator: ", "))"
        }

        let end = hour(window.span.end)
        return """
        \(currentTime)

        Forecast from now until \(end):
        \(summary.joined(separator: "\n"))

        Hour by hour:
        \(hours.joined(separator: "\n"))

        Recommend what to wear and bring from now until \(end).
        """
    }

    /// How a whole-degree temperature in `unit` (Celsius or Fahrenheit) feels, so the model doesn't
    /// judge the number itself: on its own it called 30°C at night "chilly". Each unit has its own
    /// whole-degree bands, so the same number always gets the same word.
    private static func feel(_ temperature: Double, in unit: TemperatureUnit) -> String {
        let bands: [Double] = unit == .fahrenheit ? [32, 46, 59, 72, 84] : [0, 8, 15, 22, 29]
        let words = ["freezing", "cold", "cool", "mild", "warm"]
        return zip(bands, words).first { temperature < $0.0 }?.1 ?? "hot"
    }

    /// For when there's no hourly forecast to cover: the whole day's high, low and maximums.
    /// It leaves out the day's peak UV, which may have passed, and after dark asks about the night,
    /// so a plan made in the evening doesn't suggest sunscreen.
    private static func wholeDayPrompt(for weather: DailyWeather, currentTime: String, isDark: Bool, temperature: (Double) -> String) -> String {
        """
        \(currentTime)

        \(isDark ? "Today's forecast, including the hours that have passed:" : "Today's forecast:")
        - Condition: \(weather.conditionDescription)
        - High: \(temperature(weather.highTemperatureF)), Low: \(temperature(weather.lowTemperatureF))
        - Chance of precipitation: \(weather.precipitationProbability)%
        - Wind: \(Int(weather.windSpeedMph.rounded())) mph

        Recommend what to wear and bring for the rest of \(isDark ? "tonight" : "today").
        """
    }

    private static func message(for availability: SystemLanguageModel.Availability) -> String {
        guard case .unavailable(let reason) = availability else {
            return String(localized: "AI recommendations aren't available right now.")
        }
        switch reason {
        case .deviceNotEligible:
            return String(localized: "This device doesn't support Apple Intelligence.")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Turn on Apple Intelligence in Settings to get AI recommendations.")
        case .modelNotReady:
            return String(localized: "The on-device model is still downloading. Try again shortly.")
        @unknown default:
            return String(localized: "AI recommendations aren't available right now.")
        }
    }
}

/// Holds the session `prewarm()` made until a recommendation takes it. Each session is used
/// for one recommendation only, so later ones don't carry an earlier day's transcript.
private final class PreparedSession: Sendable {
    private let session = Mutex<LanguageModelSession?>(nil)

    func store(_ newSession: LanguageModelSession) {
        session.withLock { $0 = newSession }
    }

    func take() -> LanguageModelSession? {
        session.withLock { $0.take() }
    }
}
