import CoreLocation
import Foundation

/// Decides whether the widgets' plan is out of date and, if so, fetches and publishes today's plan.
/// Used by the background app refresh task; everything it touches is injected so tests can drive it.
@MainActor
struct BackgroundPlanRefresher {
    enum Outcome: Equatable {
        /// The saved plan is final for today (see `hasCurrentSnapshot`); nothing fetched.
        case alreadyCurrent
        /// A new plan was fetched and published.
        case refreshed
        /// Today's weather was published without outfit suggestions (model unavailable or failed).
        case refreshedWeatherOnly
        /// Current Location is selected but there's no known fix; nothing fetched.
        case skippedNoCoordinate
        /// The weather fetch failed; the saved plan was left as is.
        case failed
        /// While this run was fetching, the app changed the city or provider, or saved a plan
        /// for today that is at least as complete; nothing published so the app's plan stays.
        case supersededByApp
        /// The task was cancelled (e.g. the system's background time expired); nothing published.
        case cancelled
    }

    let fetcher: DayPlanFetching
    /// Defines "today"; production passes the device's current calendar and time zone.
    let calendar: Calendar
    let now: () -> Date
    let loadSnapshot: () -> PlanSnapshot?
    let publish: (PlanSnapshot) -> Void
    let selection: () -> LocationSelection
    let lastKnownGPSCoordinate: () -> CLLocationCoordinate2D?
    let provider: () -> WeatherProvider

    /// How long to wait before trying again while the saved plan is still from an earlier day.
    static let staleRetryInterval: TimeInterval = 60 * 60
    /// Run a little after midnight so "today" has clearly rolled over.
    static let minutesAfterMidnight = 5

    func refreshIfStale() async -> Outcome {
        let availability = await fetcher.recommendationAvailability()
        let savedSnapshot = loadSnapshot()
        guard !hasCurrentSnapshot(savedSnapshot, availability: availability) else { return .alreadyCurrent }

        let selection = selection()
        let coordinate: CLLocationCoordinate2D
        switch selection {
        case .custom(_, let latitude, let longitude):
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        case .currentLocation:
            guard let lastFix = lastKnownGPSCoordinate() else { return .skippedNoCoordinate }
            coordinate = lastFix
        }

        let provider = provider()
        guard let (weather, _) = try? await fetcher.fetchWeather(for: coordinate, from: provider) else { return .failed }
        let recommendation: OutfitRecommendation? = if availability == .available {
            try? await fetcher.recommendation(for: weather)
        } else {
            nil
        }
        // `try?` above also swallows `CancellationError`: if the system expired the task mid-generation,
        // don't replace the saved plan (maybe yesterday's full plan) with a weather-only one.
        guard !Task.isCancelled else { return .cancelled }
        // The user may have opened the app and loaded a plan for another city or provider while
        // we were fetching; publishing now would overwrite it with this older request's plan.
        guard self.selection() == selection, self.provider() == provider else { return .supersededByApp }
        // Likewise, don't replace a plan the app saved for today meanwhile with a less complete one.
        if let latest = loadSnapshot(),
           latest.generatedAt != savedSnapshot?.generatedAt,
           latest.isFromToday(now: now(), calendar: calendar),
           latest.recommendation != nil || recommendation == nil {
            return .supersededByApp
        }
        publish(PlanSnapshot(weather: weather, recommendation: recommendation, generatedAt: now(), provider: provider))
        return recommendation == nil ? .refreshedWeatherOnly : .refreshed
    }

    /// When the next background refresh should run: just after the next local midnight, or
    /// within the hour while the saved plan still needs a refresh (see `hasCurrentSnapshot`),
    /// e.g. because this run failed or today's suggestions are still missing.
    ///
    /// Synchronous so the app can submit the request before it's suspended on `.background`;
    /// the caller passes the model's current availability.
    ///
    /// Policy: a weather-only plan from today with the model `.available` (generation keeps
    /// failing, e.g. rate limited) retries hourly until midnight. That's bounded to one day and
    /// iOS throttles background refresh anyway; at midnight the plan goes stale and the cycle restarts.
    func nextRequestDate(availability: RecommendationAvailability) -> Date {
        let now = now()
        guard hasCurrentSnapshot(loadSnapshot(), availability: availability) else { return now.addingTimeInterval(Self.staleRetryInterval) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        return calendar.date(byAdding: .minute, value: Self.minutesAfterMidnight, to: calendar.startOfDay(for: tomorrow))!
    }

    /// Whether the saved plan is final for today, so no refresh is needed before midnight:
    /// - none saved, or generated on an earlier day (device time zone): not current;
    /// - from today with outfit suggestions: current;
    /// - from today, weather only: current only when the model can't make suggestions on this
    ///   device today (not eligible, Apple Intelligence off). If it's available again (an earlier
    ///   generation failed) or still getting ready, refresh so the suggestions can be retried.
    private func hasCurrentSnapshot(_ snapshot: PlanSnapshot?, availability: RecommendationAvailability) -> Bool {
        guard let snapshot,
              snapshot.isFromToday(now: now(), calendar: calendar) else { return false }
        if snapshot.recommendation != nil { return true }
        switch availability {
        case .unavailable(.deviceNotEligible), .unavailable(.appleIntelligenceNotEnabled):
            return true
        case .available, .unavailable(.modelNotReady):
            return false
        }
    }
}
