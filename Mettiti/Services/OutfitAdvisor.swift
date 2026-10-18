import Foundation
import FoundationModels

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

    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw OutfitAdvisorError.modelUnavailable(Self.message(for: model.availability))
        }

        let session = LanguageModelSession(instructions: Instructions { Self.instructions })

        let prompt = Self.prompt(for: weather, unit: unitProvider())

        let response = try await session.respond(to: prompt, generating: OutfitRecommendation.self)
        return response.content
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

    /// `locale` only decides what `.system` means. The prompt itself is always English with an explicit
    /// unit ("72°F"), because the model reads it, not the user.
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
