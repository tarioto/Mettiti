import Combine
import CoreLocation
import Testing
@testable import Mettiti

@MainActor
struct DayPlanViewModelTests {
    @Test func pullToRefreshAfterLocationFailureLoadsPlanOnceLocationArrives() async throws {
        let location = FakeLocationProvider()
        let fetcher = FakeDayPlanFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .currentLocation
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { _ in }
        )

        viewModel.start()
        location.fail("Couldn't find your location right now.")
        #expect(viewModel.state.isFailed)

        await viewModel.refresh()
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        location.deliver(coordinate)

        try await waitUntil { viewModel.state.isLoaded }
        let requested = await fetcher.requestedCoordinates
        #expect(requested.map(\.latitude) == [47.6])
        #expect(requested.map(\.longitude) == [-122.3])
    }

    @Test func refreshInCurrentLocationAfterCustomCityDoesNotReloadThatCity() async throws {
        let location = FakeLocationProvider()
        let fetcher = FakeDayPlanFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        try await waitUntil { viewModel.state.isLoaded }

        locationPreference.selection = .currentLocation
        location.fail("Couldn't find your location right now.")
        #expect(viewModel.state.isFailed)
        let requestsBeforeRefresh = location.locationRequestCount

        await viewModel.refresh()

        let requested = await fetcher.requestedCoordinates
        #expect(requested.map(\.latitude) == [10])
        #expect(location.locationRequestCount == requestsBeforeRefresh + 1)
        #expect(snapshots.count == 1)
    }

    @Test func refreshInCurrentLocationReloadsLastGPSFixWithoutNewLocationRequest() async throws {
        let location = FakeLocationProvider()
        let fetcher = FakeDayPlanFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .currentLocation
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { _ in }
        )

        viewModel.start()
        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { viewModel.state.isLoaded }
        let requestsBeforeRefresh = location.locationRequestCount

        await viewModel.refresh()

        let requested = await fetcher.requestedCoordinates
        #expect(requested.map(\.latitude) == [47.6, 47.6])
        #expect(location.locationRequestCount == requestsBeforeRefresh)
    }

    @Test func refreshAfterReturningToCurrentLocationRequestsNewFixInsteadOfReloadingOldOne() async throws {
        let location = FakeLocationProvider()
        let fetcher = FakeDayPlanFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .currentLocation
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { viewModel.state.isLoaded }

        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        try await waitUntil { viewModel.state.isLoaded }

        locationPreference.selection = .currentLocation
        let requestsBeforeRefresh = location.locationRequestCount

        await viewModel.refresh()

        let requested = await fetcher.requestedCoordinates
        #expect(requested.map(\.latitude) == [47.6, 10])
        #expect(location.locationRequestCount == requestsBeforeRefresh + 1)
        #expect(snapshots.count == 2)
    }

    @Test func refreshForCustomCityReloadsThatCity() async throws {
        let fetcher = FakeDayPlanFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { _ in }
        )

        viewModel.start()
        try await waitUntil { viewModel.state.isLoaded }

        await viewModel.refresh()

        let requested = await fetcher.requestedCoordinates
        #expect(requested.map(\.latitude) == [10, 10])
    }

    @Test func slowLoadForPreviousCityDoesNotOverwriteNewerCity() async throws {
        let fetcher = GatedDayPlanFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { snapshots.append($0) }
        )

        let loadA = Task { await viewModel.refresh() }
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        locationPreference.selection = .custom(name: "City B", latitude: 20, longitude: 20)
        try await waitUntil { await fetcher.isWaiting(onLatitude: 20) }

        await fetcher.complete(latitude: 20, with: .success(.forecast(high: 20)))
        try await waitUntil { viewModel.state.loadedHigh == 20 }

        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        await loadA.value

        #expect(viewModel.state.loadedHigh == 20)
        #expect(snapshots.map(\.weather.highTemperatureF) == [20])
    }

    @Test func supersededLoadThatFailsDoesNotReplaceNewerPlan() async throws {
        let fetcher = GatedDayPlanFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { _ in }
        )

        let loadA = Task { await viewModel.refresh() }
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        locationPreference.selection = .custom(name: "City B", latitude: 20, longitude: 20)
        try await waitUntil { await fetcher.isWaiting(onLatitude: 20) }

        await fetcher.complete(latitude: 20, with: .success(.forecast(high: 20)))
        try await waitUntil { viewModel.state.loadedHigh == 20 }

        await fetcher.complete(latitude: 10, with: .failure(FakeFetchError()))
        await loadA.value

        #expect(viewModel.state.loadedHigh == 20)
    }

    @Test func pullToRefreshFinishesOnlyWhenTheRefreshedLoadFinishes() async throws {
        let fetcher = GatedDayPlanFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { _ in }
        )

        var refreshFinished = false
        let refresh = Task {
            await viewModel.refresh()
            refreshFinished = true
        }
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        #expect(!refreshFinished)

        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        await refresh.value

        #expect(refreshFinished)
        #expect(viewModel.state.loadedHigh == 10)
    }

    // MARK: Weather without a recommendation (#12)

    @Test func recommendationFailureStillShowsWeatherAndPublishesWeatherOnlySnapshot() async throws {
        let fetcher = FakeDayPlanFetcher(recommendation: .failure(FakeFetchError()))
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { viewModel.state.recommendationState != nil && !viewModel.state.isRecommendationLoading }

        #expect(viewModel.state.loadedHigh == DailyWeather.placeholder.highTemperatureF)
        #expect(viewModel.state.recommendationFailureMessage == "Stale request failed")
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.recommendation == nil)
        #expect(snapshots.first?.weather.highTemperatureF == DailyWeather.placeholder.highTemperatureF)
    }

    @Test(arguments: [
        RecommendationState.UnavailableReason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady,
    ])
    func unavailableModelShowsWeatherWithReasonWithoutAttemptingGeneration(reason: RecommendationState.UnavailableReason) async throws {
        let fetcher = FakeDayPlanFetcher(availability: .unavailable(reason))
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { viewModel.state.recommendationState != nil && !viewModel.state.isRecommendationLoading }

        #expect(viewModel.state.loadedHigh == DailyWeather.placeholder.highTemperatureF)
        #expect(viewModel.state.unavailableReason == reason)
        #expect(await fetcher.recommendationRequestCount == 0)
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.recommendation == nil)
    }

    @Test func weatherFetchFailureStillFailsThePlan() async throws {
        let fetcher = FakeDayPlanFetcher(weather: .failure(FakeFetchError()))
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { viewModel.state.isFailed }

        #expect(await fetcher.recommendationRequestCount == 0)
        #expect(snapshots.isEmpty)
    }

    @Test func successfulRecommendationIsReadyAndSavedToSnapshot() async throws {
        let outfit = OutfitRecommendation(summary: "Bring a coat.", items: [RecommendedItem(emoji: "🧥", name: "Coat", reason: "Cold")])
        let fetcher = FakeDayPlanFetcher(recommendation: .success(outfit))
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { viewModel.state.readySummary != nil }

        #expect(viewModel.state.readySummary == "Bring a coat.")
        #expect(snapshots.map(\.recommendation?.summary) == ["Bring a coat."])
    }

    @Test func weatherShowsWhileRecommendationIsStillGenerating() async throws {
        let fetcher = GatedRecommendationFetcher()
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { await fetcher.pendingRecommendationCount == 1 }

        #expect(viewModel.state.isRecommendationLoading)
        #expect(viewModel.state.loadedHigh == 10)
        #expect(snapshots.isEmpty)

        await fetcher.completeRecommendation(with: .success(.placeholder))
        try await waitUntil { viewModel.state.readySummary != nil }
        #expect(snapshots.count == 1)
    }

    @Test func retryAfterRecommendationFailureMakesItReadyWithoutRefetchingWeather() async throws {
        let fetcher = FakeDayPlanFetcher(recommendation: .failure(FakeFetchError()))
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, publishSnapshot: { snapshots.append($0) })
        viewModel.start()
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }

        await fetcher.setRecommendation(.success(.placeholder))
        viewModel.retryRecommendation()
        try await waitUntil { viewModel.state.readySummary != nil }

        #expect(viewModel.state.readySummary == OutfitRecommendation.placeholder.summary)
        #expect(await fetcher.requestedCoordinates.count == 1)
        #expect(await fetcher.recommendationRequestCount == 2)
        #expect(snapshots.map { $0.recommendation == nil } == [true, false])
    }

    @Test func lateRecommendationFromSupersededLoadDoesNotOverwriteNewerCity() async throws {
        let fetcher = GatedRecommendationFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        try await waitUntil { await fetcher.pendingRecommendationCount == 1 }

        locationPreference.selection = .custom(name: "City B", latitude: 20, longitude: 20)
        try await waitUntil { await fetcher.pendingRecommendationCount == 2 }

        // City B's recommendation completes, then City A's stale one arrives late.
        await fetcher.completeRecommendation(with: .success(OutfitRecommendation(summary: "City B", items: [])))
        try await waitUntil { viewModel.state.readySummary == "City B" }
        await fetcher.completeRecommendation(with: .success(OutfitRecommendation(summary: "City A", items: [])))
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.state.readySummary == "City B")
        #expect(viewModel.state.loadedHigh == 20)
        #expect(snapshots.map(\.recommendation?.summary) == ["City B"])
    }

    @Test func retryCancelledBySwitchingToCurrentLocationLeavesPlanIdleSoNextGPSFixLoads() async throws {
        let location = FakeLocationProvider()
        let fetcher = FakeDayPlanFetcher(recommendation: .failure(FakeFetchError()))
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { _ in }
        )
        viewModel.start()
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }

        // Same main-actor turn: the retry is cancelled before it ever runs.
        viewModel.retryRecommendation()
        locationPreference.selection = .currentLocation
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.state.isIdle)

        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { await fetcher.requestedCoordinates.count == 2 }
        #expect(await fetcher.requestedCoordinates.map(\.latitude) == [10, 47.6])
    }

    @Test func retrySupersededByLoadForAnotherCityNeverWritesStateOrPublishes() async throws {
        let fetcher = GatedRecommendationFetcher()
        let locationPreference = LocationPreferenceStore()
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(),
            fetcher: fetcher,
            publishSnapshot: { snapshots.append($0) }
        )
        viewModel.start()
        try await waitUntil { await fetcher.pendingRecommendationCount == 1 }
        await fetcher.completeRecommendation(with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }

        var highsAfterSwitch: [Double?] = []
        let recorder = viewModel.$state.sink { highsAfterSwitch.append($0.loadedHigh) }
        highsAfterSwitch.removeAll()

        viewModel.retryRecommendation()
        locationPreference.selection = .custom(name: "City B", latitude: 20, longitude: 20)
        try await waitUntil { viewModel.state.loadedHigh == 20 && viewModel.state.isRecommendationLoading }
        try await Task.sleep(for: .milliseconds(50))

        await fetcher.completeRecommendation(with: .success(OutfitRecommendation(summary: "City B", items: [])))
        try await waitUntil { viewModel.state.readySummary == "City B" }
        recorder.cancel()

        #expect(!highsAfterSwitch.contains(10))
        #expect(snapshots.map(\.weather.highTemperatureF) == [10, 20])
        #expect(snapshots.map(\.recommendation?.summary) == [nil, "City B"])
    }
}

