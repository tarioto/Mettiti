import CoreLocation
import FoundationModels
import Observation
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        try await waitUntil { viewModel.state.isLoaded }

        select(.currentLocation, in: locationPreference, for: viewModel)
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { viewModel.state.isLoaded }

        select(.custom(name: "City A", latitude: 10, longitude: 10), in: locationPreference, for: viewModel)
        try await waitUntil { viewModel.state.isLoaded }

        select(.currentLocation, in: locationPreference, for: viewModel)
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { snapshots.append($0) }
        )

        let loadA = Task { await viewModel.refresh() }
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        select(.custom(name: "City B", latitude: 20, longitude: 20), in: locationPreference, for: viewModel)
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { _ in }
        )

        let loadA = Task { await viewModel.refresh() }
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        select(.custom(name: "City B", latitude: 20, longitude: 20), in: locationPreference, for: viewModel)
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        try await waitUntil { await fetcher.pendingRecommendationCount == 1 }

        select(.custom(name: "City B", latitude: 20, longitude: 20), in: locationPreference, for: viewModel)
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { _ in }
        )
        viewModel.start()
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }

        // Same main-actor turn: the retry is cancelled before it ever runs.
        viewModel.retryRecommendation()
        select(.currentLocation, in: locationPreference, for: viewModel)
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { snapshots.append($0) }
        )
        viewModel.start()
        try await waitUntil { await fetcher.pendingRecommendationCount == 1 }
        await fetcher.completeRecommendation(with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }

        let recorder = StateRecorder(viewModel, skippingCurrent: true)

        viewModel.retryRecommendation()
        select(.custom(name: "City B", latitude: 20, longitude: 20), in: locationPreference, for: viewModel)
        try await waitUntil { viewModel.state.loadedHigh == 20 && viewModel.state.isRecommendationLoading }
        try await Task.sleep(for: .milliseconds(50))

        await fetcher.completeRecommendation(with: .success(OutfitRecommendation(summary: "City B", items: [])))
        try await waitUntil { viewModel.state.readySummary == "City B" }
        recorder.stop()

        #expect(!recorder.states.map(\.loadedHigh).contains(10))
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { _ in }
        )

        viewModel.start()
        try await waitUntil { viewModel.state.isLoaded }

        select(.custom(name: "City A", latitude: 10, longitude: 10), in: locationPreference, for: viewModel)

        #expect(viewModel.state.isLoaded)
        let requested = await fetcher.requestedCoordinates
        #expect(requested.count == 1)
    }

    // MARK: System errors (#29)

    @Test func offlineWeatherFetchFailsThePlanWithAFriendlyMessage() async throws {
        let fetcher = FakeDayPlanFetcher(weather: .failure(URLError(.notConnectedToInternet)))
        let viewModel = makeCustomCityViewModel(fetcher: fetcher)

        viewModel.start()
        try await waitUntil { viewModel.state.isFailed }

        #expect(viewModel.state.failureMessage == "You're offline. Check your connection and try again.")
    }

    @Test func offlineRefreshKeepsTodaysPlanWithAFriendlyNotice() async throws {
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA))

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .failure(URLError(.timedOut)))

        try await waitUntil { viewModel.refreshFailureMessage != nil }
        #expect(viewModel.refreshFailureMessage == "The weather service is taking too long to respond. Try again in a moment.")
    }

    @Test func modelErrorFailsTheSuggestionWithAFriendlyMessage() async throws {
        let busy = LanguageModelSession.GenerationError.rateLimited(.init(debugDescription: "Raw system text"))
        let fetcher = FakeDayPlanFetcher(recommendation: .failure(busy))
        let viewModel = makeCustomCityViewModel(fetcher: fetcher)

        viewModel.start()
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }

        #expect(viewModel.state.recommendationFailureMessage == "Apple Intelligence is busy right now. Try again in a moment.")
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: cityA) },
            publishSnapshot: { _ in }
        )

        viewModel.start()
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        select(.custom(name: "City B", latitude: 20, longitude: 20), in: locationPreference, for: viewModel)

        try await waitUntil { viewModel.state.loadedHigh == 20 }
        #expect(viewModel.state.isRecommendationLoading)
    }

    @Test func choosingAnotherCityDuringTheRefreshNeverShowsTheSavedOutfitWithItsWeather() async throws {
        let fetcher = GatedRecommendationFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = cityA
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: cityA) },
            publishSnapshot: { snapshots.append($0) }
        )
        viewModel.start()
        try await waitUntil { await fetcher.pendingRecommendationCount == 1 }
        let recorder = StateRecorder(viewModel)
        defer { recorder.stop() }

        let cityB = LocationSelection.custom(name: "City B", latitude: 20, longitude: 20)
        select(cityB, in: locationPreference, for: viewModel)
        try await waitUntil { await fetcher.pendingRecommendationCount == 2 }
        #expect(viewModel.state.loadedHigh == 20)
        #expect(viewModel.state.isRecommendationLoading)

        // City B's recommendation completes, then City A's superseded one arrives late.
        await fetcher.completeRecommendation(with: .success(OutfitRecommendation(summary: "City B outfit", items: [])))
        try await waitUntil { viewModel.state.readySummary == "City B outfit" }
        await fetcher.completeRecommendation(with: .success(OutfitRecommendation(summary: "City A outfit", items: [])))
        try await Task.sleep(for: .milliseconds(50))

        // After the Saved Plan, only City B's loading states and weather are shown.
        #expect(recorder.states.dropFirst().allSatisfy { $0.isIdle || $0.isLoadingWeather || $0.loadedHigh == 20 })
        #expect(viewModel.state.readySummary == "City B outfit")
        #expect(snapshots.map(\.location) == [cityB])
    }

    @Test func weatherFailureForAnotherCityChosenDuringTheRefreshFailsThePlanInsteadOfKeepingTheSavedOne() async throws {
        let fetcher = GatedDayPlanFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = cityA
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: cityA) },
            publishSnapshot: { _ in }
        )
        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        select(.custom(name: "City B", latitude: 20, longitude: 20), in: locationPreference, for: viewModel)
        try await waitUntil { await fetcher.isWaiting(onLatitude: 20) }
        await fetcher.complete(latitude: 20, with: .failure(FakeFetchError()))

        // The Saved Plan is City A's, so City B's failure shows the error screen, not a notice.
        try await waitUntil { viewModel.state.isFailed }
        #expect(viewModel.refreshFailureMessage == nil)
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
        #expect(viewModel.state.loadedHigh == 99)
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
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: .currentLocation) },
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        location.fail("Couldn't find your location right now.")

        #expect(viewModel.state.readySummary == "Saved outfit")
        #expect(viewModel.refreshFailureMessage == "Couldn't find your location right now.")
        #expect(snapshots.isEmpty)

        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { await fetcher.isWaiting(onLatitude: 47.6) }
        #expect(viewModel.state.readySummary == "Saved outfit")
        await fetcher.complete(latitude: 47.6, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(viewModel.refreshFailureMessage == nil)
        #expect(snapshots.map(\.weather.highTemperatureF) == [10])
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
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
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
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: providerPreference,
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: cityA, provider: .apple) },
            publishSnapshot: { snapshots.append($0) }
        )

        viewModel.start()
        try await waitUntil { await fetcher.pendingRecommendationCount == 1 }
        #expect(viewModel.state.loadedHigh == 99)
        let recorder = StateRecorder(viewModel)
        defer { recorder.stop() }

        select(.openMeteo, in: providerPreference, for: viewModel)

        try await waitUntil { viewModel.state.loadedHigh == 10 && viewModel.state.isRecommendationLoading }
        try await waitUntil { await fetcher.pendingRecommendationCount == 2 }
        await fetcher.completeRecommendation(with: .success(OutfitRecommendation(summary: "Open-Meteo outfit", items: [])))
        try await waitUntil { viewModel.state.readySummary == "Open-Meteo outfit" }
        await fetcher.completeRecommendation(with: .success(OutfitRecommendation(summary: "Apple outfit", items: [])))
        try await Task.sleep(for: .milliseconds(50))

        // The old provider's refresh had the same weather, so only the outfit tells the plans apart.
        #expect(!recorder.states.dropFirst().contains { $0.readySummary == "Saved outfit" })
        #expect(viewModel.state.readySummary == "Open-Meteo outfit")
        #expect(snapshots.map(\.provider) == [.openMeteo])
    }

    @Test func planCoversTheChosenPlanWindowFromNow() async throws {
        let fetcher = FakeDayPlanFetcher()
        let planWindowPreference = PlanWindowPreferenceStore(defaults: isolatedDefaults())
        planWindowPreference.window = .threeHours
        var snapshots: [PlanSnapshot] = []
        let viewModel = makePlanWindowViewModel(fetcher: fetcher, planWindowPreference: planWindowPreference, publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { viewModel.state.readySummary != nil }

        // Without an hourly forecast, the span is in the device's time zone.
        let expected = PlanSpan(window: .threeHours, startingAt: planWindowClock, timeZone: pacific)
        #expect(viewModel.state.span == expected)
        #expect(await fetcher.requestedSpans == [expected])
        #expect(snapshots.map(\.span) == [expected])
    }

    @Test func changingThePlanWindowRegeneratesTheOutfitForTheNewWindowWithoutRefetching() async throws {
        let fetcher = FakeDayPlanFetcher()
        let planWindowPreference = PlanWindowPreferenceStore(defaults: isolatedDefaults())
        let viewModel = makePlanWindowViewModel(fetcher: fetcher, planWindowPreference: planWindowPreference)
        viewModel.start()
        try await waitUntil { viewModel.state.readySummary != nil }

        select(.oneHour, in: planWindowPreference, for: viewModel)
        try await waitUntil { await fetcher.recommendationRequestCount == 2 }
        try await waitUntil { viewModel.state.span?.window == .oneHour && viewModel.state.readySummary != nil }
        select(.oneHour, in: planWindowPreference, for: viewModel)
        try await Task.sleep(for: .milliseconds(50))

        #expect(await fetcher.requestedSpans.map(\.window) == [.restOfDay, .oneHour])
        #expect(await fetcher.requestedCoordinates.count == 1)
    }

    @Test func changingThePlanWindowWhileRefreshingKeepsTheRefreshAndUsesTheNewWindow() async throws {
        let fetcher = GatedDayPlanFetcher()
        let planWindowPreference = PlanWindowPreferenceStore(defaults: isolatedDefaults())
        let viewModel = makePlanWindowViewModel(fetcher: fetcher, planWindowPreference: planWindowPreference)
        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 60)))
        try await waitUntil { viewModel.state.readySummary != nil }

        let refresh = Task { await viewModel.refresh() }
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        select(.oneHour, in: planWindowPreference, for: viewModel)
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 70)))
        await refresh.value

        #expect(viewModel.state.loadedHigh == 70)
        #expect(viewModel.state.span?.window == .oneHour)
        #expect(viewModel.state.readySummary != nil)
    }

    @Test func retryingTheOutfitCoversTheWindowFromTheRetry() async throws {
        let fetcher = FakeDayPlanFetcher(recommendation: .failure(FakeFetchError()))
        let planWindowPreference = PlanWindowPreferenceStore(defaults: isolatedDefaults())
        planWindowPreference.window = .oneHour
        let clock = FakeClock(planWindowClock)
        let viewModel = makePlanWindowViewModel(fetcher: fetcher, planWindowPreference: planWindowPreference, clock: clock)
        viewModel.start()
        try await waitUntil { await fetcher.recommendationRequestCount == 1 }
        try await waitUntil { if case .failed = viewModel.state.recommendationState { true } else { false } }

        clock.now = planWindowClock.addingTimeInterval(2 * 60 * 60)
        await fetcher.setRecommendation(.success(.placeholder))
        viewModel.retryRecommendation()
        try await waitUntil { viewModel.state.readySummary != nil }

        let expected = PlanSpan(window: .oneHour, startingAt: clock.now, timeZone: pacific)
        #expect(await fetcher.requestedSpans.last == expected)
        #expect(viewModel.state.span == expected)
    }

    @Test(arguments: [
        (PlanWindow.restOfDay, true),
        (PlanWindow.threeHours, false),
    ])
    func savedPlanIsOnlyShownForTheSamePlanWindow(window: PlanWindow, isShown: Bool) {
        let planWindowPreference = PlanWindowPreferenceStore(defaults: isolatedDefaults())
        planWindowPreference.window = window
        // Saved before Plan Windows existed, so it covers the rest of the day.
        let saved = PlanSnapshot.saved(high: 99, summary: "Saved outfit", location: cityA, generatedAt: planWindowClock)
        let viewModel = makePlanWindowViewModel(fetcher: GatedRecommendationFetcher(), planWindowPreference: planWindowPreference, saved: saved)

        viewModel.start()

        #expect((viewModel.state.loadedHigh == 99) == isShown)
    }

    @Test func oldProvidersSuggestionFinishingRightAfterTheChangeIsNeverShownOrSaved() async throws {
        let fetcher = MainActorGatedRecommendationFetcher()
        let providerPreference = WeatherProviderPreferenceStore(defaults: isolatedDefaults())
        providerPreference.provider = .apple
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = cityA
        var snapshots: [PlanSnapshot] = []
        let viewModel = DayPlanViewModel(
            locationManager: FakeLocationProvider(),
            locationPreference: locationPreference,
            providerPreference: providerPreference,
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: cityA, provider: .apple) },
            publishSnapshot: { snapshots.append($0) }
        )
        viewModel.start()
        try await waitUntil { fetcher.pendingCount == 1 }
        let recorder = StateRecorder(viewModel)
        defer { recorder.stop() }

        // The old suggestion resumes in the same main-actor job as the change, so it runs before
        // the new provider's load starts.
        fetcher.complete(with: OutfitRecommendation(summary: "Apple outfit", items: []))
        select(.openMeteo, in: providerPreference, for: viewModel)
        try await waitUntil { fetcher.pendingCount == 1 }
        fetcher.complete(with: OutfitRecommendation(summary: "Open-Meteo outfit", items: []))
        try await waitUntil { viewModel.state.readySummary == "Open-Meteo outfit" }

        #expect(!recorder.states.contains { $0.readySummary == "Apple outfit" })
        #expect(snapshots.map(\.provider) == [.openMeteo])
    }

    // MARK: Perceived latency (#23)

    @Test func modelIsPrewarmedWhileWeatherIsStillLoading() async throws {
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher)

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        #expect(fetcher.prewarmCount == 1)
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
        // Subscribed after start, so the first recorded state is the Saved Plan, not .idle.
        let recorder = StateRecorder(viewModel)
        defer { recorder.stop() }
        try await waitUntil { fetcher.isStreaming }
        // The fake handles events in order, so the partial is delivered before the finished outfit.
        fetcher.send(partial: OutfitRecommendation(summary: "Half a", items: []))
        fetcher.finish(with: .success(OutfitRecommendation(summary: "Fresh outfit", items: [])))
        try await waitUntil { viewModel.state.readySummary == "Fresh outfit" }

        #expect(!recorder.states.contains { $0.partialSummary != nil })
        #expect(recorder.states.dropLast().allSatisfy { $0.readySummary == "Saved outfit" && $0.loadedHigh == 99 })
        #expect(viewModel.state.loadedHigh == 10)
    }

    @Test func savedPlanWithoutAnOutfitStreamsTheFreshSuggestionWithTheFreshWeather() async throws {
        let fetcher = StreamingRecommendationFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: nil, location: cityA))

        viewModel.start()
        try await waitUntil { fetcher.isStreaming }
        fetcher.send(partial: OutfitRecommendation(summary: "Bring a", items: []))
        try await waitUntil { viewModel.state.partialSummary == "Bring a" }

        #expect(viewModel.state.loadedHigh == 10)
    }

    @Test func refreshAfterAFailedOneStillHoldsPartialsBackOverTheSavedPlansOutfit() async throws {
        let fetcher = StreamingRecommendationFetcher(failingWeatherRequests: 1)
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA))
        viewModel.start()
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        let recorder = StateRecorder(viewModel)
        defer { recorder.stop() }
        let refresh = Task { await viewModel.refresh() }
        try await waitUntil { fetcher.isStreaming }
        fetcher.send(partial: OutfitRecommendation(summary: "Half a", items: []))
        fetcher.finish(with: .success(OutfitRecommendation(summary: "Fresh outfit", items: [])))
        await refresh.value

        #expect(!recorder.states.contains { $0.partialSummary != nil })
        #expect(recorder.states.dropLast().allSatisfy { $0.readySummary == "Saved outfit" })
        #expect(viewModel.state.readySummary == "Fresh outfit")
    }

    @Test func refreshAfterAFailedOneStreamsIntoASavedPlanWithoutAnOutfit() async throws {
        let fetcher = StreamingRecommendationFetcher(failingWeatherRequests: 1)
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: nil, location: cityA))
        viewModel.start()
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        let refresh = Task { await viewModel.refresh() }
        try await waitUntil { fetcher.isStreaming }
        fetcher.send(partial: OutfitRecommendation(summary: "Bring a", items: []))
        try await waitUntil { viewModel.state.partialSummary == "Bring a" }
        #expect(viewModel.state.loadedHigh == 10)

        fetcher.finish(with: .success(OutfitRecommendation(summary: "Bring a coat.", items: [])))
        await refresh.value
        #expect(viewModel.state.readySummary == "Bring a coat.")
    }

    @Test func tryAgainOnASavedPlanWithoutAnOutfitStreamsTheFreshOne() async throws {
        let fetcher = StreamingRecommendationFetcher(failingWeatherRequests: 1)
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: nil, location: cityA), publishSnapshot: { snapshots.append($0) })
        viewModel.start()
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }
        let recorder = StateRecorder(viewModel)
        defer { recorder.stop() }

        viewModel.retryRecommendation()
        try await waitUntil { fetcher.isStreaming }
        // The earlier failure (and its Try Again button) gives way to the outfit loading on the
        // Saved Plan's weather while the fresh weather loads.
        #expect(recorder.states.dropFirst().first.map { $0.loadedHigh == 99 && $0.isRecommendationLoading } == true)
        #expect(!recorder.states.dropFirst().contains { $0.recommendationFailureMessage != nil })
        fetcher.send(partial: OutfitRecommendation(summary: "Bring a", items: []))
        try await waitUntil { viewModel.state.partialSummary == "Bring a" }
        #expect(viewModel.state.loadedHigh == 10)

        fetcher.finish(with: .success(OutfitRecommendation(summary: "Bring a coat.", items: [])))
        try await waitUntil { viewModel.state.readySummary == "Bring a coat." }
        #expect(viewModel.refreshFailureMessage == nil)
        #expect(snapshots.map(\.recommendation?.summary) == ["Bring a coat."])
    }

    @Test func refreshBehindTheSavedPlansOutfitSaysItsUpdatingUntilItFinishes() async throws {
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA))

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        #expect(viewModel.isUpdatingSavedPlan)

        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(!viewModel.isUpdatingSavedPlan)
    }

    @Test func failedRefreshBehindTheSavedPlansOutfitStopsSayingItsUpdating() async throws {
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA))

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        #expect(!viewModel.isUpdatingSavedPlan)
        #expect(viewModel.state.readySummary == "Saved outfit")
    }

    @Test func savedPlanWithoutAnOutfitDoesNotSayItsUpdatingSinceTheOutfitShowsItsProgress() async throws {
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: nil, location: cityA))

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        #expect(!viewModel.isUpdatingSavedPlan)
        #expect(viewModel.state.isRecommendationLoading)
    }

    // MARK: Superseded loads (#23 review)

    @Test func loadSupersededWhileCheckingTheModelWritesNothingSoTheNextGPSFixLoads() async throws {
        let location = FakeLocationProvider()
        let fetcher = AvailabilityGatedFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = cityA
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { _ in }
        )

        let loadA = Task { await viewModel.refresh() }
        try await waitUntil { await fetcher.isHoldingAvailability }
        select(.currentLocation, in: locationPreference, for: viewModel)
        #expect(viewModel.state.isIdle)

        await fetcher.releaseAvailability()
        await loadA.value
        #expect(viewModel.state.isIdle)

        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { viewModel.state.readySummary != nil }
        #expect(viewModel.state.loadedHigh == 47.6)
    }

    @Test func savedPlansOutfitForCurrentLocationSaysItsUpdatingWhileWaitingForTheFirstFix() async throws {
        let location = FakeLocationProvider()
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCurrentLocationViewModel(location: location, fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: .currentLocation))

        viewModel.start()
        #expect(viewModel.isUpdatingSavedPlan)

        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { await fetcher.isWaiting(onLatitude: 47.6) }
        #expect(viewModel.isUpdatingSavedPlan)

        await fetcher.complete(latitude: 47.6, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(!viewModel.isUpdatingSavedPlan)
    }

    @Test func locationErrorWhileWaitingForTheFirstFixStopsSayingTheSavedPlanIsUpdating() async throws {
        let location = FakeLocationProvider()
        let viewModel = makeCurrentLocationViewModel(location: location, fetcher: GatedDayPlanFetcher(), saved: .saved(high: 99, summary: "Saved outfit", location: .currentLocation))

        viewModel.start()
        location.fail("No location")

        #expect(!viewModel.isUpdatingSavedPlan)
        #expect(viewModel.refreshFailureMessage == "No location")
        #expect(viewModel.state.readySummary == "Saved outfit")
    }

    @Test func refreshBehindTheSavedPlansOutfitSaysItsUpdatingBeforeTheLoadRuns() async throws {
        let fetcher = GatedDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA))

        viewModel.start()

        #expect(viewModel.isUpdatingSavedPlan)
    }

    @Test func loadCancelledBeforeItRunsWritesNothingSoTheNextGPSFixLoads() async throws {
        let location = FakeLocationProvider()
        let fetcher = FakeDayPlanFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = cityA
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { _ in }
        )

        // City B's load is enqueued, then superseded before it gets to run.
        select(.custom(name: "City B", latitude: 20, longitude: 20), in: locationPreference, for: viewModel)
        select(.currentLocation, in: locationPreference, for: viewModel)
        // Main-actor jobs run in order, so B's load has run (and returned) once this resumes.
        await Task.yield()
        #expect(viewModel.state.isIdle)

        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { viewModel.state.readySummary != nil }
        #expect(await fetcher.requestedCoordinates.map(\.latitude) == [47.6])
    }

    @Test func tryAgainAfterAFailedSuggestionPrewarmsTheModel() async throws {
        let fetcher = GatedDayPlanFetcher(availability: .available, recommendation: .failure(FakeFetchError()))
        let viewModel = makeCustomCityViewModel(fetcher: fetcher)
        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.recommendationFailureMessage != nil }
        #expect(fetcher.prewarmCount == 1)

        viewModel.retryRecommendation()

        #expect(fetcher.prewarmCount == 2)
    }

    @Test func savedPlanWithoutAnOutfitSaysTheModelIsUnavailableBeforeTheFreshWeatherArrives() async throws {
        let fetcher = GatedDayPlanFetcher(availability: .unavailable(.appleIntelligenceNotEnabled))
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: nil, location: cityA))

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }

        #expect(viewModel.state.loadedHigh == 99)
        #expect(viewModel.state.unavailableReason == .appleIntelligenceNotEnabled)

        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(viewModel.state.unavailableReason == .appleIntelligenceNotEnabled)
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

    // MARK: Failed suggestion behind the Saved Plan's outfit

    @Test func failedSuggestionKeepsTheSavedPlansOutfitWithANotice() async throws {
        let fetcher = GatedDayPlanFetcher(availability: .available, recommendation: .failure(FakeFetchError()))
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA), publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        #expect(viewModel.state.readySummary == "Saved outfit")
        #expect(viewModel.state.loadedHigh == 99)
        #expect(viewModel.refreshFailureMessage == RecommendationState.failed("").problemMessage)
        #expect(!viewModel.isUpdatingSavedPlan)
        #expect(snapshots.isEmpty)
    }

    @Test func unavailableModelKeepsTheSavedPlansOutfitWithANotice() async throws {
        let fetcher = GatedDayPlanFetcher(availability: .unavailable(.modelNotReady))
        var snapshots: [PlanSnapshot] = []
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA), publishSnapshot: { snapshots.append($0) })

        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        #expect(viewModel.state.readySummary == "Saved outfit")
        #expect(viewModel.state.loadedHigh == 99)
        #expect(viewModel.refreshFailureMessage == RecommendationState.unavailable(.modelNotReady).problemMessage)
        #expect(snapshots.isEmpty)
    }

    @Test func streamThatFailsPartwayKeepsTheSavedPlansOutfit() async throws {
        let fetcher = StreamingRecommendationFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA))

        viewModel.start()
        try await waitUntil { fetcher.isStreaming }
        fetcher.send(partial: OutfitRecommendation(summary: "Half a", items: []))
        fetcher.finish(with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        #expect(viewModel.state.readySummary == "Saved outfit")
    }

    @Test func refreshAfterAFailedSuggestionReplacesTheSavedPlan() async throws {
        let fetcher = StreamingRecommendationFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, saved: .saved(high: 99, summary: "Saved outfit", location: cityA))
        viewModel.start()
        try await waitUntil { fetcher.isStreaming }
        fetcher.finish(with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.refreshFailureMessage != nil }

        let refresh = Task { await viewModel.refresh() }
        try await waitUntil { fetcher.isStreaming }
        fetcher.finish(with: .success(OutfitRecommendation(summary: "Fresh outfit", items: [])))
        await refresh.value

        #expect(viewModel.state.readySummary == "Fresh outfit")
        #expect(viewModel.state.loadedHigh == 10)
        #expect(viewModel.refreshFailureMessage == nil)
    }

    // MARK: Returning to the app (#24)

    @Test func returningOnANewDayClearsYesterdaysPlanAndLoadsToday() async throws {
        let clock = FakeClock(date("2026-10-18T20:00:00-07:00"))
        let fetcher = GatedDayPlanFetcher()
        let store = FakeSnapshotStore()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, store: store, clock: clock)
        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 99)))
        try await waitUntil { viewModel.state.loadedHigh == 99 }

        clock.now = date("2026-10-19T07:00:00-07:00")
        viewModel.refreshIfStale()

        #expect(viewModel.state.loadedHigh == nil)
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        #expect(viewModel.state.loadedHigh == nil)
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
        #expect(store.published.map(\.weather.highTemperatureF) == [99, 10])
    }

    @Test func returningSoonAfterTheLastLoadKeepsThePlanWithoutRefetching() async throws {
        let clock = FakeClock(date("2026-10-19T08:00:00-07:00"))
        let fetcher = FakeDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, store: FakeSnapshotStore(), clock: clock)
        viewModel.start()
        try await waitUntil { viewModel.state.isLoaded }

        clock.now = date("2026-10-19T10:59:00-07:00")
        viewModel.refreshIfStale()

        #expect(viewModel.state.isLoaded)
        try await Task.sleep(for: .milliseconds(50))
        let requested = await fetcher.requestedCoordinates
        #expect(requested.count == 1)
    }

    @Test func returningHoursLaterTheSameDayRefreshesWithThePlanStillOnScreen() async throws {
        let clock = FakeClock(date("2026-10-19T08:00:00-07:00"))
        let fetcher = GatedDayPlanFetcher()
        let store = FakeSnapshotStore()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, store: store, clock: clock)
        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 99)))
        try await waitUntil { viewModel.state.loadedHigh == 99 }

        clock.now = date("2026-10-19T11:00:00-07:00")
        viewModel.refreshIfStale()

        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        #expect(viewModel.state.loadedHigh == 99)
        #expect(viewModel.isUpdatingSavedPlan)
        await fetcher.complete(latitude: 10, with: .failure(FakeFetchError()))
        try await waitUntil { viewModel.refreshFailureMessage != nil }
        #expect(viewModel.state.loadedHigh == 99)
        #expect(store.published.count == 1)
    }

    @Test func returningOnANewDayShowsTodaysPlanFromTheBackgroundRefreshWhileItReloads() async throws {
        let clock = FakeClock(date("2026-10-18T20:00:00-07:00"))
        let fetcher = GatedDayPlanFetcher()
        let store = FakeSnapshotStore()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, store: store, clock: clock)
        viewModel.start()
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 99)))
        try await waitUntil { viewModel.state.loadedHigh == 99 }

        store.saved = .saved(high: 50, summary: "Background outfit", location: cityA, generatedAt: date("2026-10-19T00:05:00-07:00"))
        clock.now = date("2026-10-19T07:00:00-07:00")
        viewModel.refreshIfStale()

        #expect(viewModel.state.readySummary == "Background outfit")
        try await waitUntil { await fetcher.isWaiting(onLatitude: 10) }
        #expect(viewModel.state.loadedHigh == 50)
        await fetcher.complete(latitude: 10, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
    }

    @Test func returningOnANewDayInCurrentLocationWaitsForAFreshFix() async throws {
        let clock = FakeClock(date("2026-10-18T20:00:00-07:00"))
        let location = FakeLocationProvider()
        let fetcher = GatedDayPlanFetcher()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .currentLocation
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: fetcher,
            loadSnapshot: { nil },
            publishSnapshot: { _ in },
            now: { clock.now },
            calendar: gregorianCalendar(in: pacific)
        )
        viewModel.start()
        location.deliver(CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        try await waitUntil { await fetcher.isWaiting(onLatitude: 47.6) }
        await fetcher.complete(latitude: 47.6, with: .success(.forecast(high: 99)))
        try await waitUntil { viewModel.state.loadedHigh == 99 }

        clock.now = date("2026-10-19T07:00:00-07:00")
        viewModel.refreshIfStale()

        #expect(viewModel.state.isIdle)
        #expect(location.locationRequestCount == 2)
        location.deliver(CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0))
        try await waitUntil { await fetcher.isWaiting(onLatitude: 40.7) }
        await fetcher.complete(latitude: 40.7, with: .success(.forecast(high: 10)))
        try await waitUntil { viewModel.state.loadedHigh == 10 }
    }

    @Test func returningOnANewDayAfterTheLocationNeverArrivedStillClearsYesterdaysPlan() async throws {
        let clock = FakeClock(date("2026-10-18T20:00:00-07:00"))
        let location = FakeLocationProvider()
        let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
        locationPreference.selection = .currentLocation
        let viewModel = DayPlanViewModel(
            locationManager: location,
            locationPreference: locationPreference,
            providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
            planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
            fetcher: GatedDayPlanFetcher(),
            loadSnapshot: { .saved(high: 99, summary: "Saved outfit", location: .currentLocation, generatedAt: date("2026-10-18T08:00:00-07:00")) },
            publishSnapshot: { _ in },
            now: { clock.now },
            calendar: gregorianCalendar(in: pacific)
        )
        viewModel.start()
        location.fail("Couldn't find your location right now.")
        #expect(viewModel.state.readySummary == "Saved outfit")

        clock.now = date("2026-10-19T07:00:00-07:00")
        viewModel.refreshIfStale()
        #expect(viewModel.state.isIdle)
        #expect(location.locationRequestCount == 2)

        // Still waiting on that fix: switching back in shouldn't ask again.
        viewModel.refreshIfStale()
        #expect(location.locationRequestCount == 2)
    }

    @Test func refreshIfStaleBeforeAnyLoadDoesNothing() async throws {
        let fetcher = FakeDayPlanFetcher()
        let viewModel = makeCustomCityViewModel(fetcher: fetcher, store: FakeSnapshotStore(), clock: FakeClock(.now))

        viewModel.refreshIfStale()

        #expect(viewModel.state.isIdle)
        let requested = await fetcher.requestedCoordinates
        #expect(requested.isEmpty)
    }
}

