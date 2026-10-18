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
    /// Why refreshing today's saved plan failed. The saved plan stays on screen with this as a
    /// notice instead of the error screen; cleared when the next load starts.
    @Published private(set) var refreshFailureMessage: String?

    private let locationManager: LocationProviding
    private let locationPreference: LocationPreferenceStore
    private let providerPreference: WeatherProviderPreferenceStore
    private let fetcher: DayPlanFetching
    private let loadSnapshot: @MainActor () -> PlanSnapshot?
    private let publishSnapshot: @MainActor (PlanSnapshot) -> Void
    private var hasStarted = false
    /// Last GPS fix; only Current Location refreshes reuse it, so custom-city loads never set it.
    /// Cleared on every selection change so returning to Current Location waits for a fresh fix.
    private var lastCoordinate: CLLocationCoordinate2D?
    /// True while today's saved plan is on screen and a fresh one loads in the background (#22).
    /// Cleared whenever that load finishes, fails or is replaced by another selection or provider.
    private var isRevalidating = false
    /// The only load allowed to update `state`; starting another cancels it.
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(locationManager: LocationProviding, locationPreference: LocationPreferenceStore, providerPreference: WeatherProviderPreferenceStore, fetcher: DayPlanFetching = DayPlanFetcher(), loadSnapshot: @escaping @MainActor () -> PlanSnapshot? = SharedStore.load, publishSnapshot: @escaping @MainActor (PlanSnapshot) -> Void = DayPlanViewModel.saveAndReloadWidgets) {
        self.locationManager = locationManager
        self.locationPreference = locationPreference
        self.providerPreference = providerPreference
        self.fetcher = fetcher
        self.loadSnapshot = loadSnapshot
        self.publishSnapshot = publishSnapshot

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
                // The saved plan is for the old provider, so the new one loads in the open.
                self.isRevalidating = false
                Task { await self.refresh() }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        showCachedPlanIfCurrent()
        beginLoading(for: locationPreference.selection)
    }

    /// Shows the saved plan right away when it's from today for the same location and provider,
    /// so launch doesn't wait on the network and the on-device model.
    private func showCachedPlanIfCurrent() {
        isRevalidating = false
        guard let snapshot = loadSnapshot(),
              snapshot.isFromToday(now: .now, calendar: .current),
              snapshot.location == locationPreference.selection,
              snapshot.provider == providerPreference.provider else { return }
        isRevalidating = true
        let recommendation: RecommendationState = snapshot.recommendation.map { .ready($0) } ?? .loading
        state = .loaded(weather: snapshot.weather, hourly: snapshot.hourly, provider: providerPreference.provider, recommendation: recommendation)
    }

    func retry() {
        hasStarted = false
        state = .idle
        start()
    }

    /// Asks the model again for the weather already on screen, without refetching it.
    func retryRecommendation() {
        guard case .loaded(let weather, let hourly, let provider, _) = state else { return }
        loadTask?.cancel()
        loadTask = Task { await loadRecommendation(weather: weather, hourly: hourly, provider: provider) }
    }

    func refresh() async {
        switch locationPreference.selection {
        case .currentLocation:
            if let lastCoordinate {
                await startLoad(for: lastCoordinate).value
            } else {
                // Leave .failed so handleGPSCoordinate loads the next fix.
                loadTask?.cancel()
                refreshFailureMessage = nil
                state = .idle
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
        let task = Task { await loadPlan(for: coordinate) }
        loadTask = task
        return task
    }

    private func applySelection(_ selection: LocationSelection) {
        hasStarted = true
        isRevalidating = false
        state = .idle
        lastCoordinate = nil
        beginLoading(for: selection)
    }

    private func handleGPSCoordinate(_ coordinate: CLLocationCoordinate2D) {
        guard case .currentLocation = locationPreference.selection else { return }
        lastCoordinate = coordinate
        // A saved plan on screen isn't .idle, but the first fix still has to start its refresh.
        let revalidationAwaitsFix = isRevalidating && loadTask == nil
        guard case .idle = state else {
            if revalidationAwaitsFix { startLoad(for: coordinate) }
            return
        }
        startLoad(for: coordinate)
    }

    private func handleGPSError(_ message: String) {
        guard case .currentLocation = locationPreference.selection else { return }
        fail(message)
    }

    /// Fails the plan, unless today's saved plan is on screen: that stays, with a notice.
    private func fail(_ message: String) {
        if isRevalidating {
            isRevalidating = false
            refreshFailureMessage = message
        } else {
            state = .failed(message)
        }
    }

    private func loadPlan(for coordinate: CLLocationCoordinate2D) async {
        if !isRevalidating { state = .loadingWeather }
        // Read here (not in the provider sink, which fires before @Published updates).
        let provider = providerPreference.provider
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
        // While revalidating, the saved plan stays on screen until the fresh one is complete.
        if !isRevalidating {
            state = .loaded(weather: weather, hourly: hourly, provider: provider, recommendation: .loading)
        }
        let recommendation: RecommendationState
        if case .unavailable(let reason) = await fetcher.recommendationAvailability() {
            recommendation = .unavailable(reason)
        } else {
            do {
                recommendation = .ready(try await fetcher.recommendation(for: weather))
            } catch {
                recommendation = .failed(error.localizedDescription)
            }
        }
        guard !Task.isCancelled else { return }
        isRevalidating = false
        state = .loaded(weather: weather, hourly: hourly, provider: provider, recommendation: recommendation)
        publishSnapshot(PlanSnapshot(weather: weather, recommendation: recommendation.outfit, generatedAt: .now, provider: provider, location: locationPreference.selection, hourly: hourly))
    }

    /// Default snapshot sink: shares the plan with the widget and refreshes its timelines.
    static func saveAndReloadWidgets(_ snapshot: PlanSnapshot) {
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
