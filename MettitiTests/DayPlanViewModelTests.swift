import Combine
import CoreLocation
import Synchronization
import Testing
@testable import Mettiti

@MainActor
struct DayPlanViewModelTests {
    @Test func pullToRefreshAfterLocationFailureLoadsPlanOnceLocationArrives() async throws {
        let location = FakeLocationProvider()
        let fetcher = FakeDayPlanFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .currentLocation
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .currentLocation
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .currentLocation
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
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

    @Test func reselectingTheSameCityKeepsThePlanWithoutRefetching() async throws {
        let location = FakeLocationProvider()
        let fetcher = FakeDayPlanFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { _ in }
        )

        viewModel.start()
        try await waitUntil { viewModel.state.isLoaded }

        locationPreference.selection = .custom(name: "City A", latitude: 10, longitude: 10)

        #expect(viewModel.state.isLoaded)
        let requested = await fetcher.requestedCoordinates
        #expect(requested.count == 1)
    }

    // MARK: Saved Plan on launch (#22)

    @Test func todaysPlanForTheSameCityShowsInstantlyThenIsReplacedByTheFreshOne() async throws {
        let fetcher = GatedDayPlanFetcher()
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(
            fetcher: fetcher,
            saved: .saved(high: 99, summary: "Saved outfit", location: cityA),
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()

        #expect(viewModel.state.loadedHigh == 99)
        #expect(viewModel.state.readySummary == "Saved outfit")
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        #expect(viewModel.state.loadedHigh == 99)

        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(viewModel.state.readySummary == OutfitRecommendation.placeholder.summary)
        #expect(snapshots.map(\.weather.highTemperatureF) == [10])
    }

    @Test(arguments: [
        PlanSnapshot.saved(high: 99, summary: "Yesterday", location: cityA, generatedAt: .now.addingTimeInterval(-2 * 24 * 60 * 60)),
        .saved(high: 99, summary: "Other city", location: .custom(name: "City B", latitude: 20, longitude: 20)),
        .saved(high: 99, summary: "Other provider", location: cityA, provider: .openMeteo),
        .saved(high: 99, summary: "Saved before locations were stored", location: cityA).withoutLocation,
    ])
    func savedPlanThatDoesNotMatchIsNotShown(snapshot: PlanSnapshot) async throws {
        let viewModel = makeCustomCityViewModel(fetcher: GatedDayPlanFetcher(), saved: snapshot)

        viewModel.start()

        #expect(viewModel.state.loadedHigh == nil)
    }

    @Test func todaysPlanForCurrentLocationIsReplacedOnceTheGPSFixArrives() async throws {
        let location = FakeLocationProvider()
        let fetcher = GatedDayPlanFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .currentLocation
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: .currentLocation) },
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        #expect(viewModel.state.loadedHigh == 99)

        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { await fetcher.isWaiting(onLatitude: 47.6) }
        #expect(viewModel.state.loadedHigh == 99)

        await fetcher.complete(latitude: 47.6, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(snapshots.map(\.weather.highTemperatureF) == [10])
    }

