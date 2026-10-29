import Foundation
import Testing
@testable import Mettiti

struct WidgetPlanTimelineTests {
    @Test func planFromYesterdayIsNotShown() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T18:00:00-07:00")),
            window: .restOfDay,
            now: date("2026-10-08T09:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.empty])
    }

    @Test func planFromEarlierTodayIsShown() {
        let generatedAt = date("2026-10-08T00:30:00-07:00")
        let timeline = WidgetPlanTimeline(saved: .generated(at: generatedAt), window: .restOfDay, now: date("2026-10-08T09:00:00-07:00"), calendar: gregorianCalendar(in: pacific))

        #expect(timeline.current.snapshot?.generatedAt == generatedAt)
        #expect(timeline.current.snapshot?.recommendation != nil)
    }

    @Test func weatherOnlyPlanFromEarlierTodayIsShown() {
        let generatedAt = date("2026-10-08T07:00:00-07:00")
        let timeline = WidgetPlanTimeline(saved: .weatherOnly(at: generatedAt), window: .restOfDay, now: date("2026-10-08T09:00:00-07:00"), calendar: gregorianCalendar(in: pacific))

        #expect(timeline.current.snapshot?.generatedAt == generatedAt)
        #expect(timeline.current.snapshot?.recommendation == nil)
    }

    @Test func noSavedPlanShowsNothing() {
        let timeline = WidgetPlanTimeline(saved: nil, window: .restOfDay, now: date("2026-10-08T09:00:00-07:00"), calendar: gregorianCalendar(in: pacific))

        #expect(timeline.entries.map(\.content) == [.empty])
    }

    @Test func planFromJustBeforeMidnightIsHiddenJustAfterMidnight() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T23:59:00-07:00")),
            window: .restOfDay,
            now: date("2026-10-08T00:01:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.empty])
    }

    @Test func dayIsJudgedInTheDeviceTimeZoneNotUTC() {
        // 08:00 and 20:00 Tokyo are the same local day, but 08:00 is still Oct 7 in UTC.
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-08T08:00:00+09:00")),
            window: .restOfDay,
            now: date("2026-10-08T20:00:00+09:00"),
            calendar: gregorianCalendar(in: tokyo)
        )

