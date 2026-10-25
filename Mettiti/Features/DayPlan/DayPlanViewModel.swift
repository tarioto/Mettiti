import CoreLocation
import Observation
import WidgetKit

enum LoadState {
    case idle
    case loadingWeather
    /// Weather is shown as soon as it arrives; the outfit recommendation follows separately.
    /// `span` is what the plan covers.
    case loaded(weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, provider: WeatherProvider, recommendation: RecommendationState)
    case failed(String)

    /// Changes when the screen moves between the first-load skeleton, the plan and the error, so
    /// they crossfade. Stays the same while the plan's outfit comes and goes inside the loaded plan.
    var crossfadeID: String {
        switch self {
        case .idle, .loadingWeather: return "skeleton"
        case .loaded: return "plan"
        case .failed: return "error"
        }
    }
}

@MainActor
@Observable
final class DayPlanViewModel {
    private(set) var state: LoadState = .idle
    /// Why refreshing today's Saved Plan failed. The Saved Plan stays on screen with this as a
    /// notice instead of the error screen; cleared when the next load starts.
    private(set) var refreshFailureMessage: String?
    /// The Window Override: the Plan Window picked on the main screen, in place of the Settings
    /// default until the next launch or the next day (#100). Never saved, and never changes the
    /// Settings default.
    private(set) var planWindowOverride: PlanWindow?
    /// The Plan Window the plan on screen covers, or will once it's made: the Window Override if
    /// there is one, otherwise the Settings default.
    var activePlanWindow: PlanWindow {
        planWindowOverride ?? planWindowPreference.window
    }
    /// Where the plan is for, for the Location card: the searched city as soon as it's picked, or
    /// Current Location once weather for a fix has arrived, with its city name filled in once it's
    /// looked up. A later fix moves it only when a load brings weather for that fix.
    private(set) var location: PlanLocation?

    private let locationManager: LocationProviding
    private let locationPreference: LocationPreferenceStore
    private let providerPreference: WeatherProviderPreferenceStore
    private let planWindowPreference: PlanWindowPreferenceStore
    private let fetcher: DayPlanFetching
    private let loadSnapshot: @MainActor () -> PlanSnapshot?
    private let publishSnapshot: @MainActor (PlanSnapshot) -> Void
    private let now: @MainActor () -> Date
    /// The device's calendar (autoupdating, so a time zone change while the app is in memory counts):
    /// the fallback for `calendar`, and the time zone for display when there's no forecast.
    private let deviceCalendar: Calendar
    /// Defines "today" for every day and staleness check: the selected location's, so the app
    /// agrees with the widgets and background refresh. The device's when the selection has no time zone.
    private var calendar: Calendar { locationPreference.selection.calendar(fallback: deviceCalendar) }
    private let lookUpCityName: @Sendable (CLLocationCoordinate2D) async -> String?
    @ObservationIgnored private var hasStarted = false
    /// Last GPS fix; only Current Location refreshes reuse it, so custom-city loads never set it.
    /// Cleared on every selection change so returning to Current Location waits for a fresh fix.
    @ObservationIgnored private var lastCoordinate: CLLocationCoordinate2D?
    /// True while today's Saved Plan is on screen in place of a fresh one (#22): while the fresh
    /// one loads in the background, and after that failed (with `refreshFailureMessage`) so a later
    /// refresh or GPS fix still replaces it in place. Cleared once a fresh plan is on screen or
    /// another selection or provider replaces it.
    @ObservationIgnored private var isShowingSavedPlan = false
    /// When `planWindowOverride` was picked, so it can end on the next day.
    @ObservationIgnored private var planWindowOverrideDay: Date?
    /// Set while `loadTask` is fetching the weather; that load reads the Plan Window once the
    /// weather arrives, so switching windows meanwhile leaves it running.
    @ObservationIgnored private var inFlightWeatherFetchID: UUID?
    /// When the newest load was asked for: its weather fetch, or for Current Location the
    /// location request it's waiting on (which may never deliver a fix).
    @ObservationIgnored private var lastLoadRequestedAt: Date?
    /// The only load allowed to update `state`; starting another cancels it.
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The selection, provider and Plan Window last loaded for, so hearing about one that hasn't
    /// changed does nothing.
    @ObservationIgnored private var appliedSelection: LocationSelection
    @ObservationIgnored private var appliedProvider: WeatherProvider
    @ObservationIgnored private var appliedPlanWindow: PlanWindow
    /// The weather the outfit on screen was written for (#99); nil when that's unknown.
    @ObservationIgnored private var adviceBasis: WindowSummary?
    /// Whether the next load may keep the outfit on screen when the weather hasn't changed in a
    /// way that matters (#99). Automatic refreshes may; pull-to-refresh and changing the
    /// location or provider always remake it, and changing the Plan Window only brings back an
    /// outfit already made for that window (`outfitsByWindow`). Kept until the load starts, since for
    /// Current Location that waits on a fix; any later load remakes it unless asked again.
    @ObservationIgnored private var keepsUnchangedAdvice = false
    /// Outfits made this session, by Plan Window, each with the weather it was written for, so
    /// switching back to a window is instant while its weather hasn't meaningfully changed (#100).
    /// Dropped when a refetch remakes the outfit, or the location or provider changes; a refetch
    /// that keeps the outfit keeps them too.
    @ObservationIgnored private var outfitsByWindow: [PlanWindow: Advice] = [:]