    @Test func choosingAnotherCityAfterAFailedRefreshShowsItsWeatherBeforeTheOutfit() async throws {
        let fetcher = GatedRecommendationFetcher(failingLatitudes: [10])
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = cityA
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: cityA) },
            publishSnapshot: { _ in }
        )

        viewModel.start()
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        locationPreference.selection = .custom(name: "City B", latitude: 20, longitude: 20)

        try await waitUntil { viewModel.state.loadedHigh == 20 }
        #expect(viewModel.state.isRecommendationLoading)
    }

    @Test func failedRefreshKeepsTodaysPlanOnScreenWithANoticeUntilTheNextLoad() async throws {
        let fetcher = GatedDayPlanFetcher()
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(
            fetcher: fetcher,
            saved: .saved(high: 99, summary: "Saved outfit", location: cityA),
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .failure(FakeFetchError()))

        try await waitUntil { viewModel.refreshFailureMessage != nil }
        #expect(viewModel.refreshFailureMessage == FakeFetchError().errorDescription)
        #expect(viewModel.state.readySummary == "Saved outfit")
        #expect(snapshots.isEmpty)

        let refreshed = Task { await viewModel.refresh() }
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        #expect(viewModel.refreshFailureMessage == nil)
        #expect(viewModel.state.readySummary == "Saved outfit")
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        await refreshed.value
        #expect(viewModel.state.loadedHigh == 10)
    }

    @Test func locationErrorDuringTheRefreshKeepsTodaysPlanOnScreenUntilALaterFixReplacesIt() async throws {
        let location = FakeLocationProvider()
        let fetcher = GatedDayPlanFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .currentLocation
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: .currentLocation) },
            publishSnapshot: { _ in }
        )

        viewModel.start()
        location.fail("Couldn't find your location right now.")

        #expect(viewModel.state.readySummary == "Saved outfit")
        #expect(viewModel.refreshFailureMessage == "Couldn't find your location right now.")

        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { await fetcher.isWaiting(onLatitude: 47.6) }
        #expect(viewModel.state.readySummary == "Saved outfit")
        await fetcher.complete(latitude: 47.6, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(viewModel.refreshFailureMessage == nil)
    }

    @Test func refreshBeforeTheFirstGPSFixKeepsTodaysPlanAndTheNextFixRefreshesIt() async throws {
        let location = FakeLocationProvider()
        let fetcher = GatedDayPlanFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .currentLocation
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: .currentLocation) },
            publishSnapshot: { _ in }
        )

        viewModel.start()
        await viewModel.refresh()
        #expect(viewModel.state.readySummary == "Saved outfit")

        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { await fetcher.isWaiting(onLatitude: 47.6) }
        #expect(viewModel.state.readySummary == "Saved outfit")

        location.fail("Couldn't find your location right now.")
        #expect(viewModel.state.readySummary == "Saved outfit")
        #expect(viewModel.refreshFailureMessage != nil)
    }

    @Test func failedRefreshOfASavedPlanWithoutAnOutfitStopsTheSpinner() async throws {
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: nil, location: cityA))

        viewModel.start()
        #expect(viewModel.state.isRecommendationLoading)
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .failure(FakeFetchError()))

        try await waitUntil { viewModel.refreshFailureMessage != nil }
        #expect(viewModel.state.loadedHigh == 99)
        #expect(viewModel.state.recommendationFailureMessage != nil)
    }

    @Test func tryAgainOnTheSavedPlanRefreshesTheWholePlanInPlace() async throws {
        let fetcher = GatedDayPlanFetcher()
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(
            fetcher: fetcher,
            saved: .saved(high: 99, summary: nil, location: cityA),
            publishSnapshot: { snapshots.append($0) }
        )
        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }

        viewModel.retryRecommendation()

        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        #expect(viewModel.state.loadedHigh == 99)
        await fetcher.complete(latitude: 10, with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.refreshFailureMessage != nil }
        #expect(viewModel.state.loadedHigh == 99)
        #expect(snapshots.isEmpty)

        viewModel.retryRecommendation()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(viewModel.refreshFailureMessage == nil)
        #expect(snapshots.map(\.weather.highTemperatureF) == [10])
    }

    @Test func changingProviderDuringTheRefreshReplacesTheSavedPlanWithTheNewProvidersWeather() async throws {
        let fetcher = GatedRecommendationFetcher()
        let providerPreference = WeatherProviderPreferenceStore(defaults: isolatedDefaults())
        providerPreference.provider = .apple
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = cityA
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: providerPreference,
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: cityA, provider: .apple) },
            publishSnapshot: { _ in }
        )

        viewModel.start()
        try await waitUntil { await fetcher.pendingRecommendationCount == 1 }
        #expect(viewModel.state.loadedHigh == 99)

        providerPreference.provider = .openMeteo

        try await waitUntil { viewModel.state.loadedHigh == 10 && viewModel.state.isRecommendationLoading }
    }

    // MARK: Perceived latency (#23)

    @Test func modelIsPrewarmedWhileWeatherIsStillLoading() async throws {
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher)

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        #expect(await fetcher.prewarmCount == 1)
        #expect(viewModel.state.isLoadingWeather)
    }

    @Test func partialSuggestionShowsAsItStreamsAndOnlyTheFinishedOneIsSaved() async throws {
        let fetcher = StreamingRecommendationFetcher()
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { viewModel.state.isRecommendationLoading }
        fetcher.send(partial: OutfitRecommendation(summary: "Bring a", items: []))
        try await waitUntil { viewModel.state.partialSummary == "Bring a" }
        fetcher.send(partial: OutfitRecommendation(summary: "Bring a coat.", items: [RecommendedItem(emoji: "🧥", name: "Coat", reason: "")]))
        try await waitUntil { viewModel.state.partialItemNames == ["Coat"] }
        #expect(snapshots.isEmpty)

        fetcher.finish(with: .success(OutfitRecommendation(summary: "Bring a coat.", items: [RecommendedItem(emoji: "🧥", name: "Coat", reason: "Cold")])))
        try await waitUntil { viewModel.state.readySummary != nil }

        #expect(viewModel.state.readySummary == "Bring a coat.")
        #expect(snapshots.map(\.recommendation?.items.first?.reason) == ["Cold"])
    }

    @Test func savedPlanStaysOnScreenWhileTheFreshSuggestionStreams() async throws {
        let fetcher = StreamingRecommendationFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA))

        viewModel.start()
        try await waitUntil { fetcher.isStreaming }
        fetcher.send(partial: OutfitRecommendation(summary: "Half a", items: []))
        // Give the partial time to reach the view model before checking it was ignored.
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.state.readySummary == "Saved outfit")
        #expect(viewModel.state.loadedHigh == 99)

        fetcher.finish(with: .success(OutfitRecommendation(summary: "Fresh outfit", items: [])))
        try await waitUntil { viewModel.state.readySummary == "Fresh outfit" }
        #expect(viewModel.state.loadedHigh == 10)
    }

    @Test func streamThatFailsPartwayShowsTheFailureNotThePartialSuggestion() async throws {
        let fetcher = StreamingRecommendationFetcher()
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { fetcher.isStreaming }
        fetcher.send(partial: OutfitRecommendation(summary: "Bring a", items: []))
        try await waitUntil { viewModel.state.partialSummary == "Bring a" }
        fetcher.finish(with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }

        #expect(snapshots.map { $0.recommendation == nil } == [true])
    }
}