        #expect(timeline.current.snapshot != nil)
    }

    @Test func planFromYesterdayInDeviceTimeZoneIsHiddenEvenWhenTodayInUTC() {
        // 23:00 Oct 7 and 01:00 Oct 8 in Pacific time are both Oct 8 in UTC.
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T23:00:00-07:00")),
            window: .restOfDay,
            now: date("2026-10-08T01:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.empty])
    }

    @Test func reloadsHourlyDuringTheDay() {
        let now = date("2026-10-08T09:15:00-07:00")
        let timeline = WidgetPlanTimeline(saved: nil, window: .restOfDay, now: now, calendar: gregorianCalendar(in: pacific))

        #expect(timeline.reloadDate == date("2026-10-08T10:15:00-07:00"))
    }

    @Test func reloadsAtMidnightWhenTheNextHourCrossesIt() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-08T09:00:00-07:00")),
            window: .restOfDay,
            now: date("2026-10-08T23:30:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.reloadDate == date("2026-10-09T00:00:00-07:00"))
    }

    @Test func midnightIsTheDeviceTimeZonesMidnight() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let timeline = WidgetPlanTimeline(saved: nil, window: .restOfDay, now: date("2026-10-08T23:45:00+09:00"), calendar: gregorianCalendar(in: tokyo))

        #expect(timeline.reloadDate == date("2026-10-09T00:00:00+09:00"))
    }

    // MARK: - Plan Window

    @Test func planWithinItsWindowIsShownThenAsksToUpdateAtTheWindowsEnd() {
        let generatedAt = date("2026-10-08T14:00:00-07:00")
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: generatedAt, window: .threeHours),
            window: .threeHours,
            now: date("2026-10-08T15:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.date) == [date("2026-10-08T15:00:00-07:00"), date("2026-10-08T17:00:00-07:00")])
        #expect(timeline.entries.map(\.content) == [.plan(generatedAt), .needsUpdate])
    }

    @Test func planWhoseWindowHasPassedAsksToUpdateInsteadOfShowingOldAdvice() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-08T09:00:00-07:00"), window: .oneHour),
            window: .oneHour,
            now: date("2026-10-08T10:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.needsUpdate])
        #expect(timeline.current.snapshot == nil)
    }

    @Test func planForAnotherWindowThanTheSettingsDefaultAsksToUpdate() {
        // e.g. the default was just changed in Settings and the app hasn't remade the plan yet.
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-08T09:00:00-07:00"), window: .twelveHours),
            window: .threeHours,
            now: date("2026-10-08T10:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.needsUpdate])
    }

    @Test func windowEndingAfterMidnightTurnsToTheEmptyStateAtItsEnd() {
        // By then the plan is from an earlier day.
        let generatedAt = date("2026-10-08T22:00:00-07:00")
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: generatedAt, window: .threeHours),
            window: .threeHours,
            now: date("2026-10-08T22:30:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.date) == [date("2026-10-08T22:30:00-07:00"), date("2026-10-09T01:00:00-07:00")])
        #expect(timeline.entries.map(\.content) == [.plan(generatedAt), .empty])
    }

    @Test func lateEveningPlanStaysShownPastMidnightWhileItsWindowRuns() {
        // Rest of day made at 10 PM covers at least 3 hours, so until 1 AM.
        let generatedAt = date("2026-10-07T22:00:00-07:00")
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: generatedAt, window: .restOfDay),
            window: .restOfDay,
            now: date("2026-10-08T00:30:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.plan(generatedAt), .empty])
    }

    @Test func planFromAnEarlierDayWhoseWindowHasPassedShowsTheEmptyState() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T22:00:00-07:00"), window: .threeHours),
            window: .threeHours,
            now: date("2026-10-08T01:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.empty])
    }

    @Test func planFromAnEarlierDayForAnotherWindowShowsTheEmptyState() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T22:00:00-07:00"), window: .twelveHours),
            window: .threeHours,
            now: date("2026-10-08T01:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.empty])
    }

    // MARK: - A city in another time zone than the device's

    @Test func cityPlanAsksToUpdateAtItsWindowsEndEvenAfterTheDevicesMidnight() {
        // 2–5 PM in Tokyo is 10 PM – 1 AM on a Pacific device.
        let generatedAt = date("2026-10-08T14:00:00+09:00")
        let now = date("2026-10-08T16:30:00+09:00")
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: generatedAt, window: .threeHours, in: tokyo),
            window: .threeHours,
            now: now,
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.date) == [now, date("2026-10-08T17:00:00+09:00")])
        #expect(timeline.entries.map(\.content) == [.plan(generatedAt), .needsUpdate])
    }

    @Test func cityRestOfDayPlanEndsAtTheCitysMidnightWithTheEmptyState() {
        // Tokyo's midnight is 8 AM on a Pacific device, the same day there as the plan.
        let generatedAt = date("2026-10-08T18:00:00+09:00")
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: generatedAt, window: .restOfDay, in: tokyo),
            window: .restOfDay,
            now: date("2026-10-08T19:00:00+09:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.date).last == date("2026-10-09T00:00:00+09:00"))
        #expect(timeline.entries.map(\.content) == [.plan(generatedAt), .empty])
    }

    @Test func cityPlanFromAnEarlierDayThereShowsTheEmptyState() {
        // Oct 7, 8 PM and Oct 8, 9 AM in Tokyo are both Oct 7 on a Pacific device.
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-07T20:00:00+09:00"), window: .threeHours, in: tokyo),
            window: .threeHours,
            now: date("2026-10-08T09:00:00+09:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.entries.map(\.content) == [.empty])
    }

    @Test func cityPlanReloadsAtTheCitysMidnight() {
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-08T22:00:00+09:00"), window: .restOfDay, in: tokyo),
            window: .restOfDay,
            now: date("2026-10-08T23:30:00+09:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.reloadDate == date("2026-10-09T00:00:00+09:00"))
    }

    @Test func planForThePreviousLocationIsNotShownAfterSwitchingToACityInAnotherZone() {
        // Device in Rome; the plan is Rome's, the selection is now Tokyo.
        let seattleToTokyo = LocationSelection.custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: date("2026-10-08T09:00:00+02:00"), window: .restOfDay, in: rome, location: .custom(name: "Rome", latitude: 41.9, longitude: 12.5)),
            selection: seattleToTokyo,
            window: .restOfDay,
            now: date("2026-10-08T16:30:00+02:00"),
            calendar: gregorianCalendar(in: rome)
        )

        #expect(timeline.entries.map(\.content) == [.needsUpdate])
        // 11:30 PM in Tokyo: the reload is at Tokyo's midnight, half an hour away.
        #expect(timeline.reloadDate == date("2026-10-09T00:00:00+09:00"))
    }

    @Test func reloadMidnightIsTheSelectedCitysEvenWithoutASavedPlan() {
        let timeline = WidgetPlanTimeline(
            saved: nil,
            selection: .custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo),
            window: .restOfDay,
            now: date("2026-10-08T23:30:00+09:00"),
            calendar: gregorianCalendar(in: rome)
        )

        #expect(timeline.reloadDate == date("2026-10-09T00:00:00+09:00"))
    }

    @Test func planForTheSelectedLocationIsShownAndJudgedInTheCitysZone() {
        let tokyoSelection = LocationSelection.custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)
        let generatedAt = date("2026-10-08T08:00:00+09:00")
        let timeline = WidgetPlanTimeline(
            saved: PlanSnapshot(weather: .placeholder, recommendation: .placeholder, generatedAt: generatedAt, provider: .apple, location: tokyoSelection),
            selection: tokyoSelection,
            window: .restOfDay,
            now: date("2026-10-08T20:00:00+09:00"),
            calendar: gregorianCalendar(in: rome)
        )

        #expect(timeline.entries.map(\.content).first == .plan(generatedAt))
        #expect(timeline.entries.map(\.date).last == date("2026-10-09T00:00:00+09:00"))
    }

    @Test func planSavedWithoutALocationIsJudgedAsBefore() {
        let generatedAt = date("2026-10-08T08:00:00-07:00")
        let timeline = WidgetPlanTimeline(
            saved: .generated(at: generatedAt),
            selection: .custom(name: "Seattle", latitude: 47.6, longitude: -122.3),
            window: .restOfDay,
            now: date("2026-10-08T09:00:00-07:00"),
            calendar: gregorianCalendar(in: pacific)
        )

        #expect(timeline.current.snapshot?.generatedAt == generatedAt)
    }

    @Test func planSavedBeforePlanWindowsCountsAsRestOfDay() {
        let generatedAt = date("2026-10-08T09:00:00-07:00")
        let timeline = WidgetPlanTimeline(saved: .generated(at: generatedAt), window: .restOfDay, now: date("2026-10-08T15:00:00-07:00"), calendar: gregorianCalendar(in: pacific))

        #expect(timeline.entries.map(\.date) == [date("2026-10-08T15:00:00-07:00"), date("2026-10-09T00:00:00-07:00")])
        #expect(timeline.entries.map(\.content) == [.plan(generatedAt), .empty])
    }
}