    init(locationManager: LocationProviding, locationPreference: LocationPreferenceStore, providerPreference: WeatherProviderPreferenceStore, planWindowPreference: PlanWindowPreferenceStore, fetcher: DayPlanFetching = DayPlanFetcher(), loadSnapshot: @escaping @MainActor () -> PlanSnapshot? = SharedStore.load, publishSnapshot: @escaping @MainActor (PlanSnapshot) -> Void = DayPlanViewModel.saveAndReloadWidgets, now: @escaping @MainActor () -> Date = { .now }, calendar: Calendar = .autoupdatingCurrent, lookUpCityName: @escaping @Sendable (CLLocationCoordinate2D) async -> String? = PlaceNameLookup.cityName) {
        self.locationManager = locationManager
        self.locationPreference = locationPreference
        self.providerPreference = providerPreference
        self.planWindowPreference = planWindowPreference
        self.fetcher = fetcher
        self.loadSnapshot = loadSnapshot
        self.publishSnapshot = publishSnapshot
        self.now = now
        self.deviceCalendar = calendar
        self.lookUpCityName = lookUpCityName
        appliedSelection = locationPreference.selection
        appliedProvider = providerPreference.provider
        appliedPlanWindow = planWindowPreference.window

        locationManager.onCoordinate = { [weak self] coordinate in
            self?.handleGPSCoordinate(coordinate)
        }
        locationManager.onError = { [weak self] message in
            self?.handleGPSError(message)
        }
    }

    /// Loads the plan for the location preference's selection, unless it's the one already loaded.
    func locationSelectionDidChange() {
        let selection = locationPreference.selection
        guard selection != appliedSelection else { return }
        appliedSelection = selection
        hasStarted = true
        isShowingSavedPlan = false
        state = .idle
        lastCoordinate = nil
        location = nil
        keepsUnchangedAdvice = false
        outfitsByWindow = [:]
        beginLoading(for: selection)
    }

    /// Reloads the plan from the provider preference's provider, unless it's the one already loaded.
    func providerDidChange() {
        guard providerPreference.provider != appliedProvider else { return }
        appliedProvider = providerPreference.provider
        guard hasStarted else { return }
        // The Saved Plan is for the old provider, so the new one loads in the open.
        isShowingSavedPlan = false
        outfitsByWindow = [:]
        // Cancelled now, not when the refresh starts, so the old provider's load can't write in between.
        loadTask?.cancel()
        Task { await refresh() }
    }

