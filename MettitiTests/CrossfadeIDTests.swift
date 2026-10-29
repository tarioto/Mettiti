import Foundation
import Testing
@testable import Mettiti

struct CrossfadeIDTests {
    private let weather = DailyWeather(date: Date(timeIntervalSince1970: 1_800_000_000), highTemperatureF: 75, lowTemperatureF: 55, precipitationProbability: 5, uvIndex: 7, windSpeedMph: 4, conditionCode: 0, conditionDescription: "Clear sky")
    private let hourly = HourlyForecast(timeZone: TimeZone(identifier: "America/Los_Angeles")!, points: [
        HourlyTemperaturePoint(date: Date(timeIntervalSince1970: 1_800_000_000), meanF: 60, minF: 58, maxF: 62, precipitationProbability: 10),
    ])

    private var span: PlanSpan {
        PlanSpan(window: .threeHours, startingAt: weather.date, timeZone: hourly.timeZone)
    }

    // MARK: Weather card

    @Test func weatherContentIDIsTheSameForIdenticalWeather() {
        let again = weather
        let hourlyAgain = hourly
        #expect(DayPlanView.WeatherContentID(weather: weather, hourly: hourly) == DayPlanView.WeatherContentID(weather: again, hourly: hourlyAgain))
    }

    @Test func weatherContentIDChangesWhenTheWeatherChanges() {
        let warmer = DailyWeather(date: weather.date, highTemperatureF: 90, lowTemperatureF: 55, precipitationProbability: 5, uvIndex: 7, windSpeedMph: 4, conditionCode: 0, conditionDescription: "Clear sky")
        #expect(DayPlanView.WeatherContentID(weather: weather, hourly: hourly) != DayPlanView.WeatherContentID(weather: warmer, hourly: hourly))
    }

    @Test func weatherContentIDChangesWhenTheHourlyDataChanges() {
        let changed = HourlyForecast(timeZone: hourly.timeZone, points: [
            HourlyTemperaturePoint(date: hourly.points[0].date, meanF: 65, minF: 63, maxF: 67, precipitationProbability: 10),
        ])
        #expect(DayPlanView.WeatherContentID(weather: weather, hourly: hourly) != DayPlanView.WeatherContentID(weather: weather, hourly: changed))
        #expect(DayPlanView.WeatherContentID(weather: weather, hourly: hourly) != DayPlanView.WeatherContentID(weather: weather, hourly: nil))
    }

    // MARK: LoadState

    @Test func loadStateIDIsTheSameForEveryLoadedPlan() {
        let other = DailyWeather(date: weather.date, highTemperatureF: 90, lowTemperatureF: 55, precipitationProbability: 5, uvIndex: 7, windSpeedMph: 4, conditionCode: 3, conditionDescription: "Overcast")
        let first = LoadState.loaded(weather: weather, hourly: hourly, span: span, provider: .openMeteo, recommendation: .loading)
        let second = LoadState.loaded(weather: other, hourly: nil, span: span, provider: .openMeteo, recommendation: .loading)

        #expect(first.crossfadeID == "plan")
        #expect(first.crossfadeID == second.crossfadeID)
    }

    @Test func loadStateIDSeparatesSkeletonPlanAndError() {
        #expect(LoadState.idle.crossfadeID == LoadState.loadingWeather.crossfadeID)
        #expect(LoadState.idle.crossfadeID != LoadState.failed("x").crossfadeID)
        #expect(LoadState.failed("x").crossfadeID != LoadState.loaded(weather: weather, hourly: nil, span: span, provider: .openMeteo, recommendation: .loading).crossfadeID)
    }

    // MARK: RecommendationState

    @Test func recommendationIDChangesWithTheOutfit() {
        let sunny = RecommendationState.ready(OutfitRecommendation(summary: "Sunny.", items: [RecommendedItem(emoji: "🕶️", name: "Sunglasses", reason: "Bright.")]))
        let sameSunny = RecommendationState.ready(OutfitRecommendation(summary: "Sunny.", items: [RecommendedItem(emoji: "🕶️", name: "Sunglasses", reason: "Bright.")]))
        let rainy = RecommendationState.ready(OutfitRecommendation(summary: "Rainy.", items: [RecommendedItem(emoji: "☂️", name: "Umbrella", reason: "Wet.")]))

        #expect(sunny.crossfadeID == sameSunny.crossfadeID)
        #expect(sunny.crossfadeID != rainy.crossfadeID)
    }

    @Test func recommendationIDSeparatesLoadingOutfitAndNotice() {
        let ready = RecommendationState.ready(OutfitRecommendation(summary: "Sunny.", items: []))
        #expect(RecommendationState.loading.crossfadeID != ready.crossfadeID)
        #expect(RecommendationState.unavailable(.deviceNotEligible).crossfadeID == RecommendationState.failed("x").crossfadeID)
        #expect(RecommendationState.unavailable(.deviceNotEligible).crossfadeID != ready.crossfadeID)
    }
}