/// What an entry shows, with plans told apart by when they were made.
private enum ShownContent: Equatable {
    case empty
    case plan(Date)
    case needsUpdate
}

private extension WidgetPlanTimeline.Entry {
    var content: ShownContent {
        switch state {
        case .empty: .empty
        case .plan(let snapshot): .plan(snapshot.generatedAt)
        case .needsUpdate: .needsUpdate
        }
    }
}

// MARK: - One rule for the location's calendar (#164)

struct LocationCalendarRuleTests {
    private let device = gregorianCalendar(in: pacific)
    private let zoneless = LocationSelection.custom(name: "Rome", latitude: 41.9, longitude: 12.5)
    private let tokyoCity = LocationSelection.custom(name: "Tokyo", latitude: 35.7, longitude: 139.7, timeZone: tokyo)

    /// The widget's midnight, which must be the rule's midnight.
    private func widgetReload(saved: PlanSnapshot?, selection: LocationSelection, now: Date) -> Date {
        WidgetPlanTimeline(saved: saved, selection: selection, window: .restOfDay, now: now, calendar: device).reloadDate
    }

    private func midnight(_ calendar: Calendar, after now: Date) -> Date {
        calendar.dateInterval(of: .day, for: now)!.end
    }

    @Test func cityWithAZoneUsesItsZoneEverywhere() {
        let now = date("2026-10-08T23:30:00+09:00")
        let saved = PlanSnapshot.generated(at: date("2026-10-08T22:00:00+09:00"), window: .restOfDay, in: rome, location: tokyoCity)
        let calendar = tokyoCity.calendar(fallback: device, savedPlan: saved)

        #expect(calendar.timeZone == tokyo)
        #expect(widgetReload(saved: saved, selection: tokyoCity, now: now) == midnight(calendar, after: now))
    }

    @Test func cityWithoutAZoneUsesAMatchingSavedPlansZoneThenTheDevices() {
        let romeNow = date("2026-10-08T23:30:00+02:00")
        let deviceNow = date("2026-10-08T23:30:00-07:00")
        let matching = PlanSnapshot.generated(at: date("2026-10-08T22:00:00+02:00"), window: .restOfDay, in: rome, location: zoneless)
        let other = PlanSnapshot.generated(at: date("2026-10-08T22:00:00+09:00"), window: .restOfDay, in: tokyo, location: tokyoCity)

        let withPlan = zoneless.calendar(fallback: device, savedPlan: matching)
        #expect(withPlan.timeZone == rome)
        #expect(widgetReload(saved: matching, selection: zoneless, now: romeNow) == midnight(withPlan, after: romeNow))

        for saved in [other, nil] {
            let calendar = zoneless.calendar(fallback: device, savedPlan: saved)
            #expect(calendar.timeZone == pacific)
            #expect(widgetReload(saved: saved, selection: zoneless, now: deviceNow) == midnight(calendar, after: deviceNow))
        }
    }

    @Test func currentLocationUsesTheDevicesZoneEvenWithASavedPlanFromAnotherZone() {
        let now = date("2026-10-08T23:30:00-07:00")
        let saved = PlanSnapshot.generated(at: date("2026-10-08T22:00:00+09:00"), window: .restOfDay, in: tokyo, location: .currentLocation)
        let calendar = LocationSelection.currentLocation.calendar(fallback: device, savedPlan: saved)

        #expect(calendar.timeZone == pacific)
        #expect(widgetReload(saved: saved, selection: .currentLocation, now: now) == midnight(calendar, after: now))
    }
}
