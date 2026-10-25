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
    private let preparedSession = PreparedSession()

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) async throws -> OutfitRecommendation {
        try Self.checkAvailability()
        let language = Self.responseLanguage()
        let request = Self.request(for: weather, hourly: hourly, span: span, unit: unitProvider(), language: language)
        let response = try await Self.makeSession(language: language).respond(to: request.prompt, generating: OutfitRecommendation.self)
        return request.droppingWarmLayersIfWarmThroughout(response.content)
    }

    /// Creates the next recommendation's session and loads the model into memory, so it can run
    /// while the weather is still loading (#23). Does nothing when the model is unavailable.
    func prewarm() {
        guard Self.isAvailable else { return }
        let session = Self.makeSession(language: Self.responseLanguage())
        session.prewarm()
        preparedSession.store(session)
    }

    /// Streams the recommendation, reporting the suggestion so far after each update. Uses the
    /// session from `prewarm()` if there is one.
    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        try Self.checkAvailability()
        let language = Self.responseLanguage()
        let session = preparedSession.take() ?? Self.makeSession(language: language)
        let request = Self.request(for: weather, hourly: hourly, span: span, unit: unitProvider(), language: language)
        let stream = session.streamResponse(to: request.prompt, generating: OutfitRecommendation.self)
        for try await partial in stream {
            await onPartial(request.draft(from: partial.content))
        }
        return request.droppingWarmLayersIfWarmThroughout(try await stream.collect().content)
    }

    /// What to ask the model about the plan, and whether to drop warm layers from its answer.
    static func request(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, unit: TemperatureUnit, locale: Locale = .autoupdatingCurrent, language: String = defaultLanguage) -> OutfitRequest {
        OutfitRequest(
            prompt: prompt(for: weather, hourly: hourly, span: span, unit: unit, locale: locale, language: language),
            isWarmThroughout: isWarmThroughout(weather, hourly: hourly, span: span, unit: unit.resolved(for: locale))
        )
    }

    /// Whether even the coldest part of the plan feels warm or hot: the span's low hour, or the
    /// day's low without an hourly forecast for it. `unit` must be resolved.
    private static func isWarmThroughout(_ weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, unit: TemperatureUnit) -> Bool {
        let window = hourly.map { ForecastWindow(forecast: $0, span: span.interval) }
        let coldestF = window?.low?.meanF ?? weather.lowTemperatureF
        return TemperatureFeel(fahrenheit: coldestF, in: unit).isWarm
    }

    /// The suggestion so far: fields the model hasn't reached are empty, and items appear once
    /// they have an emoji and a name. With `waitingForWholeNames`, items wait for the model to
    /// start their reason, which comes after the name.
    static func draft(from partial: OutfitRecommendation.PartiallyGenerated, waitingForWholeNames: Bool = false) -> OutfitRecommendation {
        OutfitRecommendation(
            summary: partial.summary ?? "",
            items: (partial.items ?? []).compactMap { item in
                guard let emoji = item.emoji, let name = item.name else { return nil }
                if waitingForWholeNames && item.reason == nil { return nil }
                return RecommendedItem(emoji: emoji, name: name, reason: item.reason ?? "")
            }
        )
    }

    private static func makeSession(language: String) -> LanguageModelSession {
        LanguageModelSession(instructions: Instructions { sessionInstructions(language: language) })
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

    static let defaultLanguage = "English"

    /// The English name of the language the model should answer in: the app's current localization,
    /// or English when Foundation Models doesn't support it. `appLanguages` is in preference order,
    /// as `Bundle.preferredLocalizations` gives it.
    static func responseLanguage(
        appLanguages: [String] = Bundle.main.preferredLocalizations,
        supports: (Locale) -> Bool = { SystemLanguageModel.default.supportsLocale($0) }
    ) -> String {
        guard let identifier = appLanguages.first else { return defaultLanguage }
        let locale = Locale(identifier: identifier)
        guard supports(locale),
              let code = locale.language.languageCode?.identifier,
              let name = Locale(identifier: "en").localizedString(forLanguageCode: code)
        else { return defaultLanguage }
        return name
    }

    /// Tells the model which language to write the summary, item names and reasons in.
    /// Item emojis are unaffected.
    static func responseLanguageLine(_ language: String) -> String {
        "Respond in \(language): write the summary and each item's name and reason in \(language)."
    }

    static func sessionInstructions(language: String) -> String {
        "\(instructions)\n\n\(responseLanguageLine(language))"
    }

    static let instructions = """
    You are a friendly outfit and packing assistant. Given the weather from now until \
    the end of the forecast, recommend what someone should wear and bring for that time. \
    Consider rain protection (umbrella, raincoat) and temperature layering (light or heavy \
    jacket) when relevant to the forecast. Each temperature comes with how it feels (freezing, \
    cold, cool, mild, warm or hot); base clothing on how it feels, whatever the time of day. \
    Only suggest a jacket, sweater or other warm layer when some hour feels mild or colder; \
    a warm evening that cools off a little is still warm. \
    Only suggest sun protection (sunglasses, sunscreen, \
    hat) when the forecast shows meaningful UV during daylight hours; never for hours after \
    dark. When the weather changes during the forecast, describe the change in words, such as \
    "bright until sunset" or "cooling off after 7", instead of averaging it away. \
    Keep recommendations practical, specific, and concise. \
    In the summary and in each item's reason, never quote numeric temperatures \
    or temperature units; describe temperature qualitatively instead, such as \
    "chilly morning", "mild afternoon", or "hot and sunny".
    """

    /// Covers `span`, hour by hour, or the whole day when there's no hourly forecast for it.
    ///
    /// `locale` only decides what `.system` means. Temperatures are always written in a fixed form with an
    /// explicit unit and how they feel ("72°F (warm)"), and times in English ("4 PM"), because the model
    /// reads them, not the user. Conditions are in the user's language, like the weather provider's own
    /// descriptions. Times are in the span's time zone.
    static func prompt(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, unit: TemperatureUnit, locale: Locale = .autoupdatingCurrent, language: String = defaultLanguage) -> String {
        let unit = unit.resolved(for: locale)
        func temperature(_ fahrenheit: Double) -> String {
            "\(unit.formatted(fahrenheit: fahrenheit, width: .abbreviated, locale: promptLocale)) (\(TemperatureFeel(fahrenheit: fahrenheit, in: unit).rawValue))"
        }
        let warmThroughout = isWarmThroughout(weather, hourly: hourly, span: span, unit: unit)
        // The weather is stored in mph; the model gets km/h where the locale doesn't use miles.
        func wind(_ mph: Double) -> String {
            let usesMiles = locale.measurementSystem == .us || locale.measurementSystem == .uk
            return usesMiles ? "\(Int(mph.rounded())) mph" : "\(Int((mph * 1.609344).rounded())) km/h"
        }
        let now = span.interval.start
        let timeZone = span.timeZone
        func formatted(_ date: Date, _ style: Date.FormatStyle) -> String {
            var style = style
            style.timeZone = timeZone
            // A plain space before "PM" instead of the narrow no-break one the format uses.
            return date.formatted(style.locale(promptLocale)).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        func hour(_ date: Date) -> String { formatted(date, .dateTime.hour()) }
        func clockTime(_ date: Date) -> String { formatted(date, .dateTime.hour().minute()) }

        var currentTime = "Current local time: \(clockTime(now))."
        let window = hourly.map { ForecastWindow(forecast: $0, span: span.interval) }
        guard let window, let high = window.high, let low = window.low else {
            // No sunset to go by, so assume it's dark late in the evening and at night.
            let isDark = ForecastWindow.assumesDark(at: now, in: timeZone)
            if isDark {
                currentTime += " It's dark outside, so sun protection isn't needed."
            }
            let noWarmLayer = warmThroughout ? noWarmLayerLine(low: weather.lowTemperatureF, unit: unit) : nil
            return wholeDayPrompt(for: weather, currentTime: currentTime, isDark: isDark, noWarmLayer: noWarmLayer, temperature: temperature, wind: wind, language: language)
        }

        switch window.isDaylightAtStart {
        case true: currentTime += " The sun is up."
        case false: currentTime += " The sun is down."
        case nil: break
        }

        var summary = ["- High: \(temperature(high.meanF)) at \(hour(high.date)), Low: \(temperature(low.meanF)) at \(hour(low.date))"]
        if warmThroughout {
            summary.append(noWarmLayerLine(low: low.meanF, unit: unit))
        }
        if let wettest = window.wettest, let probability = wettest.precipitationProbability {
            summary.append("- Highest chance of precipitation: \(probability)% at \(hour(wettest.date))")
        }
        if let windiest = window.windiest, let speed = windiest.windSpeedMph {
            summary.append("- Strongest wind: \(wind(speed)) at \(hour(windiest.date))")
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
            if let speed = point.windSpeedMph { parts.append("wind \(wind(speed))") }
            if let isDaylight = point.isDaylight { parts.append(isDaylight ? "daylight" : "dark") }
            return "- \(hour(point.date)): \(parts.joined(separator: ", "))"
        }

        let end = clockTime(window.span.end)
        return """
        \(currentTime)

        Forecast from now until \(end):
        \(summary.joined(separator: "\n"))

        Hour by hour:
        \(hours.joined(separator: "\n"))

        Recommend what to wear and bring from now until \(end). \(responseLanguageLine(language))
        """
    }

    /// Spelled out because the model reads "cooling off" as a reason for a jacket.
    private static func noWarmLayerLine(low fahrenheit: Double, unit: TemperatureUnit) -> String {
        "- Coldest it gets: \(TemperatureFeel(fahrenheit: fahrenheit, in: unit).rawValue), so no jacket, sweater or other warm layer is needed."
    }

    /// How a temperature feels in `unit` (Celsius or Fahrenheit), given with each temperature so
    /// the model doesn't judge the number itself: on its own it called 30°C at night "chilly". The
    /// raw values are the words the prompt uses.
    private enum TemperatureFeel: String {
        case freezing, cold, cool, mild, warm, hot

        /// Each unit has its own whole-degree bands, and the feel goes by the rounded value shown,
        /// so two hours that both read 8°C feel the same.
        init(fahrenheit: Double, in unit: TemperatureUnit) {
            let temperature = unit.convert(fromFahrenheit: fahrenheit, locale: OutfitAdvisor.promptLocale).rounded()
            let bands: [Double] = unit == .fahrenheit ? [32, 46, 59, 72, 84] : [0, 8, 15, 22, 29]
            let feels: [TemperatureFeel] = [.freezing, .cold, .cool, .mild, .warm]
            self = zip(bands, feels).first { temperature < $0.0 }?.1 ?? .hot
        }

        /// Warm enough throughout that no jacket or other warm layer is needed.
        var isWarm: Bool {
            self == .warm || self == .hot
        }
    }

    /// For when there's no hourly forecast to cover: the whole day's high, low and maximums.
    /// It leaves out the day's peak UV, which may have passed, and after dark asks about the night,
    /// so a plan made in the evening doesn't suggest sunscreen.
    private static func wholeDayPrompt(for weather: DailyWeather, currentTime: String, isDark: Bool, noWarmLayer: String?, temperature: (Double) -> String, wind: (Double) -> String, language: String) -> String {
        """
        \(currentTime)

        \(isDark ? "Today's forecast, including the hours that have passed:" : "Today's forecast:")
        - Condition: \(weather.localizedConditionDescription)
        - High: \(temperature(weather.highTemperatureF)), Low: \(temperature(weather.lowTemperatureF))\(noWarmLayer.map { "\n\($0)" } ?? "")
        - Chance of precipitation: \(weather.precipitationProbability)%
        - Wind: \(wind(weather.windSpeedMph))

        Recommend what to wear and bring for the rest of \(isDark ? "tonight" : "today"). \(responseLanguageLine(language))
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

/// What one recommendation asks the model, and whether it's warm enough throughout that warm
/// layers are dropped from the answer.
struct OutfitRequest: Sendable {
    let prompt: String
    let isWarmThroughout: Bool

    /// The prompt says no warm layer is needed when it's warm throughout, but the model still
    /// suggested a heavy jacket for a Bangkok evening that only "cooled off" to warm.
    func droppingWarmLayersIfWarmThroughout(_ recommendation: OutfitRecommendation) -> OutfitRecommendation {
        isWarmThroughout ? recommendation.withoutWarmLayers() : recommendation
    }

    /// The suggestion so far, without warm layers if it's warm throughout. Then items wait until
    /// their name is written, so "Heavy" doesn't show before it becomes "Heavy jacket" and goes.
    func draft(from partial: OutfitRecommendation.PartiallyGenerated) -> OutfitRecommendation {
        droppingWarmLayersIfWarmThroughout(OutfitAdvisor.draft(from: partial, waitingForWholeNames: isWarmThroughout))
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
