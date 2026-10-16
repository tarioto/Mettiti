import CoreLocation
import FoundationModels

/// Whether the on-device model can make outfit suggestions right now.
enum RecommendationAvailability: Equatable, Sendable {
    case available
    case unavailable(RecommendationState.UnavailableReason)
}

/// The network and on-device model calls behind a day plan, so tests can stub them out.
protocol DayPlanFetching: Sendable {
    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?)
    func recommendationAvailability() async -> RecommendationAvailability
    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation
}

struct DayPlanFetcher: DayPlanFetching {
    private let weatherService = WeatherService()
    private let hourlyForecastService = HourlyForecastService()
    private let appleWeatherService = AppleWeatherService()
    private let outfitAdvisor = OutfitAdvisor()

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        switch provider {
        case .openMeteo:
            async let hourlyTask: HourlyForecast? = try? hourlyForecastService.fetchHourlyForecast(for: coordinate)
            let weather = try await weatherService.fetchTodayForecast(for: coordinate)
            return (weather, await hourlyTask)
        case .apple:
            // WeatherKit has no hourly uncertainty, so borrow Open-Meteo's ensemble spread
            // for the chart's band. If that request fails, the chart just shows the line.
            async let ensembleTask: HourlyForecast? = try? hourlyForecastService.fetchHourlyForecast(for: coordinate, includePrecipitation: false)
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
}