// MARK: - Helpers

@MainActor
private func makeCustomCityViewModel(fetcher: DayPlanFetching, publishSnapshot: @escaping @MainActor (PlanSnapshot) -> Void = { _ in }) -> DayPlanViewModel {
    let locationPreference = LocationPreferenceStore()
    locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
    return DayPlanViewModel(
        locationManager: FakeLocationProvider(),
        locationPreference: locationPreference,
        providerPreference: WeatherProviderPreferenceStore(),
        fetcher: fetcher,
        publishSnapshot: publishSnapshot
    )
}

private extension LoadState {
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    var loadedHigh: Double? {
        if case .loaded(let weather, _, _, _) = self { return weather.highTemperatureF }
        return nil
    }

    var recommendationState: RecommendationState? {
        if case .loaded(_, _, _, let recommendation) = self { return recommendation }
        return nil
    }

    var isRecommendationLoading: Bool {
        if case .loading = recommendationState { return true }
        return false
    }

    var unavailableReason: RecommendationState.UnavailableReason? {
        if case .unavailable(let reason) = recommendationState { return reason }
        return nil
    }

    var readySummary: String? {
        if case .ready(let outfit) = recommendationState { return outfit.summary }
        return nil
    }

    var recommendationFailureMessage: String? {
        if case .failed(let message) = recommendationState { return message }
        return nil
    }
}