// MARK: - Helpers

private let cityA = LocationSelection.custom(name: "City A", latitude: 10, longitude: 10)

@MainActor
private func makeCurrentLocationViewModel(location: FakeLocationProvider, fetcher: DayPlanFetching, saved: PlanSnapshot? = nil) -> DayPlanViewModel {
    let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
    locationPreference.selection = .currentLocation
    return DayPlanViewModel(
        locationManager: location,
        locationPreference: locationPreference,
        providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
        planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
        fetcher: fetcher,
        loadSnapshot: { saved },
        publishSnapshot: { _ in }
    )
}

@MainActor
private func makeCustomCityViewModel(fetcher: DayPlanFetching, saved: PlanSnapshot? = nil, publishSnapshot: @escaping @MainActor (PlanSnapshot) -> Void = { _ in }) -> DayPlanViewModel {
    let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
    locationPreference.selection = cityA
    return DayPlanViewModel(
        locationManager: FakeLocationProvider(),
        locationPreference: locationPreference,
        providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
        planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
        fetcher: fetcher,
        loadSnapshot: { saved },
        publishSnapshot: publishSnapshot
    )
}

/// A custom-city view model with a Plan Window store the test controls, at 2:20 PM PDT unless
/// the test moves `clock` on.
@MainActor
private func makePlanWindowViewModel(fetcher: DayPlanFetching, planWindowPreference: PlanWindowPreferenceStore, saved: PlanSnapshot? = nil, clock: FakeClock = FakeClock(planWindowClock), publishSnapshot: @escaping @MainActor (PlanSnapshot) -> Void = { _ in }) -> DayPlanViewModel {
    let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
    locationPreference.selection = cityA
    return DayPlanViewModel(
        locationManager: FakeLocationProvider(),
        locationPreference: locationPreference,
        providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
        planWindowPreference: planWindowPreference,
        fetcher: fetcher,
        loadSnapshot: { saved },
        publishSnapshot: publishSnapshot,
        now: { clock.now },
        calendar: gregorianCalendar(in: pacific)
    )
}