    /// Switches the plan to the Plan Window preference's new window, unless it's the one already
    /// loaded. A new Settings default replaces any Window Override.
    func planWindowDidChange() {
        guard planWindowPreference.window != appliedPlanWindow else { return }
        // The store already holds the new default, so the window on screen is worked out from the old one.
        let previousWindow = planWindowOverride ?? appliedPlanWindow
        appliedPlanWindow = planWindowPreference.window
        planWindowOverride = nil
        guard activePlanWindow != previousWindow else {
            // The Window Override became the default: its plan, never saved so far, is now the
            // one the widgets should show. One still being made is saved when it's done.
            if !isShowingSavedPlan, case .loaded(let weather, let hourly, let span, let provider, let recommendation) = state,
               !recommendation.isInProgress {
                publishIfSettingsDefault(weather: weather, hourly: hourly, span: span, provider: provider, advice: currentAdvice)
            }
            return
        }
        showPlanForActiveWindow()
    }

    /// Overrides the Plan Window from the main screen until the next launch or the next day
    /// (#100), leaving the Settings default as it is.
    func selectPlanWindow(_ window: PlanWindow) {
        guard window != activePlanWindow else { return }
        planWindowOverride = window == planWindowPreference.window ? nil : window
        planWindowOverrideDay = now()
        showPlanForActiveWindow()
    }

    /// Ends the Window Override once it's from an earlier day, so each day starts from the
    /// Settings default.
    private func endPlanWindowOverrideIfNewDay() {
        guard planWindowOverride != nil, let planWindowOverrideDay,
              !calendar.isDate(planWindowOverrideDay, inSameDayAs: now()) else { return }
        planWindowOverride = nil
    }

    /// Shows the plan for the newly active Plan Window. The weather on screen is kept while it's
    /// still fresh for that window, and an outfit already made for that window comes back at once
    /// unless the weather has meaningfully changed since; otherwise the outfit is remade, or the
    /// whole plan reloads with fresh weather. The old window's outfit is for the wrong
    /// window, so the Plan and Wear & bring cards show the skeleton (the Weather card too when it
    /// reloads) until the new one is complete.
    private func showPlanForActiveWindow() {
        guard hasStarted else { return }
        // The load fetching the weather reads the new window once it has it.
        if inFlightWeatherFetchID != nil { return }
        // Current Location without a fix yet: today's Saved Plan (if any) stays as it is, and the
        // fix's load reads the new window. Asks again in case an earlier request failed, leaving
        // whether that load may keep an unchanged outfit as it was.
        if case .currentLocation = locationPreference.selection, lastCoordinate == nil {
            Task { await reload() }
            return
        }
        if case .loaded(let weather, let hourly, _, let provider, _) = state,
           !isShowingSavedPlan,
           !isWeatherStale(for: activePlanWindow),
           let made = outfitsByWindow[activePlanWindow] {
            let span = currentSpan(for: hourly)
            if !WindowSummary(weather: weather, hourly: hourly, span: span).differsMeaningfully(from: made.basis) {
                loadTask?.cancel()
                loadTask = nil
                showFreshWeather(weather: weather, hourly: hourly, span: span, provider: provider, keeping: made)
                return
            }
        }
        // The plan on screen (a Saved Plan included) is for the old window now.
        let wasShowingSavedPlan = isShowingSavedPlan
        isShowingSavedPlan = false
        adviceBasis = nil
        // A Saved Plan's weather is stale whatever its age: it's not from the newest load.
        if wasShowingSavedPlan || isWeatherStale(for: activePlanWindow) {
            // Cancelled now, not when the refresh starts, so the old window's load can't write in between.
            loadTask?.cancel()
            // An outfit already made for the new window comes back if its weather hasn't
            // meaningfully changed (#99); any other outfit is for the old window, so it's remade.
            keepsUnchangedAdvice = true
            Task { await reload() }
            return
        }
        if case .loaded(let weather, let hourly, let span, let provider, _) = state {
            state = .loaded(weather: weather, hourly: hourly, span: span, provider: provider, recommendation: .loading)
        }
        remakeRecommendationForWeatherOnScreen()
    }