private extension DailyWeather {
    static func forecast(high: Double) -> DailyWeather {
        DailyWeather(
            date: .now,
            highTemperatureF: high,
            lowTemperatureF: high - 10,
            precipitationProbability: 0,
            uvIndex: 0,
            windSpeedMph: 0,
            conditionCode: 0,
            conditionDescription: "Clear"
        )
    }
}

private struct FakeFetchError: LocalizedError {
    var errorDescription: String? { "Stale request failed" }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private final class FakeLocationProvider: LocationProviding {
    @Published private var coordinate: CLLocationCoordinate2D?
    @Published private var errorMessage: String?

    var coordinatePublisher: AnyPublisher<CLLocationCoordinate2D?, Never> { $coordinate.eraseToAnyPublisher() }
    var errorMessagePublisher: AnyPublisher<String?, Never> { $errorMessage.eraseToAnyPublisher() }

    private(set) var locationRequestCount = 0

    func requestLocation() {
        locationRequestCount += 1
        errorMessage = nil
    }

    func fail(_ message: String) {
        errorMessage = message
    }

    func deliver(_ coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

private actor FakeDayPlanFetcher: DayPlanFetching {
    private(set) var requestedCoordinates: [CLLocationCoordinate2D] = []
    private(set) var recommendationRequestCount = 0
    private let weatherResult: Result<DailyWeather, Error>
    private var recommendationResult: Result<OutfitRecommendation, Error>
    private let availability: RecommendationAvailability

    init(
        weather: Result<DailyWeather, Error> = .success(.placeholder),
        recommendation: Result<OutfitRecommendation, Error> = .success(.placeholder),
        availability: RecommendationAvailability = .available
    ) {
        weatherResult = weather
        recommendationResult = recommendation
        self.availability = availability
    }

    func setRecommendation(_ result: Result<OutfitRecommendation, Error>) {
        recommendationResult = result
    }

    func recommendationAvailability() async -> RecommendationAvailability {
        availability
    }

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        requestedCoordinates.append(coordinate)
        return (try weatherResult.get(), nil)
    }

    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation {
        recommendationRequestCount += 1
        return try recommendationResult.get()
    }
}

/// Holds each weather request until the test completes it, so tests control completion order.
private actor GatedDayPlanFetcher: DayPlanFetching {
    private var pending: [Double: CheckedContinuation<DailyWeather, Error>] = [:]

    func isWaiting(onLatitude latitude: Double) -> Bool {
        pending[latitude] != nil
    }

    func complete(latitude: Double, with result: Result<DailyWeather, Error>) {
        pending.removeValue(forKey: latitude)?.resume(with: result)
    }

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        let weather = try await withCheckedThrowingContinuation { continuation in
            pending[coordinate.latitude] = continuation
        }
        return (weather, nil)
    }

    func recommendationAvailability() async -> RecommendationAvailability {
        .available
    }

    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation {
        .placeholder
    }
}

/// Returns weather right away (high = latitude) but holds each recommendation until the test
/// completes it, newest first, so tests can observe the plan while suggestions are generating.
private actor GatedRecommendationFetcher: DayPlanFetching {
    private var pending: [CheckedContinuation<OutfitRecommendation, Error>] = []

    var pendingRecommendationCount: Int { pending.count }

    func completeRecommendation(with result: Result<OutfitRecommendation, Error>) {
        pending.popLast()?.resume(with: result)
    }

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        (.forecast(high: coordinate.latitude), nil)
    }

    func recommendationAvailability() async -> RecommendationAvailability {
        .available
    }

    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
    }
}
