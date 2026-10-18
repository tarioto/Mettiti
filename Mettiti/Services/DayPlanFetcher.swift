import CoreLocation
import FoundationModels

/// The network and on-device model calls behind a day plan, so tests can stub them out.
protocol DayPlanFetching: Sendable {
    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?)
    func recommendationAvailability() async -> RecommendationAvailability
    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation
    /// Starts loading the on-device model so a recommendation requested soon after starts faster.
    func prewarmRecommendation()
    /// Like `recommendation(for:)`, but reports the suggestion so far as the model writes it.
    func recommendation(for weather: DailyWeather, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation
}

struct DayPlanFetcher: DayPlanFetching {
    private let weatherService = WeatherService()
    private let hourlyForecastService = HourlyForecastService()
    private let appleWeatherService = AppleWeatherService()
    private let outfitAdvisor = OutfitAdvisor()

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        switch provider {
        case .openMeteo:
            // The forecast request also carries the hourly chance of rain for the chart.
            async let ensembleTask: HourlyForecast? = try? hourlyForecastService.fetchHourlyForecast(for: coordinate)
            let forecast = try await weatherService.fetchForecast(for: coordinate)
            let hourly = (await ensembleTask)?.applyingPrecipitation(forecast.hourlyPrecipitation)
            return (forecast.daily, hourly)
        case .apple:
            // WeatherKit has no hourly uncertainty, so borrow Open-Meteo's ensemble spread
            // for the chart's band. If that request fails, the chart just shows the line.
            async let ensembleTask: HourlyForecast? = try? hourlyForecastService.fetchHourlyForecast(for: coordinate)
            let forecast = try await appleWeatherService.fetchForecast(for: coordinate)
            guard let ensemble = await ensembleTask else { return (forecast.daily, forecast.hourly) }
            return (forecast.daily, forecast.hourly.applyingSpread(from: ensemble))
        }
    }

    func recommendationAvailability() async -> RecommendationAvailability {
        Self.currentAvailability()
    }

    /// The on-device model's availability right now. Synchronous for callers that can't
    /// await, e.g. scheduling background work as the app moves to the background.
    static func currentAvailability() -> RecommendationAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        @unknown default:
            // A reason this SDK doesn't know yet: treat it as temporary so the user can retry.
            return .unavailable(.modelNotReady)
        }
    }

    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation {
        try await outfitAdvisor.recommendation(for: weather)
    }

    func prewarmRecommendation() {
        outfitAdvisor.prewarm()
    }

    func recommendation(for weather: DailyWeather, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        try await outfitAdvisor.recommendation(for: weather, onPartial: onPartial)
    }
}