// MARK: - Helpers

private let cityA = LocationSelection.custom(name: "City A", latitude: 10, longitude: 10)

@MainActor
private func makeCustomCityViewModel(fetcher: DayPlanFetching, saved: PlanSnapshot? = nil, publishSnapshot: @escaping @MainActor (PlanSnapshot) -> Void = { _ in }) -> DayPlanViewModel {
    let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
    locationPreference.selection = cityA
    return DayPlanViewModel(
        locationManager: FakeLocationProvider(),
        locationPreference: locationPreference,
        providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
        fetcher: fetcher,
        loadSnapshot: { saved },
        publishSnapshot: publishSnapshot
    )
}

private extension PlanSnapshot {
    /// A plan saved earlier today, distinguishable from fresh plans by its high and summary.
    static func saved(high: Double, summary: String?, location: LocationSelection, provider: WeatherProvider = .apple, generatedAt: Date = .now) -> PlanSnapshot {
        PlanSnapshot(
            weather: .forecast(high: high),
            recommendation: summary.map { OutfitRecommendation(summary: $0, items: []) },
            generatedAt: generatedAt,
            provider: provider,
            location: location
        )
    }

    var withoutLocation: PlanSnapshot {
        var snapshot = self
        snapshot.location = nil
        return snapshot
    }
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

    var isLoadingWeather: Bool {
        if case .loadingWeather = self { return true }
        return false
    }

    var partialSummary: String? {
        if case .generating(let partial) = recommendationState { return partial.summary }
        return nil
    }

    var partialItemNames: [String]? {
        if case .generating(let partial) = recommendationState { return partial.items.map(\.name) }
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
    private(set) var prewarmCount = 0

    nonisolated func prewarmRecommendation() {
        Task { await recordPrewarm() }
    }

    private func recordPrewarm() { prewarmCount += 1 }

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
    private let failingLatitudes: Set<Double>

    init(failingLatitudes: Set<Double> = []) {
        self.failingLatitudes = failingLatitudes
    }

    var pendingRecommendationCount: Int { pending.count }

    func completeRecommendation(with result: Result<OutfitRecommendation, Error>) {
        pending.popLast()?.resume(with: result)
    }

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        if failingLatitudes.contains(coordinate.latitude) { throw FakeFetchError() }
        return (.forecast(high: coordinate.latitude), nil)
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

/// Returns weather right away (high = latitude), then streams whatever partial suggestions
/// the test sends until the test finishes the stream.
private final class StreamingRecommendationFetcher: DayPlanFetching {
    private enum Event: Sendable {
        case partial(OutfitRecommendation)
        case finished(Result<OutfitRecommendation, Error>)
    }

    private let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let streaming = Mutex(false)

    init() {
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
    }

    /// Whether a recommendation is waiting on the stream, so sent partials will be seen.
    var isStreaming: Bool { streaming.withLock { $0 } }

    func send(partial: OutfitRecommendation) {
        continuation.yield(.partial(partial))
    }

    func finish(with result: Result<OutfitRecommendation, Error>) {
        continuation.yield(.finished(result))
    }

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        (.forecast(high: coordinate.latitude), nil)
    }

    func recommendationAvailability() async -> RecommendationAvailability {
        .available
    }

    func recommendation(for weather: DailyWeather) async throws -> OutfitRecommendation {
        Issue.record("The app should stream suggestions instead")
        return .placeholder
    }

    func recommendation(for weather: DailyWeather, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        streaming.withLock { $0 = true }
        for await event in events {
            switch event {
            case .partial(let partial):
                await onPartial(partial)
            case .finished(let result):
                return try result.get()
            }
        }
        throw CancellationError()
    }
}
