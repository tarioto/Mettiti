import CoreLocation
import Combine
import WidgetKit

enum LoadState {
    case idle
    case loadingWeather
    /// Weather is shown as soon as it arrives; the outfit recommendation follows separately.
    case loaded(weather: DailyWeather, hourly: HourlyForecast?, provider: WeatherProvider, recommendation: RecommendationState)
    case failed(String)
}

@MainActor
final class DayPlanViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    /// Why refreshing today's Saved Plan failed. The Saved Plan stays on screen with this as a
    /// notice instead of the error screen; cleared when the next load starts.
    @Published private(set) var refreshFailureMessage: String?
    /// True while a refresh runs behind the Saved Plan's outfit, which stays on screen until the
    /// fresh plan is complete, so the screen can say it's updating (#23).
    @Published private(set) var isUpdatingSavedPlan = false

    private let locationManager: LocationProviding
    private let locationPreference: LocationPreferenceStore
    private let providerPreference: WeatherProviderPreferenceStore
    private let fetcher: DayPlanFetching
    private let loadSnapshot: @MainActor () -> PlanSnapshot?
    private let publishSnapshot: @MainActor (PlanSnapshot) -> Void
    private let now: @MainActor () -> Date
    /// Defines "today"; autoupdating so a time zone change while the app is in memory counts.
    private let calendar: Calendar
    private var hasStarted = false
    /// Last GPS fix; only Current Location refreshes reuse it, so custom-city loads never set it.
    /// Cleared on every selection change so returning to Current Location waits for a fresh fix.
    private var lastCoordinate: CLLocationCoordinate2D?
    /// True while today's Saved Plan is on screen in place of a fresh one (#22): while the fresh
    /// one loads in the background, and after that failed (with `refreshFailureMessage`) so a later
    /// refresh or GPS fix still replaces it in place. Cleared once a fresh plan is on screen or
    /// another selection or provider replaces it.
    private var isShowingSavedPlan = false
    /// When the newest load was asked for: its weather fetch, or for Current Location the
    /// location request it's waiting on (which may never deliver a fix).
    private var lastLoadRequestedAt: Date?
    /// The only load allowed to update `state`; starting another cancels it.
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(locationManager: LocationProviding, locationPreference: LocationPreferenceStore, providerPreference: WeatherProviderPreferenceStore, fetcher: DayPlanFetching = DayPlanFetcher(), loadSnapshot: @escaping @MainActor () -> PlanSnapshot? = SharedStore.load, publishSnapshot: @escaping @MainActor (PlanSnapshot) -> Void = DayPlanViewModel.saveAndReloadWidgets, now: @escaping @MainActor () -> Date = { .now }, calendar: Calendar = .autoupdatingCurrent) {
        self.locationManager = locationManager
        self.locationPreference = locationPreference
        self.providerPreference = providerPreference
        self.fetcher = fetcher
        self.loadSnapshot = loadSnapshot
        self.publishSnapshot = publishSnapshot
        self.now = now
        self.calendar = calendar

        locationManager.coordinatePublisher
            .compactMap { $0 }
            .sink { [weak self] coordinate in
                self?.handleGPSCoordinate(coordinate)
            }
            .store(in: &cancellables)

        locationManager.errorMessagePublisher
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.handleGPSError(message)
            }
            .store(in: &cancellables)

        // removeDuplicates before dropFirst so reselecting the initial selection is skipped too.
        locationPreference.$selection
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] selection in
                self?.applySelection(selection)
            }
            .store(in: &cancellables)

        providerPreference.$provider
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.hasStarted else { return }
                // The Saved Plan is for the old provider, so the new one loads in the open.
                self.isShowingSavedPlan = false
                Task { await self.refresh() }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        showSavedPlanIfCurrent()
        beginLoading(for: locationPreference.selection)
    }

    /// Shows the Saved Plan right away when it's from today for the same location and provider,
    /// so launch doesn't wait on the network and the on-device model.
    private func showSavedPlanIfCurrent() {
        isShowingSavedPlan = false
        guard let snapshot = loadSnapshot(),
              snapshot.isFromToday(now: now(), calendar: calendar),
              snapshot.location == locationPreference.selection,
              snapshot.provider == providerPreference.provider else { return }
        isShowingSavedPlan = true
        let recommendation: RecommendationState = snapshot.recommendation.map { .ready($0) } ?? .loading
        state = .loaded(weather: snapshot.weather, hourly: snapshot.hourly, provider: providerPreference.provider, recommendation: recommendation)
    }

    /// How old the plan can get before returning to the app refreshes it on the same day. The
    /// day's high, low and rain chance rarely move within a few hours, and each refresh reruns
    /// the on-device model, so quick app switches never refresh but morning to evening does.
    private static let foregroundRefreshInterval: TimeInterval = 3 * 60 * 60

    /// Refreshes a plan left in memory once it's from an earlier day or older than
    /// `foregroundRefreshInterval` (#24). Same rules as launch: today's Saved Plan stays on screen
    /// while the fresh one loads; a plan from an earlier day is never shown as current.
    func refreshIfStale() {
        guard hasStarted, let lastLoadRequestedAt else { return }
        let now = now()
        guard !calendar.isDate(lastLoadRequestedAt, inSameDayAs: now)
                || now.timeIntervalSince(lastLoadRequestedAt) >= Self.foregroundRefreshInterval else { return }
        showSavedPlanIfCurrent()
        if !isShowingSavedPlan { state = .idle }
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
        guard case .loaded(let weather, let hourly, let provider, _) = state else { return }
        loadTask?.cancel()
        fetcher.prewarmRecommendation()
        loadTask = Task { await loadRecommendation(weather: weather, hourly: hourly, provider: provider) }
    }

    func refresh() async {
        switch locationPreference.selection {
        case .currentLocation:
            if let lastCoordinate {
                await startLoad(for: lastCoordinate).value
            } else {
                loadTask?.cancel()
                loadTask = nil
                refreshFailureMessage = nil
                // Keep today's Saved Plan on screen; its refresh starts with the next fix.
                // Otherwise go .idle so handleGPSCoordinate loads the next fix.
                if !isShowingSavedPlan { state = .idle }
                isUpdatingSavedPlan = isShowingSavedPlanOutfit
                lastLoadRequestedAt = now()
                locationManager.requestLocation()
            }
        case .custom(_, let latitude, let longitude):
            await startLoad(for: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)).value
        }
    }

    private func beginLoading(for selection: LocationSelection) {
        switch selection {
        case .currentLocation:
            loadTask?.cancel()
            loadTask = nil
            refreshFailureMessage = nil
            // The Saved Plan's refresh starts with the fix, so it's already updating.
            isUpdatingSavedPlan = isShowingSavedPlanOutfit
            lastLoadRequestedAt = now()
            locationManager.requestLocation()
        case .custom(_, let latitude, let longitude):
            startLoad(for: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }

    /// Supersedes any in-flight load so only the newest one can write `state` or the snapshot.
    @discardableResult
    private func startLoad(for coordinate: CLLocationCoordinate2D) -> Task<Void, Never> {
        loadTask?.cancel()
        refreshFailureMessage = nil
        // Set here, not in the task, so the caption and disabled refresh button show at once.
        isUpdatingSavedPlan = isShowingSavedPlanOutfit
        lastLoadRequestedAt = now()
        let task = Task { await loadPlan(for: coordinate) }
        loadTask = task
        return task
    }

    private func applySelection(_ selection: LocationSelection) {
        hasStarted = true
        isShowingSavedPlan = false
        isUpdatingSavedPlan = false
        state = .idle
        lastCoordinate = nil
        beginLoading(for: selection)
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

    private func handleGPSError(_ message: String) {
        guard case .currentLocation = locationPreference.selection else { return }
        fail(message)
    }

    /// Fails the plan, unless today's Saved Plan is on screen: that stays, with a notice.
    private func fail(_ message: String) {
        isUpdatingSavedPlan = false
        if isShowingSavedPlan {
            refreshFailureMessage = message
            // A Saved Plan without an outfit shows .loading; nothing is loading it any more.
            if case .loaded(let weather, let hourly, let provider, .loading) = state {
                state = .loaded(weather: weather, hourly: hourly, provider: provider, recommendation: .failed(message))
            }
        } else {
            state = .failed(message)
        }
    }

    private func loadPlan(for coordinate: CLLocationCoordinate2D) async {
        // Superseded before it ran (e.g. by a quick second selection change): write nothing.
        guard !Task.isCancelled else { return }
        if !isShowingSavedPlan { state = .loadingWeather }
        // Read here (not in the provider sink, which fires before @Published updates).
        let provider = providerPreference.provider
        // Loads the model while the weather is in flight, so the suggestion starts sooner (#23).
        fetcher.prewarmRecommendation()
        // `startLoad` set isUpdatingSavedPlan; a superseding load sets it itself, one that ends here clears it.
        defer { if !Task.isCancelled { isUpdatingSavedPlan = false } }
        await prepareSavedPlanWithoutOutfitForRefresh()
        do {
            let (weather, hourly) = try await fetcher.fetchWeather(for: coordinate, from: provider)
            guard !Task.isCancelled else { return }
            await loadRecommendation(weather: weather, hourly: hourly, provider: provider)
        } catch {
            guard !Task.isCancelled else { return }
            fail(error.localizedDescription)
        }
    }

    /// Fills in the recommendation for weather that's already on screen; never fails the whole plan.
    private func loadRecommendation(weather: DailyWeather, hourly: HourlyForecast?, provider: WeatherProvider) async {
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
            // else (including a Saved Plan without an outfit) gives way to the fresh weather and
            // the suggestion as it streams in, so the Saved Plan is no longer what's on screen.
            if !isShowingSavedPlanOutfit {
                isShowingSavedPlan = false
                state = .loaded(weather: weather, hourly: hourly, provider: provider, recommendation: .loading)
            }
            do {
                recommendation = .ready(try await fetcher.recommendation(for: weather) { [weak self] partial in
                    guard let self, !Task.isCancelled, !self.isShowingSavedPlanOutfit else { return }
                    self.state = .loaded(weather: weather, hourly: hourly, provider: provider, recommendation: .generating(partial))
                })
            } catch {
                recommendation = .failed(error.localizedDescription)
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
        state = .loaded(weather: weather, hourly: hourly, provider: provider, recommendation: recommendation)
        publishSnapshot(PlanSnapshot(weather: weather, recommendation: recommendation.outfit, generatedAt: now(), provider: provider, location: locationPreference.selection, hourly: hourly))
    }

    /// Whether today's Saved Plan is on screen with its outfit, which partial suggestions
    /// mustn't replace. Stays true after a failed refresh, so the next one holds partials back too.
    private var isShowingSavedPlanOutfit: Bool {
        guard isShowingSavedPlan, case .loaded(_, _, _, .ready) = state else { return false }
        return true
    }

    /// Readies a Saved Plan without an outfit for its refresh: an earlier refresh's failure (and
    /// its Try Again button) gives way to the outfit loading, and if the model can't make one,
    /// that shows right away instead of only once the refresh finishes.
    private func prepareSavedPlanWithoutOutfitForRefresh() async {
        guard isShowingSavedPlan, !isShowingSavedPlanOutfit, case .loaded(let weather, let hourly, let provider, let recommendation) = state else { return }
        if case .failed = recommendation {
            state = .loaded(weather: weather, hourly: hourly, provider: provider, recommendation: .loading)
        }
        guard case .unavailable(let reason) = await fetcher.recommendationAvailability(),
              !Task.isCancelled else { return }
        state = .loaded(weather: weather, hourly: hourly, provider: provider, recommendation: .unavailable(reason))
    }

    /// Default snapshot sink: shares the plan with the widget and refreshes its timelines.
    static func saveAndReloadWidgets(_ snapshot: PlanSnapshot) {
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