    /// Whether the weather last loaded is too old for `window`.
    private func isWeatherStale(for window: PlanWindow) -> Bool {
        guard let lastLoadRequestedAt else { return false }
        return window.isPlanStale(lastLoadedAt: lastLoadRequestedAt, now: now(), calendar: calendar)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        appliedSelection = locationPreference.selection
        appliedProvider = providerPreference.provider
        appliedPlanWindow = planWindowPreference.window
        showSavedPlanIfCurrent()
        keepsUnchangedAdvice = true
        beginLoading(for: locationPreference.selection)
    }

    /// Shows the Saved Plan right away when it's from today for the same location, provider and
    /// Plan Window, so launch doesn't wait on the network and the on-device model.
    private func showSavedPlanIfCurrent() {
        isShowingSavedPlan = false
        adviceBasis = nil
        guard let snapshot = loadSnapshot(),
              snapshot.isFromToday(now: now(), calendar: calendar),
              snapshot.location == locationPreference.selection,
              snapshot.provider == providerPreference.provider,
              snapshot.planWindow == activePlanWindow else { return }
        isShowingSavedPlan = true
        adviceBasis = snapshot.adviceBasis
        let recommendation: RecommendationState = snapshot.recommendation.map { .ready($0) } ?? .loading
        let span = snapshot.span ?? PlanSpan(window: .restOfDay, startingAt: snapshot.generatedAt, timeZone: snapshot.hourly?.timeZone ?? deviceCalendar.timeZone)
        state = .loaded(weather: snapshot.weather, hourly: snapshot.hourly, span: span, provider: providerPreference.provider, recommendation: recommendation)
    }

    /// The active Plan Window's span from now (the Window Override's, if any), in the forecast location's time zone (the
    /// device's without an hourly forecast).
    private func currentSpan(for hourly: HourlyForecast?) -> PlanSpan {
        PlanSpan(window: activePlanWindow, startingAt: now(), timeZone: hourly?.timeZone ?? deviceCalendar.timeZone)
    }

    /// Refreshes a plan left in memory once it's stale for the current Plan Window: from an
    /// earlier day, or older than the window's `staleAfter` (#24, #98). Same rules as launch:
    /// today's Saved Plan stays on screen while the fresh one loads; a plan from an earlier day is
    /// never shown as current.
    func refreshIfStale() {
        endPlanWindowOverrideIfNewDay()
        guard hasStarted, let lastLoadRequestedAt,
              activePlanWindow.isPlanStale(lastLoadedAt: lastLoadRequestedAt, now: now(), calendar: calendar) else { return }
        // The Saved Plan is never for the Window Override, so today's plan for it stays on screen
        // in its place, and may be kept if its weather hasn't meaningfully changed (#99).
        let overridePlan = planWindowOverride != nil && !isShowingSavedPlan ? currentAdvice.map { (state, $0.basis) } : nil
        showSavedPlanIfCurrent()
        if !isShowingSavedPlan, let (planState, basis) = overridePlan {
            isShowingSavedPlan = true
            adviceBasis = basis
            state = planState
        }
        if !isShowingSavedPlan { state = .idle }
        keepsUnchangedAdvice = true
        beginLoading(for: locationPreference.selection)
    }

    func retry() {
        hasStarted = false
        state = .idle
        start()
    }

    /// Asks the model again for the weather already on screen, without refetching it.
    func retryRecommendation() {
        // The Saved Plan's weather is stale too, so try the whole plan again, keeping it on screen.
        if isShowingSavedPlan {
            Task { await refresh() }
            return
        }
        remakeRecommendationForWeatherOnScreen()
    }

    /// Asks the model again for the weather on screen, covering the Plan Window from now.
    private func remakeRecommendationForWeatherOnScreen() {
        guard case .loaded(let weather, let hourly, _, let provider, _) = state else { return }
        loadTask?.cancel()
        inFlightWeatherFetchID = nil
        fetcher.prewarmRecommendation()
        let span = currentSpan(for: hourly)
        loadTask = Task { await loadRecommendation(weather: weather, hourly: hourly, span: span, provider: provider) }
    }

    /// Refetches the weather and remakes the outfit, e.g. on pull-to-refresh.
    func refresh() async {
        keepsUnchangedAdvice = false
        await reload()
    }