private let planWindowClock = date("2026-10-09T21:20:00Z")

/// A view model whose Saved Plan store and clock the test controls, for tests that move time on.
@MainActor
private func makeCustomCityViewModel(fetcher: DayPlanFetching, store: FakeSnapshotStore, clock: FakeClock) -> DayPlanViewModel {
    let locationPreference = LocationPreferenceStore(defaults: isolatedDefaults())
    locationPreference.selection = cityA
    return DayPlanViewModel(
        locationManager: FakeLocationProvider(),
        locationPreference: locationPreference,
        providerPreference: WeatherProviderPreferenceStore(defaults: isolatedDefaults()),
        planWindowPreference: PlanWindowPreferenceStore(defaults: isolatedDefaults()),
        fetcher: fetcher,
        loadSnapshot: { store.saved },
        publishSnapshot: { store.publish($0) },
        now: { clock.now },
        calendar: gregorianCalendar(in: pacific)
    )
}

@MainActor
private final class FakeClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// Stands in for the shared Saved Plan: the latest published plan is the one loaded next.
@MainActor
private final class FakeSnapshotStore {
    var saved: PlanSnapshot?
    private(set) var published: [PlanSnapshot] = []

    func publish(_ snapshot: PlanSnapshot) {
        published.append(snapshot)
        saved = snapshot
    }
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

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    var loadedHigh: Double? {
        if case .loaded(let weather, _, _, _, _) = self { return weather.highTemperatureF }
        return nil
    }

