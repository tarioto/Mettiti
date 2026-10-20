import CoreLocation
import Foundation

/// Decides whether the widgets' plan is out of date and, if so, fetches and publishes today's plan.
/// Used by the background app refresh task; everything it touches is injected so tests can drive it.
@MainActor
struct BackgroundPlanRefresher {
    enum Outcome: Equatable {
        /// The saved plan doesn't need refreshing yet (see `hasCurrentSnapshot`); nothing fetched.
        case alreadyCurrent
        /// A new plan was fetched and published.
        case refreshed
        /// Today's weather was published without outfit suggestions (model unavailable or failed).
        case refreshedWeatherOnly
        /// It's quiet hours where the plan is for (see `quietHoursStart`); nothing fetched.
        case skippedQuietHours
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
    /// Defines "today" and the hour where the saved plan doesn't say (see `locationCalendar(for:)`);
    /// production passes the device's current calendar and time zone.
    let calendar: Calendar
    let now: () -> Date
    let loadSnapshot: () -> PlanSnapshot?
    let publish: (PlanSnapshot) -> Void
    let selection: () -> LocationSelection
    let lastKnownGPSCoordinate: () -> CLLocationCoordinate2D?
    let provider: () -> WeatherProvider
    /// The Settings default Plan Window; background refresh never follows the main screen's override.
    let planWindow: () -> PlanWindow

    /// How long to wait before trying again while the saved plan still needs a refresh, e.g.
    /// because this run failed. Shorter windows' own staleness comes first.
    static let staleRetryInterval: TimeInterval = 60 * 60
    /// Quiet hours run from this hour to `morningHour`, in the location's time zone. A plan made
    /// then would be about the night, so no background refresh makes one; they wait until morning.
    static let quietHoursStart = 23
    static let morningHour = 6

    func refreshIfStale() async -> Outcome {
        let availability = await fetcher.recommendationAvailability()
        let savedSnapshot = loadSnapshot()
        let window = planWindow()
        let calendar = locationCalendar(for: savedSnapshot)
        guard !hasCurrentSnapshot(savedSnapshot, window: window, now: now(), calendar: calendar, availability: availability) else { return .alreadyCurrent }
        // iOS can run a request late; `nextRequestDate` then asks for the morning.
        guard !Self.isQuietHour(now(), in: calendar) else { return .skippedQuietHours }

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
        guard let (weather, hourly) = try? await fetcher.fetchWeather(for: coordinate, from: provider) else { return .failed }
        let span = PlanSpan(window: window, startingAt: now(), timeZone: hourly?.timeZone ?? calendar.timeZone)
        let recommendation: OutfitRecommendation? = if availability == .available {
            try? await fetcher.recommendation(for: weather, hourly: hourly, span: span)
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
           latest.isFromToday(now: now(), calendar: latest.locationCalendar(fallback: self.calendar)),
           latest.recommendation != nil || recommendation == nil {
            return .supersededByApp
        }
        let adviceBasis = recommendation.map { _ in WindowSummary(weather: weather, hourly: hourly, span: span) }
        publish(PlanSnapshot(weather: weather, recommendation: recommendation, generatedAt: now(), provider: provider, location: selection, hourly: hourly, span: span, adviceBasis: adviceBasis))
        return recommendation == nil ? .refreshedWeatherOnly : .refreshed
    }

    /// When the next background refresh should run, by the same staleness rule as the app:
    /// - a current plan (see `hasCurrentSnapshot`): once it goes stale for its Plan Window;
    /// - otherwise (none, from an earlier day, for another window, stale, or still missing its
    ///   suggestions): retry within the hour, or sooner for a short window; during quiet hours,
    ///   at the coming `morningHour`.
    /// Never sooner than `PlanWindow.minimumRefreshInterval` from now, and a time in quiet hours
    /// moves to the next `morningHour`. Hours are the location's (see `locationCalendar(for:)`).
    ///
    /// Synchronous so the app can submit the request before it's suspended on `.background`;
    /// the caller passes the model's current availability.
    ///
    /// Policy: a weather-only plan from today with the model `.available` (generation keeps
    /// failing, e.g. rate limited) keeps retrying through the day. iOS throttles background
    /// refresh anyway, and quiet hours bound it.
    func nextRequestDate(availability: RecommendationAvailability) -> Date {
        let now = now()
        let window = planWindow()
        let snapshot = loadSnapshot()
        let calendar = locationCalendar(for: snapshot)
        let floor = now.addingTimeInterval(PlanWindow.minimumRefreshInterval)
        guard let snapshot, hasCurrentSnapshot(snapshot, window: window, now: now, calendar: calendar, availability: availability) else {
            // A run skipped for quiet hours tries again first thing; it made no plan, so there's
            // no refresh for the floor to space this one from.
            if Self.isQuietHour(now, in: calendar) { return Self.morning(after: now, in: calendar) }
            let retry = now.addingTimeInterval(min(Self.staleRetryInterval, window.staleAfter))
            return Self.outsideQuietHours(max(retry, floor), in: calendar)
        }
        let due = snapshot.generatedAt.addingTimeInterval(window.staleAfter)
        return Self.outsideQuietHours(max(due, floor), in: calendar)
    }

    /// The calendar for the selected location: the saved plan's location's time zone when the
    /// plan is for that location, otherwise (or for a plan that didn't record it) the device's.
    private func locationCalendar(for snapshot: PlanSnapshot?) -> Calendar {
        guard let snapshot, snapshot.location == selection() else { return calendar }
        return snapshot.locationCalendar(fallback: calendar)
    }

    private static func isQuietHour(_ date: Date, in calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= quietHoursStart || hour < morningHour
    }

    /// `date`, or the next `morningHour` when `date` is in quiet hours.
    private static func outsideQuietHours(_ date: Date, in calendar: Calendar) -> Date {
        isQuietHour(date, in: calendar) ? morning(after: date, in: calendar) : date
    }

    /// The first `morningHour` after `date`.
    private static func morning(after date: Date, in calendar: Calendar) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: morningHour, minute: 0, second: 0), matchingPolicy: .nextTime)!
    }

    /// Whether the saved plan needs no refresh yet:
    /// - none saved, from an earlier day (the location's), for another Plan Window than the
    ///   Settings default, or stale for that window: not current;
    /// - otherwise with outfit suggestions: current;
    /// - otherwise weather only: current only when the model can't make suggestions on this
    ///   device today (not eligible, Apple Intelligence off). If it's available again (an earlier
    ///   generation failed) or still getting ready, refresh so the suggestions can be retried.
    private func hasCurrentSnapshot(_ snapshot: PlanSnapshot?, window: PlanWindow, now: Date, calendar: Calendar, availability: RecommendationAvailability) -> Bool {
        guard let snapshot,
              snapshot.planWindow == window,
              !window.isPlanStale(lastLoadedAt: snapshot.generatedAt, now: now, calendar: calendar) else { return false }
        if snapshot.recommendation != nil { return true }
        switch availability {
        case .unavailable(.deviceNotEligible), .unavailable(.appleIntelligenceNotEnabled):
            return true
        case .available, .unavailable(.modelNotReady):
            return false
        }
    }
}