    /// Refetches the weather; `keepsUnchangedAdvice` decides whether the outfit may be kept.
    private func reload() async {
        endPlanWindowOverrideIfNewDay()
        switch locationPreference.selection {
        case .currentLocation:
            if let lastCoordinate {
                await startLoad(for: lastCoordinate).value
            } else {
                loadTask?.cancel()
                loadTask = nil
                inFlightWeatherFetchID = nil
                refreshFailureMessage = nil
                // Keep today's Saved Plan on screen; its refresh starts with the next fix.
                // Otherwise go .idle so handleGPSCoordinate loads the next fix.
                if !isShowingSavedPlan {
                    state = .idle
                }
                lastLoadRequestedAt = now()
                locationManager.requestLocation()
            }
        case .custom(_, let latitude, let longitude, _):
            await startLoad(for: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)).value
        }
    }

    private func beginLoading(for selection: LocationSelection) {
        switch selection {
        case .currentLocation:
            loadTask?.cancel()
            loadTask = nil
            inFlightWeatherFetchID = nil
            refreshFailureMessage = nil
            lastLoadRequestedAt = now()
            locationManager.requestLocation()
        case .custom(let name, let latitude, let longitude, _):
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            location = PlanLocation(name: name, coordinate: coordinate, isCurrentLocation: false)
            startLoad(for: coordinate)
        }
    }

    /// Supersedes any in-flight load so only the newest one can write `state` or the snapshot.
    @discardableResult
    private func startLoad(for coordinate: CLLocationCoordinate2D) -> Task<Void, Never> {
        loadTask?.cancel()
        refreshFailureMessage = nil
        lastLoadRequestedAt = now()
        let keepingUnchangedAdvice = keepsUnchangedAdvice
        keepsUnchangedAdvice = false
        let fetchID = UUID()
        inFlightWeatherFetchID = fetchID
        let task = Task { await loadPlan(for: coordinate, keepingUnchangedAdvice: keepingUnchangedAdvice, fetchID: fetchID) }
        loadTask = task
        return task
    }

    private func handleGPSCoordinate(_ coordinate: CLLocationCoordinate2D) {
        guard case .currentLocation = locationPreference.selection else { return }
        lastCoordinate = coordinate
        // A Saved Plan on screen isn't .idle, but the first fix still has to start its refresh.
        let savedPlanAwaitsFix = isShowingSavedPlan && loadTask == nil
        guard case .idle = state else {
            if savedPlanAwaitsFix { startLoad(for: coordinate) }
            return
        }
        startLoad(for: coordinate)
    }

    /// Moves Current Location's card to where the weather going on screen was fetched for, so it
    /// never shows a newer fix than the weather does (#120). Nil, or a searched city, leaves it.
    private func showLocation(ofWeatherAt coordinate: CLLocationCoordinate2D?) {
        guard let coordinate, case .currentLocation = locationPreference.selection else { return }
        showCurrentLocation(at: coordinate)
    }

    /// A fix near the one already shown keeps its name, so small moves don't look it up again.
    private func showCurrentLocation(at coordinate: CLLocationCoordinate2D) {
        if let location, location.isCurrentLocation, location.isNear(coordinate) { return }
        let shown = PlanLocation(name: nil, coordinate: coordinate, isCurrentLocation: true)
        location = shown
        Task {
            let name = await lookUpCityName(coordinate)
            // A later load's fix or another selection has replaced it meanwhile.
            guard location == shown else { return }
            location?.name = name
        }
    }

    private func handleGPSError(_ message: String) {
        guard case .currentLocation = locationPreference.selection else { return }
        fail(message)
    }

    /// Fails the plan, unless today's Saved Plan is on screen: that stays, with a notice.
    private func fail(_ message: String) {
        if isShowingSavedPlan {
            refreshFailureMessage = message
            // A Saved Plan without an outfit shows .loading; nothing is loading it any more. The
            // notice says what went wrong, which may be about the weather, so the Wear & bring card doesn't.
            if case .loaded(let weather, let hourly, let span, let provider, .loading) = state {
                state = .loaded(weather: weather, hourly: hourly, span: span, provider: provider, recommendation: .failed(UserFacingMessage.noSuggestion))
            }
        } else {
            state = .failed(message)
        }
    }

    /// Fetches the weather and makes the outfit for it, or with `keepingUnchangedAdvice`, keeps
    /// the outfit on screen when the weather hasn't meaningfully changed since it was made.
    private func loadPlan(for coordinate: CLLocationCoordinate2D, keepingUnchangedAdvice: Bool, fetchID: UUID) async {
        // Superseded before it ran (e.g. by a quick second selection change): write nothing.
        guard !Task.isCancelled else { return }
        // Read before the weather loading state replaces the outfit on screen.
        let adviceToKeep = keepingUnchangedAdvice ? currentAdvice : nil
        // A Saved Plan's outfit stays on screen.
        if !isShowingSavedPlan, !isHoldingOutfit {
            state = .loadingWeather
        }
        let provider = providerPreference.provider
        // Loads the model while the weather is in flight, so the suggestion starts sooner (#23).
        // Not when the outfit will likely be kept, so an unchanged forecast never wakes the model.
        if adviceToKeep == nil { fetcher.prewarmRecommendation() }
        await prepareSavedPlanWithoutOutfitForRefresh()
        // Only this load clears its own marker; a superseding one has set or cleared it itself.
        let fetchFinished = { [weak self] in
            if self?.inFlightWeatherFetchID == fetchID { self?.inFlightWeatherFetchID = nil }
        }
        do {
            let (weather, hourly) = try await fetcher.fetchWeather(for: coordinate, from: provider)
            fetchFinished()
            guard !Task.isCancelled else { return }
            let span = currentSpan(for: hourly)
            // The outfit to keep must be for the window the plan now covers, which a switch during
            // the fetch may have changed: the one on screen, or one already made for that window.
            let candidate = keepingUnchangedAdvice
                ? [adviceToKeep, outfitsByWindow[span.window]].compactMap { $0 }.first { $0.basis.window == span.window }
                : nil
            if let candidate, !WindowSummary(weather: weather, hourly: hourly, span: span).differsMeaningfully(from: candidate.basis) {
                showLocation(ofWeatherAt: coordinate)
                showFreshWeather(weather: weather, hourly: hourly, span: span, provider: provider, keeping: candidate)
                return
            }
            // The outfit is remade for this weather, so other windows' outfits are remade as needed too.
            outfitsByWindow = [:]
            await loadRecommendation(weather: weather, hourly: hourly, span: span, provider: provider, fetchedFor: coordinate)
        } catch {
            fetchFinished()
            guard !Task.isCancelled else { return }
            fail(UserFacingMessage.describing(error))
        }
    }

    /// Fills in the recommendation for weather that's already on screen; never fails the whole plan.
    /// `coordinate` is where freshly fetched weather is for, so the Location card moves with it
    /// once it's on screen; nil when the weather was on screen already.
    private func loadRecommendation(weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, provider: WeatherProvider, fetchedFor coordinate: CLLocationCoordinate2D? = nil) async {
        // A retry runs this directly as `loadTask`, so it needs its own guard (#10).
        guard !Task.isCancelled else { return }
        let recommendation: RecommendationState
        let availability = await fetcher.recommendationAvailability()
        // A load superseded during that await (e.g. by a selection change) mustn't write `state`.
        guard !Task.isCancelled else { return }
        if case .unavailable(let reason) = availability {
            recommendation = .unavailable(reason)
        } else {
            // The Saved Plan's outfit stays on screen until the fresh one is complete. Anything
            // else (including a Saved Plan without an outfit) gives way to the fresh weather and the outfit's skeleton, so the Saved Plan is no
            // longer what's on screen.
            if !isHoldingOutfit {
                isShowingSavedPlan = false
                showLocation(ofWeatherAt: coordinate)
                state = .loaded(weather: weather, hourly: hourly, span: span, provider: provider, recommendation: .loading)
            }
            do {
                recommendation = .ready(try await fetcher.recommendation(for: weather, hourly: hourly, span: span))
            } catch {
                recommendation = .failed(UserFacingMessage.describing(error))
            }
        }
        guard !Task.isCancelled else { return }
        // A fresh plan without an outfit is worse than the Saved Plan's, which stays with a notice.
        if isShowingSavedPlanOutfit, let problem = recommendation.problemMessage {
            fail(problem)
            return
        }
        isShowingSavedPlan = false
        refreshFailureMessage = nil
        adviceBasis = recommendation.outfit.map { _ in WindowSummary(weather: weather, hourly: hourly, span: span) }
        showLocation(ofWeatherAt: coordinate)
        state = .loaded(weather: weather, hourly: hourly, span: span, provider: provider, recommendation: recommendation)
        if let currentAdvice {
            outfitsByWindow[span.window] = currentAdvice
        }
        publishIfSettingsDefault(weather: weather, hourly: hourly, span: span, provider: provider, advice: currentAdvice)
    }

    /// An outfit and the weather it was written for.
    private struct Advice {
        let outfit: OutfitRecommendation
        let basis: WindowSummary
    }

    /// The outfit on screen and the weather it was written for, when both are known.
    private var currentAdvice: Advice? {
        guard case .loaded(_, _, _, _, .ready(let outfit)) = state, let adviceBasis else { return nil }
        return Advice(outfit: outfit, basis: adviceBasis)
    }

    /// Shows fresh weather with an outfit already made, still based on its original weather so
    /// changes that add up across refreshes still count.
    private func showFreshWeather(weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, provider: WeatherProvider, keeping advice: Advice) {
        isShowingSavedPlan = false
        refreshFailureMessage = nil
        adviceBasis = advice.basis
        state = .loaded(weather: weather, hourly: hourly, span: span, provider: provider, recommendation: .ready(advice.outfit))
        outfitsByWindow[span.window] = advice
        publishIfSettingsDefault(weather: weather, hourly: hourly, span: span, provider: provider, advice: advice)
    }

    /// Saves the plan, with its outfit and the weather that was written for (nil without an
    /// outfit), as the Saved Plan shared with the widgets, when it covers the Settings default:
    /// the widgets and the next launch follow that, never the Window Override.
    private func publishIfSettingsDefault(weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, provider: WeatherProvider, advice: Advice?) {
        guard span.window == planWindowPreference.window else { return }
        publishSnapshot(PlanSnapshot(weather: weather, recommendation: advice?.outfit, generatedAt: now(), provider: provider, location: locationPreference.selection, hourly: hourly, span: span, adviceBasis: advice?.basis))
    }

    /// Whether today's Saved Plan is on screen with its outfit. Stays true after a failed refresh,
    /// so a fresh plan without an outfit still doesn't replace it.
    private var isShowingSavedPlanOutfit: Bool {
        guard isShowingSavedPlan, case .loaded(_, _, _, _, .ready) = state else { return false }
        return true
    }

    /// Whether an outfit on screen stays there until the fresh one is complete: today's Saved Plan's.
    private var isHoldingOutfit: Bool {
        guard isShowingSavedPlan, case .loaded(_, _, _, _, .ready) = state else { return false }
        return true
    }

    /// Readies a Saved Plan without an outfit for its refresh: an earlier refresh's failure (and
    /// its Try Again button) gives way to the outfit loading, and if the model can't make one,
    /// that shows right away instead of only once the refresh finishes.
    private func prepareSavedPlanWithoutOutfitForRefresh() async {
        guard isShowingSavedPlan, !isShowingSavedPlanOutfit, case .loaded(let weather, let hourly, let span, let provider, let recommendation) = state else { return }
        if case .failed = recommendation {
            state = .loaded(weather: weather, hourly: hourly, span: span, provider: provider, recommendation: .loading)
        }
        guard case .unavailable(let reason) = await fetcher.recommendationAvailability(),
              !Task.isCancelled else { return }
        state = .loaded(weather: weather, hourly: hourly, span: span, provider: provider, recommendation: .unavailable(reason))
    }

    /// Default snapshot sink: shares the plan with the widget and refreshes its timelines.
    static func saveAndReloadWidgets(_ snapshot: PlanSnapshot) {
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
