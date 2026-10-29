import CoreLocation
import Foundation
import Testing
@testable import Mettiti

@MainActor
struct BackgroundPlanRefreshTests {
    @Test func snapshotFromTodayIsLeftAloneWithoutFetching() async {
        let harness = Harness(now: date("2026-10-08T09:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-08T08:00:00-07:00"))

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .alreadyCurrent)
        #expect(await harness.fetcher.weatherRequests.isEmpty)
        #expect(harness.published.isEmpty)
    }

    @Test func snapshotFromYesterdayIsReplacedWithPlanForCustomCity() async {
        let now = date("2026-10-08T06:00:00-07:00")
        let harness = Harness(now: now)
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        harness.lastKnownGPSCoordinate = CLLocationCoordinate2D(latitude: 1, longitude: 2)
        harness.provider = .openMeteo

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .refreshed)
        #expect(await harness.fetcher.weatherRequests == [WeatherRequest(latitude: 47.6, longitude: -122.3, provider: .openMeteo)])
        #expect(harness.published.map(\.generatedAt) == [now])
        #expect(harness.published.map(\.provider) == [.openMeteo])
    }

    @Test func publishedPlanRecordsItsLocationAndHourlyForecastSoTheAppCanShowItOnLaunch() async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        await harness.fetcher.returnHourly(HourlyForecast(timeZone: pacific, points: [
            HourlyTemperaturePoint(date: date("2026-10-08T06:00:00-07:00"), meanF: 50, minF: 48, maxF: 52, precipitationProbability: 0),
        ]))

        _ = await harness.refresher.refreshIfStale()

        #expect(harness.published.map(\.location) == [.custom(name: "Seattle", latitude: 47.6, longitude: -122.3)])
        #expect(harness.published.first?.hourly?.points.map(\.date) == [date("2026-10-08T06:00:00-07:00")])
    }

    @Test func missingSnapshotIsFilledUsingLastKnownGPSFixForCurrentLocation() async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = nil
        harness.selection = .currentLocation
        harness.lastKnownGPSCoordinate = CLLocationCoordinate2D(latitude: 37.3, longitude: -122.0)
        harness.provider = .apple

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .refreshed)
        #expect(await harness.fetcher.weatherRequests == [WeatherRequest(latitude: 37.3, longitude: -122.0, provider: .apple)])
        #expect(harness.published.count == 1)
    }

    @Test func currentLocationWithoutAKnownFixSkipsTheRefresh() async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .currentLocation
        harness.lastKnownGPSCoordinate = nil

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .skippedNoCoordinate)
        #expect(await harness.fetcher.weatherRequests.isEmpty)
        #expect(harness.published.isEmpty)
    }

    @Test func weatherFetchFailureLeavesExistingSnapshotUnpublished() async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        await harness.fetcher.failWeather()

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .failed)
        #expect(harness.published.isEmpty)
    }

    @Test func onDeviceModelFailurePublishesWeatherOnlySnapshot() async {
        let now = date("2026-10-08T06:00:00-07:00")
        let harness = Harness(now: now)
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        await harness.fetcher.failRecommendation()

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .refreshedWeatherOnly)
        #expect(harness.published.count == 1)
        #expect(harness.published.first?.recommendation == nil)
        #expect(harness.published.first?.adviceBasis == nil)
        #expect(harness.published.first?.generatedAt == now)
    }

    @Test func publishedPlanRecordsTheWeatherItsOutfitWasBasedOnSoTheAppCanTellWhenItChanges() async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        _ = await harness.refresher.refreshIfStale()

        #expect(harness.published.first?.adviceBasis?.highF == DailyWeather.placeholder.highTemperatureF)
        #expect(harness.published.first?.adviceBasis?.window == harness.published.first?.span?.window)
    }

    @Test(arguments: [
        RecommendationState.UnavailableReason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady,
    ])
    func unavailableModelPublishesWeatherOnlySnapshotWithoutAttemptingGeneration(reason: RecommendationState.UnavailableReason) async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        await harness.fetcher.makeUnavailable(reason)

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .refreshedWeatherOnly)
        #expect(await harness.fetcher.recommendationRequestCount == 0)
        #expect(harness.published.count == 1)
        #expect(harness.published.first?.recommendation == nil)
    }

    @Test func todaysWeatherOnlySnapshotRetriesTheRecommendationOnceTheModelIsAvailable() async {
        // e.g. this morning's generation failed, or the model was still downloading.
        let harness = Harness(now: date("2026-10-08T09:00:00-07:00"))
        harness.snapshot = .weatherOnly(at: date("2026-10-08T06:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .refreshed)
        #expect(await harness.fetcher.recommendationRequestCount == 1)
        #expect(harness.published.count == 1)
        #expect(harness.published.first?.recommendation != nil)
    }

    @Test func todaysWeatherOnlySnapshotIsRefreshedWhileTheModelIsNotReadyYet() async {
        let now = date("2026-10-08T09:00:00-07:00")
        let harness = Harness(now: now)
        harness.snapshot = .weatherOnly(at: date("2026-10-08T06:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        await harness.fetcher.makeUnavailable(.modelNotReady)

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .refreshedWeatherOnly)
        #expect(await harness.fetcher.weatherRequests.count == 1)
        #expect(await harness.fetcher.recommendationRequestCount == 0)
        #expect(harness.published.map(\.generatedAt) == [now])
    }

    @Test(arguments: [
        RecommendationState.UnavailableReason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
    ])
    func todaysWeatherOnlySnapshotIsFinalWhenTheModelIsPermanentlyUnavailable(reason: RecommendationState.UnavailableReason) async {
        let harness = Harness(now: date("2026-10-08T08:00:00-07:00"))
        harness.snapshot = .weatherOnly(at: date("2026-10-08T06:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        await harness.fetcher.makeUnavailable(reason)

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .alreadyCurrent)
        #expect(await harness.fetcher.weatherRequests.isEmpty)
        #expect(harness.published.isEmpty)
    }

    @Test func snapshotFromEarlierTodayInDeviceZoneIsCurrentEvenWhenYesterdayInUTC() async {
        // 08:00 and 09:00 Tokyo are the same local day, but 08:00 is still Oct 7 in UTC.
        let harness = Harness(now: date("2026-10-08T09:00:00+09:00"))
        harness.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        harness.snapshot = .generated(at: date("2026-10-08T08:00:00+09:00"))
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7)

        #expect(await harness.refresher.refreshIfStale() == .alreadyCurrent)
        #expect(await harness.fetcher.weatherRequests.isEmpty)
    }

    @Test func selectionChangedInTheAppDuringTheFetchIsNotOverwritten() async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        await harness.fetcher.duringWeatherFetch { @MainActor in
            harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7)
        }

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .supersededByApp)
        #expect(harness.published.isEmpty)
    }

    @Test func providerChangedInTheAppDuringTheFetchIsNotOverwritten() async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        harness.provider = .openMeteo
        await harness.fetcher.duringWeatherFetch { @MainActor in
            harness.provider = .apple
        }

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .supersededByApp)
        #expect(harness.published.isEmpty)
    }

    @Test func todaysFullPlanSavedByTheAppDuringTheFetchIsNotReplacedWithWeatherOnly() async {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        await harness.fetcher.failRecommendation()
        let appPlanDate = date("2026-10-08T05:59:00-07:00")
        await harness.fetcher.duringWeatherFetch { @MainActor in
            harness.snapshot = .generated(at: appPlanDate)
        }

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .supersededByApp)
        #expect(harness.published.isEmpty)
    }

    @Test func cancellingWhileSuggestionsAreGeneratingPublishesNothing() async {
        // e.g. the background task's time expires mid-generation; yesterday's full plan should stay.
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        let generationStarted = await harness.fetcher.holdRecommendationUntilCancelled()
        let refresher = harness.refresher

        let refresh = Task { await refresher.refreshIfStale() }
        for await _ in generationStarted { break }
        refresh.cancel()
        let outcome = await refresh.value

        #expect(outcome == .cancelled)
        #expect(harness.published.isEmpty)
    }

    // MARK: - Plan Window

    @Test func todaysPlanStaleForItsWindowIsRefreshed() async {
        let harness = Harness(now: date("2026-10-08T08:30:00-07:00"))
        harness.planWindow = .oneHour
        harness.snapshot = .generated(at: date("2026-10-08T08:00:00-07:00"), window: .oneHour)
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
    }

    @Test func todaysPlanNotYetStaleForItsWindowIsLeftAlone() async {
        let harness = Harness(now: date("2026-10-08T08:59:00-07:00"))
        harness.planWindow = .threeHours
        harness.snapshot = .generated(at: date("2026-10-08T08:00:00-07:00"), window: .threeHours)
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        #expect(await harness.refresher.refreshIfStale() == .alreadyCurrent)
        #expect(await harness.fetcher.weatherRequests.isEmpty)
    }

    @Test func todaysPlanForAnotherWindowThanTheSettingsDefaultIsRemade() async {
        let now = date("2026-10-08T08:10:00-07:00")
        let harness = Harness(now: now)
        harness.planWindow = .sixHours
        harness.snapshot = .generated(at: date("2026-10-08T08:00:00-07:00"), window: .oneHour)
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
        #expect(harness.published.map(\.span?.window) == [.sixHours])
    }

    @Test func publishedPlanCoversTheSettingsDefaultWindowFromNow() async {
        let now = date("2026-10-08T14:00:00-07:00")
        let harness = Harness(now: now)
        harness.planWindow = .threeHours
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        _ = await harness.refresher.refreshIfStale()

        #expect(harness.published.first?.span?.window == .threeHours)
        #expect(harness.published.first?.span?.interval == DateInterval(start: now, end: date("2026-10-08T17:00:00-07:00")))
    }

    @Test(arguments: [
        (PlanWindow.oneHour, "2026-10-08T14:30:00-07:00"),
        (PlanWindow.threeHours, "2026-10-08T15:00:00-07:00"),
        (PlanWindow.sixHours, "2026-10-08T16:00:00-07:00"),
        (PlanWindow.twelveHours, "2026-10-08T17:00:00-07:00"),
        (PlanWindow.restOfDay, "2026-10-08T17:00:00-07:00"),
    ])
    func nextRequestIsWhenTheFreshPlanGoesStaleForItsWindow(window: PlanWindow, expected: String) {
        let harness = Harness(now: date("2026-10-08T14:00:00-07:00"))
        harness.planWindow = window
        harness.snapshot = .generated(at: date("2026-10-08T14:00:00-07:00"), window: window)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date(expected))
    }

    @Test func nextRequestIsNeverSoonerThanTheThirtyMinuteFloor() {
        let harness = Harness(now: date("2026-10-08T14:20:00-07:00"))
        harness.planWindow = .oneHour
        harness.snapshot = .generated(at: date("2026-10-08T14:00:00-07:00"), window: .oneHour)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-08T14:50:00-07:00"))
    }

    @Test func nextRequestFallingOvernightWaitsUntilAboutSixAM() {
        // Stale at 1:00 AM, but a plan made then would be about the night.
        let harness = Harness(now: date("2026-10-08T22:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-08T22:00:00-07:00"), window: .restOfDay)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00-07:00"))
    }

    // MARK: - Meaningful Change

    /// Today's stale plan for Seattle, made at 9 AM for `window` from the weather the fetcher
    /// returns, with no basis.
    private func staleSeattlePlanWithoutBasis(in harness: Harness, window: PlanWindow = .restOfDay) {
        let seattle = LocationSelection.custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        harness.selection = seattle
        harness.snapshot = .generated(at: date("2026-10-08T09:00:00-07:00"), window: window, location: seattle)
    }

    /// The same, with a basis whose high is `deltaF`°F off the weather the fetcher returns.
    private func staleSeattlePlan(in harness: Harness, window: PlanWindow = .restOfDay, basisHighOffBy deltaF: Double) {
        staleSeattlePlanWithoutBasis(in: harness, window: window)
        var basis = WindowSummary(weather: .placeholder, hourly: nil, span: harness.snapshot!.span!)
        basis.highF += deltaF
        harness.snapshot?.adviceBasis = basis
    }

    @Test func staleTodaysPlanWithNoMeaningfulChangeKeepsItsOutfitAndBasis() async {
        let now = date("2026-10-08T12:30:00-07:00")
        let harness = Harness(now: now)
        staleSeattlePlan(in: harness, basisHighOffBy: 1)

        let outcome = await harness.refresher.refreshIfStale()

        #expect(outcome == .refreshedKeepingOutfit)
        #expect(await harness.fetcher.weatherRequests.count == 1)
        #expect(await harness.fetcher.recommendationRequestCount == 0)
        #expect(harness.published.map(\.generatedAt) == [now])
        #expect(harness.published.first?.recommendation?.summary == OutfitRecommendation.placeholder.summary)
        #expect(harness.published.first?.adviceBasis?.highF == DailyWeather.placeholder.highTemperatureF + 1)
        #expect(harness.published.first?.span?.interval.start == now)
    }

    @Test func staleTodaysPlanWithAMeaningfulChangeIsRemade() async {
        let harness = Harness(now: date("2026-10-08T12:30:00-07:00"))
        staleSeattlePlan(in: harness, basisHighOffBy: 10)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
        #expect(await harness.fetcher.recommendationRequestCount == 1)
        #expect(harness.published.first?.adviceBasis?.highF == DailyWeather.placeholder.highTemperatureF)
    }

    @Test func staleTodaysPlanWithoutABasisIsAlwaysRemade() async {
        let harness = Harness(now: date("2026-10-08T12:30:00-07:00"))
        staleSeattlePlanWithoutBasis(in: harness)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
        #expect(await harness.fetcher.recommendationRequestCount == 1)
        #expect(harness.published.first?.adviceBasis != nil)
    }

    @Test func staleTodaysPlanWrittenInTheCurrentLanguageKeepsItsOutfitAndLanguage() async {
        let harness = Harness(now: date("2026-10-08T12:30:00-07:00"))
        staleSeattlePlan(in: harness, basisHighOffBy: 0)

        #expect(await harness.refresher.refreshIfStale() == .refreshedKeepingOutfit)
        #expect(harness.published.first?.adviceLanguage == testResponseLanguage)
    }

    @Test(arguments: ["French", nil] as [String?])
    func staleTodaysPlanWrittenInAnotherOrNoLanguageIsRemade(savedLanguage: String?) async {
        let harness = Harness(now: date("2026-10-08T12:30:00-07:00"))
        staleSeattlePlan(in: harness, basisHighOffBy: 0)
        harness.snapshot?.adviceLanguage = savedLanguage

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
        #expect(await harness.fetcher.recommendationRequestCount == 1)
        #expect(harness.published.first?.adviceLanguage == testResponseLanguage)
    }

    @Test func freshPlanWithAnOutfitInAnotherLanguageIsStillRefreshed() async {
        let harness = Harness(now: date("2026-10-08T09:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-08T08:30:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        harness.language = "French"

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
        #expect(harness.published.first?.adviceLanguage == "French")
    }

    @Test func planForAnotherLocationIsRemadeEvenWithoutAMeaningfulChange() async {
        // The outfit was written for Seattle; Portland's weather may look the same but isn't.
        let harness = Harness(now: date("2026-10-08T12:30:00-07:00"))
        staleSeattlePlan(in: harness, basisHighOffBy: 0)
        harness.selection = .custom(name: "Portland", latitude: 45.5, longitude: -122.7)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
        #expect(await harness.fetcher.recommendationRequestCount == 1)
    }

    @Test func planForAnotherWindowThanTheSettingsDefaultIsRemadeEvenWithABasis() async {
        let harness = Harness(now: date("2026-10-08T12:30:00-07:00"))
        harness.planWindow = .threeHours
        staleSeattlePlan(in: harness, window: .restOfDay, basisHighOffBy: 0)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
        #expect(await harness.fetcher.recommendationRequestCount == 1)
        #expect(harness.published.first?.adviceBasis?.window == .threeHours)
    }

    @Test(arguments: [0.0, 10.0])
    func settingsWindowChangedDuringTheFetchIsNotPublished(basisHighOffBy deltaF: Double) async {
        // Whether the outfit would be kept or remade, it's for the window the run started with.
        let harness = Harness(now: date("2026-10-08T12:30:00-07:00"))
        staleSeattlePlan(in: harness, basisHighOffBy: deltaF)
        await harness.fetcher.duringWeatherFetch { @MainActor in
            harness.planWindow = .oneHour
        }

        #expect(await harness.refresher.refreshIfStale() == .supersededByApp)
        #expect(harness.published.isEmpty)
    }

    @Test func planFromAnEarlierDayIsRemadeEvenWithoutAMeaningfulChange() async {
        let harness = Harness(now: date("2026-10-09T09:30:00-07:00"))
        staleSeattlePlan(in: harness, basisHighOffBy: 0)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
        #expect(await harness.fetcher.recommendationRequestCount == 1)
    }

    // MARK: - Quiet hours

    @Test(arguments: [
        ("2026-10-08T22:29:00-07:00", "2026-10-08T22:59:00-07:00"), // 10:59 PM: before quiet hours
        ("2026-10-08T22:30:00-07:00", "2026-10-09T06:00:00-07:00"), // 11:00 PM
        ("2026-10-08T23:29:00-07:00", "2026-10-09T06:00:00-07:00"), // 11:59 PM
        ("2026-10-09T05:29:00-07:00", "2026-10-09T06:00:00-07:00"), // 5:59 AM
        ("2026-10-09T05:30:00-07:00", "2026-10-09T06:00:00-07:00"), // 6:00 AM: after quiet hours
    ])
    func nextRequestInQuietHoursMovesToTheNextSixAM(now: String, expected: String) {
        // With no plan, a 1h window retries in 30 minutes.
        let harness = Harness(now: date(now))
        harness.planWindow = .oneHour

        #expect(harness.refresher.nextRequestDate(availability: .available) == date(expected))
    }

    @Test(arguments: ["2026-10-08T23:00:00-07:00", "2026-10-08T23:59:00-07:00", "2026-10-09T05:59:00-07:00"])
    func lateRunInQuietHoursMakesNoPlanAndWaitsForSixAM(now: String) async {
        // e.g. iOS ran a 10:45 PM request late.
        let harness = Harness(now: date(now))
        harness.snapshot = .generated(at: date("2026-10-08T15:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        #expect(await harness.refresher.refreshIfStale() == .skippedQuietHours)
        #expect(await harness.fetcher.weatherRequests.isEmpty)
        #expect(harness.published.isEmpty)
        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00-07:00"))
    }

    @Test func nextRequestAfterAPlanMadeJustBeforeSixAMKeepsTheFloor() {
        // e.g. the app made a plan for another window at 5:45 and then went to the background.
        let harness = Harness(now: date("2026-10-09T05:50:00-07:00"))
        harness.planWindow = .threeHours
        harness.snapshot = .generated(at: date("2026-10-09T05:45:00-07:00"), window: .oneHour)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:15:00-07:00"))
    }

    @Test(arguments: ["2026-10-08T22:59:00-07:00", "2026-10-09T06:00:00-07:00"])
    func runJustOutsideQuietHoursMakesThePlan(now: String) async {
        let harness = Harness(now: date(now))
        harness.snapshot = .generated(at: date("2026-10-08T15:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
    }

    @Test func runAtSixAMMakesThePlan() async {
        let harness = Harness(now: date("2026-10-09T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-08T15:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
    }

    // MARK: - A city in another time zone than the device's

    @Test func quietHoursAreTheCitys() async {
        // 11:30 PM in Tokyo is 7:30 AM on the Pacific device.
        let harness = Harness(now: date("2026-10-08T23:30:00+09:00"))
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        harness.snapshot = .generated(at: date("2026-10-08T15:00:00+09:00"), window: .restOfDay, in: tokyo, location: harness.selection)

        #expect(await harness.refresher.refreshIfStale() == .skippedQuietHours)
        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00+09:00"))
    }

    @Test func deviceNightIsNoQuietHoursForACityWhereItIsDay() async {
        // 11:30 PM on the Pacific device is 3:30 PM in Tokyo.
        let harness = Harness(now: date("2026-10-08T23:30:00-07:00"))
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        harness.snapshot = .generated(at: date("2026-10-09T09:00:00+09:00"), window: .restOfDay, in: tokyo, location: harness.selection)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
    }

    @Test func cityPlanGoingStaleOvernightThereWaitsForTheCitysSixAM() {
        // Stale at midnight in Tokyo, which is 8 AM on the Pacific device.
        let harness = Harness(now: date("2026-10-08T21:00:00+09:00"))
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        harness.snapshot = .generated(at: date("2026-10-08T21:00:00+09:00"), window: .restOfDay, in: tokyo, location: harness.selection)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00+09:00"))
    }

    @Test func planForAnotherLocationThanTheSelectionUsesTheDevicesTimeZone() async {
        // The saved plan is for Tokyo, but Seattle is selected; 7:30 AM Pacific isn't quiet.
        let harness = Harness(now: date("2026-10-08T23:30:00+09:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3)
        harness.snapshot = .generated(at: date("2026-10-08T15:00:00+09:00"), window: .restOfDay, in: tokyo, location: .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7))

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
    }

    @Test func newCityInAnotherZoneIsQuietWithNoSavedPlan() async {
        // Device in Rome, 2 AM in Tokyo is 7 PM there.
        let harness = Harness(now: date("2026-10-09T02:00:00+09:00"))
        harness.timeZone = rome
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        harness.snapshot = nil

        #expect(await harness.refresher.refreshIfStale() == .skippedQuietHours)
        #expect(await harness.fetcher.weatherRequests.isEmpty)
        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00+09:00"))
    }

    @Test func newCityInAnotherZoneIsNotQuietWhenItIsDayThereButNightOnTheDevice() async {
        // 11:30 PM in Rome is 6:30 AM in Tokyo.
        let harness = Harness(now: date("2026-10-08T23:30:00+02:00"))
        harness.timeZone = rome
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        harness.snapshot = nil

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
    }

    @Test func quietHoursAreTheCitysWhenTheSavedPlanIsForAnotherLocation() async {
        // 2 AM in Tokyo is 7 PM in Rome, where the saved plan is from.
        let harness = Harness(now: date("2026-10-09T02:00:00+09:00"))
        harness.timeZone = rome
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        harness.snapshot = .generated(at: date("2026-10-08T09:00:00+02:00"), window: .restOfDay, in: rome, location: .custom(name: "Rome", latitude: 41.9, longitude: 12.5))

        #expect(await harness.refresher.refreshIfStale() == .skippedQuietHours)
        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00+09:00"))
    }

    @Test func publishedPlanSpanPrefersTheForecastsTimeZoneOverTheSelections() async {
        let harness = Harness(now: date("2026-10-08T12:00:00-07:00"))
        harness.selection = .custom(name: "Seattle", latitude: 47.6, longitude: -122.3, timeZone: rome)
        await harness.fetcher.returnHourly(HourlyForecast(timeZone: pacific, points: []))

        _ = await harness.refresher.refreshIfStale()

        #expect(harness.published.first?.span?.timeZone == pacific)
    }

    @Test func nextRequestDateUsesTheSelectionsZoneWithoutASavedPlan() {
        let harness = Harness(now: date("2026-10-08T23:30:00+09:00"))
        harness.timeZone = rome
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00+09:00"))
    }

    @Test func nextRequestAfterMidnightWithYesterdaysPlanWaitsUntilAboutSixAM() {
        let harness = Harness(now: date("2026-10-09T00:30:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-08T22:00:00-07:00"), window: .restOfDay)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00-07:00"))
    }

    @Test func nextRequestForAPlanFromJustBeforeSixAMIsTheNormalStaleTime() {
        let harness = Harness(now: date("2026-10-08T05:50:00-07:00"))
        harness.planWindow = .oneHour
        harness.snapshot = .generated(at: date("2026-10-08T05:50:00-07:00"), window: .oneHour)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-08T06:20:00-07:00"))
    }

    @Test(arguments: [
        RecommendationState.UnavailableReason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
    ])
    func nextRequestWaitsForTheStaleTimeWhenTodaysWeatherOnlyPlanCantGetSuggestions(reason: RecommendationState.UnavailableReason) {
        let harness = Harness(now: date("2026-10-08T08:00:00-07:00"))
        harness.snapshot = .weatherOnly(at: date("2026-10-08T07:00:00-07:00"))

        #expect(harness.refresher.nextRequestDate(availability: .unavailable(reason)) == date("2026-10-08T10:00:00-07:00"))
    }

    @Test func nextRetryIsSoonerForAShortWindow() {
        let harness = Harness(now: date("2026-10-08T15:00:00-07:00"))
        harness.planWindow = .oneHour
        harness.snapshot = .weatherOnly(at: date("2026-10-08T14:50:00-07:00"), window: .oneHour)

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-08T15:30:00-07:00"))
    }

    @Test(arguments: [RecommendationAvailability.available, .unavailable(.modelNotReady)])
    func nextRequestRetriesWithinTheHourWhileTodaysSuggestionsAreStillMissing(availability: RecommendationAvailability) {
        let harness = Harness(now: date("2026-10-08T15:00:00-07:00"))
        harness.snapshot = .weatherOnly(at: date("2026-10-08T07:00:00-07:00"))

        #expect(harness.refresher.nextRequestDate(availability: availability) == date("2026-10-08T16:00:00-07:00"))
    }

    @Test func nextRequestRetriesWithinTheHourWhileThePlanIsStillStale() {
        let harness = Harness(now: date("2026-10-08T06:00:00-07:00"))
        harness.snapshot = .generated(at: date("2026-10-07T18:00:00-07:00"))

        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-08T07:00:00-07:00"))
    }
}

// MARK: - Harness

@MainActor
private final class Harness {
    let fetcher = RecordingPlanFetcher()
    var now: Date
    var timeZone = pacific
    var snapshot: PlanSnapshot?
    var selection: LocationSelection = .currentLocation
    var lastKnownGPSCoordinate: CLLocationCoordinate2D?
    var provider: WeatherProvider = .apple
    var planWindow: PlanWindow = .restOfDay
    var language = testResponseLanguage
    private(set) var published: [PlanSnapshot] = []

    init(now: Date) {
        self.now = now
    }

    var refresher: BackgroundPlanRefresher {
        BackgroundPlanRefresher(
            fetcher: fetcher,
            calendar: gregorianCalendar(in: timeZone),
            now: { [unowned self] in now },
            loadSnapshot: { [unowned self] in snapshot },
            publish: { [unowned self] in published.append($0) },
            selection: { [unowned self] in selection },
            lastKnownGPSCoordinate: { [unowned self] in lastKnownGPSCoordinate },
            provider: { [unowned self] in provider },
            planWindow: { [unowned self] in planWindow },
            responseLanguage: { [unowned self] in language }
        )
    }
}

private struct WeatherRequest: Equatable {
    let latitude: Double
    let longitude: Double
    let provider: WeatherProvider
}

private struct StubFailure: Error {}

private actor RecordingPlanFetcher: DayPlanFetching {
    private(set) var weatherRequests: [WeatherRequest] = []
    private(set) var recommendationRequestCount = 0
    var availability: RecommendationAvailability = .available
    var weatherResult: Result<DailyWeather, StubFailure> = .success(.placeholder)
    var recommendationResult: Result<OutfitRecommendation, StubFailure> = .success(.placeholder)
    var hourly: HourlyForecast?

    func failWeather() { weatherResult = .failure(StubFailure()) }
    func failRecommendation() { recommendationResult = .failure(StubFailure()) }
    func makeUnavailable(_ reason: RecommendationState.UnavailableReason) { availability = .unavailable(reason) }
    func returnHourly(_ forecast: HourlyForecast) { hourly = forecast }

    /// Runs `hook` inside `fetchWeather`, e.g. to simulate the user changing something in the app mid-fetch.
    private var weatherFetchHook: (@MainActor @Sendable () -> Void)?
    func duringWeatherFetch(_ hook: @escaping @MainActor @Sendable () -> Void) { weatherFetchHook = hook }

    func recommendationAvailability() async -> RecommendationAvailability {
        availability
    }

    nonisolated func prewarmRecommendation() {
        Issue.record("Background refresh has no one waiting on screen, so it shouldn't prewarm")
    }

    func fetchWeather(for coordinate: CLLocationCoordinate2D, from provider: WeatherProvider) async throws -> (DailyWeather, HourlyForecast?) {
        weatherRequests.append(WeatherRequest(latitude: coordinate.latitude, longitude: coordinate.longitude, provider: provider))
        if let weatherFetchHook { await weatherFetchHook() }
        return (try weatherResult.get(), hourly)
    }

    /// Makes generation hang until the calling task is cancelled (then it throws `CancellationError`,
    /// like a real on-device session). The returned stream yields once generation has started.
    private var generationStarted: AsyncStream<Void>.Continuation?
    func holdRecommendationUntilCancelled() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        generationStarted = continuation
        return stream
    }

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan) async throws -> OutfitRecommendation {
        recommendationRequestCount += 1
        if let generationStarted {
            generationStarted.yield()
            try await Task.sleep(for: .seconds(600))
        }
        return try recommendationResult.get()
    }
}