    var span: PlanSpan? {
        if case .loaded(_, _, let span, _, _) = self { return span }
        return nil
    }

    var recommendationState: RecommendationState? {
        if case .loaded(_, _, _, _, let recommendation) = self { return recommendation }
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

private struct FakeFetchError: UserFacingError {
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

/// Changes the selection the way Settings does, then tells the view model as ContentView does.
/// Reselections are passed on too, so the view model's own guard against them is tested.
@MainActor
private func select(_ selection: LocationSelection, in store: LocationPreferenceStore, for viewModel: DayPlanViewModel) {
    store.selection = selection
    viewModel.locationSelectionDidChange()
}

/// Changes the provider the way Settings does, then tells the view model as ContentView does.
@MainActor
private func select(_ provider: WeatherProvider, in store: WeatherProviderPreferenceStore, for viewModel: DayPlanViewModel) {
    store.provider = provider
    viewModel.providerDidChange()
}

/// Changes the Plan Window the way Settings does, then tells the view model as ContentView does.
@MainActor
private func select(_ window: PlanWindow, in store: PlanWindowPreferenceStore, for viewModel: DayPlanViewModel) {
    store.window = window
    viewModel.planWindowDidChange()
}

/// Records every `state` the view model takes, as `$state.sink` did: the one current at init, each
/// later write (even one overwritten in the same main-actor job), ending with the current one.
/// `onChange` runs in `state`'s willSet, so it records the value being replaced; the newest value
/// is read when `states` is.
@MainActor
private final class StateRecorder {
    private let viewModel: DayPlanViewModel
    private let skipsCurrent: Bool
    /// Each value replaced since init, oldest first.
    private var replaced: [LoadState] = []
    /// The last value, once `stop()` freezes the recording.
    private var final: LoadState?

    init(_ viewModel: DayPlanViewModel, skippingCurrent: Bool = false) {
        self.viewModel = viewModel
        skipsCurrent = skippingCurrent
        track()
    }

    var states: [LoadState] {
        let all = replaced + [final ?? viewModel.state]
        return skipsCurrent ? Array(all.dropFirst()) : all
    }

    func stop() {
        guard final == nil else { return }
        final = viewModel.state
    }

    private func track() {
        withObservationTracking { _ = viewModel.state } onChange: { [weak self] in
            // State is only written on the main actor, so its willSet calls this there.
            MainActor.assumeIsolated { self?.stateWillChange() }
        }
    }

    private func stateWillChange() {
        guard final == nil else { return }
        replaced.append(viewModel.state)
        track()
    }
}

@MainActor
private final class FakeLocationProvider: LocationProviding {
    var onCoordinate: ((CLLocationCoordinate2D) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var locationRequestCount = 0

    func requestLocation() {
        locationRequestCount += 1
    }

    func fail(_ message: String) {
        onError?(message)
    }

    func deliver(_ coordinate: CLLocationCoordinate2D) {
        onCoordinate?(coordinate)
    }
}

/// A test fetcher that doesn't stream: prewarming does nothing, and suggestions arrive whole.
private protocol WholeRecommendationFetching: DayPlanFetching {}

extension WholeRecommendationFetching {
    func prewarmRecommendation() {}

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        try await recommendation(for: weather, hourly: hourly, span: span)
    }
}

private actor FakeDayPlanFetcher: WholeRecommendationFetching {
    private(set) var requestedCoordinates: [CLLocationCoordinate2D] = []
    private(set) var recommendationRequestCount = 0
    private(set) var requestedSpans: [PlanSpan] = []
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

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) async throws -> OutfitRecommendation {
        recommendationRequestCount += 1
        requestedSpans.append(span)
        return try recommendationResult.get()
    }
}

/// Holds each weather request until the test completes it, so tests control completion order.
private actor GatedDayPlanFetcher: DayPlanFetching {
    private var pending: [Double: CheckedContinuation<DailyWeather, Error>] = [:]
    private let availability: RecommendationAvailability
    private let recommendationResult: Result<OutfitRecommendation, Error>
    private let prewarms = Mutex(0)

    init(availability: RecommendationAvailability = .available, recommendation: Result<OutfitRecommendation, Error> = .success(.placeholder)) {
        self.availability = availability
        recommendationResult = recommendation
    }

    nonisolated var prewarmCount: Int { prewarms.withLock { $0 } }

    nonisolated func prewarmRecommendation() {
        prewarms.withLock { $0 += 1 }
    }

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
        availability
    }

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) async throws -> OutfitRecommendation {
        try recommendationResult.get()
    }

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        try recommendationResult.get()
    }
}

