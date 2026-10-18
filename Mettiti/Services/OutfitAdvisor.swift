import Foundation
import FoundationModels
import Synchronization

enum OutfitAdvisorError: Error, LocalizedError {
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

    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation {
        try Self.checkAvailability()
        let response = try await Self.makeSession().respond(to: Self.prompt(for: weather, unit: unitProvider()), generating: OutfitRecommendation.self)
        return response.content
    }

    /// Creates the next recommendation's session and loads the model into memory, so it can run
    /// while the weather is still loading (#23). Does nothing when the model is unavailable.
    func prewarm() {
        guard case .available = SystemLanguageModel.default.availability else { return }
        let session = Self.makeSession()
        session.prewarm()
        preparedSession.store(session)
    }

    /// Streams the recommendation, reporting the suggestion so far after each update. Uses the
    /// session from `prewarm()` if there is one.
    func recommendation(for weather: DailyWeather, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        try Self.checkAvailability()
        let session = preparedSession.take() ?? Self.makeSession()
        let stream = session.streamResponse(to: Self.prompt(for: weather, unit: unitProvider()), generating: OutfitRecommendation.self)
        for try await snapshot in stream {
            await onPartial(Self.draft(from: snapshot.content))
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

    private static func checkAvailability() throws {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw OutfitAdvisorError.modelUnavailable(message(for: model.availability))
        }
    }

    private static let promptLocale = Locale(identifier: "en_US_POSIX")

    static let instructions = """
    You are a friendly daily outfit and packing assistant. Given today's weather, \
    recommend what someone should wear and bring. Always consider sun protection \
    (sunglasses, sunscreen, hat), rain protection (umbrella, raincoat), and \
    temperature layering (light or heavy jacket) when relevant to the forecast. \
    Keep recommendations practical, specific, and concise. \
    In the summary and in each item's reason, never quote numeric temperatures \
    or temperature units; describe temperature qualitatively instead, such as \
    "chilly morning", "mild afternoon", or "hot and sunny".
    """

    /// `locale` only decides what `.system` means. Temperatures are always written in a fixed form with an
    /// explicit unit ("72°F"), because the model reads them, not the user. The condition is whatever the
    /// weather provider returned, so it's in the user's language.
    static func prompt(for weather: DailyWeather, unit: TemperatureUnit, locale: Locale = .autoupdatingCurrent) -> String {
        let unit = unit.resolved(for: locale)
        func temperature(_ fahrenheit: Double) -> String {
            unit.formatted(fahrenheit: fahrenheit, width: .abbreviated, locale: promptLocale)
        }
        return """
        Today's forecast:
        - Condition: \(weather.conditionDescription)
        - High: \(temperature(weather.highTemperatureF)), Low: \(temperature(weather.lowTemperatureF))
        - Chance of precipitation: \(weather.precipitationProbability)%
        - UV index: \(weather.uvIndex)
        - Wind: \(Int(weather.windSpeedMph.rounded())) mph

        Recommend what to wear and bring today.
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
