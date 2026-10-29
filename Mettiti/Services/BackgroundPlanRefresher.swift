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
        /// Fresh weather was published with today's outfit, since there was no Meaningful Change
        /// from the weather it was made for; the model wasn't asked.
        case refreshedKeepingOutfit
        /// Today's weather was published without outfit suggestions (model unavailable or failed).
        case refreshedWeatherOnly
        /// It's quiet hours where the plan is for (see `quietHoursStart`); nothing fetched.
        case skippedQuietHours
        /// Current Location is selected but there's no known fix; nothing fetched.
        case skippedNoCoordinate
        /// The weather fetch failed; the saved plan was left as is.
        case failed
        /// While this run was fetching, the app changed the city, provider or Settings window, or saved a plan
        /// for today that is at least as complete; nothing published so the app's plan stays.
        case supersededByApp
        /// The task was cancelled (e.g. the system's background time expired); nothing published.
        case cancelled
    }

    let fetcher: DayPlanFetching
    /// Defines "today" and the hour for Current Location and for cities saved without a time zone
    /// (see `LocationSelection.calendar(fallback:)`);
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
    /// The language an outfit made now would be written in; an outfit in another language is remade.
    var responseLanguage: () -> String = { OutfitAdvisor.responseLanguage() }

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
        let locationCalendar = selection().calendar(fallback: calendar)
        guard !hasCurrentSnapshot(savedSnapshot, window: window, now: now(), calendar: locationCalendar, availability: availability, language: responseLanguage()) else { return .alreadyCurrent }
        // iOS can run a request late; `nextRequestDate` then asks for the morning.
        guard !Self.isQuietHour(now(), in: locationCalendar) else { return .skippedQuietHours }

        let selection = selection()
        let coordinate: CLLocationCoordinate2D
        switch selection {
        case .custom(_, let latitude, let longitude, _):
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        case .currentLocation:
            guard let lastFix = lastKnownGPSCoordinate() else { return .skippedNoCoordinate }
            coordinate = lastFix
        }

        let provider = provider()
        guard let (weather, hourly) = try? await fetcher.fetchWeather(for: coordinate, from: provider) else { return .failed }
        let span = PlanSpan(window: window, startingAt: now(), timeZone: hourly?.timeZone ?? locationCalendar.timeZone)
        let freshSummary = WindowSummary(weather: weather, hourly: hourly, span: span)
        let recommendation: OutfitRecommendation?
        let adviceBasis: WindowSummary?
        let adviceLanguage: String?
        let outcome: Outcome
        // Today's outfit for this place, source and Settings window still fits unless the weather
        // it was made for has had a Meaningful Change (#99); then only the weather is updated,
        // and the basis stays so small changes still add up.
        if let saved = savedSnapshot,
           let outfit = saved.recommendation,
           let basis = saved.adviceBasis,
           saved.adviceLanguage == responseLanguage(),
           saved.location == selection,
           saved.provider == provider,
           saved.planWindow == window,
           saved.isFromToday(now: now(), calendar: locationCalendar),
           !freshSummary.differsMeaningfully(from: basis) {
            recommendation = outfit
            adviceBasis = basis
            adviceLanguage = saved.adviceLanguage
            outcome = .refreshedKeepingOutfit
        } else {
            recommendation = if availability == .available {
                try? await fetcher.recommendation(for: weather, hourly: hourly, span: span)
            } else {
                nil
            }
            adviceBasis = recommendation.map { _ in freshSummary }
            adviceLanguage = recommendation.map { _ in responseLanguage() }
            outcome = recommendation == nil ? .refreshedWeatherOnly : .refreshed
        }
        // `try?` above also swallows `CancellationError`: if the system expired the task mid-generation,
        // don't replace the saved plan (maybe yesterday's full plan) with a weather-only one.
        guard !Task.isCancelled else { return .cancelled }
        // The user may have opened the app and loaded a plan for another city or provider, or
        // changed the Settings window, while we were fetching; publishing now would overwrite
        // the app's plan with this older request's.
        guard self.selection() == selection, self.provider() == provider, planWindow() == window else { return .supersededByApp }
        // Likewise, don't replace a plan the app saved for today meanwhile with a less complete one.
        if let latest = loadSnapshot(),
           latest.generatedAt != savedSnapshot?.generatedAt,
           latest.isFromToday(now: now(), calendar: latest.locationCalendar(fallback: calendar)),
           latest.recommendation != nil || recommendation == nil {
            return .supersededByApp
        }
        publish(PlanSnapshot(weather: weather, recommendation: recommendation, generatedAt: now(), provider: provider, location: selection, hourly: hourly, span: span, adviceBasis: adviceBasis, adviceLanguage: adviceLanguage))
        return outcome
    }

    /// When the next background refresh should run, by the same staleness rule as the app:
    /// - a current plan (see `hasCurrentSnapshot`): once it goes stale for its Plan Window;
    /// - otherwise (none, from an earlier day, for another window, stale, or still missing its
    ///   suggestions): retry within the hour, or sooner for a short window; during quiet hours,
    ///   at the coming `morningHour`.
    /// Never sooner than `PlanWindow.minimumRefreshInterval` after the last plan was made (or,
    /// outside quiet hours, from now), and a time in quiet hours moves to the next `morningHour`.
    /// Hours are the selected location's (see `LocationSelection.calendar(fallback:)`).
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
        let locationCalendar = selection().calendar(fallback: calendar)
        let floor = now.addingTimeInterval(PlanWindow.minimumRefreshInterval)
        guard let snapshot, hasCurrentSnapshot(snapshot, window: window, now: now, calendar: locationCalendar, availability: availability, language: responseLanguage()) else {
            if Self.isQuietHour(now, in: locationCalendar) {
                // E.g. a run skipped for quiet hours: try again first thing, spaced only from the
                // last plan made, since nothing has been refreshed since.
                let lastPlanFloor = snapshot.map { $0.generatedAt.addingTimeInterval(PlanWindow.minimumRefreshInterval) } ?? .distantPast
                return max(Self.morning(after: now, in: locationCalendar), lastPlanFloor)
            }
            let retry = now.addingTimeInterval(min(Self.staleRetryInterval, window.staleAfter))
            return Self.outsideQuietHours(max(retry, floor), in: locationCalendar)
        }
        let due = snapshot.generatedAt.addingTimeInterval(window.staleAfter)
        return Self.outsideQuietHours(max(due, floor), in: locationCalendar)
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
    /// - otherwise with outfit suggestions: current, unless written in another language;
    /// - otherwise weather only: current only when the model can't make suggestions on this
    ///   device today (not eligible, Apple Intelligence off). If it's available again (an earlier
    ///   generation failed) or still getting ready, refresh so the suggestions can be retried.
    private func hasCurrentSnapshot(_ snapshot: PlanSnapshot?, window: PlanWindow, now: Date, calendar: Calendar, availability: RecommendationAvailability, language: String) -> Bool {
        guard let snapshot,
              snapshot.planWindow == window,
              !window.isPlanStale(lastLoadedAt: snapshot.generatedAt, now: now, calendar: calendar) else { return false }
        // An outfit in another language (or from before it was recorded) is remade.
        if snapshot.recommendation != nil { return snapshot.adviceLanguage == language }
        switch availability {
        case .unavailable(.deviceNotEligible), .unavailable(.appleIntelligenceNotEnabled):
            return true
        case .available, .unavailable(.modelNotReady):
            return false
        }
    }
}