/// Returns weather right away (high = latitude) but holds each recommendation until the test
/// completes it, newest first, so tests can observe the plan while suggestions are generating.
private actor GatedRecommendationFetcher: WholeRecommendationFetching {
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

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) async throws -> OutfitRecommendation {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
    }
}

/// Returns weather right away (high = latitude) but holds each recommendation on the main actor
/// until the test completes it, so a completion resumes the load ahead of work queued after it.
@MainActor
private final class MainActorGatedRecommendationFetcher: DayPlanFetching {
    private var pending: [CheckedContinuation<OutfitRecommendation, Error>] = []

    var pendingCount: Int { pending.count }

    func complete(with recommendation: OutfitRecommendation) {
        pending.removeFirst().resume(returning: recommendation)
    }

    nonisolated func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        (.forecast(high: coordinate.latitude), nil)
    }

    nonisolated func recommendationAvailability() async -> RecommendationAvailability {
        .available
    }

    nonisolated func prewarmRecommendation() {}

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) async throws -> OutfitRecommendation {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        try await recommendation(for: weather, hourly: hourly, span: span)
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
    private let weatherFailuresLeft: Mutex<Int>

    /// The first `failingWeatherRequests` weather requests fail, e.g. to fail a Saved Plan's refresh.
    init(failingWeatherRequests: Int = 0) {
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        weatherFailuresLeft = Mutex(failingWeatherRequests)
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
        let fails = weatherFailuresLeft.withLock { left in
            defer { left = max(left - 1, 0) }
            return left > 0
        }
        if fails { throw FakeFetchError() }
        return (.forecast(high: coordinate.latitude), nil)
    }

    func recommendationAvailability() async -> RecommendationAvailability {
        .available
    }

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) async throws -> OutfitRecommendation {
        Issue.record("The app should stream suggestions instead")
        return .placeholder
    }

    func prewarmRecommendation() {}

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
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

/// Returns weather right away (high = latitude) but holds the first model availability check
/// until the test releases it, so a test can supersede a load while it waits there.
private actor AvailabilityGatedFetcher: WholeRecommendationFetching {
    private var heldCheck: CheckedContinuation<Void, Never>?
    private var hasHeldACheck = false

    var isHoldingAvailability: Bool { heldCheck != nil }

    func releaseAvailability() {
        heldCheck?.resume()
        heldCheck = nil
    }

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        (.forecast(high: coordinate.latitude), nil)
    }

    func recommendationAvailability() async -> RecommendationAvailability {
        if !hasHeldACheck {
            hasHeldACheck = true
            await withCheckedContinuation { heldCheck = $0 }
        }
        return .available
    }

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) async throws -> OutfitRecommendation {
        .placeholder
    }
}
