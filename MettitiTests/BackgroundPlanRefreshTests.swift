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
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7)
        harness.snapshot = .generated(at: date("2026-10-08T15:00:00+09:00"), window: .restOfDay, in: tokyo, location: harness.selection)

        #expect(await harness.refresher.refreshIfStale() == .skippedQuietHours)
        #expect(harness.refresher.nextRequestDate(availability: .available) == date("2026-10-09T06:00:00+09:00"))
    }

    @Test func deviceNightIsNoQuietHoursForACityWhereItIsDay() async {
        // 11:30 PM on the Pacific device is 3:30 PM in Tokyo.
        let harness = Harness(now: date("2026-10-08T23:30:00-07:00"))
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7)
        harness.snapshot = .generated(at: date("2026-10-09T09:00:00+09:00"), window: .restOfDay, in: tokyo, location: harness.selection)

        #expect(await harness.refresher.refreshIfStale() == .refreshed)
    }

    @Test func cityPlanGoingStaleOvernightThereWaitsForTheCitysSixAM() {
        // Stale at midnight in Tokyo, which is 8 AM on the Pacific device.
        let harness = Harness(now: date("2026-10-08T21:00:00+09:00"))
        harness.selection = .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7)
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
            planWindow: { [unowned self] in planWindow }
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

    func recommendation(for weather: DailyWeather, hourly: HourlyForecast?, span: PlanSpan, onPartial: @MainActor (OutfitRecommendation) -> Void) async throws -> OutfitRecommendation {
        Issue.record("Background refresh has no one to show partial suggestions to, so it shouldn't stream")
        return try await recommendation(for: weather, hourly: hourly, span: span)
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
